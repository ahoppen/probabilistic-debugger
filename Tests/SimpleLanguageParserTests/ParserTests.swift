import SimpleLanguageAST
import TestUtils

@testable import SimpleLanguageParser

import XCTest


class ParserTests: XCTestCase {
  func testSimpleExpr() {
    XCTAssertNoThrow(try {
      let expr = "1 + 2"
      let parser = Parser(sourceCode: expr)
      let ast = try parser.parseExpr()
      let expectedAst = BinaryOperatorExpr(lhs: IntegerExpr(value: 1, range: .whatever),
                                           operator: .plus,
                                           rhs: IntegerExpr(value: 2, range: .whatever),
                                           range: .whatever)
      XCTAssertEqualASTIgnoringRanges(ast, expectedAst)
    }())
  }
  
  func testExprWithThreeTerms() {
    XCTAssertNoThrow(try {
      let expr = "1 + 2 + 3"
      let parser = Parser(sourceCode: expr)
      let ast = try parser.parseExpr()
      let onePlusTwo = BinaryOperatorExpr(lhs: IntegerExpr(value: 1, range: .whatever),
                                          operator: .plus,
                                          rhs: IntegerExpr(value: 2, range: .whatever),
                                          range: .whatever)
      let expectedAst = BinaryOperatorExpr(lhs: onePlusTwo,
                                           operator: .plus,
                                           rhs: IntegerExpr(value: 3, range: .whatever),
                                           range: .whatever)
      XCTAssertEqualASTIgnoringRanges(ast, expectedAst)
    }())
  }
  
  func testExprWithPrecedence() {
    XCTAssertNoThrow(try {
      let expr = "1 + 2 < 3"
      let parser = Parser(sourceCode: expr)
      let ast = try parser.parseExpr()
      let onePlusTwo = BinaryOperatorExpr(lhs: IntegerExpr(value: 1, range: .whatever),
                                          operator: .plus,
                                          rhs: IntegerExpr(value: 2, range: .whatever),
                                          range: .whatever)
      let expectedAst = BinaryOperatorExpr(lhs: onePlusTwo,
                                           operator: .lessThan,
                                           rhs: IntegerExpr(value: 3, range: .whatever),
                                           range: .whatever)
      XCTAssertEqualASTIgnoringRanges(ast, expectedAst)
    }())
  }
  
  func testSingleIdentifier() {
    XCTAssertNoThrow(try {
      let parser = Parser(sourceCode: "x")
      let ast = try parser.parseExpr()
      let expectedAst = VariableExpr(variable: .unresolved(name: "x"), range: .whatever)
      
      XCTAssertEqualASTIgnoringRanges(ast, expectedAst)
    }())
  }
  
  func testParenthesisAtEnd() {
    XCTAssertNoThrow(try {
      let expr = "1 + (2 + 3)"
      let parser = Parser(sourceCode: expr)
      let ast = try parser.parseExpr()
      let twoPlusThree = BinaryOperatorExpr(lhs: IntegerExpr(value: 2, range: .whatever),
                                            operator: .plus,
                                            rhs: IntegerExpr(value: 3, range: .whatever),
                                            range: .whatever)
      let expectedAst = BinaryOperatorExpr(lhs: IntegerExpr(value: 1, range: .whatever),
                                           operator: .plus,
                                           rhs: ParenExpr(subExpr: twoPlusThree, range: .whatever),
                                           range: .whatever)
      
      XCTAssertEqualASTIgnoringRanges(ast, expectedAst)
    }())
  }
  
  func testParenthesisAtStart() {
    XCTAssertNoThrow(try {
      let expr = "(1 + 2) + 3"
      let parser = Parser(sourceCode: expr)
      let ast = try parser.parseExpr()
      let onePlusTwo = BinaryOperatorExpr(lhs: IntegerExpr(value: 1, range: .whatever),
                                          operator: .plus,
                                          rhs: IntegerExpr(value: 2, range: .whatever),
                                          range: .whatever)
      let expectedAst = BinaryOperatorExpr(lhs: ParenExpr(subExpr: onePlusTwo, range: .whatever),
                                           operator: .plus,
                                           rhs: IntegerExpr(value: 3, range: .whatever),
                                           range: .whatever)
      XCTAssertEqualASTIgnoringRanges(ast, expectedAst)
    }())
  }
  
  func testDiscreteIntegerDistribution() {
    XCTAssertNoThrow(try {
      let expr = "discrete({1: 0.2, 2: 0.8})"
      let parser = Parser(sourceCode: expr)
      let ast = try parser.parseExpr()
      let distribution = DiscreteIntegerDistributionExpr(distribution: [
        1: 0.2,
        2: 0.8
      ], range: .whatever)
      XCTAssertEqualASTIgnoringRanges(ast, distribution)
    }())
  }
  
  func testParseVariableDeclaration() {
    XCTAssertNoThrow(try {
      let stmt = "int x = y + 2"
      let parser = Parser(sourceCode: stmt)
      let ast = try parser.parseStmt()
      
      let expr = BinaryOperatorExpr(lhs: VariableExpr(variable: .unresolved(name: "y"), range: .whatever),
                                    operator: .plus,
                                    rhs: IntegerExpr(value: 2, range: .whatever),
                                    range: .whatever)
      
      let declExpr = VariableDeclStmt(variable: Variable(name: "x", type: .int),
                                      expr: expr,
                                      range: .whatever)
      
      XCTAssertNotNil(ast)
      XCTAssertEqualASTIgnoringRanges(ast!, declExpr)
    }())
  }
  
  func testVariableAssignemnt() {
    XCTAssertNoThrow(try {
      let stmt = "x = x + 1"
      let parser = Parser(sourceCode: stmt)
      let ast = try parser.parseStmt()
      
      let expr = BinaryOperatorExpr(lhs: VariableExpr(variable: .unresolved(name: "x"), range: .whatever),
                                    operator: .plus,
                                    rhs: IntegerExpr(value: 1, range: .whatever),
                                    range: .whatever)
      
      let declExpr = AssignStmt(variable: .unresolved(name: "x"),
                                expr: expr,
                                range: .whatever)
      
      XCTAssertNotNil(ast)
      XCTAssertEqualASTIgnoringRanges(ast!, declExpr)
    }())
  }
  
  func testParseIfStmt() {
    XCTAssertNoThrow(try {
      let sourceCode = """
      if x == 1 {
        int y = 2
        y = y + 1
      }
      """
      let parser = Parser(sourceCode: sourceCode)
      let ast = try parser.parseStmt()
      
      let varDecl = VariableDeclStmt(variable: Variable(name: "y", type: .int),
                                     expr: IntegerExpr(value: 2, range: .whatever),
                                     range: .whatever)
      let addExpr = BinaryOperatorExpr(lhs: VariableExpr(variable: .unresolved(name: "y"), range: .whatever),
                                       operator: .plus,
                                       rhs: IntegerExpr(value: 1, range: .whatever),
                                       range: .whatever)
      let assign = AssignStmt(variable: .unresolved(name: "y"),
                              expr: addExpr,
                              range: .whatever)
      let codeBlock = CodeBlockStmt(body: [varDecl, assign], range: .whatever)
      let condition = BinaryOperatorExpr(lhs: VariableExpr(variable: .unresolved(name: "x"), range: .whatever),
                                         operator: .equal,
                                         rhs: IntegerExpr(value: 1, range: .whatever),
                                         range: .whatever)
      let ifStmt = IfStmt(condition: condition, body: codeBlock, range: .whatever)
      XCTAssertEqualASTIgnoringRanges(ast!, ifStmt)
    }())
  }
  
  func testParseIfStmtWithParanthesInCondition() {
    XCTAssertNoThrow(try {
      let sourceCode = """
      if (x == 1) {
        int y = 2
        y = y + 1
      }
      """
      let parser = Parser(sourceCode: sourceCode)
      let ast = try parser.parseStmt()
      
      let varDecl = VariableDeclStmt(variable: Variable(name: "y", type: .int),
                                     expr: IntegerExpr(value: 2, range: .whatever),
                                     range: .whatever)
      let addExpr = BinaryOperatorExpr(lhs: VariableExpr(variable: .unresolved(name: "y"), range: .whatever),
                                       operator: .plus,
                                       rhs: IntegerExpr(value: 1, range: .whatever),
                                       range: .whatever)
      let assign = AssignStmt(variable: .unresolved(name: "y"),
                              expr: addExpr,
                              range: .whatever)
      let codeBlock = CodeBlockStmt(body: [varDecl, assign], range: .whatever)
      let condition = BinaryOperatorExpr(lhs: VariableExpr(variable: .unresolved(name: "x"), range: .whatever),
                                         operator: .equal,
                                         rhs: IntegerExpr(value: 1, range: .whatever),
                                         range: .whatever)
      let parenCondition = ParenExpr(subExpr: condition, range: .whatever)
      let ifStmt = IfStmt(condition: parenCondition, body: codeBlock, range: .whatever)
      XCTAssertEqualASTIgnoringRanges(ast!, ifStmt)
    }())
  }
  
  func testParseWhileStmt() {
    XCTAssertNoThrow(try {
      let sourceCode = """
      while 1 < x {
        x = x - 1
      }
      """
      let parser = Parser(sourceCode: sourceCode)
      let ast = try parser.parseStmt()
      
      let subExpr = BinaryOperatorExpr(lhs: VariableExpr(variable: .unresolved(name: "x"), range: .whatever),
                                       operator: .minus,
                                       rhs: IntegerExpr(value: 1, range: .whatever),
                                       range: .whatever)
      let assign = AssignStmt(variable: .unresolved(name: "x"),
                              expr: subExpr,
                              range: .whatever)
      let codeBlock = CodeBlockStmt(body: [assign], range: .whatever)
      let condition = BinaryOperatorExpr(lhs: IntegerExpr(value: 1, range: .whatever),
                                         operator: .lessThan,
                                         rhs: VariableExpr(variable: .unresolved(name: "x"), range: .whatever),
                                         range: .whatever)
      let whileStmt = WhileStmt(condition: condition, body: codeBlock, range: .whatever)
      XCTAssertEqualASTIgnoringRanges(ast!, whileStmt)
    }())
  }
  
  func testParseObserveWithoutParan() {
    XCTAssertNoThrow(try {
      let stmt = "observe x < 0"
      let parser = Parser(sourceCode: stmt)
      let ast = try parser.parseStmt()
      
      let condition = BinaryOperatorExpr(lhs: VariableExpr(variable: .unresolved(name: "x"), range: .whatever),
                                         operator: .lessThan,
                                         rhs: IntegerExpr(value: 0, range: .whatever),
                                         range: .whatever)
      let observeStmt = ObserveStmt(condition: condition, range: .whatever)
      
      XCTAssertEqualASTIgnoringRanges(ast!, observeStmt)
    }())
  }
  
  func testParseObserveWithParan() {
    XCTAssertNoThrow(try {
      let stmt = "observe(x < 0)"
      let parser = Parser(sourceCode: stmt)
      let ast = try parser.parseStmt()
      
      let condition = BinaryOperatorExpr(lhs: VariableExpr(variable: .unresolved(name: "x"), range: .whatever),
                                         operator: .lessThan,
                                         rhs: IntegerExpr(value: 0, range: .whatever),
                                         range: .whatever)
      let parenCondition = ParenExpr(subExpr: condition, range: .whatever)
      let observeStmt = ObserveStmt(condition: parenCondition, range: .whatever)
      
      XCTAssertEqualASTIgnoringRanges(ast!, observeStmt)
    }())
  }
  
  func testParseEmptyCodeBlock() {
    XCTAssertNoThrow(try {
      let parser = Parser.init(sourceCode: "{}")
      let ast = try parser.parseStmt()
      
      let codeBlock = CodeBlockStmt(body: [], range: .whatever)
      XCTAssertEqualASTIgnoringRanges(ast!, codeBlock)
    }())
  }
  
  func testParseFileWithoutSemicolons() {
    XCTAssertNoThrow(try {
      let parser = Parser.init(sourceCode: """
      int a = discrete({0: 0.5, 1: 0.5})
      int b = discrete({0: 0.5, 1: 0.5})
      int c = a + b
      observe 0 < c
      """)
      let ast = try parser.parseFile()
      
      let discreteDistribution = DiscreteIntegerDistributionExpr(distribution: [
        0: 0.5,
        1: 0.5
      ], range: .whatever)
      let aDecl = VariableDeclStmt(variable: Variable(name: "a", type: .int),
                                   expr: discreteDistribution,
                                   range: .whatever)
      let bDecl = VariableDeclStmt(variable: Variable(name: "b", type: .int),
                                   expr: discreteDistribution,
                                   range: .whatever)
      let addition = BinaryOperatorExpr(lhs: VariableExpr(variable: .unresolved(name: "a"), range: .whatever),
                                        operator: .plus,
                                        rhs: VariableExpr(variable: .unresolved(name: "b"), range: .whatever),
                                        range: .whatever)
      let cDecl = VariableDeclStmt(variable: Variable(name: "c", type: .int),
                                   expr: addition,
                                   range: .whatever)
      let observeCondition = BinaryOperatorExpr(lhs: IntegerExpr(value: 0, range: .whatever),
                                                operator: .lessThan,
                                                rhs: VariableExpr(variable: .unresolved(name: "c"), range: .whatever),
                                                range: .whatever)
      let observeStmt = ObserveStmt(condition: observeCondition, range: .whatever)
      
      let stmts: [Stmt] = [aDecl, bDecl, cDecl, observeStmt]
      
      XCTAssertEqualASTIgnoringRanges(ast, stmts)
    }())
  }
  
  func testParseFileWithSemicolons() {
    XCTAssertNoThrow(try {
      let parser = Parser.init(sourceCode: """
      int a = discrete({0: 0.5, 1: 0.5});
      int b = discrete({0: 0.5, 1: 0.5});
      int c = a + b;
      observe(0 < c)
      """)
      let ast = try parser.parseFile()
      
      let discreteDistribution = DiscreteIntegerDistributionExpr(distribution: [
        0: 0.5,
        1: 0.5
      ], range: .whatever)
      let aDecl = VariableDeclStmt(variable: Variable(name: "a", type: .int),
                                   expr: discreteDistribution,
                                   range: .whatever)
      let bDecl = VariableDeclStmt(variable: Variable(name: "b", type: .int),
                                   expr: discreteDistribution,
                                   range: .whatever)
      let addition = BinaryOperatorExpr(lhs: VariableExpr(variable: .unresolved(name: "a"), range: .whatever),
                                        operator: .plus,
                                        rhs: VariableExpr(variable: .unresolved(name: "b"), range: .whatever),
                                        range: .whatever)
      let cDecl = VariableDeclStmt(variable: Variable(name: "c", type: .int),
                                   expr: addition,
                                   range: .whatever)
      let observeCondition = BinaryOperatorExpr(lhs: IntegerExpr(value: 0, range: .whatever),
                                                operator: .lessThan,
                                                rhs: VariableExpr(variable: .unresolved(name: "c"), range: .whatever),
                                                range: .whatever)
      let observeStmt = ObserveStmt(condition: ParenExpr(subExpr: observeCondition, range: .whatever),
                                    range: .whatever)
      
      let stmts: [Stmt] = [aDecl, bDecl, cDecl, observeStmt]
      
      XCTAssertEqualASTIgnoringRanges(ast, stmts)
    }())
  }
}
