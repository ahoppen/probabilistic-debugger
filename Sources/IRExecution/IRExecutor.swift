import IR

/// Executes the given IR program by describing the variable distributions through sampling
public class IRExecutor {
  /// The program to execute
  private let program: IRProgram
  
  /// The execution branches that have terminated
  private var finishedExecutionStates: [ExecutionState] = []
  
  /// A list of states describing execution branches that haven't terminated yet
  private var statesToExecute: [ExecutionState]
  
  public init(program: IRProgram, sampleCount: Int) {
    self.program = program
    let initialState = ExecutionState(
      position: InstructionPosition(basicBlock: program.startBlock, instructionIndex: 0),
      samples: Array(repeating: Sample(values: [:]), count: sampleCount)
    )
    self.statesToExecute = [initialState]
  }
  
  /// Execute one instruction for the last state in `statesToExecute`
  private func executeStateOnTopOfExecutionStack() {
    guard let stateToExecute = statesToExecute.popLast() else {
      fatalError("No state to execute")
    }
    if program.instruction(at: stateToExecute.position)! is ReturnInstruction {
      finishedExecutionStates.append(stateToExecute)
    } else {
      let newStates = stateToExecute.execute(in: program)
      statesToExecute.append(contentsOf: newStates)
    }
  }
  
  /// Execute the given program and return the samples that describe the probability distribution of the variables in the end.
  /// Note that different samples may have been generated through different execution paths, so different variables might be defined in the different samples.
  public func execute() -> [ExecutionState] {
    while !statesToExecute.isEmpty {
      executeStateOnTopOfExecutionStack()
    }
    assert(finishedExecutionStates.allSatisfy({ program.instruction(at: $0.position) is ReturnInstruction }))
    return finishedExecutionStates
  }
}
