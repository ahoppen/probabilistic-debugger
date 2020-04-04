import IR

fileprivate extension IRExecutionState {
  func instruction(in program: IRProgram) -> Instruction? {
    return program.instruction(at: self.position)
  }
}

fileprivate extension IRProgram {
  /// The position of the (only) return instruction in the program
  var returnPosition: InstructionPosition {
    for basicBlock in self.basicBlocks.values {
      for (instructionIndex, instruction) in basicBlock.instructions.enumerated() {
        if instruction is ReturnInstruction {
          return InstructionPosition(basicBlock: basicBlock.name, instructionIndex: instructionIndex)
        }
      }
    }
    fatalError("Could not find a ReturnInstruction in the program")
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
    return try runUntilCondition(state: state, stopPositions: [program.returnPosition])
  }
  
  
  /// Run the program until the next instruction that matches the `stopCondition`.
  /// If the execution flow branches during execution, this assumes that all execution branches will all hit the **same** instruction which matches the `stopCondition`, i.e. all execution branches join at this condition again.
  /// Alternatively, there may be **no** viable execution branches left, in which case the function returns `nil`.
  public func runUntilCondition(state: IRExecutionState, stopPositions: Set<InstructionPosition>) throws -> IRExecutionState? {
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
    guard let position = stoppedExecutionBranches.first?.position else {
      // No execution branches left
      return nil
    }
    assert(stoppedExecutionBranches.map(\.position).allEqual)
    let combinedSamples = stoppedExecutionBranches.flatMap({ $0.samples })
    return IRExecutionState(position: position, samples: combinedSamples)
  }
}
