fileprivate extension BasicBlock {
  var declaredVariables: Set<IRVariable> {
    return Set(instructions.compactMap({
      $0.assignedVariable
    }))
  }
}

public enum IRVerifier {
  public static func verify(ir: IRProgram) {
    IRVerifier.verifyAllBlocksReachable(ir: ir)
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
  
  private static func verifyAllVariablesDeclaredBeforeUse(ir: IRProgram) {
    for block in ir.basicBlocks {
      var declaredVariables = Set(ir.properPredominators[block.name]!.flatMap({ (blockName) -> Set<IRVariable> in
        return ir[blockName].declaredVariables
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
    for block in ir.basicBlocks {
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
