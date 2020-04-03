import SimpleLanguageAST

/// An error that occurred while parsing the source file
public struct CompilerError: Error {
  /// The range at which the error occurred. If only a position is known, this is a range of the form `pos..<pos`
  public let range: SourceRange
  
  /// The error message
  public let message: String
  
  public init(range: SourceRange, message: String) {
    self.range = range
    self.message = message
  }
  
  public init(location: SourceLocation, message: String) {
    self.range = location..<location
    self.message = message
  }
  
  public var localizedDescription: String {
    return "\(range.lowerBound): \(message)"
  }
}
