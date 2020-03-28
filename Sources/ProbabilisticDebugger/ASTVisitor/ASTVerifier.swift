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
