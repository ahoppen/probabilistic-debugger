public struct Token: Equatable {
  /// The content of the token
  public let content: TokenContent
  
  /// The range in which the token appeared in the source code
  public let range: Range<Position>
  
  public init(content: TokenContent, range: Range<Position>) {
    self.content = content
    self.range = range
  }
}

public enum TokenContent: Equatable {
  // MARK: Identifier
  
  /// An identifier
  case identifier(content: String)
  
  // MARK: Literals
  
  /// An integer literal
  case integerLiteral(value: Int)
  
  // MARK: Keywords
  
  /// The `if` keyword
  case `if`
  
  /// The `else` keyword
  case `else`
  
  /// The `while` keyword
  case `while`
  
  /// The `int` keyword
  case int
  
  /// The `observe` keyword
  case observe
  
  // MARK: Special characters
  
  /// The `(` character
  case leftParen
  
  /// The `)` character
  case rightParen
  
  /// The `{` character
  case leftBrace
  
  /// The `}` character
  case rightBrace
  
  /// The `:` character
  case colon
  
  /// The `,` character
  case comma
  
  /// The `;` character
  case semicolon
  
  /// The `=` character
  case equal
  
  /// The `==` operator
  case equalEqual
  
  /// The `<` operator
  case lessThan
  
  /// The `+` operator
  case plus
  
  /// The `-` operator
  case minus
}
