public struct IRProgram: Equatable, CustomStringConvertible {
  public let basicBlocks: [BasicBlock]
  
  public init(basicBlocks: [BasicBlock]) {
    self.basicBlocks = basicBlocks
  }
  
  public var description: String {
    return basicBlocks.map({ $0.description }).joined(separator: "\n\n")
  }
}
