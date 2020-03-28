public protocol ASTNode: CustomDebugStringConvertible {
  /// The range in the source code that represents this AST node
  var range: Range<Position> { get }
  
  /// Check if this AST node is equal to the `other` node while not comparing ranges.
  /// For testing purposes.
  func equalsIgnoringRange(other: ASTNode) -> Bool
  
  func accept<VisitorType: ASTVisitor>(_ visitor: VisitorType) -> VisitorType.ReturnType
  func accept<VisitorType: ASTVerifier>(_ visitor: VisitorType) throws -> VisitorType.ReturnType
  func accept<VisitorType: ASTRewriter>(_ visitor: VisitorType) -> Self
}

public extension ASTNode {
  var debugDescription: String {
    return ASTDebugDescriptionGenerator().debugDescription(for: self)
  }
}
