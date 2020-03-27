public protocol ASTNode: CustomDebugStringConvertible {
  /// The range in the source code that represents this AST node
  var range: Range<Position> { get }
  
  /// Check if this AST node is equal to the `other` node while not comparing ranges.
  /// For testing purposes.
  func equalsIgnoringRange(other: ASTNode) -> Bool
}
