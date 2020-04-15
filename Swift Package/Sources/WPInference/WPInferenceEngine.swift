import IR

fileprivate struct WPInferenceState {
  /// The position up to which WP-inference has run.
  /// This means that the instruction at this position **has already been inferred**.
  var position: InstructionPosition
  
  /// The term that has been inferred so far up to this program position.
  var term: WPTerm
}

public class WPInferenceEngine {
  private let program: IRProgram
  
  public init(program: IRProgram) {
    self.program = program
  }
  
  private func inferAcrossBlockBoundary(state: WPInferenceState, predecessor: BasicBlockName) -> (position: InstructionPosition, term: WPTerm) {
    assert(state.position.instructionIndex == 0)
    
    let branchPosition = InstructionPosition(
      basicBlock: predecessor,
      instructionIndex: program.basicBlocks[predecessor]!.instructions.count - 1
    )
    let instruction = program.instruction(at: branchPosition)
    switch instruction {
    case is JumpInstruction:
      // The jump jumps unconditionally, so there is no need to modify the state
      return (branchPosition, state.term)
    case let instruction as BranchInstruction:
      let takenBranch: Bool
      if state.position.basicBlock == instruction.targetTrue {
        takenBranch = true
      } else {
        assert(state.position.basicBlock == instruction.targetFalse)
        takenBranch = false
      }
      return (branchPosition, .boolToInt(.equal(lhs: WPTerm(instruction.condition), rhs: .bool(takenBranch))) * state.term)
    default:
      fatalError("Block that jumps to a different block should have terminated with a jump or branch instruction")
    }
  }
  
  private func branchesToInfer(before state: WPInferenceState) -> [(position: InstructionPosition, term: WPTerm)] {
    if state.position.instructionIndex > 0 {
      let previousPosition = InstructionPosition(basicBlock: state.position.basicBlock, instructionIndex: state.position.instructionIndex - 1)
      
      if let phiInstruction = program.instruction(at: previousPosition) as? PhiInstruction {
        // FIXME: Handle multiple Phi instructions
        return program.directPredecessors[state.position.basicBlock]!.map({ (predecessor) in
          let newState = WPInferenceState(
            position: previousPosition,
            term: state.term.replacing(variable: phiInstruction.assignee, with: .variable(phiInstruction.choices[predecessor]!))
          )
          return inferAcrossBlockBoundary(state: newState, predecessor: predecessor)
        })
      }
      return [(position: previousPosition, term: state.term)]
    } else {
      return program.directPredecessors[state.position.basicBlock]!.map({ (predecessor) in
        return inferAcrossBlockBoundary(state: state, predecessor: predecessor)
      })
    }
  }
  
  public func infer(term: WPTerm) -> Double {
    let programStartState = InstructionPosition(basicBlock: program.startBlock, instructionIndex: 0)
    
    var inferenceStatesWorklist: [WPInferenceState] = [WPInferenceState(position: program.returnPosition, term: term)]
    var finishedInferenceStates: [WPInferenceState] = []
    
    while let worklistEntry = inferenceStatesWorklist.popLast() {
      for (position, term) in self.branchesToInfer(before: worklistEntry) {
        let newStateToInfer: WPInferenceState
        switch program.instruction(at: position) {
        case let instruction as AssignInstruction:
          let newTerm = term.replacing(
            variable: instruction.assignee,
            with: WPTerm(instruction.value)
          )
          newStateToInfer = WPInferenceState(
            position: position,
            term: newTerm
          )
        case let instruction as AddInstruction:
          let newTerm = term.replacing(
            variable: instruction.assignee,
            with: WPTerm(instruction.lhs) + WPTerm(instruction.rhs)
          )
          newStateToInfer = WPInferenceState(
            position: position,
            term: newTerm
          )
        case let instruction as SubtractInstruction:
          let newTerm = term.replacing(
            variable: instruction.assignee,
            with: WPTerm(instruction.lhs) - WPTerm(instruction.rhs)
          )
          newStateToInfer = WPInferenceState(
            position: position,
            term: newTerm
          )
        case let instruction as CompareInstruction:
          let newTerm = term.replacing(
            variable: instruction.assignee,
            with: .equal(lhs: WPTerm(instruction.lhs), rhs: WPTerm(instruction.rhs))
          )
          newStateToInfer = WPInferenceState(position: position, term: newTerm)
        case let instruction as DiscreteDistributionInstruction:
          var terms: [WPTerm] = []
          for (value, probability) in instruction.distribution {
            let term = .double(probability) * term.replacing(variable: instruction.assignee, with: .integer(value))
            terms.append(term)
          }
          newStateToInfer = WPInferenceState(
            position: position,
            term: .add(terms: terms)
          )
        case let instruction as ObserveInstruction:
          fatalError("not implemented: \(instruction)")
        case is JumpInstruction:
          // Already handled by branchesToInfer. Nothing to do anymore.
          newStateToInfer = WPInferenceState(position: position, term: term)
        case is BranchInstruction:
          // Already handled by branchesToInfer. Nothing to do anymore.
          newStateToInfer = WPInferenceState(position: position, term: term)
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
    
    let combinedTerm = WPTerm.add(terms: finishedInferenceStates.map(\.term))
    
    switch combinedTerm.simplified {
    case .integer(let value):
      return Double(value)
    case .double(let value):
      return value
    case let simplifiedTerm:
      fatalError("WP evaluation term \(simplifiedTerm) (original: \(combinedTerm) was not fully simplified")
    }
  }
}
