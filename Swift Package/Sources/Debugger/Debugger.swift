import IR
import IRExecution
import WPInference

fileprivate extension VariableOrValue {
  init(_ irValue: IRValue) {
    switch irValue {
    case .integer(let value):
      self = .integer(value)
    case .bool(let value):
      self = .bool(value)
    }
  }
}

/// Wrapper around `IRExecutor` that keeps track of the current execution state and translates the `IRExecutionState`s into values for variables in the source code.
public class Debugger {
  // MARK: - Private members
  
  /// The executor that actually executes the IR
  private let executor: IRExecutor
  
  public let inferenceEngine: WPInferenceEngine
  
  private var program: IRProgram {
    return executor.program
  }
  
  /// Debug information to translate IR variable values back to source variable values
  private let debugInfo: DebugInfo
  
  /// The debugger can save execution states on a state stack. This is particularly useful to look into a branch using the 'step into' command and later returning to the state that does not have samples filtered out.
  /// The last element on the stateStack is always the last element.
  /// Must always contain at least one element.
  public private(set) var stateStack: [IRExecutionState?] {
    didSet {
      assert(!stateStack.isEmpty)
    }
  }
  
  /// The current state of the debugger. Can be `nil` if execution of the program has filtered out all samples.
  public var currentState: IRExecutionState? {
    get {
      return stateStack.last!
    }
    set {
      stateStack[stateStack.count - 1] = newValue
    }
  }
  
  private func currentStateOrThrow() throws -> IRExecutionState {
    guard let currentState = currentState else {
      throw DebuggerError(message: "Execution has filtered out all samples. Either the branch that was chosen is not feasible or the path is unlikely and there were an insufficient number of samples in the beginning to assign some to this branch.")
    }
    return currentState
  }
  
  private func runToNextInstructionWithDebugInfo(currentState: IRExecutionState) throws {
    self.currentState = try executor.runUntilPosition(state: currentState, stopPositions: Set(debugInfo.info.keys))
  }
  
  // MARK: - Creating a debugger
  
  public init(program: IRProgram, debugInfo: DebugInfo, sampleCount: Int) {
    self.executor = IRExecutor(program: program)
    self.inferenceEngine = WPInferenceEngine(program: program)
    self.debugInfo = debugInfo
    self.stateStack = [IRExecutionState(initialStateIn: program, sampleCount: sampleCount, loops: debugInfo.loops)]
    
    if debugInfo.info[self.currentState!.position] == nil {
      // Step to the first instruction with debug info
      try! runToNextInstructionWithDebugInfo(currentState: self.currentState!)
    }
  }
  
  public init(_ other: Debugger) {
    self.executor = other.executor
    self.debugInfo = other.debugInfo
    self.stateStack = other.stateStack
    self.inferenceEngine = other.inferenceEngine
  }
  
  // MARK: - Retrieving current state
  
  public var sourceLocation: SourceCodeLocation? {
    guard let currentState = currentState else {
      return nil
    }
    return debugInfo.info[currentState.position]?.sourceCodeLocation
  }
  
  public var samples: [SourceCodeSample] {
    guard let currentState = currentState else {
      return []
    }
    
    guard let instructionInfo = debugInfo.info[currentState.position] else {
      fatalError("Could not find debug info for the current statement")
    }
    let sourceCodeSamples = currentState.samples.map({ (irSample) -> SourceCodeSample in
      let variableValues = instructionInfo.variables.mapValues({ (irVariable) in
        irSample.values[irVariable]!
      })
      return SourceCodeSample(id: irSample.id, values: variableValues)
    })
    return sourceCodeSamples
  }
  
  /// The probability with which this state is reached when program execution is started at the beginning.
  public var reachingProbability: Double {
    guard let currentState = currentState else {
      return 0
    }
    return inferenceEngine.reachingProbability(of: currentState)
  }
  
  /// The error that might have been introduced by limiting the maximum number of loop iterations.
  public var approximationError: Double {
    guard let currentState = currentState else {
      return 0
    }
    return inferenceEngine.approximationError(of: currentState)
  }
  
  public func variableValuesRefinedUsingWP(approximationErrorHandling: WPInferenceEngine.ApproximationErrorHandling) -> [String: [IRValue: Double]] {
    guard let currentState = currentState else {
      return [:]
    }
    
    var variableValues: [String: [IRValue: Double]] = [:]
    guard let instructionInfo = debugInfo.info[currentState.position] else {
      fatalError("Could not find debug info for the current statement")
    }
    for (sourceVariable, irVariable) in instructionInfo.variables {
      var variableDistribution: [IRValue: Double] = [:]
      let possibleValues = Set(currentState.samples.map({ $0.values[irVariable]! }))
      
      // FIXME: Support WP inference for IRExecutionStates with multiple branching histories
      assert(currentState.branchingHistories.count == 1)
      for value in possibleValues {
        variableDistribution[value] = inferenceEngine.inferProbability(
          of: irVariable,
          beingEqualTo: VariableOrValue(value),
          approximationErrorHandling: approximationErrorHandling,
          loopUnrolls: currentState.loopUnrolls,
          to: currentState.position,
          branchingHistory: currentState.branchingHistories.first!
        )
      }
      variableValues[sourceVariable] = variableDistribution
    }
    return variableValues
  }
  
  public func sourceLocation(of executionState: IRExecutionState) -> SourceCodeLocation? {
    return debugInfo.info[executionState.position]?.sourceCodeLocation
  }
  
  // MARK: - Slicing the program for a variable
  
  /// Returns a set of source code ranges that do not have an influence on `sourceVariable` up to the current position.
  public func slice(for sourceVariable: String) throws -> Set<Range<SourceCodeLocation>> {
    guard let currentState = currentState else {
      return []
    }
    guard let irVariable = debugInfo.info[currentState.position]?.variables[sourceVariable] else {
      throw DebuggerError(message: "Source variable '\(sourceVariable)' does not exist at the current position")
    }
    
    // FIXME: Support WP inference for IRExecutionStates with multiple branching histories
    assert(currentState.branchingHistories.count == 1)
    let slice = inferenceEngine.slice(
      term: .variable(irVariable),
      loopUnrolls: currentState.loopUnrolls,
      inferenceStopPosition: currentState.position,
      branchingHistory: currentState.branchingHistories.first!
    )
    let slicedRanges = debugInfo.info.compactMap({ (instructionPosition, instructionDebugInfo) -> Range<SourceCodeLocation>? in
      if slice.contains(instructionPosition) {
        return nil
      } else {
        return instructionDebugInfo.sourceCodeRange
      }
    })
    return Set(slicedRanges)
  }
  
  // MARK: - Step through the program
  
  /// Run the program until the end
  public func runUntilEnd() throws {
    var currentState = try self.currentStateOrThrow()
    
    // First advance execution to a position that predominates the return position and postdominates all positions where we have been before.
    let instructionsThatPredominateReturnPosition = Set(debugInfo.info.keys.filter({
      guard program.predominators[program.returnPosition.basicBlock]!.contains($0.basicBlock) else {
        // Does not predominate the return positio
        return false
      }
      if program.transitivePredecessors[currentState.position.basicBlock]!.contains($0.basicBlock) {
        // Position is before the current position. We might have been here before.
        return false
      }
      for choice in currentState.branchingHistories.map(\.choices).flatMap({ $0 }) {
        // Check if the position is before any block in the branching history. If it is , we might have been here before.
        switch choice {
        case .choice(source: let source, target: let target):
          if program.transitivePredecessors[source]!.contains($0.basicBlock) {
            return false
          }
          if program.transitivePredecessors[target]!.contains($0.basicBlock) {
            return false
          }
        case .any(predominatedBy: let predominator):
          if program.transitivePredecessors[predominator]!.contains($0.basicBlock) {
            return false
          }
        }
      }
      return true
    }))
    
    // Now advance to that position.
    if !instructionsThatPredominateReturnPosition.contains(currentState.position) {
      self.currentState = try executor.runUntilPosition(state: currentState, stopPositions: instructionsThatPredominateReturnPosition)
      currentState = try self.currentStateOrThrow()
    }
    
    // We have now reached a position from which we can completely execute the program and abbreviate the branching history using a .any(predominatedBy)
    let finalBranchingHistories = currentState.branchingHistories.map({ $0.addingBranchingChoice(.any(predominatedBy: currentState.position.basicBlock))})
    
    if currentState.position != program.returnPosition {
      self.currentState = try executor.runUntilEnd(state: try currentStateOrThrow())
      self.currentState = self.currentState?.settingBranchingHistories(finalBranchingHistories)
    }
  }
  
  /// Continue execution of the program to the next statement with debug info that is reachable by all execution branches.
  /// For normal instructions this means stepping to the next instruction that has debug info (and thus maps to a statement in the source program).
  /// For branch instruction, this means jumping to the immediate postdominator block.
  public func stepOver() throws {
    let currentState = try currentStateOrThrow()
    
    if executor.program.instruction(at: currentState.position) is BranchInstruction {
      // Run to the first instruction with debug info in the postdominator block of the current block
      guard let postdominatorBlock = program.immediatePostdominator[currentState.position.basicBlock]! else {
        fatalError("A branch instruction must have an immediate postdominator since it does not terminate the program")
      }
      let firstNonPhiInstructionInBlock = program.basicBlocks[postdominatorBlock]!.instructions.firstIndex(where: { !($0 is PhiInstruction) })!
      // We can simplify the branching history if we are stepping over a if/else or loop
      let finalBranchingHistory = currentState.branchingHistories.map({ $0.addingBranchingChoice(.any(predominatedBy: currentState.position.basicBlock))})
      self.currentState = try executor.runUntilPosition(state: currentState, stopPositions: [
        InstructionPosition(basicBlock: postdominatorBlock, instructionIndex: firstNonPhiInstructionInBlock)]
      )
      self.currentState = self.currentState?.settingBranchingHistories(finalBranchingHistory)
      if debugInfo.info[self.currentState!.position] == nil {
        // Step to the first instruction with debug info
        try runToNextInstructionWithDebugInfo(currentState: self.currentState!)
      }
    } else {
      try runToNextInstructionWithDebugInfo(currentState: currentState)
    }
  }
  
  /// If the program is currently at a `BranchInstruction`, either focus on the `true` or the `false` branch, discarding any samples that would not execute this branch.
  public func stepInto(branch: Bool) throws {
    let currentState = try currentStateOrThrow()
    
    guard let branchInstruction = executor.program.instruction(at: currentState.position) as? BranchInstruction else {
      throw DebuggerError(message: "Can only step into a branch if the debugger is currently positioned at a branching point")
    }
    
    let filteredState = currentState.filterSamples { sample in
      return branchInstruction.condition.evaluated(in: sample).boolValue! == branch
    }
    if filteredState.samples.isEmpty {
      throw DebuggerError(message: "Stepping into the \(branch) branch results in 0 samples being left. Ignoring the step")
    }
    try runToNextInstructionWithDebugInfo(currentState: filteredState)
  }
  
  // MARK: - Saving and restoring states
  
  /// Save the current state on the state stack so it can be restored later using `restoreState`.
  public func saveState() {
    self.stateStack.append(currentState)
  }
  
  /// Restore the last saved state.
  public func restoreState() throws {
    if self.stateStack.count == 1 {
      throw DebuggerError(message: "No state to restore on the states stack")
    }
    self.stateStack.removeLast()
  }
  
  /// Clears the stack of saved states and positions the debugger at this execution state
  public func jumpToState(_ state: IRExecutionState) {
    self.stateStack = [state]
  }
}
