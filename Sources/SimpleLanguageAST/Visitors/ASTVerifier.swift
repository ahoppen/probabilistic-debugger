/// An `ASTVisitor` that can throw errors while visiting.
/// It can have two different return types for the different node types: `Stmt` and `Expr`.
public protocol ASTVerifier {
  
  /// The type returned when visiting `Expr` nodes
  associatedtype ExprReturnType
  
  /// The type returned when visiting `Stmt` nodes
  associatedtype StmtReturnType
  
  func visit(_ expr: BinaryOperatorExpr) throws -> ExprReturnType
  func visit(_ expr: IntegerExpr) throws -> ExprReturnType
  func visit(_ expr: VariableExpr) throws -> ExprReturnType
  func visit(_ expr: ParenExpr) throws -> ExprReturnType
  func visit(_ expr: DiscreteIntegerDistributionExpr) throws -> ExprReturnType
  func visit(_ stmt: VariableDeclStmt) throws -> StmtReturnType
  func visit(_ stmt: AssignStmt) throws -> StmtReturnType
  func visit(_ stmt: ObserveStmt) throws -> StmtReturnType
  func visit(_ stmt: CodeBlockStmt) throws -> StmtReturnType
  func visit(_ stmt: IfStmt) throws -> StmtReturnType
  func visit(_ stmt: WhileStmt) throws -> StmtReturnType
}

public extension ASTVerifier where ExprReturnType == Void, StmtReturnType == Void {
  func visit(_ expr: BinaryOperatorExpr) throws {
    try expr.lhs.accept(self)
    try expr.rhs.accept(self)
  }
  
  func visit(_ expr: IntegerExpr) throws {}
  
  func visit(_ expr: VariableExpr) throws {}
  
  func visit(_ expr: ParenExpr) throws {
    try expr.subExpr.accept(self)
  }
  
  func visit(_ expr: DiscreteIntegerDistributionExpr) throws {}
  
  func visit(_ stmt: VariableDeclStmt) throws {
    try stmt.expr.accept(self)
  }
  
  func visit(_ stmt: AssignStmt) throws {
    try stmt.expr.accept(self)
  }
  
  func visit(_ stmt: ObserveStmt) throws {
    try stmt.condition.accept(self)
  }
  
  func visit(_ codeBlock: CodeBlockStmt) throws {
    for stmt in codeBlock.body {
      try stmt.accept(self)
    }
  }
  
  func visit(_ stmt: IfStmt) throws {
    try stmt.condition.accept(self)
    try stmt.body.accept(self)
  }
  
  func visit(_ stmt: WhileStmt) throws {
    try stmt.condition.accept(self)
    try stmt.body.accept(self)
  }
}
