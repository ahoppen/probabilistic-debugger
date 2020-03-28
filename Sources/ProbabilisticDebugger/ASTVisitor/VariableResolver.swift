/// A scope in which variables are declared.
/// Can be queried for variable declarations in itself or any of its parent scopes.
fileprivate class VariableScope {
  let outerScope: VariableScope?
  private var identifiers: [String: Variable] = [:]
      
  init(outerScope: VariableScope?) {
    self.outerScope = outerScope
  }

  func declare(variable: Variable) {
    assert(!isDeclared(name: variable.name), "Variable already declared")
    identifiers[variable.name] = variable
  }
  
  func isDeclared(name: String) -> Bool {
    return identifiers[name] != nil
  }
  
  func lookup(name: String) -> Variable? {
    if let variable = identifiers[name] {
      return variable
    } else if let outerScope = outerScope {
      return outerScope.lookup(name: name)
    } else {
      return nil
    }
  }
}

/// Resolves variable references in a source file.
/// While doing it, checks that no variable is declared twice or used before being defined.
internal class VariableResolver: ASTRewriter {
  private var variableScope = VariableScope(outerScope: nil)
  private var errors: [ParserError] = []
  
  public func resolveVariables(in stmts: [Stmt]) throws -> [Stmt] {
    let resolvedStmts = stmts.map({ $0.accept(self) })
    // We are gathering all errors but our current approach of throwing the first error does not allow us to return all errors.
    if let firstError = errors.first {
      throw firstError
    }
    return resolvedStmts
  }
  
  // MARK: - Handle scopes
  
  private func pushScope() {
    variableScope = VariableScope(outerScope: variableScope)
  }
  
  private func popScope() {
    guard let outerScope = self.variableScope.outerScope else {
      fatalError("Cannot pop scope. Already on outer scope")
    }
    self.variableScope = outerScope
  }
  
  // MARK: - Visit nodes
  
  func visit(_ stmt: CodeBlockStmt) -> CodeBlockStmt {
    pushScope()
    defer { popScope() }
    
    return CodeBlockStmt(body: stmt.body.map( { $0.accept(self) }),
                         range: stmt.range)
  }
  
  func visit(_ stmt: VariableDeclStmt) -> VariableDeclStmt {
    guard !variableScope.isDeclared(name: stmt.variable.name) else {
      errors.append(ParserError(range: stmt.range, message: "Variable '\(stmt.variable.name)' is already declared."))
      return stmt
    }
    let resolvedExpr = stmt.expr.accept(self)
    variableScope.declare(variable: stmt.variable)
    return VariableDeclStmt(variable: stmt.variable,
                            expr: resolvedExpr,
                            range: stmt.range)
  }
  
  func visit(_ stmt: AssignStmt) -> AssignStmt {
    guard case .unresolved(let name) = stmt.variable else {
      fatalError("Variable has already been resolved")
    }
    guard let variable = variableScope.lookup(name: name) else {
      errors.append(ParserError(range: stmt.range, message: "Variable '\(name)' has not been declared"))
      return stmt
    }
    return AssignStmt(variable: .resolved(variable),
                      expr: stmt.expr.accept(self),
                      range: stmt.range)
  }
  
  func visit(_ expr: VariableExpr) -> VariableExpr {
    guard case .unresolved(let name) = expr.variable else {
      fatalError("Variable has already been resolved")
    }
    guard let variable = variableScope.lookup(name: name) else {
      errors.append(ParserError(range: expr.range, message: "Variable '\(name)' has not been declared"))
      return expr
    }
    return VariableExpr(variable: .resolved(variable),
                          range: expr.range)
  }
}
