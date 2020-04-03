enum DirectPredecessors {
  static func compute<BasicBlocksType: Sequence>(basicBlocks: BasicBlocksType) -> [BasicBlockName: Set<BasicBlockName>] where BasicBlocksType.Element == BasicBlock {
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
}

enum TransitivePredecessors {
  private static func transitivivePredecessors(of block: BasicBlockName, directPredecessors: [BasicBlockName: Set<BasicBlockName>]) -> Set<BasicBlockName> {
    var predecessors = Set<BasicBlockName>()
    predecessors.formUnion(directPredecessors[block]!)
    for predecessor in directPredecessors[block]! {
      predecessors.formUnion(transitivivePredecessors(of: predecessor, directPredecessors: directPredecessors))
    }
    return predecessors
  }
  
  static func compute(directPredecessors: [BasicBlockName: Set<BasicBlockName>]) -> [BasicBlockName: Set<BasicBlockName>] {
    var predecessors = [BasicBlockName: Set<BasicBlockName>]()
    for (blockName, _) in directPredecessors {
      predecessors[blockName] = Self.transitivivePredecessors(of: blockName, directPredecessors: directPredecessors)
    }
    return predecessors
  }
}

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

enum Predominators {
  static func compute(directPredecessors: [BasicBlockName: Set<BasicBlockName>], startBlock: BasicBlockName) -> [BasicBlockName: Set<BasicBlockName>] {
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
}

enum ProperPredominators {
  static func compute(predominators: [BasicBlockName: Set<BasicBlockName>]) ->  [BasicBlockName: Set<BasicBlockName>] {
    var properPredominators = [BasicBlockName: Set<BasicBlockName>]()
    for (blockName, predominators) in predominators {
      properPredominators[blockName] = predominators.subtracting([blockName])
    }
    return properPredominators
  }
}
