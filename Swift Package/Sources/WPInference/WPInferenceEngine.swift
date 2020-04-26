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
  private let program: IRProgram
  private var inferenceCache: [WPInferenceState: WPInferenceState?] = [:]
  
  public init(program: IRProgram) {
    self.program = program
  }
  
  /// Given a state that is pointed to the first instruction in a basic block and a predecessor block of this state, move the instruction position to the predecessor block and perform WP-inference for the branch or jump instruction in the predecessor block.
  private func inferAcrossBlockBoundary(state: WPInferenceState, predecessor: BasicBlockName) -> [WPInferenceState] {
    if let remainingLoopUnrolls = state.remainingLoopUnrolls[conditionBlock: state.position.basicBlock],
      program.properPredominators[state.position.basicBlock]!.contains(predecessor) {
      // We want to leave a loop to the top. Check if the loop has been unrolled a sufficient number of times
      
      if !remainingLoopUnrolls.canStopUnrolling {
        // All execution branches require at least one more loop unroll. We can't exit the loop to the top yet.
        return []
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
      let newState = state
        .withPosition(predecessorBlockPosition)
      return [newState]
    case let instruction as BranchInstruction:
      var remainingLoopUnrolls = state.remainingLoopUnrolls
      
      // We might have have jumped from the body of a loop
      // Check if we are at a loop for which we have have an upper bound on the number of iterations
      let loop = IRLoop(conditionBlock: predecessorBlockPosition.basicBlock, bodyStartBlock: state.position.basicBlock)
      if let loopUnrolling = remainingLoopUnrolls[loop] {
        if !loopUnrolling.canUnrollOnceMore {
          return []
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
      
      // Compute the branching histories that lead to the predecessor state.
      let newBranchingHistories = state.branchingHistories.compactMap({ (branchingHistory) -> BranchingHistory? in
        var branchingHistory = branchingHistory
        // If we are leaving an any BranchingChoice to the top, shave it off the branching history to allow consuming a deliberate branch underneath it.
        if case .any(predominatedBy: let predominator) = branchingHistory.lastChoice, !program.predominators[predecessor]!.contains(predominator) {
          branchingHistory = branchingHistory.droppingLastChoice()
        }
        
        switch branchingHistory.lastChoice {
        case .choice(source: predecessor, target: state.position.basicBlock):
          // We are taking a deliberate choice. Consider it taken care of by removing it off the list
          return branchingHistory.droppingLastChoice()
        case .any(predominatedBy: let predominator) where program.predominators[predecessor]!.contains(predominator):
          // We are taking an `any` branching choice. Keep it in the list since we might take it again.
          // Note that predominators contains the block itself.
          return branchingHistory
        default:
          return nil
        }
      })
      
      if newBranchingHistories.isEmpty {
        // We haven't jumped into this branch of execution.
        // Dropping inference at this stage would mean that we loose some focusRate.
        // Thus we could not differentiate between the rate that was lost due to deliberate branching choices or due to loop iteration bounds.
        // To fix this up, continue inference with a term that has been marked as beeing intentionally lost.
        // Since this state is only for keeping track of the intentionalLossRate and to keep the focusRate up, set term and observeSatisfactionRate to 0.
        let newBranchingHistories = state.branchingHistories.compactMap({  (branchingHistory) -> BranchingHistory? in
          // Shave off as many branching choices as necessary to expose the BranchingChoice that we have taken.
          for index in (0..<branchingHistory.choices.count).reversed() {
            switch branchingHistory.choices[index] {
            case .choice(source: predecessor, target: let target):
              // We have found the violated branching choice. Remove that choice and any after it
              assert(target != state.position.basicBlock)
              return BranchingHistory(choices: Array(branchingHistory.choices[0..<index]))
            case .choice: // source != predecessor because of case above
              // We have found a branching choice that is unrelated to the one we are looking for. Continue searching.
              continue
            case .any:
              fatalError("We did find a branching choice that was violated")
            }
          }
          return nil
        })
        
        if newBranchingHistories.isEmpty {
          // Might happen if state.branchingHistories contains only empty branching histories
          return []
        } else {
          let newState = WPInferenceState(
            position: predecessorBlockPosition,
            term: .integer(0),
            observeSatisfactionRate: .integer(0),
            focusRate: .boolToInt(.equal(lhs: WPTerm(instruction.condition), rhs: .bool(takenBranch))) * state.focusRate,
            intentionalLossRate: .boolToInt(.equal(lhs: WPTerm(instruction.condition), rhs: .bool(takenBranch))) * state.focusRate,
            generateLostStatesForBlocks: state.generateLostStatesForBlocks,
            remainingLoopUnrolls: remainingLoopUnrolls,
            branchingHistories: newBranchingHistories
          )
          return [newState]
        }
      } else {
        var newStates: [WPInferenceState] = []
        newStates += state
          .withPosition(predecessorBlockPosition)
          .withRemainingLoopUnrolls(remainingLoopUnrolls)
          .withBranchingHistories(newBranchingHistories)
          .updatingTerms(term: true, observeSatisfactionRate: true, focusRate: true, intentionalLossRate: true) {
            return .boolToInt(.equal(lhs: WPTerm(instruction.condition), rhs: .bool(takenBranch))) * $0
          }
        if state.generateLostStatesForBlocks.contains(predecessor) {
          newStates += WPInferenceState(
            position: predecessorBlockPosition,
            term: .integer(0),
            observeSatisfactionRate: .integer(0),
            focusRate: .boolToInt(.equal(lhs: WPTerm(instruction.condition), rhs: .bool(!takenBranch))) * state.focusRate,
            intentionalLossRate: .boolToInt(.equal(lhs: WPTerm(instruction.condition), rhs: .bool(!takenBranch))) * state.focusRate,
            generateLostStatesForBlocks: state.generateLostStatesForBlocks,
            remainingLoopUnrolls: remainingLoopUnrolls,
            branchingHistories: newBranchingHistories
          )
        }
        return newStates
      }
    default:
      fatalError("Block that jumps to a different block should have terminated with a jump or branch instruction")
    }
  }
  
  /// Given a state that is positioned right after a Phi Instruction, perform WP-inference for all Phi instructions in the current block assuming that the previous block was `predecessorBlock`
  private func evalutePhiInstructions(in state: WPInferenceState, predecessorBlock: BasicBlockName) -> WPInferenceState {
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
  private func branchesToInfer(before state: WPInferenceState) -> [WPInferenceState] {
    if state.position.instructionIndex > 0 {
      let previousPosition = InstructionPosition(basicBlock: state.position.basicBlock, instructionIndex: state.position.instructionIndex - 1)
      
      if program.instruction(at: previousPosition) is PhiInstruction {
        // Evaluate all Phi instructions in the current block and jump to the predecessor blocks.
        return program.directPredecessors[state.position.basicBlock]!.sorted().flatMap({ (predecessor) -> [WPInferenceState] in
          let stateAtBeginningOfBlock = evalutePhiInstructions(in: state, predecessorBlock: predecessor)
          return inferAcrossBlockBoundary(state: stateAtBeginningOfBlock, predecessor: predecessor)
        })
      } else {
        // We are at a normal instruction, just adjust the position to the previous one and return all the values
        return [state.withPosition(previousPosition)]
      }
    } else {
      // We have reached the start of a block. Continue inference in the predecessor blocks.
      return program.directPredecessors[state.position.basicBlock]!.sorted().flatMap({ (predecessor) in
        return inferAcrossBlockBoundary(state: state, predecessor: predecessor)
      })
    }
  }
  
  private func performInference(for initialState: WPInferenceState) -> WPInferenceState? {
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
      
      for stateToInfer in self.branchesToInfer(before: worklistEntry) {
        let position = stateToInfer.position
        let newStateToInfer: WPInferenceState
        let instruction = program.instruction(at: position)!
        switch instruction {
        case let instruction as AssignInstruction:
          newStateToInfer = stateToInfer.replacing(variable: instruction.assignee, by: WPTerm(instruction.value))
        case let instruction as AddInstruction:
          newStateToInfer = stateToInfer.replacing(variable: instruction.assignee, by: WPTerm(instruction.lhs) + WPTerm(instruction.rhs))
        case let instruction as SubtractInstruction:
          newStateToInfer = stateToInfer.replacing(variable: instruction.assignee, by: WPTerm(instruction.lhs) - WPTerm(instruction.rhs))
        case let instruction as CompareInstruction:
          switch instruction.comparison {
          case .equal:
            newStateToInfer = stateToInfer.replacing(variable: instruction.assignee, by: .equal(lhs: WPTerm(instruction.lhs), rhs: WPTerm(instruction.rhs)))
          case .lessThan:
            newStateToInfer = stateToInfer.replacing(variable: instruction.assignee, by: .lessThan(lhs: WPTerm(instruction.lhs), rhs: WPTerm(instruction.rhs)))
          }
        case let instruction as DiscreteDistributionInstruction:
          newStateToInfer = stateToInfer.updatingTerms(term: true, observeSatisfactionRate: true, focusRate: true, intentionalLossRate: true) { (term) in
            let terms = instruction.distribution.map({ (value, probability) in
              return .double(probability) * term.replacing(variable: instruction.assignee, with: .integer(value))
            })
            return .add(terms: terms)
          }
        case let instruction as ObserveInstruction:
          newStateToInfer = stateToInfer.updatingTerms(term: true, observeSatisfactionRate: true, focusRate: false, intentionalLossRate: false) {
            return .boolToInt(WPTerm(instruction.observation)) * $0
          }
        case is JumpInstruction, is BranchInstruction:
          // Already handled by branchesToInfer. Nothing to do anymore.
          newStateToInfer = stateToInfer
        case is ReturnInstruction:
          fatalError("WP inference is initialised at the ReturnInstruction which means the ReturnInstruction has already been inferred")
        case is PhiInstruction:
          fatalError("Should always be jumped over by branchesToInfer")
        case let unknownInstruction:
          fatalError("Unknown instruction: \(type(of: unknownInstruction))")
        }
        if newStateToInfer.focusRate.isZero {
          // This state is not contributing anything. There is no point in pursuing it.
        } else if newStateToInfer.position == programStartState {
          // At least one branching history of the state must have been completely taken care of.
          // Otherwise there are branches that we haven't considered which means we have reached the top of the program on a branching path that hasn't been specified in branching histories.
          if newStateToInfer.branchingHistories.contains(where: { $0.isEmpty }) {
            finishedInferenceStates.append(newStateToInfer)
          }
        } else {
          // Check if we already have an inference state with the same characteristics.
          // If we do, combine the terms of newStateToInfer with the existing entry.
          let existingIndex = inferenceStatesWorklist.firstIndex(where: {
            return $0.position == newStateToInfer.position &&
              $0.remainingLoopUnrolls == newStateToInfer.remainingLoopUnrolls &&
              $0.branchingHistories == newStateToInfer.branchingHistories
          })
          if let existingIndex = existingIndex {
            let existingEntry = inferenceStatesWorklist[existingIndex]
            assert(existingEntry.generateLostStatesForBlocks == newStateToInfer.generateLostStatesForBlocks, "generateLostStatesForBlocks should never change")
            
            inferenceStatesWorklist[existingIndex] = WPInferenceState(
              position: existingEntry.position,
              term: WPTerm.add(terms: [existingEntry.term, newStateToInfer.term]),
              observeSatisfactionRate: WPTerm.add(terms: [existingEntry.observeSatisfactionRate, newStateToInfer.observeSatisfactionRate]),
              focusRate: WPTerm.add(terms: [existingEntry.focusRate, newStateToInfer.focusRate]),
              intentionalLossRate: WPTerm.add(terms: [existingEntry.intentionalLossRate, newStateToInfer.intentionalLossRate]),
              generateLostStatesForBlocks: existingEntry.generateLostStatesForBlocks,
              remainingLoopUnrolls: existingEntry.remainingLoopUnrolls,
              branchingHistories: existingEntry.branchingHistories
            )
          } else {
            inferenceStatesWorklist.append(newStateToInfer)
            inferenceStatesWorklist.sort(by: { !program.predominators[$0.position.basicBlock]!.contains($1.position.basicBlock) })
          }
        }
      }
    }
    
    assert(finishedInferenceStates.allSatisfy({ $0.branchingHistories.contains(where: { $0.isEmpty }) }))
    assert(finishedInferenceStates.map(\.position).allEqual)
    assert(finishedInferenceStates.map(\.generateLostStatesForBlocks).allEqual)
    
    guard let firstFinishedState = finishedInferenceStates.first else {
      return nil
    }
    
    return WPInferenceState(
      position: firstFinishedState.position,
      term: WPTerm.add(terms: finishedInferenceStates.map(\.term)),
      observeSatisfactionRate: WPTerm.add(terms: finishedInferenceStates.map(\.observeSatisfactionRate)),
      focusRate: WPTerm.add(terms: finishedInferenceStates.map(\.focusRate)),
      intentionalLossRate: WPTerm.add(terms: finishedInferenceStates.map(\.intentionalLossRate)),
      generateLostStatesForBlocks: firstFinishedState.generateLostStatesForBlocks,
      remainingLoopUnrolls: LoopUnrolls([:]),
      branchingHistories: []
    )
  }
  
  /// Perform WP-inference on the given `term` using the program for which this inference engine was constructed.
  /// If the program contains loops, `loopRepetitionBounds` need to be specified that bound the number of loop iterations the WP-inference should perform.
  /// The function returns the following values:
  ///  - `value`: The result of inferring `term` without any normalization factors applied
  ///  - `runsNotCutOffByLoopIterationBounds`: The proportion of runs that were not cut off because of loop iteration bounds
  ///  - `observeSatisfactionRate`: Based on the runs that were not cut off because of loop iteration bounds, the proportion of runs that satisified all `observe` instructions
  ///  - `intentionalFocusRate`: Based on the runs that were not cut off because of loop iteration bounds, the proportion of all possible runs on which the inferrence was focused via the branching history.
  public func infer(term: WPTerm, loopUnrolls: LoopUnrolls, inferenceStopPosition: InstructionPosition, branchingHistories: [BranchingHistory]) -> (value: WPTerm, runsNotCutOffByLoopIterationBounds: WPTerm, observeSatisfactionRate: WPTerm, intentionalFocusRate: WPTerm) {
    
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
    
    // Generate lost states for all blocks that predominate the block until which inferrence is performed but which are not postdominated by the inferenceStopPosition
    var generateLostStatesForBlocks: Set<BasicBlockName> = []
    for block in program.transitivePredecessors[inferenceStopPosition.basicBlock]! {
      if !program.postdominators[block]!.contains(inferenceStopPosition.basicBlock),
        !program.predominators[block]!.contains(inferenceStopPosition.basicBlock) {
        generateLostStatesForBlocks.insert(block)
      }
    }
    
    // WPInferenceStates that have not yet reached the start of the program and for which further inference needs to be performed
    let initialState = WPInferenceState(
      position: inferenceStopPosition,
      term: term,
      observeSatisfactionRate: .integer(1),
      focusRate: .integer(1),
      intentionalLossRate: .integer(0),
      generateLostStatesForBlocks: generateLostStatesForBlocks,
      remainingLoopUnrolls: loopUnrolls,
      branchingHistories: branchingHistories
    )
    
    let inferredStateOrNil: WPInferenceState?
    
    if let cachedReuslt = inferenceCache[initialState] {
      inferredStateOrNil = cachedReuslt
    } else {
      inferredStateOrNil = self.performInference(for: initialState)
      inferenceCache[initialState] = inferredStateOrNil
    }
    
    guard let inferredState = inferredStateOrNil else {
      // There was no successful inference run of the program. Manually put together the "zero" inference results.
      return (
        value: .integer(0),
        runsNotCutOffByLoopIterationBounds: .integer(0),
        observeSatisfactionRate: .integer(1),
        intentionalFocusRate: .integer(1)
      )
    }
    
    let focusRateSum = inferredState.focusRate
    let intentionalLossRate = inferredState.intentionalLossRate / focusRateSum
    let intentionalFocusRate = (.integer(1) - intentionalLossRate)
    
    assert(0 <= focusRateSum.doubleValue && focusRateSum.doubleValue <= 1)
    assert(0 <= intentionalLossRate.doubleValue && intentionalLossRate.doubleValue <= 1)
    assert(0 <= intentionalFocusRate.doubleValue && intentionalFocusRate.doubleValue <= 1)
    
    return (
      value: inferredState.term,
      runsNotCutOffByLoopIterationBounds: focusRateSum,
      observeSatisfactionRate: (inferredState.observeSatisfactionRate / focusRateSum / intentionalFocusRate),
      intentionalFocusRate: intentionalFocusRate
    )
  }
}

public extension WPInferenceEngine {
  /// Infer the probability that `variable` has the value `value` after executing the program to `inferenceStopPosition`.
  /// If `inferenceStopPosition` is `nil`, inference is done until the end of the program.
  /// If the program contains loops, `loopUnrolls` specifies how often loops should be unrolled.
  func inferProbability(of variable: IRVariable, beingEqualTo value: VariableOrValue, loopUnrolls: LoopUnrolls, to inferenceStopPosition: InstructionPosition, branchingHistories: [BranchingHistory]) -> Double {
    return inferProbability(of: .boolToInt(.equal(lhs: .variable(variable), rhs: WPTerm(value))), loopUnrolls: loopUnrolls, to: inferenceStopPosition, branchingHistories: branchingHistories)
  }
  
  func inferProbability(of term: WPTerm, loopUnrolls: LoopUnrolls, to inferenceStopPosition: InstructionPosition, branchingHistories: [BranchingHistory]) -> Double {
    let inferred = infer(term: term, loopUnrolls: loopUnrolls, inferenceStopPosition: inferenceStopPosition, branchingHistories: branchingHistories)
    let probabilityTerm = (inferred.value / inferred.observeSatisfactionRate / inferred.intentionalFocusRate)
    return probabilityTerm.doubleValue
  }
  
  func reachingProbability(of state: IRExecutionState) -> Double {
    let inferred = self.infer(term: .integer(0), loopUnrolls: state.loopUnrolls, inferenceStopPosition: state.position, branchingHistories: state.branchingHistories)
    return (inferred.observeSatisfactionRate * inferred.intentionalFocusRate).doubleValue
  }
  
  func approximationError(of state: IRExecutionState) -> Double {
    let inferred = self.infer(term: .integer(0), loopUnrolls: state.loopUnrolls, inferenceStopPosition: state.position, branchingHistories: state.branchingHistories)
    return 1 - inferred.runsNotCutOffByLoopIterationBounds.doubleValue
  }
}
