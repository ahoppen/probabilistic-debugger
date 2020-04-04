extension Set {
  static func intersection(of sets: [Set<Element>]) -> Set<Element> {
    guard let first = sets.first else {
      return []
    }
    var intersection = first
    for set in sets.dropFirst() {
      intersection.formIntersection(set)
    }
    return intersection
  }
}

enum IRAnalysis {
  static func directPredecessors<BasicBlocksType: Sequence>(basicBlocks: BasicBlocksType) -> [BasicBlockName: Set<BasicBlockName>] where BasicBlocksType.Element == BasicBlock {
    var predecessors: [BasicBlockName: Set<BasicBlockName>] = [:]
    // Initialise with no predecessors
    for basicBlock in basicBlocks {
      predecessors[basicBlock.name] = []
    }
    
    for basicBlock in basicBlocks {
      for instruction in basicBlock.instructions {
        if let jumpInstr = instruction as? JumpInstruction {
          predecessors[jumpInstr.target] = predecessors[jumpInstr.target]!.union([basicBlock.name])
        } else if let branchInstr = instruction as? BranchInstruction {
          predecessors[branchInstr.targetTrue] = predecessors[branchInstr.targetTrue]!.union([basicBlock.name])
          predecessors[branchInstr.targetFalse] = predecessors[branchInstr.targetFalse]!.union([basicBlock.name])
        }
      }
    }
    return predecessors
  }
  
  static func directSuccessors<BasicBlocksType: Sequence>(basicBlocks: BasicBlocksType) -> [BasicBlockName: Set<BasicBlockName>] where BasicBlocksType.Element == BasicBlock {
    var successors: [BasicBlockName: Set<BasicBlockName>] = [:]
    // Initialise with no predecessors
    for basicBlock in basicBlocks {
      let lastInstruction = basicBlock.instructions.last!
      switch lastInstruction {
      case let instruction as BranchInstruction:
        successors[basicBlock.name] = [instruction.targetTrue, instruction.targetFalse]
      case let instruction as JumpInstruction:
        successors[basicBlock.name] = [instruction.target]
      case is ReturnInstruction:
        successors[basicBlock.name] = []
      default:
        fatalError("Last instruction in a basic block must be a jumping instruction")
      }
    }
    
    return successors
  }
  
  static func predominators(directPredecessors: [BasicBlockName: Set<BasicBlockName>], startBlock: BasicBlockName) -> [BasicBlockName: Set<BasicBlockName>] {
    var predominators = [BasicBlockName: Set<BasicBlockName>]()
    let allBasicBlockNames = Set(directPredecessors.keys)
    for basicBlockName in allBasicBlockNames {
      predominators[basicBlockName] = allBasicBlockNames
    }
    predominators[startBlock] = [startBlock]
    
    var converged = false
    while !converged {
      converged = true
      for basicBlockName in allBasicBlockNames {
        let newValue = Set.intersection(of: directPredecessors[basicBlockName]!.map({ predominators[$0]! })).union([basicBlockName])
        if newValue != predominators[basicBlockName]! {
          converged = false
          predominators[basicBlockName] = newValue
        }
      }
    }

    return predominators
  }
  
  static func postdominators(directSuccessors: [BasicBlockName: Set<BasicBlockName>], startBlock: BasicBlockName) -> [BasicBlockName: Set<BasicBlockName>] {
    var postdominators = [BasicBlockName: Set<BasicBlockName>]()
    let allBasicBlockNames = Set(directSuccessors.keys)
    for basicBlockName in allBasicBlockNames {
      postdominators[basicBlockName] = allBasicBlockNames
    }
    for (basicBlockName, successors) in directSuccessors {
      if successors.isEmpty {
        postdominators[basicBlockName] = [basicBlockName]
      }
    }

    var converged = false
    while !converged {
      converged = true
      for basicBlockName in allBasicBlockNames {
        let newValue = Set.intersection(of: directSuccessors[basicBlockName]!.map({ postdominators[$0]! })).union([basicBlockName])
        if newValue != postdominators[basicBlockName]! {
          converged = false
          postdominators[basicBlockName] = newValue
        }
      }
    }

    return postdominators
  }
  
  static func properDominators(dominators: [BasicBlockName: Set<BasicBlockName>]) -> [BasicBlockName: Set<BasicBlockName>] {
    var properDominators = [BasicBlockName: Set<BasicBlockName>]()
    for (blockName, dominators) in dominators {
      properDominators[blockName] = dominators.subtracting([blockName])
    }
    return properDominators
  }
  
  static func immediateDominator(properDominators: [BasicBlockName: Set<BasicBlockName>]) -> [BasicBlockName: BasicBlockName?] {
    var immediateDominators: [BasicBlockName: BasicBlockName?] = [:]
    for (blockName, properDominatorsOfBlock) in properDominators {
      let nonImmediateDominators = properDominatorsOfBlock.flatMap({ properDominators[$0]! })
      let immediateDominatorsOfBlock = properDominatorsOfBlock.subtracting(nonImmediateDominators)
      assert(immediateDominatorsOfBlock.count <= 1, "A block should have at most one immediate dominator")
      immediateDominators[blockName] = immediateDominatorsOfBlock.first
    }
    return immediateDominators
  }
}
