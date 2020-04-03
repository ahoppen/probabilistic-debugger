import IR

/// During execution of a probabilistic program, describes an execution branch that is a concrete program position.
/// The variables at this concrete program position might have different values. Their probability distribution is described by an Array of `Sample`s.
public struct ExecutionState {
  /// The position of the next instruction to execute to advance the execution of this execution state.
  /// If no instruction exists at this program position in the IR, then the program has terminated.
  public let position: ProgramPosition
  
  /// The samples that describe the probability distribution of the variables at the given execution state.
  public let samples: [Sample]
  
  internal init(position: ProgramPosition, samples: [Sample]) {
    assert(samples.count > 0, "There is no point in pursuing an execution branch without any samples")
    self.position = position
    self.samples = samples
  }
  
  /// Execute the next instruction of this execution state and return any execution states resulting form it.
  /// For simple instructions like add or subtract that don't branch, exactly one new state is returned.
  /// An observe instruction returns no states if all samples are filtered out through its execution.
  /// A branch instruction may produce two new execution states if both branches are viable execution paths.
  internal func execute(in program: IRProgram) -> [ExecutionState] {
    guard let instruction = program.instruction(at: self.position) else {
      fatalError("Program has already terminated")
    }
    switch instruction {
    case is AssignInstruction, is AddInstruction, is SubtractInstruction, is CompareInstruction, is DiscreteDistributionInstruction:
      // Modify samples and advance program position by 1
      let newSamples = samples.compactMap({ $0.executeNonControlFlowInstruction(instruction) })
      let newPosition = ProgramPosition(basicBlock: position.basicBlock, instructionIndex: position.instructionIndex + 1)
      return [ExecutionState(position: newPosition, samples: newSamples)]
    case is ObserveInstruction:
      let newSamples = samples.compactMap({ $0.executeNonControlFlowInstruction(instruction) })
      // If there are no samples left, there is no point in pursuing this execution path
      if newSamples.isEmpty {
        return []
      } else {
        let newPosition = ProgramPosition(basicBlock: position.basicBlock, instructionIndex: position.instructionIndex + 1)
        return [ExecutionState(position: newPosition, samples: newSamples)]
      }
    case let instruction as JumpInstruction:
      // Simply jump to the new position and execute its phi instructions. No need to modify samples
      return [self.jumpTo(block: instruction.target, in: program, samples: samples, previousBlock: position.basicBlock)]
    case let instruction as BranchInstruction:
      // Split samples into those that satisfy the condition and those that don't. Then jump to the new block and execute phi instructions
      let trueSamples = samples.filter({ instruction.condition.evaluated(in: $0).boolValue == true })
      let falseSamples = samples.filter({ instruction.condition.evaluated(in: $0).boolValue == false })
      
      var newStates: [ExecutionState] = []
      if trueSamples.count > 0 {
        let trueState = self.jumpTo(block: instruction.targetTrue, in: program, samples: trueSamples, previousBlock: position.basicBlock)
        newStates.append(trueState)
      }
      
      if falseSamples.count > 0 {
        let falseState = self.jumpTo(block: instruction.targetFalse, in: program, samples: falseSamples, previousBlock: position.basicBlock)
        newStates.append(falseState)
      }
      assert(newStates.count > 0, "At least one execution path needs to be viable")
      
      return newStates
    case is PhiInstruction:
      fatalError("Should have been handled during the jump to a new basic block")
    case is ReturnInstruction:
      fatalError("Should have been handled by the executor")
    default:
      fatalError("Unknown instruction \(type(of: instruction))")
    }
  }
  
  /// Move the program position to the start of the given `block` and execute any `phi` instructions at its start
  private func jumpTo(block: BasicBlockName, in program: IRProgram, samples: [Sample], previousBlock: BasicBlockName) -> ExecutionState {
    var samples = samples
    var position = ProgramPosition(basicBlock: block, instructionIndex: 0)
    while let phiInstruction = program.instruction(at: position) as? PhiInstruction {
      samples = samples.map( {
        $0.assigning(variable: phiInstruction.assignee, variableOrValue: .variable(phiInstruction.choices[previousBlock]!))
      })
      position = ProgramPosition(basicBlock: position.basicBlock, instructionIndex: position.instructionIndex + 1)
    }
    return ExecutionState(position: position, samples: samples)
  }
}
