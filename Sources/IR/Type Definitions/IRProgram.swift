public class IRProgram: Equatable, CustomStringConvertible {
  // MARK: - IR Program
  
  public let basicBlocks: [BasicBlock]
  public let startBlock: BasicBlockName
  
  public subscript(_ basicBlockName: BasicBlockName) -> BasicBlock? {
    return basicBlocks.filter({ $0.name == basicBlockName }).first
  }
  
  /// Create a new IR program that consists of the given basic blocks and verify that it is syntactically correct.
  public init(startBlock: BasicBlockName, basicBlocks: [BasicBlock]) {
    self.startBlock = startBlock
    self.basicBlocks = basicBlocks
    
    IRVerifier.verify(ir: self)
  }
  
  public var description: String {
    return basicBlocks.map({ $0.description }).joined(separator: "\n\n")
  }
  
  public static func == (lhs: IRProgram, rhs: IRProgram) -> Bool {
    return lhs.basicBlocks == rhs.basicBlocks
  }
  
  // MARK: - Analysis results
  // These could be cached if computation is a performance bottleneck
  
  public var directPredecessors: [BasicBlockName: Set<BasicBlockName>] {
    return DirectPredecessors.compute(basicBlocks: basicBlocks)
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
