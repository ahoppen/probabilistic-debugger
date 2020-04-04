public class IRProgram: CustomStringConvertible {
  // MARK: IR Program
  
  public let basicBlocks: [BasicBlockName: BasicBlock]
  public let startBlock: BasicBlockName
  
  /// Create a new IR program that consists of the given basic blocks and verify that it is syntactically correct.
  public init(startBlock: BasicBlockName, basicBlocks: [BasicBlock]) {
    self.startBlock = startBlock
    self.basicBlocks = Dictionary(uniqueKeysWithValues: zip(basicBlocks.map(\.name), basicBlocks))
    
    IRVerifier.verify(ir: self)
  }
  
  /// Returns the instruction at the given `position` or `nil` if the program does not have an instruction at this position.
  public func instruction(at position: InstructionPosition) -> Instruction? {
    guard let block = self.basicBlocks[position.basicBlock], block.instructions.count > position.instructionIndex else {
      return nil
    }
    return block.instructions[position.instructionIndex]
  }
  
  public var description: String {
    return basicBlocks.values.sorted(by: { $0.name.name < $1.name.name }).map(\.description).joined(separator: "\n\n")
  }
  
  // MARK: Analysis results
  // These could be cached if computation is a performance bottleneck
  
  public var directPredecessors: [BasicBlockName: Set<BasicBlockName>] {
    return IRAnalysis.directPredecessors(basicBlocks: basicBlocks.values)
  }
  
  public var directSuccessors: [BasicBlockName: Set<BasicBlockName>] {
    return IRAnalysis.directSuccessors(basicBlocks: basicBlocks.values)
  }
  
  public var predominators: [BasicBlockName: Set<BasicBlockName>] {
    return IRAnalysis.predominators(directPredecessors: directPredecessors, startBlock: startBlock)
  }
  
  public var postdominators: [BasicBlockName: Set<BasicBlockName>] {
    return IRAnalysis.postdominators(directSuccessors: directSuccessors, startBlock: startBlock)
  }
  
  public var properPredominators: [BasicBlockName: Set<BasicBlockName>] {
    return IRAnalysis.properDominators(dominators: predominators)
  }
  
  public var properPostdominators: [BasicBlockName: Set<BasicBlockName>] {
    return IRAnalysis.properDominators(dominators: postdominators)
  }
  
  public var immediatePostdominator: [BasicBlockName: BasicBlockName?] {
    return IRAnalysis.immediateDominator(properDominators: properPostdominators)
  }
}
