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
            ▷ IdentifierExpr(x)
        ▽ CodeBlockStmt
          ▽ AssignStmt(name: x)
            ▽ BinaryOperatorExpr(minus)
              ▷ IdentifierExpr(x)
              ▷ IntegerExpr(1)
      """)
  }
}
