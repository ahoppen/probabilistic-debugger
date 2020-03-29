import SimpleLanguageAST
import SimpleLanguageParser

internal class TypeChecker: ASTVerifier {
  /// The type of an expression or `nil` if the verifier runs on a statement (which naturally doesn't have a type).
  typealias ExprReturnType = Type
  typealias StmtReturnType = Void
  
  func typeCheck(stmts: [Stmt]) throws {
    for stmt in stmts {
      _ = try stmt.accept(self)
    }
  }
  
  // MARK: - AST visitation
  
  func visit(_ expr: BinaryOperatorExpr) throws -> Type {
    let lhsType = try expr.lhs.accept(self)
    let rhsType = try expr.rhs.accept(self)
    switch (expr.operator, lhsType, rhsType) {
    case (.plus, .int, .int), (.minus, .int, .int):
      return .int
    case (.equal, .int, .int), (.lessThan, .int, .int):
      return .bool
    case (.plus, _, _), (.minus, _, _), (.equal, _, _), (.lessThan, _, _):
      throw ParserError(range: expr.range, message: "Cannot apply '\(expr.operator)' to '\(lhsType)' and '\(rhsType)'")
    }
  }
  
  func visit(_ expr: IntegerExpr) throws -> Type {
    return .int
  }
  
  func visit(_ expr: VariableExpr) throws -> Type {
    guard case .resolved(let variable) = expr.variable else {
      fatalError("Variables must be resolved in the AST before type checking")
    }
    return variable.type
  }
  
  func visit(_ expr: ParenExpr) throws -> Type {
    return try expr.subExpr.accept(self)
  }
  
  func visit(_ expr: DiscreteIntegerDistributionExpr) throws -> Type {
    return .int
  }
  
  func visit(_ stmt: VariableDeclStmt) throws {
    let exprType = try stmt.expr.accept(self)
    if stmt.variable.type != exprType {
      throw ParserError(range: stmt.range, message: "Cannot assign expression of type '\(exprType)' to variable of type '\(stmt.variable.type)'")
    }
  }
  
  func visit(_ stmt: AssignStmt) throws {
    guard case .resolved(let variable) = stmt.variable else {
      fatalError("Variables must be resolved in the AST before type checking")
    }
    let exprType = try stmt.expr.accept(self)
    if variable.type != exprType {
      throw ParserError(range: stmt.range, message: "Cannot assign expression of type '\(exprType)' to variable of type '\(variable.type)'")
    }
  }
  
  func visit(_ stmt: ObserveStmt) throws {
    let conditionType = try stmt.condition.accept(self)
    if conditionType != .bool {
      throw ParserError(range: stmt.range, message: "'observe' condition must to be boolean")
    }
  }
  
  func visit(_ codeBlock: CodeBlockStmt) throws {
    for stmt in codeBlock.body {
      _ = try stmt.accept(self)
    }
  }
  
  func visit(_ stmt: IfStmt) throws {
    let conditionType = try stmt.condition.accept(self)
    if conditionType != .bool {
      throw ParserError(range: stmt.range, message: "'if' condition must to be boolean")
    }
  }
  
  func visit(_ stmt: WhileStmt) throws {
    let conditionType = try stmt.condition.accept(self)
    if conditionType != .bool {
      throw ParserError(range: stmt.range, message: "'while' condition must to be boolean")
    }
  }
}