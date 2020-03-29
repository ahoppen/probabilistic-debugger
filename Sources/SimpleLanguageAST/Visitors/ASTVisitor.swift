public protocol ASTVisitor {
  associatedtype ReturnType
  
  func visit(_ expr: BinaryOperatorExpr) -> ReturnType
  func visit(_ expr: IntegerExpr) -> ReturnType
  func visit(_ expr: VariableExpr) -> ReturnType
  func visit(_ expr: ParenExpr) -> ReturnType
  func visit(_ expr: DiscreteIntegerDistributionExpr) -> ReturnType
  func visit(_ stmt: VariableDeclStmt) -> ReturnType
  func visit(_ stmt: AssignStmt) -> ReturnType
  func visit(_ stmt: ObserveStmt) -> ReturnType
  func visit(_ stmt: CodeBlockStmt) -> ReturnType
  func visit(_ stmt: IfStmt) -> ReturnType
  func visit(_ stmt: WhileStmt) -> ReturnType
}
