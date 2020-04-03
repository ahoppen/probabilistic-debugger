import IR
import IRExecution
import TestUtils

import XCTest

class IRExecutorStepTests: XCTestCase {
  func testDeterministicExecutionWithoutBranch() {
    let bb0Name = BasicBlockName("bb0")
    
    let var0 = IRVariable(name: "0", type: .int)
    let var1 = IRVariable(name: "1", type: .int)

    let bb0 = BasicBlock(name: bb0Name, instructions: [
      AssignInstruction(assignee: var0, value: .integer(1)),
      AddInstruction(assignee: var1, lhs: .variable(var0), rhs: .integer(1)),
      ReturnInstruction(),
    ])

    let irProgram = IRProgram(startBlock: bb0Name, basicBlocks: [bb0])
    // bb0:
    //   int %0 = int 1
    //   int %1 = add int %0 int 1
    //   return

    let executor = IRExecutor(program: irProgram)
    let initialState = IRExecutionState(initialStateIn: irProgram, sampleCount: 1)
    
    XCTAssertNoThrow(try {
      let step1StateOptional = try executor.runSingleBranchUntilCondition(state: initialState, stopCondition: { (position) in
        position.instructionIndex == 1
      })
      guard let step1State = step1StateOptional else {
        XCTFail(); return
      }
      XCTAssertEqual(step1State.samples.only.values, [
        var0: .integer(1)
      ])
      let step2StateOptional = try executor.runSingleBranchUntilCondition(state: step1State, stopCondition: { (position) in
        position.instructionIndex == 2
      })
      guard let step2State = step2StateOptional else {
        XCTFail(); return
      }
      XCTAssertEqual(step2State.samples.only.values, [
        var0: .integer(1),
        var1: .integer(2)
      ])
    }())
  }
}
