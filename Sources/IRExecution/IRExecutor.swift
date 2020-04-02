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
      position: ProgramPosition(basicBlock: program.startBlock, instructionIndex: 0),
      samples: Array(repeating: Sample(values: [:]), count: sampleCount)
    )
    self.statesToExecute = [initialState]
  }
  
  /// Execute one instruction for the last state in `statesToExecute`
  private func executeStateOnTopOfExecutionStack() {
    guard let stateToExecute = statesToExecute.popLast() else {
      fatalError("No state to execute")
    }
    let newStates = stateToExecute.execute(in: program)
    for state in newStates {
      // Sort state into running and finished states
      if program.instruction(at: state.position) != nil {
        statesToExecute.append(state)
      } else {
        finishedExecutionStates.append(state)
      }
    }
  }
  
  /// Execute the given program and return the samples that describe the probability distribution of the variables in the end.
  /// Note that different samples may have been generated through different execution paths, so different variables might be defined in the different samples.
  public func execute() -> [Sample] {
    while !statesToExecute.isEmpty {
      executeStateOnTopOfExecutionStack()
    }
    return finishedExecutionStates.flatMap({ $0.samples })
  }
}
