@testable import IR

import XCTest

class IRAnalysisTests: XCTestCase {
  func testComputeLoopsForProgramWithOneLoop() {
    let bb1 = BasicBlockName("bb1")
    let bb2 = BasicBlockName("bb2")
    let bb3 = BasicBlockName("bb3")
    let bb4 = BasicBlockName("bb4")
    
    let directSuccessors: [BasicBlockName: Set<BasicBlockName>] = [
      bb1: [bb2],
      bb2: [bb3, bb4],
      bb3: [bb2],
      bb4: [],
    ]
    
    XCTAssertEqual(IRAnalysis.loops(directSuccessors: directSuccessors), [[bb2, bb3]])
  }
  
  func testComputeLoopsWithBranchInLoop() {
    let bb1 = BasicBlockName("bb1")
    let bb2 = BasicBlockName("bb2")
    let bb3 = BasicBlockName("bb3")
    let bb4 = BasicBlockName("bb4")
    let bb5 = BasicBlockName("bb5")
    let bb6 = BasicBlockName("bb6")
    let bb7 = BasicBlockName("bb7")
    
    let directSuccessors: [BasicBlockName: Set<BasicBlockName>] = [
      bb1: [bb2],
      bb2: [bb3, bb7],
      bb3: [bb4, bb5],
      bb4: [bb6],
      bb5: [bb6],
      bb6: [bb2],
      bb7: [],
    ]
    
    XCTAssertEqual(IRAnalysis.loops(directSuccessors: directSuccessors), [
      [bb2, bb3, bb5, bb6],
      [bb2, bb3, bb4, bb6]
    ])
  }
}
