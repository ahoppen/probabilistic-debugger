public struct Token: Equatable, CustomStringConvertible {
  /// The content of the token
  public let content: TokenContent
  
  /// The range in which the token appeared in the source code
  public let range: Range<Position>
  
  public init(content: TokenContent, range: Range<Position>) {
    self.content = content
    self.range = range
  }
  
  public var description: String {
    return content.description
  }
}

public enum TokenContent: Equatable, CustomStringConvertible {
  
  // MARK: Identifier
  
  /// An identifier
  case identifier(name: String)
  
  // MARK: Literals
  
  /// An integer literal
  case integerLiteral(value: Int)
  
  /// A floating-point literal
  case floatLiteral(value: Double)
  
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
  
  // MARK: - Checks for types with associated values
  
  var isIdentifier: Bool {
    switch self {
    case .identifier:
      return true
    default:
      return false
    }
  }
  
  var isIntegerLiteral: Bool {
    switch self {
    case .integerLiteral:
      return true
    default:
      return false
    }
  }
  
  var isFloatLiteral: Bool {
    switch self {
    case .floatLiteral:
      return true
    default:
      return false
    }
  }
  
  public var description: String {
    switch self {
    case .identifier(name: let name):
      return name
    case .integerLiteral(value: let value):
      return String(value)
    case .floatLiteral(value: let value):
      return String(value)
    case .if:
      return "if"
    case .else:
      return "else"
    case .while:
      return "while"
    case .int:
      return "int"
    case .observe:
      return "observer"
    case .leftParen:
      return "("
    case .rightParen:
      return ")"
    case .leftBrace:
      return "{"
    case .rightBrace:
      return "}"
    case .colon:
      return ":"
    case .comma:
      return ","
    case .semicolon:
      return ";"
    case .equal:
      return "="
    case .equalEqual:
      return "=="
    case .lessThan:
      return "<"
    case .plus:
      return "+"
    case .minus:
      return "-"
    }
  }
}
