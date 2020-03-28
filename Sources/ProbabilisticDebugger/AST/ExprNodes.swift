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
  
  public func accept<VisitorType: ASTVisitor>(_ visitor: VisitorType) -> VisitorType.ReturnType {
    visitor.visit(self)
  }
}

public struct IntegerExpr: Expr {
  public let value: Int
  public let range: Range<Position>
  
  public init(value: Int, range: Range<Position>) {
    self.value = value
    self.range = range
  }
  
  public func accept<VisitorType: ASTVisitor>(_ visitor: VisitorType) -> VisitorType.ReturnType {
    visitor.visit(self)
  }
}

public struct IdentifierExpr: Expr {
  public let name: String
  public let range: Range<Position>
  
  public init(name: String, range: Range<Position>) {
    self.name = name
    self.range = range
  }
  
  public func accept<VisitorType: ASTVisitor>(_ visitor: VisitorType) -> VisitorType.ReturnType {
    visitor.visit(self)
  }
}

public struct ParenExpr: Expr {
  public let subExpr: Expr
  public let range: Range<Position>
  
  public init(subExpr: Expr, range: Range<Position>) {
    self.subExpr = subExpr
    self.range = range
  }
  
  public func accept<VisitorType: ASTVisitor>(_ visitor: VisitorType) -> VisitorType.ReturnType {
    visitor.visit(self)
  }
}

public struct DiscreteIntegerDistributionExpr: Expr {
  public let distribution: [Int: Double]
  public let range: Range<Position>
  
  public init(distribution: [Int: Double], range: Range<Position>) {
    self.distribution = distribution
    self.range = range
  }
  
  public func accept<VisitorType: ASTVisitor>(_ visitor: VisitorType) -> VisitorType.ReturnType {
    visitor.visit(self)
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

public extension IdentifierExpr {
  func equalsIgnoringRange(other: ASTNode) -> Bool {
    guard let other = other as? IdentifierExpr else {
      return false
    }
    return self.name == other.name
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
