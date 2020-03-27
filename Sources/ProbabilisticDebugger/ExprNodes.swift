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

public struct IdentifierExpr: Expr {
  public let name: String
  public let range: Range<Position>
  
  public init(name: String, range: Range<Position>) {
    self.name = name
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


// MARK: - Debug Descriptions

public extension BinaryOperatorExpr {
  var debugDescription: String {
    return """
      ▽ BinaryOperatorExpr(\(self.operator))
      \(lhs.debugDescription.indented())
      \(rhs.debugDescription.indented())
      """
  }
}

public extension IntegerExpr {
  var debugDescription: String {
    return "▷ IntegerExpr(\(value))"
  }
}

public extension IdentifierExpr {
  var debugDescription: String {
    return "▷ IdentifierExpr(\(name))"
  }
}

public extension ParenExpr {
  var debugDescription: String {
    return """
      ▽ ParenExpr
      \(subExpr.debugDescription.indented())
      """
  }
}
