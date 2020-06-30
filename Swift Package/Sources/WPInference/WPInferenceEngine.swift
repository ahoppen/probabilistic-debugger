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
  
  /// Perform a single inference step.
  /// The current instruction of `stateToInfer` has **not** been inferred yet.
  /// `previousBlock` is the block that has been inferred before this block. It must be specified when inferring a `BranchInstruction`. For all other instructions, it can be omitted.
  private func performInferenceStep(_ state: WPInferenceState) -> WPInferenceState? {
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
      guard let previousBlock = state.previousBlock else {
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
      case .any(predominatedBy: let predominator) where program.predominators[state.position.basicBlock]!.contains(predominator):
        // We are taking an `any` branching choice. Keep it in the list since we might take it again.
        // Note that predominators contains the block itself.

        state.branchingHistory = cleanedBranchingHistory
        state.updateTerms(term: true, focusRate: true, observeAndDeliberateBranchIgnoringFocusRate: true, controlFlowDependency: controlFlowDependency) {
          return .probability(of: instruction.condition, equalTo: .bool(takenBranch)) * $0
        }
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
  
  private func performInferenceStepForSpecificBlockBoundary(for state: WPInferenceState, towards predecessor: BasicBlockName, upTo inferenceStopPosition: InstructionPosition) -> WPInferenceState? {
    var state = state
    // Check if loop unrolls prevent us from performing inference across this block boundary
    let loop = IRLoop(conditionBlock: predecessor, bodyStartBlock: state.position.basicBlock)
    if let loopUnrollsRemaining = state.remainingLoopUnrolls[loop] {
      if loopUnrollsRemaining == 0 {
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
    let lastInstructionPositionInPredominator = InstructionPosition(basicBlock: predominator, instructionIndex: program.basicBlocks[predominator]!.instructions.count)
    let previousBlock = state.position.basicBlock
    // Start inference from a virtual instruction just after the last instruction in the predecessor block
    state.position = InstructionPosition(basicBlock: predecessor, instructionIndex: program.basicBlocks[predecessor]!.instructions.count)
    state.previousBlock = previousBlock
    return performInference(for: state, upTo: lastInstructionPositionInPredominator)
  }
  
  private func performInferenceStepForAllBlockBoundaries(for state: WPInferenceState, upTo inferenceStopPosition: InstructionPosition) -> WPInferenceState? {
    var inferredSubStates = [WPInferenceState]()
    var remainingLoopUnrolls = state.remainingLoopUnrolls
    for predecessor in program.directPredecessors[state.position.basicBlock]!.sorted() {
      let loop = IRLoop(conditionBlock: predecessor, bodyStartBlock: state.position.basicBlock)
      if let loopUnrollsRemaining = remainingLoopUnrolls[loop] {
        if loopUnrollsRemaining > 0 {
          remainingLoopUnrolls = remainingLoopUnrolls.recordingTraversalOfUnrolledLoopBody(loop)
        }
      }
      if let inferredState = performInferenceStepForSpecificBlockBoundary(for: state, towards: predecessor, upTo: inferenceStopPosition) {
        inferredSubStates.append(inferredState)
      }
    }
    inferredSubStates = inferredSubStates.compactMap({ (inferredSubState: WPInferenceState) -> WPInferenceState? in
      var inferredSubState = inferredSubState
      if inferredSubState.position == inferenceStopPosition {
        return inferredSubState
      }
      let previousPosition = InstructionPosition(basicBlock: inferredSubState.position.basicBlock, instructionIndex: inferredSubState.position.instructionIndex - 1)
      inferredSubState.position = previousPosition
      return performInferenceStep(inferredSubState)
    })
    
    assert(inferredSubStates.map(\.branchingHistory).allEqual)
    switch inferredSubStates.count {
    case 0:
      return nil
    case 1:
      return inferredSubStates.first!
    default:
      return WPInferenceState.merged(states: inferredSubStates, remainingLoopUnrolls: remainingLoopUnrolls, branchingHistory: inferredSubStates.first!.branchingHistory)
    }
  }
  
  private func performInference(for state: WPInferenceState, upTo inferenceStopPosition: InstructionPosition) -> WPInferenceState? {
    var state = state
    while state.position != inferenceStopPosition {
      if state.position.instructionIndex > 0 {
        let previousPosition = InstructionPosition(basicBlock: state.position.basicBlock, instructionIndex: state.position.instructionIndex - 1)
        if program.instruction(at: previousPosition) is PhiInstruction {
          if let inferredState = performInferenceStepForAllBlockBoundaries(for: state, upTo: inferenceStopPosition) {
            state = inferredState
          } else {
            return nil
          }
        } else {
          state.position = previousPosition
          if let newState = performInferenceStep(state) {
            state = newState
          } else {
            return nil
          }
        }
      } else {
        if let inferredState = performInferenceStepForAllBlockBoundaries(for: state, upTo: inferenceStopPosition) {
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
      inferredStateOrNil = self.performInference(for: initialState, upTo: InstructionPosition(basicBlock: program.startBlock, instructionIndex: 0))
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
