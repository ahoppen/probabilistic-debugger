import IR

/// A specification of a looping branch in the IR program characterised by the basic block that contains the condition and the basic block that contains the start of the loop's body.
/// There should be a path from the `bodyBlock` to the `conditionBlock` in the program.
public struct LoopingBranch: Hashable {
  /// The basic block that contains the condition of the loop
  public let conditionBlock: BasicBlockName
  
  /// The block that contains the first instructions of the loop body.
  public let bodyBlock: BasicBlockName
  
  public init(conditionBlock: BasicBlockName, bodyBlock: BasicBlockName) {
    self.conditionBlock = conditionBlock
    self.bodyBlock = bodyBlock
  }
}

fileprivate struct WPInferenceState {
  /// The position up to which WP-inference has run.
  /// This means that the instruction at this position **has already been inferred**.
  let position: InstructionPosition
  
  /// The term that has been inferred so far up to this program position.
  let term: WPTerm
  
  /// A term that after full inference determines the fraction of all runs that satisfies all observes in the program.
  /// This is a normalization term that boost the sum of the probability distribution up to 1 again after samples have been lost through `observe`s.
  let runsWithSatisifiedObserves: WPTerm
  
  /// A term that after full inference determines the fraction of all runs that were not discareded because we bounded the number of loop iterations.
  /// If using `runsWithSatisifiedObserves` as a normalization factor, we always end up at a probability sum of `1`.
  /// If we have discarded runs because of the maximum number of loop iterations, we don't, however, want to end up at a probability sum of `1` but want to explicitly state which percentag of all runs was not considered.
  /// Hence this normalization term pushes the probability sum down below `1` again if runs were discared.
  /// The final normalized value is determined by `term / runsWithSatisfiedObserves * runsNotCutOffByLoopIterationBounds`
  let runsNotCutOffByLoopIterationBounds: WPTerm
  
  /// To allow WP-inference of loops without finding fixpoints for finding loop invariants, we set an upper limit on the number of loop iterations for each loop in the program.
  /// This dictionary keeps track of how many iterations we have left in each loop before aborting WP-inference.
  let remainingLoopRepetitions: [LoopingBranch: Int]
  
  init(position: InstructionPosition, term: WPTerm, runsWithSatisifiedObserves: WPTerm, runsNotCutOffByLoopIterationBounds: WPTerm, remainingLoopRepetitions: [LoopingBranch: Int]) {
    self.position = position
    self.term = term.simplified
    self.runsWithSatisifiedObserves = runsWithSatisifiedObserves
    self.runsNotCutOffByLoopIterationBounds = runsNotCutOffByLoopIterationBounds
    self.remainingLoopRepetitions = remainingLoopRepetitions
  }
  
  func replacing(variable: IRVariable, by replacementTerm: WPTerm) -> WPInferenceState {
    return self.updatingTerms({
      return $0.replacing(variable: variable, with: replacementTerm)
    })
  }
  
  func updatingTerms(keepingRunsNotCutOffByLoopIterationBounds: Bool = false, _ update: (WPTerm) -> WPTerm) -> WPInferenceState {
    return WPInferenceState(
      position: position,
      term: update(term),
      runsWithSatisifiedObserves: update(runsWithSatisifiedObserves),
      runsNotCutOffByLoopIterationBounds: keepingRunsNotCutOffByLoopIterationBounds ? runsNotCutOffByLoopIterationBounds : update(runsNotCutOffByLoopIterationBounds),
      remainingLoopRepetitions: remainingLoopRepetitions
    )
  }
  
  func withPosition(_ newPosition: InstructionPosition) -> WPInferenceState {
    return WPInferenceState(
      position: newPosition,
      term: term,
      runsWithSatisifiedObserves: runsWithSatisifiedObserves,
      runsNotCutOffByLoopIterationBounds: runsNotCutOffByLoopIterationBounds,
      remainingLoopRepetitions: remainingLoopRepetitions
    )
  }
  
  func withRemainingLoopIterations(_ remainingLoopIterations: [LoopingBranch: Int]) -> WPInferenceState {
    return WPInferenceState(
      position: position,
      term: term,
      runsWithSatisifiedObserves: runsWithSatisifiedObserves,
      runsNotCutOffByLoopIterationBounds: runsNotCutOffByLoopIterationBounds,
      remainingLoopRepetitions: remainingLoopIterations
    )
  }
}

public class WPInferenceEngine {
  private let program: IRProgram
  
  public init(program: IRProgram) {
    self.program = program
  }
  
  /// Given a state that is pointed to the first instruction in a basic block and a predecessor block of this state, move the instruction position to the predecessor block and perform WP-inference for the branch or jump instruction in the predecessor block.
  private func inferAcrossBlockBoundary(state: WPInferenceState, predecessor: BasicBlockName) -> WPInferenceState? {
    assert(state.position.instructionIndex == 0)
    assert(program.directPredecessors[state.position.basicBlock]!.contains(predecessor))
    
    // Compute the instruction position of the new inference state
    var remainingLoopIterations = state.remainingLoopRepetitions
    let predecessorBlockPosition = InstructionPosition(
      basicBlock: predecessor,
      instructionIndex: program.basicBlocks[predecessor]!.instructions.count - 1
    )
    
    // Check if we are at a loop for which we have have an upper bound on the number of iterations
    let loopSpec = LoopingBranch(conditionBlock: predecessorBlockPosition.basicBlock, bodyBlock: state.position.basicBlock)
    if let remainingIterations = state.remainingLoopRepetitions[loopSpec] {
      if remainingIterations == 0 {
        return nil
      } else {
        remainingLoopIterations[loopSpec] = remainingIterations - 1
      }
    }
    
    // Perform WP-inference for the branch or jump instruction
    let instruction = program.instruction(at: predecessorBlockPosition)
    switch instruction {
    case is JumpInstruction:
      // The jump jumps unconditionally, so there is no need to modify the state's term
      return state
        .withPosition(predecessorBlockPosition)
        .withRemainingLoopIterations(remainingLoopIterations)
    case let instruction as BranchInstruction:
      let takenBranch: Bool
      if state.position.basicBlock == instruction.targetTrue {
        takenBranch = true
      } else {
        assert(state.position.basicBlock == instruction.targetFalse)
        takenBranch = false
      }
      return state
        .withPosition(predecessorBlockPosition)
        .withRemainingLoopIterations(remainingLoopIterations)
        .updatingTerms({ .boolToInt(.equal(lhs: WPTerm(instruction.condition), rhs: .bool(takenBranch))) * $0 })
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
      state = state
        .withPosition(newPosition)
        .updatingTerms({ $0.replacing(variable: instruction.assignee, with: .variable(instruction.choices[predecessorBlock]!)) })
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
        return program.directPredecessors[state.position.basicBlock]!.sorted().compactMap({ (predecessor) in
          let stateAtBeginningOfBlock = evalutePhiInstructions(in: state, predecessorBlock: predecessor)
          return inferAcrossBlockBoundary(state: stateAtBeginningOfBlock, predecessor: predecessor)
        })
      } else {
        // We are at a normal instruction, just adjust the position to the previous one and return all the values
        return [state.withPosition(previousPosition)]
      }
    } else {
      // We have reached the start of a block. Continue inference in the predecessor blocks.
      return program.directPredecessors[state.position.basicBlock]!.sorted().compactMap({ (predecessor) in
        return inferAcrossBlockBoundary(state: state, predecessor: predecessor)
      })
    }
  }
  
  public func inferProbability(of variable: IRVariable, beingEqualTo value: VariableOrValue, loopRepetitionBounds: [LoopingBranch: Int]) -> Double {
    let inferredTerm = infer(term: .boolToInt(.equal(lhs: .variable(variable), rhs: WPTerm(value))), loopRepetitionBounds: loopRepetitionBounds)
    switch inferredTerm {
    case .integer(let value):
      return Double(value)
    case .double(let value):
      return value
    case let simplifiedTerm:
      fatalError("WP evaluation term \(simplifiedTerm) (original: \(self)) was not fully simplified and thus the probability could not be outputted as a constant")
    }
  }
  
  /// Perform WP-inference on the given `term` using the program for which this inference engine was constructed.
  /// If the program contains loops, `loopRepetitionBounds` need to be specified that bound the number of loop iterations the WP-inference should perform.
  public func infer(term: WPTerm, loopRepetitionBounds: [LoopingBranch: Int] = [:]) -> WPTerm {
    #if DEBUG
    // Check that we have a loop repetition bound for every loop in the program
    for loop in program.loops {
      assert(!loop.isEmpty)
      var foundLoopRepetitionBound = false
      for (block1, block2) in zip(loop, loop.dropFirst() + [loop.first!]) {
        // Iterate through all successors in the loop
        if loopRepetitionBounds[LoopingBranch(conditionBlock: block1, bodyBlock: block2)] != nil {
          foundLoopRepetitionBound = true
          break
        }
      }
      assert(foundLoopRepetitionBound, "No loop repetition bound specified for loop \(loop)")
    }
    #endif
    
    
    
    let programStartState = InstructionPosition(basicBlock: program.startBlock, instructionIndex: 0)
    
    // WPInferenceStates that have not yet reached the start of the program and for which further inference needs to be performed
    let initialState = WPInferenceState(
      position: program.returnPosition,
      term: term,
      runsWithSatisifiedObserves: .integer(1),
      runsNotCutOffByLoopIterationBounds: .integer(1),
      remainingLoopRepetitions: loopRepetitionBounds
    )
    var inferenceStatesWorklist = [initialState]
    
    // WPInferenceStates that have reached the start of the program. The sum of these state's terms determines the final result
    var finishedInferenceStates: [WPInferenceState] = []
    
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
          newStateToInfer = stateToInfer.updatingTerms({ (term) in
            let terms = instruction.distribution.map({ (value, probability) in
              return .double(probability) * term.replacing(variable: instruction.assignee, with: .integer(value))
            })
            return .add(terms: terms)
          })
        case let instruction as ObserveInstruction:
          newStateToInfer = stateToInfer.updatingTerms(keepingRunsNotCutOffByLoopIterationBounds: true, {
            return .boolToInt(WPTerm(instruction.observation)) * $0
          })
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
        if newStateToInfer.position == programStartState {
          finishedInferenceStates.append(newStateToInfer)
        } else {
          inferenceStatesWorklist.append(newStateToInfer)
        }
      }
    }
    
    let value = WPTerm.add(terms: finishedInferenceStates.map(\.term))
    let runsWithSatisifiedObserves = WPTerm.add(terms: finishedInferenceStates.map(\.runsWithSatisifiedObserves))
    let runsNotCutOffByLoopIterationBounds = WPTerm.add(terms: finishedInferenceStates.map(\.runsNotCutOffByLoopIterationBounds))
    
    return (value / runsWithSatisifiedObserves * runsNotCutOffByLoopIterationBounds).simplified
  }
}
