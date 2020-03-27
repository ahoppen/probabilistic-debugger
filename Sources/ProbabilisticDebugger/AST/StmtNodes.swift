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
