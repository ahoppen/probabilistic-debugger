import IR
import SimpleLanguageAST
import SimpleLanguageParser
import SimpleLanguageTypeChecker

fileprivate extension SourceVariable {
  /// A name of this variable that is unique across the source file and does not collide with any other definitions of variables with the same name.
  var usr: String {
    if disambiguationIndex == 1 {
      return name
    } else {
      return "\(name)#\(disambiguationIndex)"
    }
  }
}

fileprivate extension Dictionary {
  /// Transform the keys of the dicitonary.
  /// Assumes that if two keys are different in the old dictionary, they are also mapped to different keys.
  func mapKeys<T: Hashable>(_ transform: (Key) -> T) -> Dictionary<T, Value> {
    let keysAndValues = self.map({ (key, value) -> (T, Value) in
      return (transform(key), value)
    })
    return Dictionary<T, Value>(uniqueKeysWithValues: keysAndValues)
  }
  
  func mapKeysAndValues<NewKey: Hashable, NewValue>(_ transform: (Key, Value) -> (NewKey, NewValue)) -> Dictionary<NewKey, NewValue> {
    let keysAndValues = self.map({ (key, value) -> (NewKey, NewValue) in
      return transform(key, value)
    })
    return Dictionary<NewKey, NewValue>(uniqueKeysWithValues: keysAndValues)
  }
}

fileprivate extension SourceCodeLocation {
  init(_ sourceLocation: SourceLocation) {
    self.init(line: sourceLocation.line, column: sourceLocation.column)
  }
}

public class SLIRGen: ASTVisitor {
  public typealias ExprReturnType = VariableOrValue
  public typealias StmtReturnType = Void
  
  public init() {}
  
  // MARK: - Current generation state
  
  /// The basic block that is currently being worked on
  private var currentBasicBlock = BasicBlock(name: BasicBlockName("bb1"), instructions: [])
  
  /// A mapping of the source variables (potentially) accessible to the currently visited AST node and the IR variable that currently holds its value
  private var declaredVariables: [SourceVariable: IRVariable] = [:]
  
  /// Debug info that is collected during IR generation
  private var debugInfo: [InstructionPosition: InstructionDebugInfo] = [:]
  
  /// The basic blocks that are generated completely
  private var finishedBasicBlocks: [BasicBlock] = []
  
  private func startNewBasicBlock(name: BasicBlockName, declaredVariables: [SourceVariable: IRVariable]) {
    finishedBasicBlocks.append(currentBasicBlock)
    self.currentBasicBlock = BasicBlock(name: name, instructions: [])
    self.declaredVariables = declaredVariables
  }
  
  /// Append an instruction to the current basic block. If `sourceLocation` is not `nil`, also create debug info for this instruction.
  private func append(instruction: Instruction, sourceLocation: SourceLocation?) {
    currentBasicBlock = currentBasicBlock.appending(instruction: instruction)
    if let sourceLocation = sourceLocation {
      let programPosition = InstructionPosition(basicBlock: currentBasicBlock.name, instructionIndex: currentBasicBlock.instructions.count - 1)
      // FIXME: Hide variables that are no longer valid in the current scope
      let debugInfo = InstructionDebugInfo(variables: declaredVariables.mapKeys({ $0.usr }), sourceCodeLocation: SourceCodeLocation(sourceLocation))
      self.debugInfo[programPosition] = debugInfo
    }
  }
  
  private func irVariable(for variable: SourceVariable) -> IRVariable {
    guard let irVariable = declaredVariables[variable] else {
      fatalError("Could not find IR variable for source variable '\(variable)'")
    }
    return irVariable
  }
  
  private func record(sourceVariable: SourceVariable, irVariable: IRVariable) {
    self.declaredVariables[sourceVariable] = irVariable
  }
  
  // MARK: - Generating new basic block and variable names
  
  // bb1 is used for the starting block
  private var nextUnusedBasicBlockNumber = 2
  
  private func unusedBasicBlockName() -> BasicBlockName {
    defer {
      nextUnusedBasicBlockNumber += 1
    }
    return BasicBlockName("bb\(nextUnusedBasicBlockNumber)")
  }
  
  private var nextUnusedVariableNumber = 1
  
  /// Create a new variable in the IR whose name hasn't been used yet
  private func unusedIRVariable(type: IRType) -> IRVariable {
    defer {
      nextUnusedVariableNumber += 1
    }
    return IRVariable(name: "\(nextUnusedVariableNumber)", type: type)
  }
  
  // MARK: - Generate IR
  
  public func generateIR(for stmts: [Stmt]) -> (program: IRProgram, debugInfo: DebugInfo) {
    assert(!stmts.isEmpty)
    for stmt in stmts {
      stmt.accept(self)
    }
    append(instruction: ReturnInstruction(), sourceLocation: stmts.last!.range.upperBound)
    finishedBasicBlocks.append(currentBasicBlock)
    return (program: IRProgram(startBlock: BasicBlockName("bb1"), basicBlocks: finishedBasicBlocks), debugInfo: DebugInfo(debugInfo))
  }
  
  public static func generateIr(for sourceCode: String) throws -> (program: IRProgram, debugInfo: DebugInfo) {
    let file = try! Parser(sourceCode: sourceCode).parseFile()
    let typeCheckedFile = try! TypeCheckPipeline.typeCheck(stmts: file)
    
    return SLIRGen().generateIR(for: typeCheckedFile)
  }
  
  public func visit(_ expr: BinaryOperatorExpr) -> VariableOrValue {
    let lhs = expr.lhs.accept(self)
    let rhs = expr.rhs.accept(self)
    
    let instruction: Instruction
    let assignee: IRVariable
    switch (expr.operator, lhs.type, rhs.type) {
    case (.plus, .int, .int):
      assignee = unusedIRVariable(type: .int)
      instruction = AddInstruction(assignee: assignee, lhs: lhs, rhs: rhs)
    case (.minus, .int, .int):
      assignee = unusedIRVariable(type: .int)
      instruction = SubtractInstruction(assignee: assignee, lhs: lhs, rhs: rhs)
    case (.equal, .int, .int):
      assignee = unusedIRVariable(type: .bool)
      instruction = CompareInstruction(comparison: .equal, assignee: assignee, lhs: lhs, rhs: rhs)
    case (.lessThan, .int, .int):
      assignee = unusedIRVariable(type: .bool)
      instruction = CompareInstruction(comparison: .lessThan, assignee: assignee, lhs: lhs, rhs: rhs)
    case (.plus, _, _), (.minus, _, _), (.equal, _, _), (.lessThan, _, _):
      fatalError("No IR instruction to apply operator '\(expr.operator)' to  types '\(lhs.type)' and '\(rhs.type)'. This should have been caught by the type checker.")
    }
    
    append(instruction: instruction, sourceLocation: nil)
    return .variable(assignee)
  }
  
  // MARK: - Generating Phi instructions
  
  /// Generate Phi-Instructions for the join of control flow between two branches
  /// The main branch is the branch that pre-dominates the basic block that is currently being worked on while the side branch might or might not have been executed.
  /// We therefore don't need to worry about source variables that might have been declared in the side branch
  private func generatePhiInstructions(mainBranchVariables: [SourceVariable: IRVariable], sideBranchVariables: [SourceVariable: IRVariable], mainBranchName: BasicBlockName, sideBranchName: BasicBlockName) {
    for (sourceVariable, mainBranchIRVariable) in mainBranchVariables {
      let sideBranchIRVariable = sideBranchVariables[sourceVariable]!
      
      if mainBranchIRVariable != sideBranchIRVariable {
        assert(mainBranchIRVariable.type == sideBranchIRVariable.type)
        
        let assignee = unusedIRVariable(type: mainBranchIRVariable.type)
        let phiInstr = PhiInstruction(assignee: assignee, choices: [
          mainBranchName: mainBranchIRVariable,
          sideBranchName: sideBranchIRVariable
        ])
        append(instruction: phiInstr, sourceLocation: nil)
        record(sourceVariable: sourceVariable, irVariable: assignee)
      }
    }
  }
  
  // MARK: - Visitation functions
  
  public func visit(_ expr: IntegerLiteralExpr) -> VariableOrValue {
    return .integer(expr.value)
  }
  
  public func visit(_ expr: VariableReferenceExpr) -> VariableOrValue {
    guard case .resolved(let variable) = expr.variable else {
      fatalError("Variables must be resolved before IRGen")
    }
    
    return .variable(irVariable(for: variable))
  }
  
  public func visit(_ expr: ParenExpr) -> VariableOrValue {
    return expr.subExpr.accept(self)
  }
  
  public func visit(_ expr: DiscreteIntegerDistributionExpr) -> VariableOrValue {
    let assignee = unusedIRVariable(type: .int)
    append(instruction: DiscreteDistributionInstruction(assignee: assignee, distribution: expr.distribution), sourceLocation: nil)
    return .variable(assignee)
  }
  
  public func visit(_ stmt: VariableDeclStmt) {
    let value = stmt.expr.accept(self)
    let irVariable = unusedIRVariable(type: value.type)
    append(instruction: AssignInstruction(assignee: irVariable, value: value), sourceLocation: stmt.range.lowerBound)
    record(sourceVariable: stmt.variable, irVariable: irVariable)
  }
  
  public func visit(_ stmt: AssignStmt) {
    guard case .resolved(let variable) = stmt.variable else {
      fatalError("Variables must be resolved before IRGen")
    }
    let value = stmt.expr.accept(self)
    let irVariable = unusedIRVariable(type: value.type)
    append(instruction: AssignInstruction(assignee: irVariable, value: value), sourceLocation: stmt.range.lowerBound)
    record(sourceVariable: variable, irVariable: irVariable)
  }
  
  public func visit(_ stmt: ObserveStmt) {
    let value = stmt.condition.accept(self)
    append(instruction: ObserveInstruction(observation: value), sourceLocation: stmt.range.lowerBound)
  }
  
  public func visit(_ codeBlock: CodeBlockStmt) {
    for stmt in codeBlock.body {
      stmt.accept(self)
    }
  }
  
  public func visit(_ stmt: IfStmt) {
    let beforeIfBlockName = currentBasicBlock.name
    let ifBodyBlockName = unusedBasicBlockName()
    let joinBlockBlockName = unusedBasicBlockName()
    
    let conditionValue = stmt.condition.accept(self)
    append(instruction: BranchInstruction(condition: conditionValue, targetTrue: ifBodyBlockName, targetFalse: joinBlockBlockName), sourceLocation: stmt.condition.range.lowerBound)
    
    let declaredVariablesBeforeIf = declaredVariables
    startNewBasicBlock(name: ifBodyBlockName, declaredVariables: declaredVariablesBeforeIf)
    
    stmt.body.accept(self)
    append(instruction: JumpInstruction(target: joinBlockBlockName), sourceLocation: nil)
    let declaredVariablesAfterIfBody = declaredVariables
    
    startNewBasicBlock(name: joinBlockBlockName, declaredVariables: declaredVariablesBeforeIf)
    generatePhiInstructions(
      mainBranchVariables: declaredVariablesBeforeIf,
      sideBranchVariables: declaredVariablesAfterIfBody,
      mainBranchName: beforeIfBlockName,
      sideBranchName: ifBodyBlockName
    )
  }
  
  public func visit(_ stmt: WhileStmt) {
    // IR jump pattern:
    // currentBlock -> conditionBlock
    // conditionBlock -> bodyBlock | joinBlock
    // bodyBlock -> conditionBlock
    
    // First, generate IR for condition, ignoring necessary Phi instructions
    let beforeWhileBlockName = currentBasicBlock.name
    let conditionBlockName = unusedBasicBlockName()
    let bodyBlockName = unusedBasicBlockName()
    let joinBlockName = unusedBasicBlockName()
    
    let variablesDeclaredBeforeCondition = declaredVariables
    
    append(instruction: JumpInstruction(target: conditionBlockName), sourceLocation: nil)
    
    startNewBasicBlock(name: conditionBlockName, declaredVariables: declaredVariables)
    
    let conditionValue = stmt.condition.accept(self)
    append(instruction: BranchInstruction(condition: conditionValue, targetTrue: bodyBlockName, targetFalse: joinBlockName), sourceLocation: stmt.condition.range.lowerBound)
    var conditionBlock = currentBasicBlock
    
    currentBasicBlock = BasicBlock(name: bodyBlockName, instructions: [])
    stmt.body.accept(self)
    append(instruction: JumpInstruction(target: conditionBlockName), sourceLocation: nil)
    var bodyBlock = currentBasicBlock
    
    // Now add phi instructions to the condition block and fix the condition and body block by renaming the variables for which we added phi instructions.
    // We don't need to add phi instructions for the body block since it is only jumped to from the condition block
    // All control flow flows through the condition block, so the assignees of the phi instructions are the correct storage for the source variables. Record this.
    var numInsertedPhiInstructions = 0
    var renamedVariables: [IRVariable: IRVariable] = [:]
    for (sourceVariable, mainBranchIRVariable) in variablesDeclaredBeforeCondition {
      let whileBodyIRVariable = declaredVariables[sourceVariable]!
      
      if mainBranchIRVariable != whileBodyIRVariable {
        assert(mainBranchIRVariable.type == whileBodyIRVariable.type)
        
        let assignee = unusedIRVariable(type: mainBranchIRVariable.type)
        let phiInstr = PhiInstruction(assignee: assignee, choices: [
          beforeWhileBlockName: mainBranchIRVariable,
          bodyBlockName: whileBodyIRVariable
        ])
        conditionBlock = conditionBlock.renaming(variable: mainBranchIRVariable, to: assignee)
        conditionBlock = conditionBlock.prepending(instruction: phiInstr)
        bodyBlock = bodyBlock.renaming(variable: mainBranchIRVariable, to: assignee)
        record(sourceVariable: sourceVariable, irVariable: assignee)
        numInsertedPhiInstructions += 1
        renamedVariables[mainBranchIRVariable] = assignee
      }
    }
    // Finally fix the debug info
    // Take into account for the shift in instruction indicies through the inserted phi instructions
    self.debugInfo = debugInfo.mapKeysAndValues({ (position, debugInfo) -> (InstructionPosition, InstructionDebugInfo) in
      if position.basicBlock == conditionBlockName {
        let newPosition = InstructionPosition(basicBlock: conditionBlockName, instructionIndex: position.instructionIndex + numInsertedPhiInstructions)
        let newVariableMap = debugInfo.variables.mapValues({
          renamedVariables[$0] ?? $0
        })
        return (newPosition, InstructionDebugInfo(variables: newVariableMap, sourceCodeLocation: debugInfo.sourceCodeLocation))
      } else {
        return (position, debugInfo)
      }
    })
    // Honor the variables that now use the asignee of the phi instruction
    
    
    // Add the finished blocks and start a new block
    finishedBasicBlocks.append(conditionBlock)
    finishedBasicBlocks.append(bodyBlock)
    
    currentBasicBlock = BasicBlock(name: joinBlockName, instructions: [])
  }
}
