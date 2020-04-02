public class IRProgram: Equatable, CustomStringConvertible {
  // MARK: - IR Program
  
  public let basicBlocks: [BasicBlockName: BasicBlock]
  public let startBlock: BasicBlockName
  
  /// Create a new IR program that consists of the given basic blocks and verify that it is syntactically correct.
  public init(startBlock: BasicBlockName, basicBlocks: [BasicBlock]) {
    self.startBlock = startBlock
    self.basicBlocks = Dictionary(uniqueKeysWithValues: zip(basicBlocks.map({ $0.name }), basicBlocks))
    
    IRVerifier.verify(ir: self)
  }
  
  public func instruction(at position: ProgramPosition) -> Instruction? {
    guard let block = self.basicBlocks[position.basicBlock], block.instructions.count > position.instructionIndex else {
      return nil
    }
    return block.instructions[position.instructionIndex]
  }
  
  public var description: String {
    return basicBlocks.values.map({ $0.description }).joined(separator: "\n\n")
  }
  
  public static func == (lhs: IRProgram, rhs: IRProgram) -> Bool {
    return lhs.basicBlocks == rhs.basicBlocks && lhs.startBlock == rhs.startBlock
  }
  
  // MARK: - Analysis results
  // These could be cached if computation is a performance bottleneck
  
  public var directPredecessors: [BasicBlockName: Set<BasicBlockName>] {
    return DirectPredecessors.compute(basicBlocks: basicBlocks.values)
  }
  
  public var transitivePredecessors: [BasicBlockName: Set<BasicBlockName>] {
    return TransitivePredecessors.compute(directPredecessors: directPredecessors)
  }
  
  public var predominators: [BasicBlockName: Set<BasicBlockName>] {
    return Predominators.compute(directPredecessors: directPredecessors, startBlock: startBlock)
  }
  
  public var properPredominators: [BasicBlockName: Set<BasicBlockName>] {
    return ProperPredominators.compute(predominators: predominators)
  }
}
