public protocol Stmt: ASTNode {}

public enum Type: CustomStringConvertible, Equatable {
  case int
  case bool
  
  public var description: String {
    switch self {
    case .int:
      return "int"
    case .bool:
      return "bool"
    }
  }
}

/// A declaration of a new variable. E.g. `int x = y + 2`
public struct VariableDeclStmt: Stmt {
  /// The type of the variable that's being declaredn
  public let variableType: Type
  /// The name of the variable that's being declared
  public let variableName: String
  /// The expression that's assigned to the variable
  public let expr: Expr
  
  public let range: Range<Position>
  
  public init(variableType: Type, variableName: String, expr: Expr, range: Range<Position>) {
    self.variableType = variableType
    self.variableName = variableName
    self.expr = expr
    self.range = range
  }
}

/// An assignment to an already declared variable. E.g. `x = x + 1`
public struct AssignStmt: Stmt {
  /// The variable that's being assigned a value
  public let variableName: String
  /// The expression that's assigned to the variable
  public let expr: Expr
  
  public let range: Range<Position>
  
  public init(variableName: String, expr: Expr, range: Range<Position>) {
    self.variableName = variableName
    self.expr = expr
    self.range = range
  }
}

/// A code block that contains multiple statements inside braces.
public struct CodeBlockStmt: Stmt {
  public let body: [Stmt]
  
  public let range: Range<Position>
  
  public init(body: [Stmt], range: Range<Position>) {
    self.body = body
    self.range = range
  }
}

public struct IfStmt: Stmt {
  public let condition: Expr
  public let body: CodeBlockStmt
  
  public let range: Range<Position>
  
  public init(condition: Expr, body: CodeBlockStmt, range: Range<Position>) {
    self.condition = condition
    self.body = body
    self.range = range
  }
}

public struct WhileStmt: Stmt {
  public let condition: Expr
  public let body: CodeBlockStmt
  
  public let range: Range<Position>
  
  public init(condition: Expr, body: CodeBlockStmt, range: Range<Position>) {
    self.condition = condition
    self.body = body
    self.range = range
  }
}

// MARK: - Equality ignoring ranges

extension VariableDeclStmt {
  public func equalsIgnoringRange(other: ASTNode) -> Bool {
    guard let other = other as? VariableDeclStmt else {
      return false
    }
    return self.variableType == other.variableType &&
      self.variableName == other.variableName &&
      self.expr.equalsIgnoringRange(other: other.expr)
  }
}

extension AssignStmt {
  public func equalsIgnoringRange(other: ASTNode) -> Bool {
    guard let other = other as? AssignStmt else {
      return false
    }
    return self.variableName == other.variableName &&
      self.expr.equalsIgnoringRange(other: other.expr)
  }
}

extension CodeBlockStmt {
  public func equalsIgnoringRange(other: ASTNode) -> Bool {
    guard let other = other as? CodeBlockStmt else {
      return false
    }
    if self.body.count != other.body.count {
      return false
    }
    return zip(self.body, other.body).allSatisfy({
      $0.0.equalsIgnoringRange(other: $0.1)
    })
  }
}

extension IfStmt {
  public func equalsIgnoringRange(other: ASTNode) -> Bool {
    guard let other = other as? IfStmt else {
      return false
    }
    return self.condition.equalsIgnoringRange(other: other.condition) &&
      self.body.equalsIgnoringRange(other: other.body)
  }
}

extension WhileStmt {
  public func equalsIgnoringRange(other: ASTNode) -> Bool {
    guard let other = other as? WhileStmt else {
      return false
    }
    return self.condition.equalsIgnoringRange(other: other.condition) &&
      self.body.equalsIgnoringRange(other: other.body)
  }
}

// MARK: - Debug descriptions

extension VariableDeclStmt {
  public var debugDescription: String {
    return """
      ▽ VariableDeclStmt(name: \(variableName), type: \(variableType))"
      \(expr.debugDescription.indented())
      """
  }
}

extension AssignStmt {
  public var debugDescription: String {
    return """
      ▽ AssignStmt(name: \(variableName))"
      \(expr.debugDescription.indented())
      """
  }
}

extension CodeBlockStmt {
  public var debugDescription: String {
    return """
      ▽ CodeBlockStmt
      \(body.map({ $0.debugDescription }).joined(separator: "\n").indented())
      """
  }
}

extension IfStmt {
  public var debugDescription: String {
    return """
      ▽ IfStmt"
        ▽ Condition
      \(condition.debugDescription.indented(2))
      \(body.debugDescription.indented())
      """
  }
}

extension WhileStmt {
  public var debugDescription: String {
    return """
      ▽ WhileStmt"
        ▽ Condition
      \(condition.debugDescription.indented(2))
      \(body.debugDescription.indented())
      """
  }
}
