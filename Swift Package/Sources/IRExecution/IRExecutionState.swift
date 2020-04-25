import IR

public struct IRExecutionState {
  /// The position of the next instruction to execute to advance the execution of this execution state.
  /// If no instruction exists at this program position in the IR, then the program has terminated.
  public let position: InstructionPosition
  
  /// During execution, keep track of how many times each loop has been traversed (unrolled).
  /// This information is required to refine the proababilities later using WP-inference.
  public let loopUnrolls: LoopUnrolls
  
  /// The samples that describe the probability distribution of the variables at the given execution state.
  public let samples: [IRSample]
  
  /// The deliberate branching choices taken during execution of the IR in the order they occurred.
  public let branchingHistories: [BranchingHistory]
  
  public var hasSamples: Bool {
    return samples.count > 0
  }
  
  public init(initialStateIn program: IRProgram, sampleCount: Int, loops: [IRLoop]) {
    self.init(position: InstructionPosition(basicBlock: program.startBlock, instructionIndex: 0), emptySamples: sampleCount, loops: loops)
  }
  
  public init(position: InstructionPosition, emptySamples sampleCount: Int, loops: [IRLoop]) {
    let samples = (0..<sampleCount).map({ IRSample(id: $0, values: [:])})
    self.init(position: position, samples: samples, loopUnrolls: LoopUnrolls(noIterationsForLoops: loops), branchingHistories: [[]])
  }
  
  public init(position: InstructionPosition, samples: [IRSample], loopUnrolls: LoopUnrolls, branchingHistories: [BranchingHistory]) {
    self.position = position
    self.samples = samples
    self.loopUnrolls = loopUnrolls
    self.branchingHistories = branchingHistories
  }
  
  /// Create a new `IRExecutionState` with the combined samples of the given states.
  /// Assumes that all `states` are at the same position.
  /// Returns `nil` if `states` is empty.
  public static func merged(states: [IRExecutionState]) -> IRExecutionState? {
    if states.count == 1 {
      return states.first!
    }
    guard let position = states.first?.position else {
      return nil
    }
    assert(states.map(\.position).allEqual)
    let combinedSamples = states.flatMap({ $0.samples })
    return IRExecutionState(position: position, samples: combinedSamples, loopUnrolls: LoopUnrolls.merged(states.map(\.loopUnrolls)), branchingHistories: states.map(\.branchingHistories).flatMap({ $0 }))
  }
  
  /// Return an  execution state at the same position that only contains the samples that satisfy the given `condition`.
  public func filterSamples(condition: (IRSample) -> Bool) -> IRExecutionState {
    return IRExecutionState(position: position, samples: samples.filter(condition), loopUnrolls: loopUnrolls, branchingHistories: branchingHistories)
  }
  
  /// Add a deliberate branching choice to this execution state.
  public func addingBranchingChoice(_ branchingChoice: BranchingChoice) -> IRExecutionState {
    return IRExecutionState(position: position, samples: samples, loopUnrolls: loopUnrolls, branchingHistories: branchingHistories.map({ $0.addingBranchingChoice(branchingChoice) }))
  }
  
  public func settingBranchingHistories(_ branchingHistories: [BranchingHistory]) -> IRExecutionState {
    return IRExecutionState(position: position, samples: samples, loopUnrolls: loopUnrolls, branchingHistories: branchingHistories)
  }
  
  public func settingLoopUnrolls(loop: IRLoop, unrolls: LoopUnrollEntry) -> IRExecutionState {
    let newLoopUnrolls = self.loopUnrolls.settingLoopUnrolls(for: loop, unrolls: unrolls)
    return IRExecutionState(position: position, samples: samples, loopUnrolls: newLoopUnrolls, branchingHistories: branchingHistories)
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
      return [IRExecutionState(position: newPosition, samples: newSamples, loopUnrolls: loopUnrolls, branchingHistories: branchingHistories)]
    case is ObserveInstruction:
      let newSamples = samples.compactMap({ $0.executeNonControlFlowInstruction(instruction) })
      // If there are no samples left, there is no point in pursuing this execution path
      if newSamples.isEmpty {
        return []
      } else {
        let newPosition = InstructionPosition(basicBlock: position.basicBlock, instructionIndex: position.instructionIndex + 1)
        return [IRExecutionState(position: newPosition, samples: newSamples, loopUnrolls: loopUnrolls, branchingHistories: branchingHistories)]
      }
    case let instruction as JumpInstruction:
      // Simply jump to the new position and execute its phi instructions. No need to modify samples
      return [self.jumpTo(block: instruction.target, in: program, samples: samples, previousBlock: position.basicBlock, loopUnrolls: loopUnrolls)]
    case let instruction as BranchInstruction:
      // Split samples into those that satisfy the condition and those that don't. Then jump to the new block and execute phi instructions
      let trueSamples = samples.filter({ instruction.condition.evaluated(in: $0).boolValue == true })
      let falseSamples = samples.filter({ instruction.condition.evaluated(in: $0).boolValue == false })
      
      var newStates: [IRExecutionState] = []
      if trueSamples.count > 0 {
        // Tell loopUnrolls to record a jump into a loop's body block even though this branch might belong to an if-else statement.
        // recordingJumpToBodyBlock will ignore the recording request if it does not know about the loop we specified.
        let loop = IRLoop(conditionBlock: position.basicBlock, bodyStartBlock: instruction.targetTrue)
        let trueStateLoopUnrolls = loopUnrolls.recordingJumpToBodyBlock(for: loop)
        let trueState = self.jumpTo(block: instruction.targetTrue, in: program, samples: trueSamples, previousBlock: position.basicBlock, loopUnrolls: trueStateLoopUnrolls)
          .addingBranchingChoice(.choice(source: position.basicBlock, target: instruction.targetTrue))
        newStates.append(trueState)
      }
      
      if falseSamples.count > 0 {
        let falseState = self.jumpTo(block: instruction.targetFalse, in: program, samples: falseSamples, previousBlock: position.basicBlock, loopUnrolls: loopUnrolls)
          .addingBranchingChoice(.choice(source: position.basicBlock, target: instruction.targetFalse))
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
  
  /// Move the program position to the start of the given `block` and execute any `phi` instructions at its start.
  private func jumpTo(block: BasicBlockName, in program: IRProgram, samples: [IRSample], previousBlock: BasicBlockName, loopUnrolls: LoopUnrolls) -> IRExecutionState {
    var samples = samples
    var position = InstructionPosition(basicBlock: block, instructionIndex: 0)
    while let phiInstruction = program.instruction(at: position) as? PhiInstruction {
      samples = samples.map( {
        $0.assigning(variable: phiInstruction.assignee, variableOrValue: .variable(phiInstruction.choices[previousBlock]!))
      })
      position = InstructionPosition(basicBlock: position.basicBlock, instructionIndex: position.instructionIndex + 1)
    }
    return IRExecutionState(position: position, samples: samples, loopUnrolls: loopUnrolls, branchingHistories: branchingHistories)
  }
}
