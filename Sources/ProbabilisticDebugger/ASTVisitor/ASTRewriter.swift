/// A class that takes an AST and rewrites it to a different AST while preserving node types.
/// By default all methods are implemented as a no-op that continues visiting.
public protocol ASTRewriter {
  func visit(_ expr: BinaryOperatorExpr) -> BinaryOperatorExpr
  func visit(_ expr: IntegerExpr) -> IntegerExpr
  func visit(_ expr: VariableExpr) -> VariableExpr
  func visit(_ expr: ParenExpr) -> ParenExpr
  func visit(_ expr: DiscreteIntegerDistributionExpr) -> DiscreteIntegerDistributionExpr
  func visit(_ stmt: VariableDeclStmt) -> VariableDeclStmt
  func visit(_ stmt: AssignStmt) -> AssignStmt
  func visit(_ stmt: ObserveStmt) -> ObserveStmt
  func visit(_ stmt: CodeBlockStmt) -> CodeBlockStmt
  func visit(_ stmt: IfStmt) -> IfStmt
  func visit(_ stmt: WhileStmt) -> WhileStmt
}

extension ASTRewriter {
  func visit(_ expr: BinaryOperatorExpr) -> BinaryOperatorExpr {
    return BinaryOperatorExpr(lhs: expr.lhs.accept(self),
                              operator: expr.operator,
                              rhs: expr.rhs.accept(self),
                              range: expr.range)
  }
  
  func visit(_ expr: IntegerExpr) -> IntegerExpr {
    return expr
  }
  
  func visit(_ expr: VariableExpr) -> VariableExpr {
    return expr
  }
  
  func visit(_ expr: ParenExpr) -> ParenExpr {
    return ParenExpr(subExpr: expr.subExpr.accept(self),
                     range: expr.range)
  }
  
  func visit(_ expr: DiscreteIntegerDistributionExpr) -> DiscreteIntegerDistributionExpr {
    return expr
  }
  
  func visit(_ stmt: VariableDeclStmt) -> VariableDeclStmt {
    return VariableDeclStmt(variable: stmt.variable,
                            expr: stmt.expr.accept(self),
                            range: stmt.range)
  }
  
  func visit(_ stmt: AssignStmt) -> AssignStmt {
    return AssignStmt(variable: stmt.variable,
                      expr: stmt.expr.accept(self),
                      range: stmt.range)
  }
  
  func visit(_ stmt: ObserveStmt) -> ObserveStmt {
    return ObserveStmt(condition: stmt.condition.accept(self),
                       range: stmt.range)
  }
  
  func visit(_ stmt: CodeBlockStmt) -> CodeBlockStmt {
    return CodeBlockStmt(body: stmt.body.map( { $0.accept(self) }),
                         range: stmt.range)
  }
  
  func visit(_ stmt: IfStmt) -> IfStmt {
    return IfStmt(condition: stmt.condition.accept(self),
                  body: stmt.body.accept(self),
                  range: stmt.range)
  }
  
  func visit(_ stmt: WhileStmt) -> WhileStmt {
    return WhileStmt(condition: stmt.condition.accept(self),
                     body: stmt.body.accept(self),
                     range: stmt.range)
  }
  
}
