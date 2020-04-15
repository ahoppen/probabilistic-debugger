import IR
import WPInference

import XCTest

class WPInferenceEngineTests: XCTestCase {
  func testInferDeterministicStraightLineProgram() {
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
    
    let inferenceEngine = WPInferenceEngine(program: irProgram)
    XCTAssertEqual(inferenceEngine.infer(term: .boolToInt(.equal(lhs: .variable(var1), rhs: .integer(2)))), 1)
    XCTAssertEqual(inferenceEngine.infer(term: .boolToInt(.equal(lhs: .variable(var1), rhs: .integer(1)))), 0)
  }
  
  func testInferProbabilisticStraightLineProgram() {
    let bb0Name = BasicBlockName("bb0")
    
    let var0 = IRVariable(name: "0", type: .int)
    let var1 = IRVariable(name: "1", type: .int)
    
    let bb0 = BasicBlock(name: bb0Name, instructions: [
      DiscreteDistributionInstruction(assignee: var0, distribution: [1: 0.6, 2: 0.4]),
      AddInstruction(assignee: var1, lhs: .variable(var0), rhs: .integer(1)),
      ReturnInstruction(),
    ])
    
    let irProgram = IRProgram(startBlock: bb0Name, basicBlocks: [bb0])
    // bb0:
    //   int %0 = int 1
    //   int %1 = add int %0 int 1
    //   return
    
    let inferenceEngine = WPInferenceEngine(program: irProgram)
    XCTAssertEqual(inferenceEngine.infer(term: .boolToInt(.equal(lhs: .variable(var1), rhs: .integer(2)))), 0.6)
    XCTAssertEqual(inferenceEngine.infer(term: .boolToInt(.equal(lhs: .variable(var1), rhs: .integer(3)))), 0.4)
    XCTAssertEqual(inferenceEngine.infer(term: .boolToInt(.equal(lhs: .variable(var1), rhs: .integer(4)))), 0)
  }

  func testInferProgramWithJump() {
    let bb0Name = BasicBlockName("bb0")
    let bb1Name = BasicBlockName("bb1")

    let var0 = IRVariable(name: "0", type: .int)
    let var1 = IRVariable(name: "1", type: .int)

    let bb0 = BasicBlock(name: bb0Name, instructions: [
      DiscreteDistributionInstruction(assignee: var0, distribution: [1: 0.6, 2: 0.4]),
      JumpInstruction(target: bb1Name),
    ])

    let bb1 = BasicBlock(name: bb1Name, instructions: [
      AddInstruction(assignee: var1, lhs: .variable(var0), rhs: .integer(1)),
      ReturnInstruction(),
    ])

    let irProgram = IRProgram(startBlock: bb0Name, basicBlocks: [bb0, bb1])
    // bb0:
    //   int %0 = int 1
    //   jump bb1
    //
    // bb1:
    //   int %1 = add int %0 int 1
    //   return

    let inferenceEngine = WPInferenceEngine(program: irProgram)
    XCTAssertEqual(inferenceEngine.infer(term: .boolToInt(.equal(lhs: .variable(var1), rhs: .integer(2)))), 0.6)
    XCTAssertEqual(inferenceEngine.infer(term: .boolToInt(.equal(lhs: .variable(var1), rhs: .integer(3)))), 0.4)
    XCTAssertEqual(inferenceEngine.infer(term: .boolToInt(.equal(lhs: .variable(var1), rhs: .integer(4)))), 0)
  }
  
  func testInferProgramWithTwoSuccessiveJump() {
    let bb0Name = BasicBlockName("bb0")
    let bb1Name = BasicBlockName("bb1")
    let bb2Name = BasicBlockName("bb2")

    let var0 = IRVariable(name: "0", type: .int)
    let var1 = IRVariable(name: "1", type: .int)

    let bb0 = BasicBlock(name: bb0Name, instructions: [
      DiscreteDistributionInstruction(assignee: var0, distribution: [1: 0.6, 2: 0.4]),
      JumpInstruction(target: bb1Name),
    ])
    
    let bb1 = BasicBlock(name: bb1Name, instructions: [
      JumpInstruction(target: bb2Name),
    ])

    let bb2 = BasicBlock(name: bb2Name, instructions: [
      AddInstruction(assignee: var1, lhs: .variable(var0), rhs: .integer(1)),
      ReturnInstruction(),
    ])

    let irProgram = IRProgram(startBlock: bb0Name, basicBlocks: [bb0, bb1, bb2])
    // bb0:
    //   int %0 = int 1
    //   jump bb1
    //
    // bb1:
    //   jump bb2
    //
    // bb2:
    //   int %1 = add int %0 int 1
    //   return

    let inferenceEngine = WPInferenceEngine(program: irProgram)
    XCTAssertEqual(inferenceEngine.infer(term: .boolToInt(.equal(lhs: .variable(var1), rhs: .integer(2)))), 0.6)
    XCTAssertEqual(inferenceEngine.infer(term: .boolToInt(.equal(lhs: .variable(var1), rhs: .integer(3)))), 0.4)
    XCTAssertEqual(inferenceEngine.infer(term: .boolToInt(.equal(lhs: .variable(var1), rhs: .integer(4)))), 0)
  }
  
  func testInferProgramWithIf() {
    let bb0Name = BasicBlockName("bb0")
    let bb1Name = BasicBlockName("bb1")
    let bb2Name = BasicBlockName("bb2")
    let bb3Name = BasicBlockName("bb3")

    let var0 = IRVariable(name: "0", type: .int)
    let var1 = IRVariable(name: "1", type: .bool)
    let var2 = IRVariable(name: "2", type: .int)
    let var3 = IRVariable(name: "3", type: .int)
    let var4 = IRVariable(name: "4", type: .int)

    let bb0 = BasicBlock(name: bb0Name, instructions: [
      DiscreteDistributionInstruction(assignee: var0, distribution: [1: 0.6, 2: 0.4]),
      CompareInstruction(comparison: .equal, assignee: var1, lhs: .variable(var0), rhs: .integer(1)),
      BranchInstruction(condition: .variable(var1), targetTrue: bb1Name, targetFalse: bb2Name)
    ])

    let bb1 = BasicBlock(name: bb1Name, instructions: [
      AssignInstruction(assignee: var2, value: .integer(10)),
      JumpInstruction(target: bb3Name)
    ])

    let bb2 = BasicBlock(name: bb2Name, instructions: [
      AssignInstruction(assignee: var3, value: .integer(20)),
      JumpInstruction(target: bb3Name)
    ])

    let bb3 = BasicBlock(name: bb3Name, instructions: [
      PhiInstruction(assignee: var4, choices: [bb1Name: var2, bb2Name: var3]),
      ReturnInstruction()
    ])

    let irProgram = IRProgram(startBlock: bb0Name, basicBlocks: [bb0, bb1, bb2, bb3])
    print(irProgram)
    // bb0:
    //   int %0 = discrete 2: 0.4, 1: 0.6
    //   bool %1 = cmp eq int %0 int 1
    //   br bool %1 bb1 bb2
    //
    // bb1:
    //   int %2 = int 10
    //   jump bb3
    //
    // bb2:
    //   int %3 = int 20
    //   jump bb3
    //
    // bb3:
    //   int %4 = phi bb1: int %2, bb2: int %3
    //   return
    //
    // equivalent to:
    //
    // int y = <not initialized>
    // if (discrete({1: 0.6, 2: 0.4}) == 1) {
    //   y = 10
    // } else {
    //   y = 20
    // }

    let inferenceEngine = WPInferenceEngine(program: irProgram)
    XCTAssertEqual(inferenceEngine.infer(term: .boolToInt(.equal(lhs: .variable(var4), rhs: .integer(10)))), 0.6)
    XCTAssertEqual(inferenceEngine.infer(term: .boolToInt(.equal(lhs: .variable(var4), rhs: .integer(20)))), 0.4)
    XCTAssertEqual(inferenceEngine.infer(term: .boolToInt(.equal(lhs: .variable(var4), rhs: .integer(15)))), 0)
  }
}
