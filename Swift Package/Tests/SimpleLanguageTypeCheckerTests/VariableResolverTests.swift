import SimpleLanguageParser
import SimpleLanguageAST
import TestUtils

@testable import SimpleLanguageTypeChecker

import XCTest

class VariableResolverTests: XCTestCase {
  func testVariableResolverSuccess() {
    let sourceCode = """
      int x = 10
      while 1 < x {
        x = x - 1
      }
      """
    let parser = Parser(sourceCode: sourceCode)
    let unresolvedStmts = try! parser.parseFile()
    
    let variableResolver = VariableResolver()
    XCTAssertNoThrow(try {
      let stmts = try variableResolver.resolveVariables(in: unresolvedStmts)
      
      XCTAssertEqual(stmts.count, 2)
      
      let varX = SourceVariable(name: "x", disambiguationIndex: 1, type: .int)
      let declareStmt = VariableDeclStmt(variable: varX,
                                         expr: IntegerLiteralExpr(value: 10, range: .whatever),
                                         range: .whatever)
      
      let subExpr = BinaryOperatorExpr(lhs: VariableReferenceExpr(variable: .resolved(varX), range: .whatever),
                                       operator: .minus,
                                       rhs: IntegerLiteralExpr(value: 1, range: .whatever),
                                       range: .whatever)
      let assign = AssignStmt(variable: .resolved(varX),
                              expr: subExpr,
                              range: .whatever)
      let codeBlock = CodeBlockStmt(body: [assign], range: .whatever)
      let condition = BinaryOperatorExpr(lhs: IntegerLiteralExpr(value: 1, range: .whatever),
                                         operator: .lessThan,
                                         rhs: VariableReferenceExpr(variable: .resolved(varX), range: .whatever),
                                         range: .whatever)
      let whileStmt = WhileStmt(condition: condition, body: codeBlock, range: .whatever)
      XCTAssertEqualASTIgnoringRanges(stmts, [declareStmt, whileStmt])
    }())
  }
  
  func testFindsUseBeforeDefine() {
    let sourceCode = "x = x - 1"
    let stmts = try! Parser(sourceCode: sourceCode).parseFile()
    XCTAssertThrowsError(try VariableResolver().resolveVariables(in: stmts))
  }
  
  func testFindsRecursiveVarDecl() {
    let sourceCode = "int x = x - 1"
    let stmts = try! Parser(sourceCode: sourceCode).parseFile()
    XCTAssertThrowsError(try VariableResolver().resolveVariables(in: stmts))
  }
  
  func testFindsDoubleDeclaration() {
    let sourceCode = """
      int x = 1
      int x = 2
      """
    let stmts = try! Parser(sourceCode: sourceCode).parseFile()
    XCTAssertThrowsError(try VariableResolver().resolveVariables(in: stmts))
  }
  
  func testVariableNotValidAfterBlock() {
    let sourceCode = """
      {
        int x = 1
      }
      x = x + 1
      """
    let stmts = try! Parser(sourceCode: sourceCode).parseFile()
    XCTAssertThrowsError(try VariableResolver().resolveVariables(in: stmts))
  }
  
  func testCanUseVariablesFromOuterScope() {
    let sourceCode = """
      int x = 1
      {
        x = x + 1
      }
      """
    let stmts = try! Parser(sourceCode: sourceCode).parseFile()
    XCTAssertNoThrow(try VariableResolver().resolveVariables(in: stmts))
  }
}
