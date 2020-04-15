import IR

fileprivate struct WPInferenceState {
  var position: InstructionPosition?
  
  var term: WPTerm
}

public class WPInferenceEngine {
  private let program: IRProgram
  
  public init(program: IRProgram) {
    self.program = program
  }
  
  private func preceedingInstructionPosition(of position: InstructionPosition) -> InstructionPosition? {
    if position.instructionIndex > 0 {
      return InstructionPosition(basicBlock: position.basicBlock, instructionIndex: position.instructionIndex - 1)
    } else {
      let predecessorBlocks = program.directPredecessors[position.basicBlock]!
      if predecessorBlocks.isEmpty {
        return nil
      } else {
        assert(predecessorBlocks.count <= 1, "Multi-block predecessors not implemented yet")
        let predecessorBlock = predecessorBlocks.first!
        let instructionIndex = program.basicBlocks[predecessorBlock]!.instructions.count - 1
        return InstructionPosition(basicBlock: predecessorBlock, instructionIndex: instructionIndex)
      }
    }
  }
  
  public func infer(term: WPTerm) -> WPTerm {
    var inferenceState = WPInferenceState(position: program.returnPosition, term: term)
    
    while let position = inferenceState.position {
      switch program.instruction(at: position) {
      case is ReturnInstruction:
        inferenceState.position = preceedingInstructionPosition(of: position)
      case let instruction as AssignInstruction:
        inferenceState.term = inferenceState.term.replacing(variable: instruction.assignee, with: WPTerm(instruction.value))
        inferenceState.position = preceedingInstructionPosition(of: position)
      case let instruction as AddInstruction:
        inferenceState.term = inferenceState.term.replacing(variable: instruction.assignee, with: .add(lhs: WPTerm(instruction.lhs), rhs: WPTerm(instruction.rhs)))
        inferenceState.position = preceedingInstructionPosition(of: position)
      case let instruction as SubtractInstruction:
        inferenceState.term = inferenceState.term.replacing(variable: instruction.assignee, with: .sub(lhs: WPTerm(instruction.lhs), rhs: WPTerm(instruction.rhs)))
        inferenceState.position = preceedingInstructionPosition(of: position)
      case let instruction as CompareInstruction:
        fatalError("not implemented: \(instruction)")
      case let instruction as DiscreteDistributionInstruction:
        fatalError("not implemented: \(instruction)")
      case let instruction as ObserveInstruction:
        fatalError("not implemented: \(instruction)")
      case let instruction as JumpInstruction:
        fatalError("not implemented: \(instruction)")
      case let instruction as BranchInstruction:
        fatalError("not implemented: \(instruction)")
      case let instruction as PhiInstruction:
        fatalError("not implemented: \(instruction)")
      default:
        fatalError("Unknown instruction: \(type(of: program.instruction(at: position)))")
      }
    }
    
    return inferenceState.term.simplified
  }
}
