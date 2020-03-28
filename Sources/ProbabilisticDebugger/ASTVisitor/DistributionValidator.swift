/// Checks that the probability in discrete distributions add up to 1.
class DistributionValidator: ASTVerifier {
  typealias ReturnType = Void
  
  func validate(stmts: [Stmt]) throws {
    for stmt in stmts {
      try stmt.accept(self)
    }
  }
  
  func visit(_ expr: DiscreteIntegerDistributionExpr) throws {
    if expr.distribution.values.reduce(0, +) != 1 {
      throw ParserError(range: expr.range, message: "Probabilities in discrete integer distribution do not add up to 1")
    }
  }
}
