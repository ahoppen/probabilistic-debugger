fileprivate extension BasicBlock {
  var declaredVariables: Set<IRVariable> {
    return Set(instructions.compactMap({
      $0.assignedVariable
    }))
  }
}

public enum IRVerifier {
  public static func verify(ir: IRProgram) {
    IRVerifier.verifyAllJumpedToBlocksExist(ir: ir)
    IRVerifier.verifyAllBlocksReachable(ir: ir)
    IRVerifier.verifyPhiStatementsCoverAllPredecessorBlocks(ir: ir)
    IRVerifier.verifyNoJumpingInstructionInMiddleOfBlock(ir: ir)
    IRVerifier.verifyAllBlocksEndWithJumpingInstruction(ir: ir)
    IRVerifier.verifyOnlyOneBlockEndsWithReturnInstruction(ir: ir)
    IRVerifier.verifyAllVariablesDeclaredBeforeUse(ir: ir)
    IRVerifier.verifyPhiInstructionsAtStartOfBlock(ir: ir)
  }
  
  private static func verifyAllBlocksReachable(ir: IRProgram) {
    for (blockName, predecessors) in ir.directPredecessors {
      if blockName != ir.startBlock && predecessors.isEmpty {
        fatalError("Basic Block \(blockName) is not reachable")
      }
    }
  }
  
  private static func verifyAllBlocksEndWithJumpingInstruction(ir: IRProgram) {
    for block in ir.basicBlocks.values {
      switch block.instructions.last {
      case is BranchInstruction, is JumpInstruction, is ReturnInstruction:
        break
      default:
        fatalError("Basic block \(block.name) does not end with a jump, branch or return instruction")
      }
    }
  }
  
  private static func verifyOnlyOneBlockEndsWithReturnInstruction(ir: IRProgram) {
    var foundReturnInstruction = false
    for block in ir.basicBlocks.values {
      if block.instructions.last is ReturnInstruction {
        if foundReturnInstruction {
          fatalError("Two blocks end with a return instruction")
        } else {
          foundReturnInstruction = true
        }
      }
    }
  }
  
  private static func verifyNoJumpingInstructionInMiddleOfBlock(ir: IRProgram) {
    for block in ir.basicBlocks.values {
      for instruction in block.instructions.dropLast() {
        switch instruction {
        case is BranchInstruction, is JumpInstruction, is ReturnInstruction:
          fatalError("Basic block \(block.name) has a branching instruction that's not at the end of the block")
        default:
          break
        }
      }
    }
  }
  
  private static func verifyAllJumpedToBlocksExist(ir: IRProgram) {
    for block in ir.basicBlocks.values {
      for instruction in block.instructions {
        if let jumpInstr = instruction as? JumpInstruction {
          if ir.basicBlocks[jumpInstr.target] == nil {
            fatalError("Jump to \(jumpInstr.target) but basic block does not exist")
          }
        }
        if let branchInstr = instruction as? BranchInstruction {
          if ir.basicBlocks[branchInstr.targetTrue] == nil {
            fatalError("Branch to \(branchInstr.targetTrue) but basic block does not exist")
          }
          if ir.basicBlocks[branchInstr.targetFalse] == nil {
            fatalError("Branch to \(branchInstr.targetFalse) but basic block does not exist")
          }
        }
      }
    }
  }
  
  private static func verifyPhiStatementsCoverAllPredecessorBlocks(ir: IRProgram) {
    for block in ir.basicBlocks.values {
      for instruction in block.instructions {
        guard let phiInstruction = instruction as? PhiInstruction else {
          continue
        }
        if Set(phiInstruction.choices.keys) != ir.directPredecessors[block.name] {
          fatalError("The choices of the phi instruction \(instruction) don't match its predecessors \(ir.directPredecessors[block.name]!)")
        }
      }
    }
  }
  
  private static func verifyAllVariablesDeclaredBeforeUse(ir: IRProgram) {
    for block in ir.basicBlocks.values {
      var declaredVariables = Set(ir.properPredominators[block.name]!.flatMap({ (blockName) -> Set<IRVariable> in
        return ir.basicBlocks[blockName]!.declaredVariables
      }))
      for instruction in block.instructions {
        if !(instruction is PhiInstruction) {
          for usedVariable in instruction.usedVariables {
            if !declaredVariables.contains(usedVariable) {
              fatalError("Variable \(usedVariable) may not be defined before it is used")
            }
          }
        }
        if let assignedVariable = instruction.assignedVariable {
          declaredVariables.insert(assignedVariable)
        }
      }
    }
  }
  
  private static func verifyPhiInstructionsAtStartOfBlock(ir: IRProgram) {
    for block in ir.basicBlocks.values {
      var inPhiInstructionSection = true
      for instruction in block.instructions {
        if instruction is PhiInstruction, !inPhiInstructionSection {
          fatalError("Found a Phi-Instruction that's not at the start of a basic block")
        }
        if !(instruction is PhiInstruction) {
          inPhiInstructionSection = false
        }
      }
    }
  }
}
