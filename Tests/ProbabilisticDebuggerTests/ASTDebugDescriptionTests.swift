import ProbabilisticDebugger
import XCTest

class ASTDebugDescriptionTests: XCTestCase {
  func testDebugDescription() {
    let sourceCode = """
      while 1 < x {
        x = x - 1
      }
      """
    let parser = Parser(sourceCode: sourceCode)
    let ast = try! parser.parseStmt()
    
    XCTAssertEqual(ast!.debugDescription, """
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
