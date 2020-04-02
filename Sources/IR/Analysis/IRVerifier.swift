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
    IRVerifier.verifyOnlyOneBlockWithoutJumpAsLastStatement(ir: ir)
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
  
  /// There should only be one block that doesn't have branch or jump as the last statement and thus terminates the program execution
  private static func verifyOnlyOneBlockWithoutJumpAsLastStatement(ir: IRProgram) {
    var foundBlockWithoutBranch = false
    for block in ir.basicBlocks.values {
      switch block.instructions.last {
      case is ConditionalBranchInstr, is JumpInstr:
        break
      default:
        if foundBlockWithoutBranch {
          fatalError("There exist two basic blocks that terminate the program execution (by not having a jump or branch as the last instruction)")
        }
        foundBlockWithoutBranch = true
      }
    }
  }
  
  private static func verifyAllJumpedToBlocksExist(ir: IRProgram) {
    for block in ir.basicBlocks.values {
      for instruction in block.instructions {
        if let jumpInstr = instruction as? JumpInstr {
          if ir.basicBlocks[jumpInstr.target] == nil {
            fatalError("Jump to \(jumpInstr.target) but basic block does not exist")
          }
        }
        if let branchInstr = instruction as? ConditionalBranchInstr {
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
        guard let phiInstruction = instruction as? PhiInstr else {
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
        if !(instruction is PhiInstr) {
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
      for instr in block.instructions {
        if instr is PhiInstr, !inPhiInstructionSection {
          fatalError("Found a Phi-Instruction that's not at the start of a basic block")
        }
        if !(instr is PhiInstr) {
          inPhiInstructionSection = false
        }
      }
    }
  }
}
