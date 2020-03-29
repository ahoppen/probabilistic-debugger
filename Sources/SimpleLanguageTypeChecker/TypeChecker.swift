import SimpleLanguageAST
import SimpleLanguageParser

internal class TypeChecker: ASTVerifier {
  /// The type of an expression or `nil` if the verifier runs on a statement (which naturally doesn't have a type).
  typealias ReturnType = Type?
  
  func typeCheck(stmts: [Stmt]) throws {
    for stmt in stmts {
      _ = try stmt.accept(self)
    }
  }
  
  // MARK: - AST visitation
  
  func visit(_ expr: BinaryOperatorExpr) throws -> Type? {
    let lhsType = try expr.lhs.accept(self)!
    let rhsType = try expr.rhs.accept(self)!
    switch (expr.operator, lhsType, rhsType) {
    case (.plus, .int, .int), (.minus, .int, .int):
      return .int
    case (.equal, .int, .int), (.lessThan, .int, .int):
      return .bool
    default:
      throw ParserError(range: expr.range, message: "Cannot apply '\(expr.operator)' to '\(lhsType)' and '\(rhsType)'")
    }
  }
  
  func visit(_ expr: IntegerExpr) throws -> Type? {
    return .int
  }
  
  func visit(_ expr: VariableExpr) throws -> Type? {
    guard case .resolved(let variable) = expr.variable else {
      fatalError("Variables must be resolved in the AST before type checking")
    }
    return variable.type
  }
  
  func visit(_ expr: ParenExpr) throws -> Type? {
    return try expr.subExpr.accept(self)
  }
  
  func visit(_ expr: DiscreteIntegerDistributionExpr) throws -> Type? {
    return .int
  }
  
  func visit(_ stmt: VariableDeclStmt) throws -> Type? {
    let exprType = try stmt.expr.accept(self)!
    if stmt.variable.type != exprType {
      throw ParserError(range: stmt.range, message: "Cannot assign expression of type '\(exprType)' to variable of type '\(stmt.variable.type)'")
    }
    return nil
  }
  
  func visit(_ stmt: AssignStmt) throws -> Type? {
    guard case .resolved(let variable) = stmt.variable else {
      fatalError("Variables must be resolved in the AST before type checking")
    }
    let exprType = try stmt.expr.accept(self)!
    if variable.type != exprType {
      throw ParserError(range: stmt.range, message: "Cannot assign expression of type '\(exprType)' to variable of type '\(variable.type)'")
    }
    return nil
  }
  
  func visit(_ stmt: ObserveStmt) throws -> Type? {
    let conditionType = try stmt.condition.accept(self)!
    if conditionType != .bool {
      throw ParserError(range: stmt.range, message: "'observe' condition must to be boolean")
    }
    return nil
  }
  
  func visit(_ codeBlock: CodeBlockStmt) throws -> Type? {
    for stmt in codeBlock.body {
      _ = try stmt.accept(self)
    }
    return nil
  }
  
  func visit(_ stmt: IfStmt) throws -> Type? {
    let conditionType = try stmt.condition.accept(self)!
    if conditionType != .bool {
      throw ParserError(range: stmt.range, message: "'if' condition must to be boolean")
    }
    return nil
  }
  
  func visit(_ stmt: WhileStmt) throws -> Type? {
    let conditionType = try stmt.condition.accept(self)!
    if conditionType != .bool {
      throw ParserError(range: stmt.range, message: "'while' condition must to be boolean")
    }
    return nil
  }
}
