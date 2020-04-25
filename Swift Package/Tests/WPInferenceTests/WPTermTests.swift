@testable import WPInference

import XCTest

class WPTermTests: XCTestCase {
  func testSimplify() {
    let term1: WPTerm = .equal(lhs: .integer(1) + .integer(1), rhs: .integer(2))
    XCTAssertEqual(term1, .bool(true))
    
    let term2: WPTerm = .double(0.5) * .boolToInt(.equal(lhs: .integer(1) + .integer(1), rhs: .integer(2)))
    XCTAssertEqual(term2, .double(0.5))
    
    let term3: WPTerm = .double(0.5) * .boolToInt(.equal(lhs: .integer(2) + .integer(1), rhs: .integer(2)))
    XCTAssertEqual(term3, .double(0))
    
    let term4 = term2 + term3
    XCTAssertEqual(term4, .double(0.5))
    
    let term5: WPTerm = .integer(5) - .integer(1) - .integer(1)
    XCTAssertEqual(term5, .integer(3))
  }
}
