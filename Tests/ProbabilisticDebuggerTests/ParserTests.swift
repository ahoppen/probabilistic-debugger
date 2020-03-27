import ProbabilisticDebugger
import XCTest

fileprivate extension Range where Bound == Position {
  /// Some range whoe value is not important because it will not be used when comparing ASTs using `equalsIgnoringRange`.
  static let whatever = Position(line: 0, column: 0, offset: "".startIndex)..<Position(line: 0, column: 0, offset: "".startIndex)
}

/// Check that the two ASTs are equal while ignoring their ranges.
func XCTAssertEqualASTIgnoringRanges(_ lhs: ASTNode, _ rhs: ASTNode) {
  XCTAssert(lhs.equalsIgnoringRange(other: rhs), "\n\(lhs.debugDescription)\nis not equal to \n\n\(rhs.debugDescription)")
}

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
      let expectedAst = IdentifierExpr(name: "x", range: .whatever)
      
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
}
