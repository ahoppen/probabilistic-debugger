/// An `ASTVisitor` that can throw errors while visiting
public protocol ASTVerifier {
  associatedtype ReturnType
  
  func visit(_ expr: BinaryOperatorExpr) throws -> ReturnType
  func visit(_ expr: IntegerExpr) throws -> ReturnType
  func visit(_ expr: VariableExpr) throws -> ReturnType
  func visit(_ expr: ParenExpr) throws -> ReturnType
  func visit(_ expr: DiscreteIntegerDistributionExpr) throws -> ReturnType
  func visit(_ stmt: VariableDeclStmt) throws -> ReturnType
  func visit(_ stmt: AssignStmt) throws -> ReturnType
  func visit(_ stmt: ObserveStmt) throws -> ReturnType
  func visit(_ stmt: CodeBlockStmt) throws -> ReturnType
  func visit(_ stmt: IfStmt) throws -> ReturnType
  func visit(_ stmt: WhileStmt) throws -> ReturnType
}

public extension ASTVerifier where ReturnType == Void {
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
