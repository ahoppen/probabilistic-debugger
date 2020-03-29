import SimpleLanguageAST
import XCTest

fileprivate extension Range where Bound == Position {
  /// Some range whoe value is not important because it will not be used when comparing ASTs using `equalsIgnoringRange`.
  static let whatever = Position(line: 0, column: 0, offset: "".startIndex)..<Position(line: 0, column: 0, offset: "".startIndex)
}

class ASTDebugDescriptionTests: XCTestCase {
  func testDebugDescription() {
    // AST for the following source code:
    // while 1 < x {
    //   x = x - 1
    // }
    
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
    
    XCTAssertEqual(whileStmt.debugDescription, """
      ▽ WhileStmt
        ▽ Condition
          ▽ BinaryOperatorExpr(lessThan)
            ▷ IntegerExpr(1)
            ▷ VariableExpr(x (unresolved))
        ▽ CodeBlockStmt
          ▽ AssignStmt(name: x (unresolved))
            ▽ BinaryOperatorExpr(minus)
              ▷ VariableExpr(x (unresolved))
              ▷ IntegerExpr(1)
      """)
  }
}
