import IR

fileprivate extension IRExecutionState {
  func instruction(in program: IRProgram) -> Instruction? {
    return program.instruction(at: self.position)
  }
}

/// Stateless class that takes an `IRExecutionState` and executes the given program on it up to a specific location (end, next instruction with debug info, ...)
public class IRExecutor {
  
  /// The program to execute
  private let program: IRProgram
  
  public init(program: IRProgram) {
    self.program = program
  }
  
  /// Run the program until the end
  public func runUntilEnd(state: IRExecutionState) -> IRExecutionState? {
    var finishedExecutionBranches: [IRExecutionState] = []
    var executionBranchesWorklist = [state]
    
    while !executionBranchesWorklist.isEmpty {
      guard let stateToExecute = executionBranchesWorklist.popLast() else {
        fatalError("No branch to execute")
      }
      if program.instruction(at: stateToExecute.position)! is ReturnInstruction {
        finishedExecutionBranches.append(stateToExecute)
      } else {
        let newStates = stateToExecute.executeNextInstruction(in: program)
        executionBranchesWorklist.append(contentsOf: newStates)
      }
    }
    guard let position = finishedExecutionBranches.first?.position else {
      // No execution branches left
      return nil
    }
    assert(finishedExecutionBranches.map(\.position).allEqual)
    let combinedSamples = finishedExecutionBranches.flatMap({ $0.samples })
    return IRExecutionState(position: position, samples: combinedSamples)
  }
  
  
  /// Run the program until the next instruction that has an associated source code location in the debug info.
  public func runUntilNextInstructionWithDebugInfo(state: IRExecutionState) throws -> IRExecutionState? {
    var currentState = state
    
    switch currentState.instruction(in: program) {
    case is BranchInstruction:
      throw ExecutionError(message: "Cannot execute a branch instruction using the 'step' command")
    case is ReturnInstruction:
      throw ExecutionError(message: "Program has already terminated")
    default:
      break
    }
    
    while true {
      let newBranches = currentState.executeNextInstruction(in: program)
      
      if newBranches.count == 0 {
        // No execution branch left. Nothing to execute anymore
        return nil
      } else if newBranches.count == 1 {
        currentState = newBranches.first!
        let position = currentState.position
        if program.debugInfo!.info[position] != nil || currentState.instruction(in: program) is ReturnInstruction {
          return currentState
        }
      } else {
        fatalError("Step must not create multiple execution branches")
      }
    }
  }
}
