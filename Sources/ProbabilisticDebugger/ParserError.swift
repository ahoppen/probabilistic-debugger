/// An error that occurred while parsing the source file
public struct ParserError: Error {
  /// The range at which the error occurred. If only a position is known, this is a range of the form `pos..<pos`
  public let range: Range<Position>
  
  /// The error message
  public let message: String
  
  public init(range: Range<Position>, message: String) {
    self.range = range
    self.message = message
  }
  
  public init(position: Position, message: String) {
    self.range = position..<position
    self.message = message
  }
  
  public var localizedDescription: String {
    return message
  }
}
