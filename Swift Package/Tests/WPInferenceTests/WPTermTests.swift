import IR
@testable import WPInference

import XCTest

class WPTermTests: XCTestCase {
  func testSimplify() {
    let term1: WPTerm = .equal(lhs: .integer(1) + .integer(1), rhs: .integer(2))
    XCTAssertEqual(term1, .bool(true))
    
    let term2: WPTerm = .double(0.5) * .boolToInt(.equal(lhs: .integer(1) + .integer(1), rhs: .integer(2)))
    XCTAssertEqual(term2, .double(0.5))
    
    let term3: WPTerm = .double(0.5) * .boolToInt(.equal(lhs: .integer(2) + .integer(1), rhs: .integer(2)))
    XCTAssertEqual(term3, .integer(0))
    
    let term4 = term2 + term3
    XCTAssertEqual(term4, .double(0.5))
    
    let term5: WPTerm = .integer(5) - .integer(1) - .integer(1)
    XCTAssertEqual(term5, .integer(3))
    
    let var1 = IRVariable(name: "1", type: .bool)
    let var2 = IRVariable(name: "2", type: .bool)
    
    let additionListEntries = [
      WPTermAdditionListEntry(factor: 1, conditions: [.variable(var1), .variable(var2)], term: .integer(1)),
      WPTermAdditionListEntry(factor: 1, conditions: [.variable(var1), .not(.variable(var2))], term: .integer(1)),
      WPTermAdditionListEntry(factor: 1, conditions: [.not(.variable(var1)), .variable(var2)], term: .integer(1)),
      WPTermAdditionListEntry(factor: 1, conditions: [.not(.variable(var1)), .not(.variable(var2))], term: .integer(1))
    ]
    let additionList = WPTerm._additionList(WPAdditionList(additionListEntries))
    XCTAssertEqual(additionList.simplified(recursively: false), .integer(1))
  }
  
  func testAdditionListMergesConditions() {
    let var1 = IRVariable(name: "1", type: .bool)
    let var2 = IRVariable(name: "2", type: .bool)
    
    let additionListEntries = [
      WPTermAdditionListEntry(factor: 1, conditions: [.variable(var1), .variable(var2)], term: .integer(1)),
      WPTermAdditionListEntry(factor: 1, conditions: [.variable(var1), .not(.variable(var2))], term: .integer(1)),
      WPTermAdditionListEntry(factor: 1, conditions: [.not(.variable(var1)), .variable(var2)], term: .integer(1)),
      WPTermAdditionListEntry(factor: 1, conditions: [.not(.variable(var1)), .not(.variable(var2))], term: .integer(1))
    ]
    let additionList = WPTerm._additionList(WPAdditionList(additionListEntries))
    XCTAssertEqual(additionList.simplified(recursively: false), .integer(1))
  }
  
  func testAdditionListMergesConditionsInTwoSteps() {
    let var1 = IRVariable(name: "1", type: .bool)
    let var2 = IRVariable(name: "2", type: .bool)
    
    let additionListEntries = [
      WPTermAdditionListEntry(factor: 1, conditions: [.variable(var1), .variable(var2)], term: .integer(1)),
      WPTermAdditionListEntry(factor: 1, conditions: [.variable(var1), .not(.variable(var2))], term: .integer(1)),
      WPTermAdditionListEntry(factor: 1, conditions: [.not(.variable(var1))], term: .integer(1)),
    ]
    let additionList = WPTerm._additionList(WPAdditionList(additionListEntries))
    XCTAssertEqual(additionList.simplified(recursively: false), .integer(1))
  }
  
  func testAdditionListEntriesWithZeroTermsGetRemoved() {
    let distribution = [0: 0.5, 1: 0.5]
    let var1 = IRVariable(name: "1", type: .int)
    let var2 = IRVariable(name: "2", type: .int)
    let term = WPTerm.boolToInt(.equal(lhs: .variable(var1), rhs: .integer(0))) * WPTerm.boolToInt(.not(.equal(lhs: .variable(var2), rhs: .integer(1))))
    let terms = distribution.map({ (value, probability) in
      return .double(probability) * term.replacing(variable: var1, with: .integer(value))
    })
    XCTAssertEqual(WPTerm.add(terms: terms), WPTerm.boolToInt(.not(.equal(lhs: .variable(var2), rhs: .integer(1)))) * .double(0.5))
  }
  
  func testRecursivelySimplifyAdditionList() {
    let additionListEntries = [
      WPTermAdditionListEntry(factor: 1, conditions: [._equal(lhs: .bool(true), rhs: .bool(true))], term: ._mul(terms: [.integer(1), .integer(2)])),
    ]
    let additionList = WPTerm._additionList(WPAdditionList(additionListEntries))
    XCTAssertEqual(additionList.simplified(recursively: true), .double(2.0))
  }
  
  func testMergeDuplicateEntriesWithDifferentFactors() {
    let queryVar = IRVariable(name: "$query", type: .int)
    
    let condition = WPTerm.boolToInt(.equal(lhs: .integer(1), rhs: .variable(queryVar)))
    
    let additionTerms: [WPTerm] = [
      condition * .double(20),
      condition * .double(4),
      condition * .double(16),
    ]
    
    XCTAssertEqual(WPTerm.add(terms: additionTerms), condition * .double(40))
  }
}
