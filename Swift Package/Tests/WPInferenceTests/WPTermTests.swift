import WPInference

import XCTest

class WPTermTests: XCTestCase {
  func testSimplify() {
    let term1: WPTerm = .equal(lhs: .integer(1) + .integer(1), rhs: .integer(2))
    XCTAssertEqual(term1.simplified, .integer(1))
    
    let term2: WPTerm = .double(0.5) * .equal(lhs: .integer(1) + .integer(1), rhs: .integer(2))
    XCTAssertEqual(term2.simplified, .double(0.5))
    
    //(0.5) * ([1 + 1 = 2]) + (0.5) * ([2 + 1 = 2])
    let term3: WPTerm = .double(0.5) * .equal(lhs: .integer(2) + .integer(1), rhs: .integer(2))
    XCTAssertEqual(term3.simplified, .double(0))
    
    let term4 = term2 + term3
    XCTAssertEqual(term4.simplified, .double(0.5))
  }
}
