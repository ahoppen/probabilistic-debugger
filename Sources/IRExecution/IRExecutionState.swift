import IR

public struct IRExecutionState {
  /// The position of the next instruction to execute to advance the execution of this execution state.
  /// If no instruction exists at this program position in the IR, then the program has terminated.
  public let position: InstructionPosition
  
  /// The samples that describe the probability distribution of the variables at the given execution state.
  public let samples: [IRSample]
  
  public var hasSamples: Bool {
    return samples.count > 0
  }
  
  public init(initialStateIn program: IRProgram, sampleCount: Int) {
    self.init(position: InstructionPosition(basicBlock: program.startBlock, instructionIndex: 0), emptySamples: sampleCount)
  }
  
  public init(position: InstructionPosition, emptySamples sampleCount: Int) {
    self.init(position: position, samples: Array(repeating: IRSample(values: [:]), count: sampleCount))
  }
  
  private init(position: InstructionPosition, samples: [IRSample]) {
    self.position = position
    self.samples = samples
  }
  
  /// Create a new `IRExecutionState` with the combined samples of the given states.
  /// Assumes that all `states` are at the same position.
  /// Returns `nil` if `states` is empty.
  public static func merged(states: [IRExecutionState]) -> IRExecutionState? {
    guard let position = states.first?.position else {
      return nil
    }
    assert(states.map(\.position).allEqual)
    let combinedSamples = states.flatMap({ $0.samples })
    return IRExecutionState(position: position, samples: combinedSamples)
  }
  
  /// Return an  execution state at the same position that only contains the samples that satisfy the given `condition`.
  public func filterSamples(condition: (IRSample) -> Bool) -> IRExecutionState {
    return IRExecutionState(position: position, samples: samples.filter(condition))
  }
  
  /// Execute the next instruction of this execution state and return any execution states resulting form it.
  /// For simple instructions like add or subtract that don't branch, exactly one new state is returned.
  /// An observe instruction returns no states if all samples are filtered out through its execution.
  /// A branch instruction may produce two new execution states if both branches are viable execution paths.
  internal func executeNextInstruction(in program: IRProgram) -> [IRExecutionState] {
    guard let instruction = program.instruction(at: self.position) else {
      fatalError("Program has already terminated")
    }
    switch instruction {
    case is AssignInstruction, is AddInstruction, is SubtractInstruction, is CompareInstruction, is DiscreteDistributionInstruction:
      // Modify samples and advance program position by 1
      let newSamples = samples.compactMap({ $0.executeNonControlFlowInstruction(instruction) })
      let newPosition = InstructionPosition(basicBlock: position.basicBlock, instructionIndex: position.instructionIndex + 1)
      return [IRExecutionState(position: newPosition, samples: newSamples)]
    case is ObserveInstruction:
      let newSamples = samples.compactMap({ $0.executeNonControlFlowInstruction(instruction) })
      // If there are no samples left, there is no point in pursuing this execution path
      if newSamples.isEmpty {
        return []
      } else {
        let newPosition = InstructionPosition(basicBlock: position.basicBlock, instructionIndex: position.instructionIndex + 1)
        return [IRExecutionState(position: newPosition, samples: newSamples)]
      }
    case let instruction as JumpInstruction:
      // Simply jump to the new position and execute its phi instructions. No need to modify samples
      return [self.jumpTo(block: instruction.target, in: program, samples: samples, previousBlock: position.basicBlock)]
    case let instruction as BranchInstruction:
      // Split samples into those that satisfy the condition and those that don't. Then jump to the new block and execute phi instructions
      let trueSamples = samples.filter({ instruction.condition.evaluated(in: $0).boolValue == true })
      let falseSamples = samples.filter({ instruction.condition.evaluated(in: $0).boolValue == false })
      
      var newStates: [IRExecutionState] = []
      if trueSamples.count > 0 {
        let trueState = self.jumpTo(block: instruction.targetTrue, in: program, samples: trueSamples, previousBlock: position.basicBlock)
        newStates.append(trueState)
      }
      
      if falseSamples.count > 0 {
        let falseState = self.jumpTo(block: instruction.targetFalse, in: program, samples: falseSamples, previousBlock: position.basicBlock)
        newStates.append(falseState)
      }
      
      return newStates
    case is PhiInstruction:
      fatalError("Should have been handled during the jump to a new basic block")
    case is ReturnInstruction:
      fatalError("Program has already terminated")
    default:
      fatalError("Unknown instruction \(type(of: instruction))")
    }
  }
  
  /// Move the program position to the start of the given `block` and execute any `phi` instructions at its start
  private func jumpTo(block: BasicBlockName, in program: IRProgram, samples: [IRSample], previousBlock: BasicBlockName) -> IRExecutionState {
    var samples = samples
    var position = InstructionPosition(basicBlock: block, instructionIndex: 0)
    while let phiInstruction = program.instruction(at: position) as? PhiInstruction {
      samples = samples.map( {
        $0.assigning(variable: phiInstruction.assignee, variableOrValue: .variable(phiInstruction.choices[previousBlock]!))
      })
      position = InstructionPosition(basicBlock: position.basicBlock, instructionIndex: position.instructionIndex + 1)
    }
    return IRExecutionState(position: position, samples: samples)
  }
}
