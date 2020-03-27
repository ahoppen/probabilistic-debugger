extension Token {
  var isOperator: Bool {
    return BinaryOperator(token: self.content) != nil
  }
  
  var isType: Bool {
    return Type(token: self.content) != nil
  }
}

fileprivate extension BinaryOperator {
  init?(token: TokenContent) {
    switch token {
    case .plus:
      self = .plus
    case .minus:
      self = .minus
    case .equalEqual:
      self = .equal
    case .lessThan:
      self = .lessThan
    default:
      return nil
    }
  }
}

fileprivate extension Type {
  init?(token: TokenContent) {
    switch token {
    case .int:
      self = .int
    default:
      return nil
    }
  }
}

public class Parser {
  private let lexer: Lexer
  
  private var peekedToken: Token?
  
  public init(sourceCode: String) {
    self.lexer = Lexer(sourceCode: sourceCode)
  }
  
  // MARK: - Retrieving tokens
  
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
  
  /// Consume the next token if it matches the given condition.
  /// If the condition is not satisfied, throw a `ParserError` with the given error message.
  /// If the end of file is reached, returns a generic error message that the end of file was unexpectedly reached.
  @discardableResult
  private func consumeToken(condition: (TokenContent) -> Bool, errorMessage: String) throws -> Token {
    guard let token = try consumeToken() else {
      throw ParserError(position: lexer.position, message: "Unexpectedly reached end of file")
    }
    if !condition(token.content) {
      throw ParserError(range: token.range, message: errorMessage)
    } else {
      return token
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
  
  // MARK: - Parse statements
  
  /// Parse a statement.
  /// Returns the parsed statment or `nil` if the end of the file has been reached
  public func parseStmt() throws -> Stmt? {
    let token = try peekToken()
    switch token?.content {
    case .int:
      return try parseVariableDecl()
    case .identifier:
      return try parseAssignStmt()
    case .if:
      return try parseIfStmt()
    case .while:
      return try parseWhileStmt()
    case nil:
      return nil
    default:
      throw ParserError(range: token!.range, message: "Expected start of statement")
    }
  }
  
  /// Parse a variable declaration of the form `int x = y + 2`.
  /// Assumes that the current token is a type.
  private func parseVariableDecl() throws -> VariableDeclStmt {
    let variableTypeToken = try consumeToken()!
    assert(variableTypeToken.isType)
    let type = Type(token: variableTypeToken.content)!
    
    let variableIdentifier = try consumeToken(condition: { $0.isIdentifier }, errorMessage: "Expected an identifier for the name of the variable declaration")
    guard case .identifier(let variableName) = variableIdentifier.content else {
      fatalError("The token we consumed was specified to be an identifier")
    }
    _ = try consumeToken(condition: { $0 == .equal }, errorMessage: "Expected '=' in variable declaration")
    
    let expr = try parseExpr()
    
    return VariableDeclStmt(variableType: type, variableName: variableName, expr: expr, range: variableTypeToken.range.lowerBound..<expr.range.upperBound)
  }
  
  /// Parse an assignment to an already declared variable. E.g. `x = x + 1`
  /// Assumes that the next token is an identifier
  private func parseAssignStmt() throws -> AssignStmt {
    let variableIdentifier = try consumeToken()!
    assert(variableIdentifier.content.isIdentifier)
    guard case .identifier(let variableName) = variableIdentifier.content else {
      fatalError("The token we consumed was specified to be an identifier")
    }
    
    _ = try consumeToken(condition: { $0 == .equal }, errorMessage: "Expected '=' in variable assignment")
    
    let expr = try parseExpr()
    
    return AssignStmt(variableName: variableName, expr: expr, range: variableIdentifier.range.lowerBound..<expr.range.upperBound)
  }
  
  private func parseIfStmt() throws -> IfStmt {
    let ifToken = try consumeToken()!
    assert(ifToken.content == .if)
    
    let condition = try parseExpr()
    
    let body = try parseCodeBlock()
    
    return IfStmt(condition: condition, body: body, range: ifToken.range.lowerBound..<body.range.upperBound)
  }
  
  private func parseWhileStmt() throws -> WhileStmt {
    let whileToken = try consumeToken()!
    assert(whileToken.content == .while)
    
    let condition = try parseExpr()
    
    let body = try parseCodeBlock()
    
    return WhileStmt(condition: condition, body: body, range: whileToken.range.lowerBound..<body.range.upperBound)
  }
  
  private func parseCodeBlock() throws -> CodeBlockStmt {
    let leftBrace = try consumeToken(condition: { $0 == .leftBrace }, errorMessage: "Expected '{' to start a code block")
    var stmts = [Stmt]()
    while let token = try peekToken(), token.content != .rightBrace {
      guard let stmt = try parseStmt() else {
        throw ParserError(position: lexer.position, message: "Reached end of file while inside a '{}' code block")
      }
      stmts.append(stmt)
    }
    guard let rightBrace = try consumeToken() else {
      throw ParserError(position: lexer.position, message: "Reached end of file while inside a '{}' code block")
    }
    assert(rightBrace.content == .rightBrace)
    
    return CodeBlockStmt(body: stmts, range: leftBrace.range.lowerBound..<rightBrace.range.upperBound)
  }
  
  // MARK: - Parse expressions
  
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
    case .discrete:
      return try parseDiscreteProbabilityDistribution(discreteKeyword: nextToken)
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
  
  /// Parse a discrete integer distribution. E.g. `discrete({1: 0.2, 2: 0.8})`.
  /// Assumes that the `discrete` keyword has already been parsed and is parsed as the `firstToken` parameter.
  private func parseDiscreteProbabilityDistribution(discreteKeyword: Token) throws -> DiscreteIntegerDistributionExpr {
    assert(discreteKeyword.content == .discrete)
    
    _ = try consumeToken(condition: { $0 == .leftParen }, errorMessage: "Expected '(' to specify discrete integer distribution")
    
    let distribution = try parseDiscreteIntegerDistributionSpecification()
    
    let rightParen = try consumeToken(condition: { $0 == .rightParen }, errorMessage: "Expected ')' to end discrete integer distribution")
    
    return DiscreteIntegerDistributionExpr(distribution: distribution, range: discreteKeyword.range.lowerBound..<rightParen.range.upperBound)
  }
  
  /// Parse a discrete probability distribution into a Swift dictionary. E.g.
  /// ```
  /// {
  ///   1: 0.2,
  ///   2: 0.8
  /// }
  /// ```
  /// gets parsed into `[1: 0.2, 2: 0.8]`
  private func parseDiscreteIntegerDistributionSpecification() throws -> [Int: Double] {
    try consumeToken(condition: { $0 == .leftBrace }, errorMessage: "Expected '{' to specify discrete integer distribution")
    var distribution = [Int: Double]()
    while true {
      let integerToken = try consumeToken(condition: { $0.isIntegerLiteral }, errorMessage: "Expected an integer literal to specify an integer value that the discrete variable distribution may take.")
      guard case .integerLiteral(let value) = integerToken.content else {
        fatalError()
      }
      if distribution[value] != nil {
        throw ParserError(range: integerToken.range, message: "Probability of value '\(value)' was already declared")
      }
      
      _ = try consumeToken(condition: { $0 == .colon }, errorMessage: "Expected a colon to separate a distribution value from its probability")
      
      let probabilityToken = try consumeToken(condition: { $0.isFloatLiteral || $0.isIntegerLiteral }, errorMessage: "Expected a number between 0 and 1 that specifies the proabability of the discrete value")
      let probability: Double
      if case .floatLiteral(let value) = probabilityToken.content {
        probability = value
      } else if case .integerLiteral(let value) = probabilityToken.content {
        probability = Double(value)
      } else {
        fatalError("We only accepted tokens of type float or integer before")
      }
      if probability < 0 || probability > 1 {
        throw ParserError(range: probabilityToken.range, message: "\(probability) is not a valid proability value (between 0 and 1)")
      }
      
      distribution[value] = probability
      
      if try peekToken()?.content == .comma {
        // Consume the comma and parse the next entry
        try consumeToken()
      } else {
        break
      }
    }
    try consumeToken(condition: { $0 == .rightBrace }, errorMessage: "Expected '}' to end discrete probability distribution")
    return distribution
  }
}
