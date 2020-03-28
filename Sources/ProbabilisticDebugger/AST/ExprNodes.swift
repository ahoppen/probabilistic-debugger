public protocol Expr: ASTNode {}

// MARK: - Expression nodes

public enum BinaryOperator {
  case plus
  case minus
  case equal
  case lessThan
  
  /// Returns the precedence of the operator. A greater value means higher precedence.
  internal var precedence: Int {
    switch self {
    case .plus, .minus:
      return 2
    case .equal, .lessThan:
      return 1
    }
  }
}

public struct BinaryOperatorExpr: Expr {
  public let lhs: Expr
  public let rhs: Expr
  public let `operator`: BinaryOperator
  
  public let range: Range<Position>
 
  public init(lhs: Expr, operator op: BinaryOperator, rhs: Expr, range: Range<Position>) {
    self.lhs = lhs
    self.rhs = rhs
    self.operator = op
    self.range = range
  }
}

public struct IntegerExpr: Expr {
  public let value: Int
  public let range: Range<Position>
  
  public init(value: Int, range: Range<Position>) {
    self.value = value
    self.range = range
  }
}

public struct VariableExpr: Expr {
  public let variable: UnresolvedVariable
  public let range: Range<Position>
  
  public init(variable: UnresolvedVariable, range: Range<Position>) {
    self.variable = variable
    self.range = range
  }
}

public struct ParenExpr: Expr {
  public let subExpr: Expr
  public let range: Range<Position>
  
  public init(subExpr: Expr, range: Range<Position>) {
    self.subExpr = subExpr
    self.range = range
  }
}

public struct DiscreteIntegerDistributionExpr: Expr {
  public let distribution: [Int: Double]
  public let range: Range<Position>
  
  public init(distribution: [Int: Double], range: Range<Position>) {
    self.distribution = distribution
    self.range = range
  }
}

// MARK: - Visitation


extension BinaryOperatorExpr {
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

extension IntegerExpr {
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

extension VariableExpr {
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

extension ParenExpr {
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

extension DiscreteIntegerDistributionExpr {
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


public extension BinaryOperatorExpr {
  func equalsIgnoringRange(other: ASTNode) -> Bool {
    guard let other = other as? BinaryOperatorExpr else {
      return false
    }
    return self.operator == other.operator &&
      self.lhs.equalsIgnoringRange(other: other.lhs) &&
      self.rhs.equalsIgnoringRange(other: other.rhs)
  }
}

public extension IntegerExpr {
  func equalsIgnoringRange(other: ASTNode) -> Bool {
    guard let other = other as? IntegerExpr else {
      return false
    }
    return self.value == other.value
  }
}

public extension VariableExpr {
  func equalsIgnoringRange(other: ASTNode) -> Bool {
    guard let other = other as? VariableExpr else {
      return false
    }
    return self.variable.hasSameName(as: other.variable)
  }
}

public extension ParenExpr {
  func equalsIgnoringRange(other: ASTNode) -> Bool {
    guard let other = other as? ParenExpr else {
      return false
    }
    return self.subExpr.equalsIgnoringRange(other: other.subExpr)
  }
}

public extension DiscreteIntegerDistributionExpr {
  func equalsIgnoringRange(other: ASTNode) -> Bool {
    guard let other = other as? DiscreteIntegerDistributionExpr else {
      return false
    }
    return self.distribution == other.distribution
  }
}
