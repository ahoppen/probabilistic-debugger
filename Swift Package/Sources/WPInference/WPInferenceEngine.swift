import IR
import IRExecution
import Utils

extension WPTerm {
  var isZero: Bool {
    switch self {
    case .integer(0), .double(0):
      return true
    default:
      return false
    }
  }
}

public class WPInferenceEngine {
  /// If WP-inference looses some probability mass due to loop iteration bounds, this specifies how the lost probability mass should be handled.
  public enum ApproximationErrorHandling {
    /// Don't handle the lost proabability mass and return a probability distribution with sum that might be less than 1.
    case drop
    /// Proportionally distribute the lost probability mass onto the known values.
    case distribute
  }
  
  private let program: IRProgram
  
  /// Cached inference results. Maps an inference state to the resulting inference state when performing WP-inference to the top of the program.
  /// The result is `nil` if there is no feasible inference run from the queried state to the top.
  private var inferenceCache: [WPInferenceState: WPInferenceState?] = [:]
  
  /// Instructions that are likely to be repeatedly visited and for which inference results should be cached.
  /// At the moment such locations are the condition blocks of loops
  private let cachableIntermediateProgramPositions: Set<InstructionPosition>
  
  public init(program: IRProgram) {
    self.program = program
    self.cachableIntermediateProgramPositions = Set(program.loopInducingBlocks.map({ block in
      let firstNonPhiInstructionInBlock = program.basicBlocks[block]!.instructions.firstIndex(where: { !($0 is PhiInstruction) })!
      return InstructionPosition(basicBlock: block, instructionIndex: firstNonPhiInstructionInBlock)
    }))
  }
  
  /// Given a state that is pointed to the first instruction in a basic block and a predecessor block of this state, move the instruction position to the predecessor block and perform WP-inference for the branch or jump instruction in the predecessor block.
  private func _inferAcrossBlockBoundary(state: WPInferenceState, predecessor: BasicBlockName) -> WPInferenceState? {
    var state = state
    
    if let remainingLoopUnrolls = state.remainingLoopUnrolls[conditionBlock: state.position.basicBlock],
      program.properPredominators[state.position.basicBlock]!.contains(predecessor) {
      // We want to leave a loop to the top. Check if the loop has been unrolled a sufficient number of times
      
      if !remainingLoopUnrolls.canStopUnrolling {
        // All execution branches require at least one more loop unroll. We can't exit the loop to the top yet.
        return nil
      }
    }
    
    assert(state.position.instructionIndex == 0)
    assert(program.directPredecessors[state.position.basicBlock]!.contains(predecessor))
    
    // Compute the instruction position of the new inference state
    let predecessorBlockPosition = InstructionPosition(
      basicBlock: predecessor,
      instructionIndex: program.basicBlocks[predecessor]!.instructions.count - 1
    )
    
    // Perform WP-inference for the branch or jump instruction
    let instruction = program.instruction(at: predecessorBlockPosition)
    switch instruction {
    case is JumpInstruction:
      // The jump jumps unconditionally, so there is no need to modify the state's term
      state.position = predecessorBlockPosition
      return state
    case let instruction as BranchInstruction:
      var remainingLoopUnrolls = state.remainingLoopUnrolls
      
      // We might have have jumped from the body of a loop
      // Check if we are at a loop for which we have have an upper bound on the number of iterations
      let loop = IRLoop(conditionBlock: predecessorBlockPosition.basicBlock, bodyStartBlock: state.position.basicBlock)
      if let loopUnrolling = remainingLoopUnrolls[loop] {
        if !loopUnrolling.canUnrollOnceMore {
          return nil
        }
        remainingLoopUnrolls = remainingLoopUnrolls.recordingTraversalOfUnrolledLoopBody(loop)
      }
      
      // Determine the branch that was taken
      let takenBranch: Bool
      if state.position.basicBlock == instruction.targetTrue {
        takenBranch = true
      } else {
        assert(state.position.basicBlock == instruction.targetFalse)
        takenBranch = false
      }
      
      let cleanedBranchingHistory: BranchingHistory
      // If we are leaving an any BranchingChoice to the top, shave it off the branching history to allow consuming a deliberate branch underneath it.
      if case .any(predominatedBy: let predominator) = state.branchingHistory.lastChoice, !program.predominators[predecessor]!.contains(predominator) {
        cleanedBranchingHistory = state.branchingHistory.droppingLastChoice()
      } else {
        cleanedBranchingHistory = state.branchingHistory
      }
      
      let controlFlowDependency: IRVariable?
      if case .variable(let conditionVariable) = instruction.condition {
        controlFlowDependency = conditionVariable
      } else {
        controlFlowDependency = nil
      }

      
      switch cleanedBranchingHistory.lastChoice {
      case .choice(source: predecessor, target: state.position.basicBlock):
        // We are taking a deliberate choice. Consider it taken care of by removing it off the list
        var newState = state
        newState.position = predecessorBlockPosition
        newState.remainingLoopUnrolls = remainingLoopUnrolls
        newState.branchingHistory = cleanedBranchingHistory.droppingLastChoice()
        newState.updateTerms(term: true, focusRate: true, observeAndDeliberateBranchIgnoringFocusRate: false, controlFlowDependency: controlFlowDependency) {
          return .probability(of: instruction.condition, equalTo: .bool(takenBranch)) * $0
        }
        return newState
      case .any(predominatedBy: let predominator) where program.predominators[predecessor]!.contains(predominator):
        // We are taking an `any` branching choice. Keep it in the list since we might take it again.
        // Note that predominators contains the block itself.

        var newState = state
        newState.position = predecessorBlockPosition
        newState.remainingLoopUnrolls = remainingLoopUnrolls
        newState.branchingHistory = cleanedBranchingHistory
        newState.updateTerms(term: true, focusRate: true, observeAndDeliberateBranchIgnoringFocusRate: true, controlFlowDependency: controlFlowDependency) {
          return .probability(of: instruction.condition, equalTo: .bool(takenBranch)) * $0
        }
        return newState
      default:
        return nil
      }
    default:
      fatalError("Block that jumps to a different block should have terminated with a jump or branch instruction")
    }
  }
  
  /// Given a state that is positioned right after a Phi Instruction, perform WP-inference for all Phi instructions in the current block assuming that the previous block was `predecessorBlock`
  private func _evalutePhiInstructions(in state: WPInferenceState, predecessorBlock: BasicBlockName) -> WPInferenceState {
    var state = state
    while state.position.instructionIndex > 0 {
      let newPosition = InstructionPosition(basicBlock: state.position.basicBlock, instructionIndex: state.position.instructionIndex - 1)
      let instruction = program.instruction(at: newPosition)! as! PhiInstruction
      state.position = newPosition
      state.replace(variable: instruction.assignee, by: .variable(instruction.choices[predecessorBlock]!))
    }
    return state
  }
  
  /// Given an inference state, return all the components of `WPInferenceState` at which inference should continue. Note that the instruction at `position` has **not** been executed yet.
  /// The final inference result is determined by summing the values retrieved by inferring all the returned branches.
  private func _branchesToInfer(before state: WPInferenceState) -> [WPInferenceState] {
    if state.position.instructionIndex > 0 {
      let previousPosition = InstructionPosition(basicBlock: state.position.basicBlock, instructionIndex: state.position.instructionIndex - 1)
      
      if program.instruction(at: previousPosition) is PhiInstruction {
        // Evaluate all Phi instructions in the current block and jump to the predecessor blocks.
        return program.directPredecessors[state.position.basicBlock]!.sorted().compactMap({ (predecessor) -> WPInferenceState? in
          let stateAtBeginningOfBlock = _evalutePhiInstructions(in: state, predecessorBlock: predecessor)
          return _inferAcrossBlockBoundary(state: stateAtBeginningOfBlock, predecessor: predecessor)
        })
      } else {
        // We are at a normal instruction, just adjust the position to the previous one and return all the values
        var newState = state
        newState.position = previousPosition
        return [newState]
      }
    } else {
      // We have reached the start of a block. Continue inference in the predecessor blocks.
      return program.directPredecessors[state.position.basicBlock]!.sorted().compactMap({ (predecessor) in
        return _inferAcrossBlockBoundary(state: state, predecessor: predecessor)
      })
    }
  }
  
  /// Try loading the result of infering the given state all the way to the top of the program from the cache.
  /// If no entry exists in the cache yet, compute the inference result and store it in the cache.
  /// It is assumed that the `state`s terms aren't very complex and that thus hashValue calculation is not a performance bottleneck
  /// The current instruction of `stateToInfer` has **not** been inferred yet.
  private func _loadInferenceResultFromCacheOrPopulateCache(_ state: WPInferenceState) -> WPInferenceState? {
    // Try normalizing the state so that e.g. queries for 0.5 * [%1 = 1] and 0.25 * [%1 = 1] will be able to use the same cache entry.
    // For this, if the query is a multipliation, normalize the contant factor to 1.
    // If the query is an addition list, normalize is so the maximum factor is 1.
    var normalizedState = state
    var normalizationFactor: Double = 1
    switch state.focusRate {
    case ._mul(terms: let factors):
      let constants = factors.compactMap({ (factor: WPTerm) -> Double? in
        switch factor {
        case .integer(let value):
          return Double(value)
        case .double(let value):
          return value
        default:
          return nil
        }
      })
      if constants.count == 1 {
        normalizationFactor = constants.first!
      }
    case ._additionList(let additionList):
      if let maxFactor = additionList.entries.map(\.factor).max() {
        assert(maxFactor != 0)
        normalizationFactor = maxFactor
      }
    default:
      break
    }
    
    if normalizationFactor != 1 {
      normalizedState.updateTerms(term: true, focusRate: true, observeAndDeliberateBranchIgnoringFocusRate: false, update: {
        .double(1 / normalizationFactor) * $0
      })
    }
    
    var result: WPInferenceState?
    if let cachedReuslt = inferenceCache[normalizedState] {
      result = cachedReuslt
    } else {
      result = self._performInference(for: _performInferenceStep(normalizedState))
      inferenceCache[normalizedState] = result
    }
    
    if normalizationFactor != 1 {
      result?.updateTerms(term: true, focusRate: true, observeAndDeliberateBranchIgnoringFocusRate: false, update: {
        return .double(normalizationFactor) * $0
      })
      return result
    } else {
      return result
    }
  }
  
  /// Perform a single inference step.
  /// The current instruction of `stateToInfer` has **not** been inferred yet.
  private func _performInferenceStep(_ state: WPInferenceState) -> WPInferenceState {
    var state = state
    let position = state.position
    let instruction = program.instruction(at: position)!
    switch instruction {
    case let instruction as AssignInstruction:
      state.replace(variable: instruction.assignee, by: WPTerm(instruction.value))
    case let instruction as AddInstruction:
      state.replace(variable: instruction.assignee, by: WPTerm(instruction.lhs) + WPTerm(instruction.rhs))
    case let instruction as SubtractInstruction:
      state.replace(variable: instruction.assignee, by: WPTerm(instruction.lhs) - WPTerm(instruction.rhs))
    case let instruction as CompareInstruction:
      switch instruction.comparison {
      case .equal:
        state.replace(variable: instruction.assignee, by: .equal(lhs: WPTerm(instruction.lhs), rhs: WPTerm(instruction.rhs)))
      case .lessThan:
        state.replace(variable: instruction.assignee, by: .lessThan(lhs: WPTerm(instruction.lhs), rhs: WPTerm(instruction.rhs)))
      }
    case let instruction as DiscreteDistributionInstruction:
      state.updateTerms(term: true, focusRate: true, observeAndDeliberateBranchIgnoringFocusRate: true) { (term) in
        let terms = instruction.distribution.map({ (value, probability) in
          return .double(probability) * (term.replacing(variable: instruction.assignee, with: .integer(value)) ?? term)
        })
        return .add(terms: terms)
      }
    case let instruction as ObserveInstruction:
      let observeDependency: IRVariable?
      if case .variable(let observedVariable) = instruction.observation {
        observeDependency = observedVariable
      } else {
        observeDependency = nil
      }
      state.updateTerms(term: true, focusRate: true, observeAndDeliberateBranchIgnoringFocusRate: false, isObserveDependency: true, observeDependency: observeDependency) {
        return .boolToInt(WPTerm(instruction.observation)) * $0
      }
    case is JumpInstruction, is BranchInstruction:
      // Already handled by branchesToInfer. Nothing to do anymore.
      break
    case is ReturnInstruction:
      fatalError("WP inference is initialised at the ReturnInstruction which means the ReturnInstruction has already been inferred")
    case is PhiInstruction:
      fatalError("Should always be jumped over by branchesToInfer")
    case let unknownInstruction:
      fatalError("Unknown instruction: \(type(of: unknownInstruction))")
    }
    return state
  }
  
  private func _performInference(for initialState: WPInferenceState) -> WPInferenceState? {
    let programStartState = InstructionPosition(basicBlock: program.startBlock, instructionIndex: 0)
    
    var inferenceStatesWorklist = [initialState]
    
    // WPInferenceStates that have reached the start of the program. The sum of these state's terms determines the final result
    var finishedInferenceStates: [WPInferenceState] = []
    
    if initialState.position == programStartState {
      inferenceStatesWorklist = []
      finishedInferenceStates = [initialState]
    }
    
    while let worklistEntry = inferenceStatesWorklist.popLast() {
      // Pop one entry of the worklist and perform WP-inference for it
      for stateToInfer in self._branchesToInfer(before: worklistEntry) {
        if stateToInfer.observeAndDeliberateBranchIgnoringFocusRate.isZero {
          continue
        }
        
        let inferredState: WPInferenceState?
        if cachableIntermediateProgramPositions.contains(stateToInfer.position) {
          inferredState = _loadInferenceResultFromCacheOrPopulateCache(stateToInfer)
        } else {
          inferredState = _performInferenceStep(stateToInfer)
        }
        
        if let inferredState = inferredState {
          if inferredState.observeAndDeliberateBranchIgnoringFocusRate.isZero {
            // This state is not contributing anything. There is no point in pursuing it.
          } else if inferredState.position == programStartState {
            // At least one branching history of the state must have been completely taken care of.
            // Otherwise there are branches that we haven't considered which means we have reached the top of the program on a branching path that hasn't been specified in branching histories.
            if inferredState.branchingHistory.isEmpty {
              finishedInferenceStates.append(inferredState)
            }
          } else {
            // Check if we already have an inference state with the same characteristics.
            // If we do, combine the terms of newStateToInfer with the existing entry.
            let existingIndex = inferenceStatesWorklist.firstIndex(where: {
              return $0.position == inferredState.position &&
                $0.remainingLoopUnrolls == inferredState.remainingLoopUnrolls &&
                $0.branchingHistory == inferredState.branchingHistory
            })
            if let existingIndex = existingIndex {
              let existingEntry = inferenceStatesWorklist[existingIndex]
              inferenceStatesWorklist[existingIndex] = WPInferenceState.merged(
                states: [existingEntry, inferredState],
                remainingLoopUnrolls: existingEntry.remainingLoopUnrolls,
                branchingHistory: existingEntry.branchingHistory
              )!
            } else {
              inferenceStatesWorklist.append(inferredState)
              inferenceStatesWorklist.sort(by: {
                // $0 < $1 if
                //  - $0 predominates $1
                //  or
                //  - $1 postdominates $0
                return program.predominators[$1.position.basicBlock]!.contains($0.position.basicBlock) ||
                  program.postdominators[$0.position.basicBlock]!.contains($1.position.basicBlock)
              })
            }
          }
        }
      }
    }
    
    assert(finishedInferenceStates.allSatisfy({ $0.branchingHistory.isEmpty }))
    
    return WPInferenceState.merged(
      states: finishedInferenceStates,
      remainingLoopUnrolls: LoopUnrolls([:]),
      branchingHistory: []
    )
  }
  
  
  /// Perform a single inference step.
  /// The current instruction of `stateToInfer` has **not** been inferred yet.
  /// `previousBlock` is the block that has been inferred before this block. It must be specified when inferring a `BranchInstruction`. For all other instructions, it can be omitted.
  private func performInferenceStep(_ state: WPInferenceState, previousBlock: BasicBlockName?) -> WPInferenceState? {
    var state = state
    let position = state.position
    let instruction = program.instruction(at: position)!
    switch instruction {
    case let instruction as AssignInstruction:
      state.replace(variable: instruction.assignee, by: WPTerm(instruction.value))
    case let instruction as AddInstruction:
      state.replace(variable: instruction.assignee, by: WPTerm(instruction.lhs) + WPTerm(instruction.rhs))
    case let instruction as SubtractInstruction:
      state.replace(variable: instruction.assignee, by: WPTerm(instruction.lhs) - WPTerm(instruction.rhs))
    case let instruction as CompareInstruction:
      switch instruction.comparison {
      case .equal:
        state.replace(variable: instruction.assignee, by: .equal(lhs: WPTerm(instruction.lhs), rhs: WPTerm(instruction.rhs)))
      case .lessThan:
        state.replace(variable: instruction.assignee, by: .lessThan(lhs: WPTerm(instruction.lhs), rhs: WPTerm(instruction.rhs)))
      }
    case let instruction as DiscreteDistributionInstruction:
      state.updateTerms(term: true, focusRate: true, observeAndDeliberateBranchIgnoringFocusRate: true) { (term) in
        let terms = instruction.distribution.map({ (value, probability) in
          return .double(probability) * (term.replacing(variable: instruction.assignee, with: .integer(value)) ?? term)
        })
        return .add(terms: terms)
      }
    case let instruction as ObserveInstruction:
      let observeDependency: IRVariable?
      if case .variable(let observedVariable) = instruction.observation {
        observeDependency = observedVariable
      } else {
        observeDependency = nil
      }
      state.updateTerms(term: true, focusRate: true, observeAndDeliberateBranchIgnoringFocusRate: false, isObserveDependency: true, observeDependency: observeDependency) {
        return .boolToInt(WPTerm(instruction.observation)) * $0
      }
    case is JumpInstruction:
      // Jump is a no-op as far as the WP-terms are concerned
      break
    case let instruction as BranchInstruction:
      guard let previousBlock = previousBlock else {
        fatalError("previousBlock must be specified when inferring a BranchInstruction")
      }
      let takenBranch: Bool
      if previousBlock == instruction.targetTrue {
        takenBranch = true
      } else {
        assert(previousBlock == instruction.targetFalse)
        takenBranch = false
      }

      let cleanedBranchingHistory: BranchingHistory
      // If we are leaving an any BranchingChoice to the top, shave it off the branching history to allow consuming a deliberate branch underneath it.
      if case .any(predominatedBy: let predominator) = state.branchingHistory.lastChoice, !program.predominators[state.position.basicBlock]!.contains(predominator) {
        cleanedBranchingHistory = state.branchingHistory.droppingLastChoice()
      } else {
        cleanedBranchingHistory = state.branchingHistory
      }
      
      let controlFlowDependency: IRVariable?
      if case .variable(let conditionVariable) = instruction.condition {
        controlFlowDependency = conditionVariable
      } else {
        controlFlowDependency = nil
      }

      switch cleanedBranchingHistory.lastChoice {
      case .choice(source: state.position.basicBlock, target: previousBlock):
        // We are taking a deliberate choice. Consider it taken care of by removing it off the list
        state.branchingHistory = cleanedBranchingHistory.droppingLastChoice()
        state.updateTerms(term: true, focusRate: true, observeAndDeliberateBranchIgnoringFocusRate: false, controlFlowDependency: controlFlowDependency) {
          return .probability(of: instruction.condition, equalTo: .bool(takenBranch)) * $0
        }
        return state
      case .any(predominatedBy: let predominator) where program.predominators[state.position.basicBlock]!.contains(predominator):
        // We are taking an `any` branching choice. Keep it in the list since we might take it again.
        // Note that predominators contains the block itself.

        state.branchingHistory = cleanedBranchingHistory
        state.updateTerms(term: true, focusRate: true, observeAndDeliberateBranchIgnoringFocusRate: true, controlFlowDependency: controlFlowDependency) {
          return .probability(of: instruction.condition, equalTo: .bool(takenBranch)) * $0
        }
        return state
      default:
        return nil
      }
    case is ReturnInstruction:
      fatalError("WP inference is initialised at the ReturnInstruction which means the ReturnInstruction has already been inferred")
    case is PhiInstruction:
      fatalError("Should always be jumped over by branchesToInfer")
    case let unknownInstruction:
      fatalError("Unknown instruction: \(type(of: unknownInstruction))")
    }
    return state
  }
  
  private func performInferenceStepForSpecificBlockBoundary(for state: WPInferenceState, towards predecessor: BasicBlockName) -> WPInferenceState? {
    var state = state
    // Check if loop unrolls prevent us from performing inference across this block boundary
    let loop = IRLoop(conditionBlock: predecessor, bodyStartBlock: state.position.basicBlock)
    if let loopUnrolling = state.remainingLoopUnrolls[loop] {
      if !loopUnrolling.canUnrollOnceMore {
        return nil
      }
      state.remainingLoopUnrolls = state.remainingLoopUnrolls.recordingTraversalOfUnrolledLoopBody(loop)
    }
    

    let cleanedBranchingHistory: BranchingHistory
    // If we are leaving an any BranchingChoice to the top, shave it off the branching history to allow consuming a deliberate branch underneath it.
    if case .any(predominatedBy: let predominator) = state.branchingHistory.lastChoice, !program.predominators[predecessor]!.contains(predominator) {
      cleanedBranchingHistory = state.branchingHistory.droppingLastChoice()
    } else {
      cleanedBranchingHistory = state.branchingHistory
    }
    
    // Check if we would render a branching history entry invalid
    switch cleanedBranchingHistory.lastChoice {
    case .choice(source: let source, target: _) where program.predominators[predecessor]!.contains(source):
      break
    case .any(predominatedBy: let predominator) where program.predominators[predecessor]!.contains(predominator):
      break
    case nil:
      break
    default:
      return nil
    }
    
    // Evaluate Phi-instructions
    while state.position.instructionIndex > 0 {
      state.position = InstructionPosition(basicBlock: state.position.basicBlock, instructionIndex: state.position.instructionIndex - 1)
      guard let instruction = program.instruction(at: state.position) as? PhiInstruction else {
        fatalError("Inferring across a block boundary can only handle Phi-instructions. All other instructions should have been handled before.")
      }
      state.replace(variable: instruction.assignee, by: .variable(instruction.choices[predecessor]!))
    }
    
    // Actually perform the inference across the block boundary
    let predominator = program.immediatePredominator[state.position.basicBlock]!!
    let lastInstructionPositionInPredominator = InstructionPosition(basicBlock: predominator, instructionIndex: program.basicBlocks[predominator]!.instructions.count - 1)
    let previousBlock = state.position.basicBlock
    state.position = InstructionPosition(basicBlock: predecessor, instructionIndex: program.basicBlocks[predecessor]!.instructions.count - 1)
    if let inferredState = performInferenceStep(state, previousBlock: previousBlock) {
      return performInference(for: inferredState, upTo: lastInstructionPositionInPredominator)
    } else {
      return nil
    }
  }
  
  private func performInferenceStepForAllBlockBoundaries(for state: WPInferenceState) -> WPInferenceState? {
    var inferredSubStates = [WPInferenceState]()
    for predecessor in program.directPredecessors[state.position.basicBlock]!.sorted() {
      if let inferredState = performInferenceStepForSpecificBlockBoundary(for: state, towards: predecessor) {
        inferredSubStates.append(inferredState)
      }
    }
    assert(inferredSubStates.map(\.branchingHistory).allEqual)
    guard !inferredSubStates.isEmpty else {
      return nil
    }
    
    let mergedLoopUnrolls = LoopUnrolls.intersection(inferredSubStates.map(\.remainingLoopUnrolls))
    
    guard let mergedState = WPInferenceState.merged(states: inferredSubStates, remainingLoopUnrolls: mergedLoopUnrolls, branchingHistory: inferredSubStates.first!.branchingHistory) else {
      return nil
    }
    return mergedState
  }
  
  private func performInference(for state: WPInferenceState, upTo inferenceStopPosition: InstructionPosition) -> WPInferenceState? {
    var state = state
    while state.position != inferenceStopPosition {
      if state.position.instructionIndex > 0 {
        let previousPosition = InstructionPosition(basicBlock: state.position.basicBlock, instructionIndex: state.position.instructionIndex - 1)
        if program.instruction(at: previousPosition) is PhiInstruction {
          if let inferredState = performInferenceStepForAllBlockBoundaries(for: state) {
            state = inferredState
          } else {
            return nil
          }
        } else {
          state.position = previousPosition
          if let newState = performInferenceStep(state, previousBlock: nil) {
            state = newState
          } else {
            return nil
          }
        }
      } else {
        if let inferredState = performInferenceStepForAllBlockBoundaries(for: state) {
          state = inferredState
        } else {
          return nil
        }
      }
    }
    return state
  }
  
  /// Perform WP-inference on the given `term` using the program for which this inference engine was constructed.
  /// If the program contains loops, `loopRepetitionBounds` need to be specified that bound the number of loop iterations the WP-inference should perform.
  /// The function returns the following values:
  ///  - `value`: The result of inferring `term` without any normalization factors applied
  ///  - `runsNotCutOffByLoopIterationBounds`: The proportion of runs that were not cut off because of loop iteration bounds
  ///  - `observeSatisfactionRate`: Based on the runs that were not cut off because of loop iteration bounds, the proportion of runs that satisified all `observe` instructions
  ///  - `intentionalFocusRate`: Based on the runs that were not cut off because of loop iteration bounds, the proportion of all possible runs on which the inferrence was focused via the branching history.
  internal func infer(term: WPTerm, loopUnrolls: LoopUnrolls, inferenceStopPosition: InstructionPosition, branchingHistory: BranchingHistory) -> (value: WPTerm, focusRate: WPTerm, observeAndDeliberateBranchIgnoringFocusRate: WPTerm) {
    #if DEBUG
    // Check that we have a loop repetition bound for every loop in the program
    for loop in program.loops {
      assert(!loop.isEmpty)
      var foundLoopRepetitionBound = false
      for (block1, block2) in zip(loop, loop.dropFirst() + [loop.first!]) {
        // Iterate through all successors in the loop
        if loopUnrolls.loops.contains(where: { $0.conditionBlock == block1 && $0.bodyStartBlock == block2 }) {
          foundLoopRepetitionBound = true
          break
        }
      }
      assert(foundLoopRepetitionBound, "No loop repetition bound specified for loop \(loop)")
    }
    #endif
    
    let initialState = WPInferenceState(
      initialInferenceStateAtPosition: inferenceStopPosition,
      term: term,
      loopUnrolls: loopUnrolls,
      branchingHistory: branchingHistory,
      slicingForTerms: []
    )
    
    let inferredStateOrNil: WPInferenceState?
    
    if let cachedReuslt = inferenceCache[initialState] {
      inferredStateOrNil = cachedReuslt
    } else {
      inferredStateOrNil = self.performInference(for: initialState, upTo: InstructionPosition(basicBlock: program.startBlock, instructionIndex: 0))
      inferenceCache[initialState] = inferredStateOrNil
    }
    
    guard let inferredState = inferredStateOrNil else {
      // There was no successful inference run of the program. Manually put together the "zero" inference results.
      return (
        value: .integer(0),
        focusRate: .integer(0),
        observeAndDeliberateBranchIgnoringFocusRate: .integer(0)
      )
    }
    
    return (
      value: inferredState.term,
      focusRate: inferredState.focusRate,
      observeAndDeliberateBranchIgnoringFocusRate: inferredState.observeAndDeliberateBranchIgnoringFocusRate
    )
  }
  
  public func slice(term: WPTerm, loopUnrolls: LoopUnrolls, inferenceStopPosition: InstructionPosition, branchingHistory: BranchingHistory) -> Set<InstructionPosition> {
    let initialState = WPInferenceState(
      initialInferenceStateAtPosition: inferenceStopPosition,
      term: .integer(0),
      loopUnrolls: loopUnrolls,
      branchingHistory: branchingHistory,
      slicingForTerms: [term]
    )
    
    let inferredStateOrNil: WPInferenceState?
    
    if let cachedReuslt = inferenceCache[initialState] {
      inferredStateOrNil = cachedReuslt
    } else {
      inferredStateOrNil = self._performInference(for: initialState)
//      inferredStateOrNil = self.performInference(for: initialState, upTo: InstructionPosition(basicBlock: program.startBlock, instructionIndex: 0))
      inferenceCache[initialState] = inferredStateOrNil
    }
    
    guard let inferredState = inferredStateOrNil else {
      // There was no successful inference run of the program. Manually put together the "zero" inference results.
      return []
    }
    return inferredState.influencingInstructions(of: term)
  }
}

public extension WPInferenceEngine {
  /// Infer the probability that `variable` has the value `value` after executing the program to `inferenceStopPosition`.
  /// If `inferenceStopPosition` is `nil`, inference is done until the end of the program.
  /// If the program contains loops, `loopUnrolls` specifies how often loops should be unrolled.
  func inferProbability(of variable: IRVariable, beingEqualTo value: VariableOrValue, approximationErrorHandling: ApproximationErrorHandling, loopUnrolls: LoopUnrolls, to inferenceStopPosition: InstructionPosition, branchingHistory: BranchingHistory) -> Double {
    let queryVariable = IRVariable.queryVariable(type: variable.type)
    let term = WPTerm.probability(of: variable, equalTo: .variable(queryVariable))
    let inferred = infer(term: term, loopUnrolls: loopUnrolls, inferenceStopPosition: inferenceStopPosition, branchingHistory: branchingHistory)
    
    let probabilityTermWithPlaceholder: WPTerm
    switch approximationErrorHandling {
    case .distribute:
      probabilityTermWithPlaceholder = (inferred.value / inferred.focusRate)
    case .drop:
      probabilityTermWithPlaceholder = (inferred.value / (inferred.focusRate / inferred.observeAndDeliberateBranchIgnoringFocusRate))
    }
    let probabilityTerm = probabilityTermWithPlaceholder.replacing(variable: queryVariable, with: WPTerm(value)) ?? probabilityTermWithPlaceholder
    return probabilityTerm.doubleValue
  }
  
  func reachingProbability(of state: IRExecutionState) -> Double {
    // FIXME: Support WP inference for IRExecutionStates with multiple branching histories
    assert(state.branchingHistories.count == 1)
    let inferred = self.infer(term: .integer(0), loopUnrolls: state.loopUnrolls, inferenceStopPosition: state.position, branchingHistory: state.branchingHistories.first!)
    return (inferred.focusRate ./. inferred.observeAndDeliberateBranchIgnoringFocusRate).doubleValue
  }
  
  func approximationError(of state: IRExecutionState) -> Double {
    // FIXME: Support WP inference for IRExecutionStates with multiple branching histories
    assert(state.branchingHistories.count == 1)
    let inferred = self.infer(term: .integer(0), loopUnrolls: state.loopUnrolls, inferenceStopPosition: state.position, branchingHistory: state.branchingHistories.first!)
    return 1 - inferred.observeAndDeliberateBranchIgnoringFocusRate.doubleValue
  }
}
