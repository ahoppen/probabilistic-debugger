import SimpleLanguageAST

public enum TypeCheckPipeline {
  public static func typeCheck(stmts: [Stmt]) throws -> [Stmt] {
    let stmts = try VariableResolver().resolveVariables(in: stmts)
    try TypeChecker().typeCheck(stmts: stmts)
    try DistributionValidator().validate(stmts: stmts)
    return stmts
  }
}
