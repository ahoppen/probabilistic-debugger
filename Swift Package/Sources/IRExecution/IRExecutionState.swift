import IR

/// During interactive IR execution in the debugger, the user might take deliberate branching choices by stepping into or stepping over a condition or loop which need to be recorded so that correct WP-inferrence can be performed.
/// This struct represents such a branching choice. Either the user jumps into one specific branch (case `choice`) or decides to step over and take both branches simultaneously (case `both`).
/// The cases where both branches are taken need to be recored in addition to the deliberate choices because a choice occur multiple times (e.g. a `if` inside a loop). To determine the correct iteration in which the deliberate branching choice was taken, we need to also record the times where the user issued a step over command.
@frozen public enum BranchingChoice: Equatable, CustomStringConvertible {
  case choice(source: BasicBlockName, target: BasicBlockName)
  case both(source: BasicBlockName)
  
  public var source: BasicBlockName {
    switch self {
    case .choice(source: let source, target: _):
      return source
    case .both(source: let source):
      return source
    }
  }
  
  public var description: String {
    switch self {
    case .choice(source: let source, target: let target):
      return "\(source) -> \(target)"
    case .both(source: let source):
      return "\(source) -> both"
    }
  }
}

/// Merge two lists of branching choices.
/// While the branching choices, match, keep the current branching choice.
/// Once we reach a point where one list of branching choices takes a different deliberate branch than the other, the rest of the lists is discarded and the two deliberate branches are unified to a `both` `BranchingChoice`.
/// This merging behaviour is correct since there is currently no way in the debugger to pursue two execution branches and merge them back together, keeping common choices that were done in the two separate execution branches.
/// The only place where execution branches are merged together is, if the user steps out of a loop (thus discarding the deliberate branching choice) or when executing a step over, the true/false branch of the if-statement are merged together again (and the equivalent for a loop). In all of these cases, there is no deliberate branching choice left.
fileprivate func mergeBranchingChoices(_ lhs: [BranchingChoice], _ rhs: [BranchingChoice]) -> [BranchingChoice] {
  var mergedChoices: [BranchingChoice] = []
  var unifiedByConvertingChoiceToBoth = false
  for (lhsEntry, rhsEntry) in zip(lhs, rhs) {
    if lhsEntry == rhsEntry {
      mergedChoices.append(lhsEntry)
    } else {
      assert(lhsEntry.source == rhsEntry.source)
      mergedChoices.append(.both(source: lhsEntry.source))
      unifiedByConvertingChoiceToBoth = true
      break
    }
  }
  // If the two choices that we unified had different length, we must have merged them at some point by converting .choice to .both
  assert(unifiedByConvertingChoiceToBoth || lhs.count == rhs.count)
  return mergedChoices
}

/// Merge a set of `BranchingChoice` lists using the function defined above.
fileprivate func mergeBranchingChoices(_ choicesList: [[BranchingChoice]]) -> [BranchingChoice] {
  guard var mergedChoices = choicesList.first else {
    // No choices to merge
    return []
  }
  for choices in choicesList.dropFirst() {
    mergedChoices = mergeBranchingChoices(mergedChoices, choices)
  }
  return mergedChoices
}

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
  public let branchingChoices: [BranchingChoice]
  
  public var hasSamples: Bool {
    return samples.count > 0
  }
  
  public init(initialStateIn program: IRProgram, sampleCount: Int, loops: [IRLoop]) {
    self.init(position: InstructionPosition(basicBlock: program.startBlock, instructionIndex: 0), emptySamples: sampleCount, loops: loops)
  }
  
  public init(position: InstructionPosition, emptySamples sampleCount: Int, loops: [IRLoop]) {
    let samples = (0..<sampleCount).map({ IRSample(id: $0, values: [:])})
    self.init(position: position, samples: samples, loopUnrolls: LoopUnrolls(noIterationsForLoops: loops), branchingChoices: [])
  }
  
  public init(position: InstructionPosition, samples: [IRSample], loopUnrolls: LoopUnrolls, branchingChoices: [BranchingChoice]) {
    self.position = position
    self.samples = samples
    self.loopUnrolls = loopUnrolls
    self.branchingChoices = branchingChoices
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
    return IRExecutionState(position: position, samples: combinedSamples, loopUnrolls: LoopUnrolls.merged(states.map(\.loopUnrolls)), branchingChoices: mergeBranchingChoices(states.map(\.branchingChoices)))
  }
  
  /// Return an  execution state at the same position that only contains the samples that satisfy the given `condition`.
  public func filterSamples(condition: (IRSample) -> Bool) -> IRExecutionState {
    return IRExecutionState(position: position, samples: samples.filter(condition), loopUnrolls: loopUnrolls, branchingChoices: branchingChoices)
  }
  
  /// Add a deliberate branching choice to this execution state.
  public func addingBranchingChoice(_ branchingChoice: BranchingChoice) -> IRExecutionState {
    return IRExecutionState(position: position, samples: samples, loopUnrolls: loopUnrolls, branchingChoices: branchingChoices + [branchingChoice])
  }
  
  public func settingLoopUnrolls(loop: IRLoop, unrolls: LoopUnrollEntry) -> IRExecutionState {
    let newLoopUnrolls = self.loopUnrolls.settingLoopUnrolls(for: loop, unrolls: unrolls)
    return IRExecutionState(position: position, samples: samples, loopUnrolls: newLoopUnrolls, branchingChoices: branchingChoices)
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
      return [IRExecutionState(position: newPosition, samples: newSamples, loopUnrolls: loopUnrolls, branchingChoices: branchingChoices)]
    case is ObserveInstruction:
      let newSamples = samples.compactMap({ $0.executeNonControlFlowInstruction(instruction) })
      // If there are no samples left, there is no point in pursuing this execution path
      if newSamples.isEmpty {
        return []
      } else {
        let newPosition = InstructionPosition(basicBlock: position.basicBlock, instructionIndex: position.instructionIndex + 1)
        return [IRExecutionState(position: newPosition, samples: newSamples, loopUnrolls: loopUnrolls, branchingChoices: branchingChoices)]
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
    return IRExecutionState(position: position, samples: samples, loopUnrolls: loopUnrolls, branchingChoices: branchingChoices)
  }
}
