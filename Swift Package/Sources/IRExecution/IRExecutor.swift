import IR

fileprivate extension IRExecutionState {
  func instruction(in program: IRProgram) -> Instruction? {
    return program.instruction(at: self.position)
  }
}

/// Stateless class that takes an `IRExecutionState` and executes the given program on it up to a specific location (end, next instruction with debug info, ...)
public class IRExecutor {
  
  /// The program to execute
  public let program: IRProgram
  
  public init(program: IRProgram) {
    self.program = program
  }
  
  /// Run the program until the end
  public func runUntilEnd(state: IRExecutionState) throws -> IRExecutionState? {
    return try runUntilPosition(state: state, stopPositions: [program.returnPosition])
  }
  
  
  /// Run the program until the next instruction that matches the `stopCondition`.
  /// If the execution flow branches during execution, this assumes that all execution branches will all hit the **same** instruction which matches the `stopCondition`, i.e. all execution branches join at this condition again.
  /// Alternatively, there may be **no** viable execution branches left, in which case the function returns `nil`.
  public func runUntilPosition(state: IRExecutionState, stopPositions: Set<InstructionPosition>) throws -> IRExecutionState? {
    if state.instruction(in: program) is ReturnInstruction {
      throw ExecutionError(message: "Program has already terminated")
    }
    
    var stoppedExecutionBranches: [IRExecutionState] = []
    var executionBranchesWorklist = [state]
    
    while !executionBranchesWorklist.isEmpty {
      guard let stateToExecute = executionBranchesWorklist.popLast() else {
        fatalError("No branch to execute")
      }
      let newStates = stateToExecute.executeNextInstruction(in: program)
      for newState in newStates {
        if stopPositions.contains(newState.position) || newState.instruction(in: program) is ReturnInstruction {
          stoppedExecutionBranches.append(newState)
        } else {
          executionBranchesWorklist.append(newState)
        }
      }
    }
    assert(stoppedExecutionBranches.map(\.position).allEqual)
    return IRExecutionState.merged(states: stoppedExecutionBranches)
  }
  
  public func runUntilNextInstruction(state: IRExecutionState) throws -> IRExecutionState? {
    if state.instruction(in: program) is ReturnInstruction {
      throw ExecutionError(message: "Program has already terminated")
    }
    let childStates = state.executeNextInstruction(in: program)
    assert(childStates.count <= 2, "runUntilNextInstruction must not be run on branch instructions where both branches are viable")
    return childStates.first
  }
}
