@testable import ProbabilisticDebugger
import XCTest

class DistributionValidatorTests: XCTestCase {
  func testSuccess() {
    let sourceCode = "int x = discrete({1: 0.2, 2: 0.8})"
    let stmts = try! Parser(sourceCode: sourceCode).parseFile()
    XCTAssertNoThrow(try DistributionValidator().validate(stmts: stmts))
  }
  
  func testFailure() {
    let sourceCode = "int x = discrete({1: 0.2, 2: 0.9})"
    let stmts = try! Parser(sourceCode: sourceCode).parseFile()
    XCTAssertThrowsError(try DistributionValidator().validate(stmts: stmts))
  }
}
