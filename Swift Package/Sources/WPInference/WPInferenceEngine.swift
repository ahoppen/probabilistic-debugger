import IR

/// A specification of a loop in an IR program. The loop is characterised by the branch that jumps into the loop's body and the basic block that contains the first instructions of the loop's body. This is, the branch may jump to the body block.
public struct LoopSpec: Hashable {
  /// The instruction that jumps into the loops body
  public let branchingInstruction: InstructionPosition
  
  /// The block that contains the first instructions of the loop body.
  public let bodyBlock: BasicBlockName
  
  public init(branchingInstruction: InstructionPosition, bodyBlock: BasicBlockName) {
    self.branchingInstruction = branchingInstruction
    self.bodyBlock = bodyBlock
  }
}

fileprivate struct WPInferenceState {
  /// The position up to which WP-inference has run.
  /// This means that the instruction at this position **has already been inferred**.
  let position: InstructionPosition
  
  /// The term that has been inferred so far up to this program position.
  let term: WPTerm
  
  /// To allow WP-inference of loops without finding fixpoints for finding loop invariants, we set an upper limit on the number of loop iterations for each loop in the program.
  /// This dictionary keeps track of how many iterations we have left in each loop before aborting WP-inference.
  let remainingLoopRepetitions: [LoopSpec: Int]
  
  init(position: InstructionPosition, term: WPTerm, remainingLoopRepetitions: [LoopSpec: Int]) {
    self.position = position
    self.term = term.simplified
    self.remainingLoopRepetitions = remainingLoopRepetitions
  }
}

public class WPInferenceEngine {
  private let program: IRProgram
  
  public init(program: IRProgram) {
    self.program = program
  }
  
  /// Given a state that is pointed to the first instruction in a basic block and a predecessor block of this state, move the instruction position to the predecessor block and perform WP-inference for the branch or jump instruction in the predecessor block.
  private func inferAcrossBlockBoundary(state: WPInferenceState, predecessor: BasicBlockName) -> (position: InstructionPosition, term: WPTerm, remainingLoopRepetitions: [LoopSpec: Int])? {
    assert(state.position.instructionIndex == 0)
    assert(program.directPredecessors[state.position.basicBlock]!.contains(predecessor))
    
    // Compute the instruction position of the new inference state
    var remainingLoopIterations = state.remainingLoopRepetitions
    let predecessorBlockPosition = InstructionPosition(
      basicBlock: predecessor,
      instructionIndex: program.basicBlocks[predecessor]!.instructions.count - 1
    )
    
    // Check if we are at a loop for which we have have an upper bound on the number of iterations
    let loopSpec = LoopSpec(branchingInstruction: predecessorBlockPosition, bodyBlock: state.position.basicBlock)
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
      return (predecessorBlockPosition, state.term, remainingLoopIterations)
    case let instruction as BranchInstruction:
      let takenBranch: Bool
      if state.position.basicBlock == instruction.targetTrue {
        takenBranch = true
      } else {
        assert(state.position.basicBlock == instruction.targetFalse)
        takenBranch = false
      }
      return (predecessorBlockPosition,
              .boolToInt(.equal(lhs: WPTerm(instruction.condition), rhs: .bool(takenBranch))) * state.term,
              remainingLoopIterations)
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
      let newTerm = state.term.replacing(variable: instruction.assignee, with: .variable(instruction.choices[predecessorBlock]!))
      state = WPInferenceState(position: newPosition, term: newTerm, remainingLoopRepetitions: state.remainingLoopRepetitions)
    }
    return state
  }
  
  /// Given an inference state, return all the components of `WPInferenceState` at which inference should continue. Note that the instruction at `position` has **not** been executed yet.
  /// The final inference result is determined by summing the values retrieved by inferring all the returned branches.
  private func branchesToInfer(before state: WPInferenceState) -> [(position: InstructionPosition, term: WPTerm, remainingLoopRepetitions: [LoopSpec: Int])] {
    if state.position.instructionIndex > 0 {
      let previousPosition = InstructionPosition(basicBlock: state.position.basicBlock, instructionIndex: state.position.instructionIndex - 1)
      
      if program.instruction(at: previousPosition) is PhiInstruction {
        // Evaluate all Phi instructions in the current block and jump to the predecessor blocks.
        return program.directPredecessors[state.position.basicBlock]!.sorted(by: { $0.name < $1.name }).compactMap({ (predecessor) in
          let stateAtBeginningOfBlock = evalutePhiInstructions(in: state, predecessorBlock: predecessor)
          return inferAcrossBlockBoundary(state: stateAtBeginningOfBlock, predecessor: predecessor)
        })
      } else {
        // We are at a normal instruction, just adjust the position to the previous one and return all the values
        return [(position: previousPosition, term: state.term, state.remainingLoopRepetitions)]
      }
    } else {
      // We have reached the start of a block. Continue inference in the predecessor blocks.
      return program.directPredecessors[state.position.basicBlock]!.sorted(by: { $0.name < $1.name }).compactMap({ (predecessor) in
        return inferAcrossBlockBoundary(state: state, predecessor: predecessor)
      })
    }
  }
  
  /// Perform WP-inference on the given `term` using the program for which this inference engine was constructed.
  /// If the program contains loops, `loopRepetitionBounds` need to be specified that bound the number of loop iterations the WP-inference should perform.
  public func infer(loopRepetitionBounds: [LoopSpec: Int] = [:], term: WPTerm) -> Double {
    let programStartState = InstructionPosition(basicBlock: program.startBlock, instructionIndex: 0)
    
    // WPInferenceStates that have not yet reached the start of the program and for which further inference needs to be performed
    var inferenceStatesWorklist: [WPInferenceState] = [WPInferenceState(position: program.returnPosition, term: term, remainingLoopRepetitions: loopRepetitionBounds)]
    
    // WPInferenceStates that have reached the start of the program. The sum of these state's terms determines the final result
    var finishedInferenceStates: [WPInferenceState] = []
    
    while let worklistEntry = inferenceStatesWorklist.popLast() {
      // Pop one entry of the worklist and perform WP-inference for it
      
      for (position, term, remainingLoopRepetitions) in self.branchesToInfer(before: worklistEntry) {
        
        let newStateToInfer: WPInferenceState
        let instruction = program.instruction(at: position)!
        switch instruction {
        case is AssignInstruction, is AddInstruction, is SubtractInstruction, is CompareInstruction:
          // Instructions that assign a new term to a variable
          let replacementTerm: WPTerm
          switch instruction {
          case let instruction as AssignInstruction:
            replacementTerm = WPTerm(instruction.value)
          case let instruction as AddInstruction:
            replacementTerm = WPTerm(instruction.lhs) + WPTerm(instruction.rhs)
          case let instruction as SubtractInstruction:
            replacementTerm = WPTerm(instruction.lhs) - WPTerm(instruction.rhs)
          case let instruction as CompareInstruction:
            switch instruction.comparison {
            case .equal:
              replacementTerm = .equal(lhs: WPTerm(instruction.lhs), rhs: WPTerm(instruction.rhs))
            case .lessThan:
              replacementTerm = .lessThan(lhs: WPTerm(instruction.lhs), rhs: WPTerm(instruction.rhs))
            }
          default:
            fatalError()
          }
          let newTerm = term.replacing(variable: instruction.assignedVariable!, with: replacementTerm)
          newStateToInfer = WPInferenceState(position: position, term: newTerm, remainingLoopRepetitions: remainingLoopRepetitions)
        case let instruction as DiscreteDistributionInstruction:
          let terms = instruction.distribution.map({ (value, probability) in
            return .double(probability) * term.replacing(variable: instruction.assignee, with: .integer(value))
          })
          newStateToInfer = WPInferenceState(position: position, term: .add(terms: terms), remainingLoopRepetitions: remainingLoopRepetitions)
        case let instruction as ObserveInstruction:
          fatalError("not implemented: \(instruction)")
        case is JumpInstruction:
          // Already handled by branchesToInfer. Nothing to do anymore.
          newStateToInfer = WPInferenceState(position: position, term: term, remainingLoopRepetitions: remainingLoopRepetitions)
        case is BranchInstruction:
          // Already handled by branchesToInfer. Nothing to do anymore.
          newStateToInfer = WPInferenceState(position: position, term: term, remainingLoopRepetitions: remainingLoopRepetitions)
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
