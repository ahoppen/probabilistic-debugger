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
  /// The variable that's being declared
  public let variable: Variable
  /// The expression that's assigned to the variable
  public let expr: Expr
  
  public let range: Range<Position>
  
  public init(variable: Variable, expr: Expr, range: Range<Position>) {
    self.variable = variable
    self.expr = expr
    self.range = range
  }
}

/// An assignment to an already declared variable. E.g. `x = x + 1`
public struct AssignStmt: Stmt {
  /// The variable that's being assigned a value
  public let variable: UnresolvedVariable
  /// The expression that's assigned to the variable
  public let expr: Expr
  
  public let range: Range<Position>
  
  public init(variable: UnresolvedVariable, expr: Expr, range: Range<Position>) {
    self.variable = variable
    self.expr = expr
    self.range = range
  }
}

public struct ObserveStmt: Stmt {
  public let condition: Expr
  
  public let range: Range<Position>
  
  public init(condition: Expr, range: Range<Position>) {
    self.condition = condition
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

// MARK: - AST Visitation

extension VariableDeclStmt {
  public func accept<VisitorType: ASTVisitor>(_ visitor: VisitorType) -> VisitorType.ReturnType {
    visitor.visit(self)
  }
  
  public func accept<VisitorType: ASTVerifier>(_ visitor: VisitorType) throws -> VisitorType.ReturnType {
    try visitor.visit(self)
  }
  
  public func accept<VisitorType: ASTRewriter>(_ visitor: VisitorType) throws -> Self {
    return try visitor.visit(self)
  }
}

extension AssignStmt {
  public func accept<VisitorType: ASTVisitor>(_ visitor: VisitorType) -> VisitorType.ReturnType {
    visitor.visit(self)
  }
  
  public func accept<VisitorType: ASTVerifier>(_ visitor: VisitorType) throws -> VisitorType.ReturnType {
    try visitor.visit(self)
  }
  
  public func accept<VisitorType: ASTRewriter>(_ visitor: VisitorType) throws -> Self {
    return try visitor.visit(self)
  }
}

extension ObserveStmt {
  public func accept<VisitorType: ASTVisitor>(_ visitor: VisitorType) -> VisitorType.ReturnType {
    visitor.visit(self)
  }
  
  public func accept<VisitorType: ASTVerifier>(_ visitor: VisitorType) throws -> VisitorType.ReturnType {
    try visitor.visit(self)
  }
  
  public func accept<VisitorType: ASTRewriter>(_ visitor: VisitorType) throws -> Self {
    return try visitor.visit(self)
  }
}

extension CodeBlockStmt {
  public func accept<VisitorType: ASTVisitor>(_ visitor: VisitorType) -> VisitorType.ReturnType {
    visitor.visit(self)
  }
  
  public func accept<VisitorType: ASTVerifier>(_ visitor: VisitorType) throws -> VisitorType.ReturnType {
    try visitor.visit(self)
  }
  
  public func accept<VisitorType: ASTRewriter>(_ visitor: VisitorType) throws -> Self {
    return try visitor.visit(self)
  }
}

extension IfStmt {
  public func accept<VisitorType: ASTVisitor>(_ visitor: VisitorType) -> VisitorType.ReturnType {
    visitor.visit(self)
  }
  
  public func accept<VisitorType: ASTVerifier>(_ visitor: VisitorType) throws -> VisitorType.ReturnType {
    try visitor.visit(self)
  }
  
  public func accept<VisitorType: ASTRewriter>(_ visitor: VisitorType) throws -> Self {
    return try visitor.visit(self)
  }
}

extension WhileStmt {
  public func accept<VisitorType: ASTVisitor>(_ visitor: VisitorType) -> VisitorType.ReturnType {
    visitor.visit(self)
  }
  
  public func accept<VisitorType: ASTVerifier>(_ visitor: VisitorType) throws -> VisitorType.ReturnType {
    try visitor.visit(self)
  }
  
  public func accept<VisitorType: ASTRewriter>(_ visitor: VisitorType) throws -> Self {
    return try visitor.visit(self)
  }
}

// MARK: - Equality ignoring ranges

extension VariableDeclStmt {
  public func equalsIgnoringRange(other: ASTNode) -> Bool {
    guard let other = other as? VariableDeclStmt else {
      return false
    }
    return self.variable.name == other.variable.name &&
      self.expr.equalsIgnoringRange(other: other.expr)
  }
}

extension AssignStmt {
  public func equalsIgnoringRange(other: ASTNode) -> Bool {
    guard let other = other as? AssignStmt else {
      return false
    }
    return self.variable.hasSameName(as: other.variable) &&
      self.expr.equalsIgnoringRange(other: other.expr)
  }
}

extension ObserveStmt {
  public func equalsIgnoringRange(other: ASTNode) -> Bool {
    guard let other = other as? ObserveStmt else {
      return false
    }
    return self.condition.equalsIgnoringRange(other: other.condition)
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
