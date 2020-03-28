struct ASTDebugDescriptionGenerator: ASTVisitor {
  typealias ReturnType = String
  
  func visit(_ expr: BinaryOperatorExpr) -> String {
    return """
      ▽ BinaryOperatorExpr(\(expr.operator))
      \(expr.lhs.debugDescription.indented())
      \(expr.rhs.debugDescription.indented())
      """
  }
  
  func visit(_ expr: IntegerExpr) -> String {
    return "▷ IntegerExpr(\(expr.value))"
  }
  
  func visit(_ expr: IdentifierExpr) -> String {
    return "▷ IdentifierExpr(\(expr.name))"
  }
  
  func visit(_ expr: ParenExpr) -> String {
    return """
      ▽ ParenExpr
      \(expr.subExpr.debugDescription.indented())
      """
  }
  
  func visit(_ expr: DiscreteIntegerDistributionExpr) -> String {
    let distributionDescription = expr.distribution.map({ "\($0.key): \($0.value)"}).joined(separator: "\n")
    return """
      ▽ DiscreteIntegerDistributionExpr
      \(distributionDescription.indented())
      """
  }
  
  func visit(_ stmt: VariableDeclStmt) -> String {
    return """
      ▽ VariableDeclStmt(name: \(stmt.variableName), type: \(stmt.variableType))
      \(stmt.expr.debugDescription.indented())
      """
  }
  
  func visit(_ stmt: AssignStmt) -> String {
    return """
      ▽ AssignStmt(name: \(stmt.variableName))
      \(stmt.expr.debugDescription.indented())
      """
  }
  
  func visit(_ stmt: ObserveStmt) -> String {
    return """
      ▽ ObserveStmt
      \(stmt.condition.debugDescription.indented())
      """
  }
  
  func visit(_ stmt: CodeBlockStmt) -> String {
    return """
      ▽ CodeBlockStmt
      \(stmt.body.map({ $0.debugDescription }).joined(separator: "\n").indented())
      """
  }
  
  func visit(_ stmt: IfStmt) -> String {
    return """
      ▽ IfStmt
        ▽ Condition
      \(stmt.condition.debugDescription.indented(2))
      \(stmt.body.debugDescription.indented())
      """
  }
  
  func visit(_ stmt: WhileStmt) -> String {
    return """
      ▽ WhileStmt
        ▽ Condition
      \(stmt.condition.debugDescription.indented(2))
      \(stmt.body.debugDescription.indented())
      """
  }
  
  func debugDescription(for node: ASTNode) -> String {
    return node.accept(self)
  }
}