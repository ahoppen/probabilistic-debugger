/// A class that takes an AST and rewrites it to a different AST while preserving node types.
/// By default all methods are implemented as a no-op that continues visiting.
public protocol ASTRewriter {
  func visit(_ expr: BinaryOperatorExpr) throws -> BinaryOperatorExpr
  func visit(_ expr: IntegerExpr) throws -> IntegerExpr
  func visit(_ expr: VariableExpr) throws -> VariableExpr
  func visit(_ expr: ParenExpr) throws -> ParenExpr
  func visit(_ expr: DiscreteIntegerDistributionExpr) throws -> DiscreteIntegerDistributionExpr
  func visit(_ stmt: VariableDeclStmt) throws -> VariableDeclStmt
  func visit(_ stmt: AssignStmt) throws -> AssignStmt
  func visit(_ stmt: ObserveStmt) throws -> ObserveStmt
  func visit(_ stmt: CodeBlockStmt) throws -> CodeBlockStmt
  func visit(_ stmt: IfStmt) throws -> IfStmt
  func visit(_ stmt: WhileStmt) throws -> WhileStmt
}

extension ASTRewriter {
  func visit(_ expr: BinaryOperatorExpr) throws -> BinaryOperatorExpr {
    return BinaryOperatorExpr(lhs: try expr.lhs.accept(self),
                              operator: expr.operator,
                              rhs: try expr.rhs.accept(self),
                              range: expr.range)
  }
  
  func visit(_ expr: IntegerExpr) -> IntegerExpr {
    return expr
  }
  
  func visit(_ expr: VariableExpr) -> VariableExpr {
    return expr
  }
  
  func visit(_ expr: ParenExpr) throws -> ParenExpr {
    return ParenExpr(subExpr: try expr.subExpr.accept(self),
                     range: expr.range)
  }
  
  func visit(_ expr: DiscreteIntegerDistributionExpr) -> DiscreteIntegerDistributionExpr {
    return expr
  }
  
  func visit(_ stmt: VariableDeclStmt) throws -> VariableDeclStmt {
    return VariableDeclStmt(variable: stmt.variable,
                            expr: try stmt.expr.accept(self),
                            range: stmt.range)
  }
  
  func visit(_ stmt: AssignStmt) throws -> AssignStmt {
    return AssignStmt(variable: stmt.variable,
                      expr: try stmt.expr.accept(self),
                      range: stmt.range)
  }
  
  func visit(_ stmt: ObserveStmt) throws -> ObserveStmt {
    return ObserveStmt(condition: try stmt.condition.accept(self),
                       range: stmt.range)
  }
  
  func visit(_ stmt: CodeBlockStmt) throws -> CodeBlockStmt {
    return CodeBlockStmt(body: try stmt.body.map( { try $0.accept(self) }),
                         range: stmt.range)
  }
  
  func visit(_ stmt: IfStmt) throws -> IfStmt {
    return IfStmt(condition: try stmt.condition.accept(self),
                  body: try stmt.body.accept(self),
                  range: stmt.range)
  }
  
  func visit(_ stmt: WhileStmt) throws -> WhileStmt {
    return WhileStmt(condition: try stmt.condition.accept(self),
                     body: try stmt.body.accept(self),
                     range: stmt.range)
  }
  
}
