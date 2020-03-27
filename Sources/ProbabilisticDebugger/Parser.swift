extension Token {
  var isOperator: Bool {
    return BinaryOperator(token: self.content) != nil
  }
}

public class Parser {
  private let lexer: Lexer
  
  private var peekedToken: Token?
  
  public init(sourceCode: String) {
    self.lexer = Lexer(sourceCode: sourceCode)
  }
  
  /// Parse an expression
  public func parseExpr() throws -> Expr {
    return try parseExprImpl(precedenceHigherThan: 0)
  }
  
  /// Parse an expression up to the next binary operator that has a precedence lower than `precedenceHigherThan`.
  private func parseExprImpl(precedenceHigherThan: Int) throws -> Expr {
    var workingExpr = try parseBaseExpr()
    while true {
      let nextToken = try peekToken()
      if let nextToken = nextToken, nextToken.isOperator {
        let op = BinaryOperator(token: nextToken.content)!
        if op.precedence <= precedenceHigherThan {
          break
        }
        try consumeToken()
        let rhs = try parseExprImpl(precedenceHigherThan: op.precedence)
        workingExpr = BinaryOperatorExpr(lhs: workingExpr,
                                         operator: op,
                                         rhs: rhs,
                                         range: workingExpr.range.lowerBound..<rhs.range.upperBound)
      } else {
        break
      }
    }
    return workingExpr
  }
  
  /// Parse an expression without binary operators.
  private func parseBaseExpr() throws -> Expr {
    guard let nextToken = try consumeToken() else {
      throw ParserError(position: lexer.position, message: "Reached end of file while parsing expression")
    }
    switch nextToken.content {
    case .integerLiteral(let value):
      return IntegerExpr(value: value, range: nextToken.range)
    case .identifier(name: let name):
      return IdentifierExpr(name: name, range: nextToken.range)
    case .leftParen:
      let subExpr = try parseExpr()
      guard let rParen = try consumeToken() else {
        throw ParserError(position: lexer.position, message: "Expected ')' to close expression in paranthesis, but found end of file")
      }
      guard rParen.content == .rightParen else {
        throw ParserError(range: rParen.range, message: "Expected ')' to close expression in paranthesis, but found '\(rParen.content)'")
      }
      return ParenExpr(subExpr: subExpr, range: nextToken.range.lowerBound..<rParen.range.upperBound)
    default:
      throw ParserError(range: nextToken.range, message: "Expected an identifier or literal, found '\(nextToken)'.")
    }
  }
  
  /// Consume the next token and return it.
  @discardableResult
  private func consumeToken() throws -> Token? {
    if let peekedToken = peekedToken {
      let nextToken = peekedToken
      self.peekedToken = nil
      return nextToken
    } else {
      return try lexer.nextToken()
    }
  }
  
  /// Peek at the next token without consuming it
  private func peekToken() throws -> Token? {
    if let peekedToken = peekedToken {
      return peekedToken
    } else {
      peekedToken = try consumeToken()
      return peekedToken
    }
  }
}
