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

fileprivate extension Range where Bound == SourceCodeLocation {
  init(_ sourceRange: Range<SourceLocation>) {
    self = SourceCodeLocation(sourceRange.lowerBound)..<SourceCodeLocation(sourceRange.upperBound)
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
  private func append(instruction: Instruction, debugInfo: (instructionType: InstructionType, sourceRange: Range<SourceLocation>)?) {
    currentBasicBlock = currentBasicBlock.appending(instruction: instruction)
    if let debugInfo = debugInfo {
      let programPosition = InstructionPosition(basicBlock: currentBasicBlock.name, instructionIndex: currentBasicBlock.instructions.count - 1)
      // FIXME: Hide variables that are no longer valid in the current scope
      let instructionDebugInfo = InstructionDebugInfo(variables: declaredVariables.mapKeys({ $0.usr }), instructionType: debugInfo.instructionType, sourceCodeRange: Range<SourceCodeLocation>(debugInfo.sourceRange))
      self.debugInfo[programPosition] = instructionDebugInfo
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
    append(instruction: ReturnInstruction(), debugInfo: (.return, stmts.last!.range.upperBound..<stmts.last!.range.upperBound))
    finishedBasicBlocks.append(currentBasicBlock)
    return (program: IRProgram(startBlock: BasicBlockName("bb1"), basicBlocks: finishedBasicBlocks), debugInfo: DebugInfo(debugInfo))
  }
  
  public static func generateIr(for sourceCode: String) throws -> (program: IRProgram, debugInfo: DebugInfo) {
    let file = try Parser(sourceCode: sourceCode).parseFile()
    let typeCheckedFile = try TypeCheckPipeline.typeCheck(stmts: file)
    
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
    
    append(instruction: instruction, debugInfo: nil)
    return .variable(assignee)
  }
  
  // MARK: - Generating Phi instructions
  
  /// Generate Phi-Instructions for the join of control flow between two branches
  /// The main branch is the branch that pre-dominates the basic block that is currently being worked on while the side branch might or might not have been executed.
  /// We therefore don't need to worry about source variables that might have been declared in the side branch
  private func generatePhiInstructions(branch1Variables: [SourceVariable: IRVariable], branch2Variables: [SourceVariable: IRVariable], branch1Name: BasicBlockName, branch2Name: BasicBlockName) {
    for sourceVariable in Set(branch1Variables.keys).intersection(Set(branch2Variables.keys)) {
      let branch1IRVariable = branch1Variables[sourceVariable]!
      let branch2IRVariable = branch2Variables[sourceVariable]!
      
      if branch1IRVariable != branch2IRVariable {
        assert(branch1IRVariable.type == branch2IRVariable.type)
        
        let assignee = unusedIRVariable(type: branch1IRVariable.type)
        let phiInstr = PhiInstruction(assignee: assignee, choices: [
          branch1Name: branch1IRVariable,
          branch2Name: branch2IRVariable
        ])
        append(instruction: phiInstr, debugInfo: nil)
        record(sourceVariable: sourceVariable, irVariable: assignee)
      }
    }
  }
  
  // MARK: - Visitation functions
  
  public func visit(_ expr: IntegerLiteralExpr) -> VariableOrValue {
    return .integer(expr.value)
  }
  
  public func visit(_ expr: BoolLiteralExpr) -> VariableOrValue {
    return .bool(expr.value)
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
    append(instruction: DiscreteDistributionInstruction(assignee: assignee, distribution: expr.distribution), debugInfo: nil)
    return .variable(assignee)
  }
  
  public func visit(_ stmt: VariableDeclStmt) {
    let value = stmt.expr.accept(self)
    let irVariable = unusedIRVariable(type: value.type)
    append(instruction: AssignInstruction(assignee: irVariable, value: value), debugInfo: (.simple, stmt.range))
    record(sourceVariable: stmt.variable, irVariable: irVariable)
  }
  
  public func visit(_ stmt: AssignStmt) {
    guard case .resolved(let variable) = stmt.variable else {
      fatalError("Variables must be resolved before IRGen")
    }
    let value = stmt.expr.accept(self)
    let irVariable = unusedIRVariable(type: value.type)
    append(instruction: AssignInstruction(assignee: irVariable, value: value), debugInfo: (.simple, stmt.range))
    record(sourceVariable: variable, irVariable: irVariable)
  }
  
  public func visit(_ stmt: ObserveStmt) {
    let value = stmt.condition.accept(self)
    append(instruction: ObserveInstruction(observation: value), debugInfo: (.simple, stmt.range))
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
    append(instruction: BranchInstruction(condition: conditionValue, targetTrue: ifBodyBlockName, targetFalse: joinBlockBlockName), debugInfo: (.ifElseBranch, stmt.range.lowerBound..<stmt.condition.range.upperBound))
    
    let declaredVariablesBeforeIf = declaredVariables
    startNewBasicBlock(name: ifBodyBlockName, declaredVariables: declaredVariablesBeforeIf)
    
    stmt.body.accept(self)
    append(instruction: JumpInstruction(target: joinBlockBlockName), debugInfo: nil)
    let declaredVariablesAfterIfBody = declaredVariables
    let lastBlockOfIfBodyName = currentBasicBlock.name
    
    startNewBasicBlock(name: joinBlockBlockName, declaredVariables: declaredVariablesBeforeIf)
    generatePhiInstructions(
      branch1Variables: declaredVariablesBeforeIf,
      branch2Variables: declaredVariablesAfterIfBody,
      branch1Name: beforeIfBlockName,
      branch2Name: lastBlockOfIfBodyName
    )
  }
  
  public func visit(_ stmt: IfElseStmt) {
    let ifBodyBlockName = unusedBasicBlockName()
    let elseBodyBlockName = unusedBasicBlockName()
    let joinBlockBlockName = unusedBasicBlockName()
    
    let declaredVariablesBeforeIf = declaredVariables
    
    // Generate condition
    
    let conditionValue = stmt.condition.accept(self)
    append(instruction: BranchInstruction(condition: conditionValue, targetTrue: ifBodyBlockName, targetFalse: elseBodyBlockName), debugInfo: (.ifElseBranch, stmt.range.lowerBound..<stmt.condition.range.upperBound))
    
    
    // Generate if body
    
    startNewBasicBlock(name: ifBodyBlockName, declaredVariables: declaredVariablesBeforeIf)
    stmt.ifBody.accept(self)
    append(instruction: JumpInstruction(target: joinBlockBlockName), debugInfo: nil)
    let declaredVariablesAfterIfBody = declaredVariables
    let lastBlockOfIfBodyName = currentBasicBlock.name
    
    // Generate else body
    startNewBasicBlock(name: elseBodyBlockName, declaredVariables: declaredVariablesBeforeIf)
    stmt.elseBody.accept(self)
    append(instruction: JumpInstruction(target: joinBlockBlockName), debugInfo: nil)
    let declaredVariablesAfterElseBody = declaredVariables
    let lastBlockOfElseBodyName = currentBasicBlock.name
    
    startNewBasicBlock(name: joinBlockBlockName, declaredVariables: declaredVariablesBeforeIf)
    generatePhiInstructions(
      branch1Variables: declaredVariablesAfterIfBody,
      branch2Variables: declaredVariablesAfterElseBody,
      branch1Name: lastBlockOfIfBodyName,
      branch2Name: lastBlockOfElseBodyName
    )
  }
  
  public func visit(_ stmt: WhileStmt) {
    // IR jump pattern:
    // currentBlock -> conditionBlock
    // conditionBlock -> bodyBlock | joinBlock
    // bodyBlock -> ... multiple intermediate block (maybe with branches) ... -> lastBodyBlock
    // lastBodyBlock -> conditionBlock
    
    // First, generate IR for condition, ignoring necessary Phi instructions
    let beforeWhileBlockName = currentBasicBlock.name
    let conditionBlockName = unusedBasicBlockName()
    let bodyStartBlockName = unusedBasicBlockName()
    let joinBlockName = unusedBasicBlockName()
    
    let variablesDeclaredBeforeCondition = declaredVariables
    
    append(instruction: JumpInstruction(target: conditionBlockName), debugInfo: nil)
    
    startNewBasicBlock(name: conditionBlockName, declaredVariables: declaredVariables)
    
    // Save and clear the finished basic blocks.
    // This way finishedBasicBlocks only contains blocks relevant to this loop body which we all need to fix up by renaming variables.
    // This way, we make sure, we don't accidentally rename variables before the loop body.
    // In the end, these will be added to finishedBasicBlocks again.
    let finishedBasicBlocksBeforeLoop = finishedBasicBlocks
    let debugInfoBeforeLoop = debugInfo
    finishedBasicBlocks = []
    debugInfo = [:]
    
    let conditionValue = stmt.condition.accept(self)
    append(instruction: BranchInstruction(condition: conditionValue, targetTrue: bodyStartBlockName, targetFalse: joinBlockName), debugInfo: (.loop, stmt.range.lowerBound..<stmt.condition.range.upperBound))
    var conditionBlock = currentBasicBlock
    
    // Don't add the condition block to finishedBasicBlocks yet because we still need to insert Phi-instructions into it
    currentBasicBlock = BasicBlock(name: bodyStartBlockName, instructions: [])
    stmt.body.accept(self)
    append(instruction: JumpInstruction(target: conditionBlockName), debugInfo: nil)
    let lastBlockInBodyName = currentBasicBlock.name
    startNewBasicBlock(name: joinBlockName, declaredVariables: declaredVariables)
    
    // Now add phi instructions to the condition block and fix the condition and body block by renaming the variables for which we added phi instructions.
    // We don't need to add phi instructions for the body block since it is only jumped to from the condition block
    // All control flow flows through the condition block, so the assignees of the phi instructions are the correct storage for the source variables. Record this.
    var numInsertedPhiInstructions = 0
    var renamedVariables: [IRVariable: IRVariable] = [:]
    for (sourceVariable, mainBranchIRVariable) in variablesDeclaredBeforeCondition.sorted(by: { $0.value.name < $1.value.name }) {
      let whileBodyIRVariable = declaredVariables[sourceVariable]!
      
      if mainBranchIRVariable != whileBodyIRVariable {
        assert(mainBranchIRVariable.type == whileBodyIRVariable.type)
        
        let assignee = unusedIRVariable(type: mainBranchIRVariable.type)
        let phiInstr = PhiInstruction(assignee: assignee, choices: [
          beforeWhileBlockName: mainBranchIRVariable,
          lastBlockInBodyName: whileBodyIRVariable
        ])
        debugInfo = debugInfo.mapValues({ (debugInfo) -> InstructionDebugInfo in
          let renamedVariables = debugInfo.variables.mapValues({ (irVariable: IRVariable) -> IRVariable in
            if irVariable == mainBranchIRVariable {
              return assignee
            } else {
              return irVariable
            }
          })
          return InstructionDebugInfo(variables: renamedVariables, instructionType: debugInfo.instructionType, sourceCodeRange: debugInfo.sourceCodeRange)
        })
        finishedBasicBlocks = finishedBasicBlocks.map({ (block) in
          return block.renaming(variable: mainBranchIRVariable, to: assignee)
        })
        conditionBlock = conditionBlock.renaming(variable: mainBranchIRVariable, to: assignee)
        conditionBlock = conditionBlock.prepending(instruction: phiInstr)
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
        return (newPosition, InstructionDebugInfo(variables: newVariableMap, instructionType: debugInfo.instructionType, sourceCodeRange: debugInfo.sourceCodeRange))
      } else {
        return (position, debugInfo)
      }
    })
    // Honor the variables that now use the asignee of the phi instruction
    
    
    // Add the finished blocks and start a new block
    finishedBasicBlocks.append(conditionBlock)
    finishedBasicBlocks.append(contentsOf: finishedBasicBlocksBeforeLoop)
    debugInfo.merge(debugInfoBeforeLoop, uniquingKeysWith: { (a, b) -> InstructionDebugInfo in
      fatalError()
    })
  }
}
