import IR

/// Executes the given IR program by describing the variable distributions through sampling
public class IRExecutor {
  /// The program to execute
  private let program: IRProgram
  
  /// The execution branches that have terminated
  public var finishedExecutionBranches: [ExecutionBranch] = []
  
  /// A list of states describing execution branches that haven't terminated yet
  public var currentExecutionBranches: [ExecutionBranch]
  
  public init(program: IRProgram, sampleCount: Int) {
    self.program = program
    let initialState = ExecutionBranch(
      position: InstructionPosition(basicBlock: program.startBlock, instructionIndex: 0),
      samples: Array(repeating: IRSample(values: [:]), count: sampleCount)
    )
    self.currentExecutionBranches = [initialState]
  }
  
  /// Execute one instruction for the last state in `currentExecutionBranches`
  public func executeNextInstructionInBranchOnTopOfExecutionStack() {
    guard let stateToExecute = currentExecutionBranches.popLast() else {
      fatalError("No branch to execute")
    }
    if program.instruction(at: stateToExecute.position)! is ReturnInstruction {
      finishedExecutionBranches.append(stateToExecute)
    } else {
      let newStates = stateToExecute.executeNextInstruction(in: program)
      currentExecutionBranches.append(contentsOf: newStates)
    }
  }
  
  /// Execute the given program and return the samples that describe the probability distribution of the variables in the end.
  /// Note that different samples may have been generated through different execution paths, so different variables might be defined in the different samples.
  public func execute() -> [ExecutionBranch] {
    while !currentExecutionBranches.isEmpty {
      executeNextInstructionInBranchOnTopOfExecutionStack()
    }
    assert(finishedExecutionBranches.allSatisfy({ program.instruction(at: $0.position) is ReturnInstruction }))
    return finishedExecutionBranches
  }
}
