import IR
import IRExecution

/// Wrapper around `IRExecutor` that keeps track of the current execution state and translates the `IRExecutionState`s into values for variables in the source code.
public class Debugger {
  // MARK: - Private members
  
  /// The executor that actually executes the IR
  private let executor: IRExecutor
  
  private var program: IRProgram {
    return executor.program
  }
  
  /// Debug information to translate IR variable values back to source variable values
  private let debugInfo: DebugInfo
  
  /// The current state of the debugger. Can be `nil` if execution of the program has filtered out all samples
  private var currentState: IRExecutionState?
  
  private func currentStateOrThrow() throws -> IRExecutionState {
    guard let currentState = currentState else {
      throw ExecutionError(message: "Execution has filtered out all samples. Either the branch that was chosen is not feasible or the path is unlikely and there were an insufficient number of samples in the beginning to assign some to this branch.")
    }
    return currentState
  }
  
  // MARK: - Operating the debugger
  
  public init(program: IRProgram, debugInfo: DebugInfo, sampleCount: Int) {
    self.executor = IRExecutor(program: program)
    self.debugInfo = debugInfo
    self.currentState = IRExecutionState(initialStateIn: program, sampleCount: sampleCount)
    
    if debugInfo.info[self.currentState!.position] == nil {
      // Step to the first instruction with debug info
      try! runToNextInstructionWithDebugInfo(currentState: self.currentState!)
    }
  }
  
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
      return SourceCodeSample(values: variableValues)
    })
    return sourceCodeSamples
  }
  
  /// Run the program until the end
  public func run() throws {
    let currentState = try currentStateOrThrow()
    self.currentState = try executor.runUntilEnd(state: currentState)
  }
  
  private func runToNextInstructionWithDebugInfo(currentState: IRExecutionState) throws {
    self.currentState = try executor.runUntilCondition(state: currentState, stopPositions: Set(debugInfo.info.keys))
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
      let numInstructionsInBlock = program.basicBlocks[postdominatorBlock]!.instructions.count
      let firstInstructionIndexWithDebugInfo = (0..<numInstructionsInBlock).first(where: {
        return debugInfo.info[InstructionPosition(basicBlock: postdominatorBlock, instructionIndex: $0)] != nil
      })!
      self.currentState = try executor.runUntilCondition(state: currentState, stopPositions: [InstructionPosition(basicBlock: postdominatorBlock, instructionIndex: firstInstructionIndexWithDebugInfo)])
    } else {
      try runToNextInstructionWithDebugInfo(currentState: currentState)
    }
  }
  
  public func stepInto(branch: Bool) throws {
    let currentState = try currentStateOrThrow()
    
    guard let branchInstruction = executor.program.instruction(at: currentState.position) as? BranchInstruction else {
      throw ExecutionError(message: "Can only step into a branch if the debugger is currently positioned at a branching point")
    }
    
    let filteredState = currentState.filterSamples { sample in
      return branchInstruction.condition.evaluated(in: sample).boolValue! == branch
    }
    if filteredState.samples.isEmpty {
      throw ExecutionError(message: "Stepping into the \(branch) branch results in 0 samples being left. Ignoring the step")
    }
    try runToNextInstructionWithDebugInfo(currentState: filteredState)
  }
}
