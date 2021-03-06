import IR
import IRExecution
@testable import WPInference

import XCTest

fileprivate extension LoopUnrolls {
  static let empty = LoopUnrolls([:])
}

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
    
    XCTAssertEqual(inferenceEngine.inferProbability(of: var1, beingEqualTo: .integer(2), loopUnrolls: .empty, to: irProgram.returnPosition, branchingHistory: []), 1)
    XCTAssertEqual(inferenceEngine.inferProbability(of: var1, beingEqualTo: .integer(1), loopUnrolls: .empty, to: irProgram.returnPosition, branchingHistory: []), 0)
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
    XCTAssertEqual(inferenceEngine.inferProbability(of: var1, beingEqualTo: .integer(2), loopUnrolls: .empty, to: irProgram.returnPosition, branchingHistory: []), 0.6)
    XCTAssertEqual(inferenceEngine.inferProbability(of: var1, beingEqualTo: .integer(3), loopUnrolls: .empty, to: irProgram.returnPosition, branchingHistory: []), 0.4)
    XCTAssertEqual(inferenceEngine.inferProbability(of: var1, beingEqualTo: .integer(4), loopUnrolls: .empty, to: irProgram.returnPosition, branchingHistory: []), 0)
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
    XCTAssertEqual(inferenceEngine.inferProbability(of: var1, beingEqualTo: .integer(2), loopUnrolls: .empty, to: irProgram.returnPosition, branchingHistory: []), 0.6)
    XCTAssertEqual(inferenceEngine.inferProbability(of: var1, beingEqualTo: .integer(3), loopUnrolls: .empty, to: irProgram.returnPosition, branchingHistory: []), 0.4)
    XCTAssertEqual(inferenceEngine.inferProbability(of: var1, beingEqualTo: .integer(4), loopUnrolls: .empty, to: irProgram.returnPosition, branchingHistory: []), 0)
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
    XCTAssertEqual(inferenceEngine.inferProbability(of: var1, beingEqualTo: .integer(2), loopUnrolls: .empty, to: irProgram.returnPosition, branchingHistory: []), 0.6)
    XCTAssertEqual(inferenceEngine.inferProbability(of: var1, beingEqualTo: .integer(3), loopUnrolls: .empty, to: irProgram.returnPosition, branchingHistory: []), 0.4)
    XCTAssertEqual(inferenceEngine.inferProbability(of: var1, beingEqualTo: .integer(4), loopUnrolls: .empty, to: irProgram.returnPosition, branchingHistory: []), 0)
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
    let inferred = inferenceEngine.infer(term: .variable(var4), loopUnrolls: .empty, inferenceStopPosition: irProgram.returnPosition, branchingHistory: [.any(predominatedBy: irProgram.startBlock)])
    XCTAssertEqual(inferred.value.doubleValue, 14)
    XCTAssertEqual(inferred.focusRate.doubleValue, 1)
    XCTAssertEqual(inferred.observeAndDeliberateBranchIgnoringFocusRate.doubleValue, 1)
    
    XCTAssertEqual(inferenceEngine.inferProbability(of: var4, beingEqualTo: .integer(10), loopUnrolls: .empty, to: irProgram.returnPosition, branchingHistory: [.any(predominatedBy: irProgram.startBlock)]), 0.6)
    XCTAssertEqual(inferenceEngine.inferProbability(of: var4, beingEqualTo: .integer(20), loopUnrolls: .empty, to: irProgram.returnPosition, branchingHistory: [.any(predominatedBy: irProgram.startBlock)]), 0.4)
    XCTAssertEqual(inferenceEngine.inferProbability(of: var4, beingEqualTo: .integer(16), loopUnrolls: .empty, to: irProgram.returnPosition, branchingHistory: [.any(predominatedBy: irProgram.startBlock)]), 0)
  }
  
  func testFoo() {
    let var1 = IRVariable(name: "1", type: .int)
    let var2 = IRVariable(name: "2", type: .bool)
    let var3 = IRVariable(name: "3", type: .int)
    let var4 = IRVariable(name: "4", type: .int)
    let var5 = IRVariable(name: "5", type: .int)
    let var6 = IRVariable(name: "6", type: .int)

    let bb1Name = BasicBlockName("bb1")
    let bb2Name = BasicBlockName("bb2")
    let bb3Name = BasicBlockName("bb3")
    let bb4Name = BasicBlockName("bb4")

    let bb1 = BasicBlock(name: bb1Name, instructions: [
      AssignInstruction(assignee: var1, value: .integer(2)),
      JumpInstruction(target: bb2Name)
    ])

    let bb2 = BasicBlock(name: bb2Name, instructions: [
      PhiInstruction(assignee: var5, choices: [bb1Name: var1, bb3Name: var4]),
      CompareInstruction(comparison: .lessThan, assignee: var2, lhs: .integer(1), rhs: .variable(var5)),
      BranchInstruction(condition: .variable(var2), targetTrue: bb3Name, targetFalse: bb4Name)
    ])

    let bb3 = BasicBlock(name: bb3Name, instructions: [
      SubtractInstruction(assignee: var3, lhs: .variable(var5), rhs: .integer(1)),
      AssignInstruction(assignee: var4, value: .variable(var3)),
      JumpInstruction(target: bb2Name)
    ])

    let bb4 = BasicBlock(name: bb4Name, instructions: [
      AssignInstruction(assignee: var6, value: .variable(var5)),
      ReturnInstruction(),
    ])
    // bb1:
    //   int %1 = int 2
    //   jump bb2
    //
    // bb2:
    //   int %5 = phi bb1: int %1, bb3: int %4
    //   bool %2 = cmp lt int 1 int %5
    //   br bool %2 bb3 bb4
    //
    // bb3:
    //   int %3 = sub int %5 int 1
    //   int %4 = int %3
    //   jump bb2
    //
    // bb4:
    //   %6 = %5
    //   return
    //
    // equivalent to:
    //
    // int x = 2
    // while 1 < x {
    //   x = x - 1
    // }

    let program = IRProgram(startBlock: bb1Name, basicBlocks: [bb1, bb2, bb3, bb4])
    let whileLoopBranch = IRLoop(
      conditionBlock: bb2Name,
      bodyStartBlock: bb3Name
    )
    let loopUnrolls = LoopUnrolls([whileLoopBranch: 5])

    let inferenceEngine = WPInferenceEngine(program: program)
    XCTAssertEqual(inferenceEngine.inferProbability(of: var6, beingEqualTo: .integer(0), loopUnrolls: loopUnrolls, to: program.returnPosition, branchingHistory: [.any(predominatedBy: program.startBlock)]), 0)
    XCTAssertEqual(inferenceEngine.inferProbability(of: var6, beingEqualTo: .integer(1), loopUnrolls: loopUnrolls, to: program.returnPosition, branchingHistory: [.any(predominatedBy: program.startBlock)]), 1)
    XCTAssertEqual(inferenceEngine.inferProbability(of: var6, beingEqualTo: .integer(2), loopUnrolls: loopUnrolls, to: program.returnPosition, branchingHistory: [.any(predominatedBy: program.startBlock)]), 0)
    XCTAssertEqual(inferenceEngine.inferProbability(of: var6, beingEqualTo: .integer(3), loopUnrolls: loopUnrolls, to: program.returnPosition, branchingHistory: [.any(predominatedBy: program.startBlock)]), 0)
    XCTAssertEqual(inferenceEngine.inferProbability(of: var6, beingEqualTo: .integer(4), loopUnrolls: loopUnrolls, to: program.returnPosition, branchingHistory: [.any(predominatedBy: program.startBlock)]), 0)
    XCTAssertEqual(inferenceEngine.inferProbability(of: var6, beingEqualTo: .integer(5), loopUnrolls: loopUnrolls, to: program.returnPosition, branchingHistory: [.any(predominatedBy: program.startBlock)]), 0)
    XCTAssertEqual(inferenceEngine.inferProbability(of: var6, beingEqualTo: .integer(6), loopUnrolls: loopUnrolls, to: program.returnPosition, branchingHistory: [.any(predominatedBy: program.startBlock)]), 0)
  }
  
  func testInferFiniteDeterministicLoop() {
    let var1 = IRVariable(name: "1", type: .int)
    let var2 = IRVariable(name: "2", type: .bool)
    let var3 = IRVariable(name: "3", type: .int)
    let var4 = IRVariable(name: "4", type: .int)
    let var5 = IRVariable(name: "5", type: .int)
    let var6 = IRVariable(name: "6", type: .int)

    let bb1Name = BasicBlockName("bb1")
    let bb2Name = BasicBlockName("bb2")
    let bb3Name = BasicBlockName("bb3")
    let bb4Name = BasicBlockName("bb4")

    let bb1 = BasicBlock(name: bb1Name, instructions: [
      AssignInstruction(assignee: var1, value: .integer(5)),
      JumpInstruction(target: bb2Name)
    ])

    let bb2 = BasicBlock(name: bb2Name, instructions: [
      PhiInstruction(assignee: var5, choices: [bb1Name: var1, bb3Name: var4]),
      CompareInstruction(comparison: .lessThan, assignee: var2, lhs: .integer(1), rhs: .variable(var5)),
      BranchInstruction(condition: .variable(var2), targetTrue: bb3Name, targetFalse: bb4Name)
    ])

    let bb3 = BasicBlock(name: bb3Name, instructions: [
      SubtractInstruction(assignee: var3, lhs: .variable(var5), rhs: .integer(1)),
      AssignInstruction(assignee: var4, value: .variable(var3)),
      JumpInstruction(target: bb2Name)
    ])

    let bb4 = BasicBlock(name: bb4Name, instructions: [
      AssignInstruction(assignee: var6, value: .variable(var5)),
      ReturnInstruction(),
    ])
    // bb1:
    //   int %1 = int 5
    //   jump bb2
    //
    // bb2:
    //   int %5 = phi bb1: int %1, bb3: int %4
    //   bool %2 = cmp lt int 1 int %5
    //   br bool %2 bb3 bb4
    //
    // bb3:
    //   int %3 = sub int %5 int 1
    //   int %4 = int %3
    //   jump bb2
    //
    // bb4:
    //   %6 = %5
    //   return
    //
    // equivalent to:
    //
    // int x = 5
    // while 1 < x {
    //   x = x - 1
    // }

    let program = IRProgram(startBlock: bb1Name, basicBlocks: [bb1, bb2, bb3, bb4])
    let whileLoopBranch = IRLoop(
      conditionBlock: bb2Name,
      bodyStartBlock: bb3Name
    )
    let loopUnrolls = LoopUnrolls([whileLoopBranch: 5])

    let inferenceEngine = WPInferenceEngine(program: program)
    XCTAssertEqual(inferenceEngine.inferProbability(of: var6, beingEqualTo: .integer(0), loopUnrolls: loopUnrolls, to: program.returnPosition, branchingHistory: [.any(predominatedBy: program.startBlock)]), 0)
    XCTAssertEqual(inferenceEngine.inferProbability(of: var6, beingEqualTo: .integer(1), loopUnrolls: loopUnrolls, to: program.returnPosition, branchingHistory: [.any(predominatedBy: program.startBlock)]), 1)
    XCTAssertEqual(inferenceEngine.inferProbability(of: var6, beingEqualTo: .integer(2), loopUnrolls: loopUnrolls, to: program.returnPosition, branchingHistory: [.any(predominatedBy: program.startBlock)]), 0)
    XCTAssertEqual(inferenceEngine.inferProbability(of: var6, beingEqualTo: .integer(3), loopUnrolls: loopUnrolls, to: program.returnPosition, branchingHistory: [.any(predominatedBy: program.startBlock)]), 0)
    XCTAssertEqual(inferenceEngine.inferProbability(of: var6, beingEqualTo: .integer(4), loopUnrolls: loopUnrolls, to: program.returnPosition, branchingHistory: [.any(predominatedBy: program.startBlock)]), 0)
    XCTAssertEqual(inferenceEngine.inferProbability(of: var6, beingEqualTo: .integer(5), loopUnrolls: loopUnrolls, to: program.returnPosition, branchingHistory: [.any(predominatedBy: program.startBlock)]), 0)
    XCTAssertEqual(inferenceEngine.inferProbability(of: var6, beingEqualTo: .integer(6), loopUnrolls: loopUnrolls, to: program.returnPosition, branchingHistory: [.any(predominatedBy: program.startBlock)]), 0)
  }

  func testInferGeometricDistribution() {
    let var1 = IRVariable(name: "1", type: .int)
    let var2 = IRVariable(name: "2", type: .int)
    let var3 = IRVariable(name: "3", type: .bool)
    let var4 = IRVariable(name: "4", type: .int)
    let var5 = IRVariable(name: "5", type: .int)
    let var6 = IRVariable(name: "6", type: .int)

    let bb1Name = BasicBlockName("bb1")
    let bb2Name = BasicBlockName("bb2")
    let bb3Name = BasicBlockName("bb3")
    let bb4Name = BasicBlockName("bb4")

    let bb1 = BasicBlock(name: bb1Name, instructions: [
      AssignInstruction(assignee: var1, value: .integer(0)),
      JumpInstruction(target: bb2Name)
    ])

    let bb2 = BasicBlock(name: bb2Name, instructions: [
      PhiInstruction(assignee: var6, choices: [bb1Name: var1, bb3Name: var5]),
      DiscreteDistributionInstruction(assignee: var2, distribution: [0: 0.5, 1: 0.5]),
      CompareInstruction(comparison: .equal, assignee: var3, lhs: .variable(var2), rhs: .integer(0)),
      BranchInstruction(condition: .variable(var3), targetTrue: bb3Name, targetFalse: bb4Name)
    ])

    let bb3 = BasicBlock(name: bb3Name, instructions: [
      AddInstruction(assignee: var4, lhs: .variable(var6), rhs: .integer(1)),
      AssignInstruction(assignee: var5, value: .variable(var4)),
      JumpInstruction(target: bb2Name)
    ])

    let bb4 = BasicBlock(name: bb4Name, instructions: [
      ReturnInstruction(),
    ])
    // bb1:
    //   int %1 = int 0
    //   jump bb2
    //
    // bb2:
    //   int %6 = phi bb1: int %1, bb3: int %5
    //   int %2 = discrete 1: 0.5, 0: 0.5
    //   bool %3 = cmp eq int %2 int 0
    //   br bool %3 bb3 bb4
    //
    // bb3:
    //   int %4 = add int %6 int 1
    //   int %5 = int %4
    //   jump bb2
    //
    // bb4:
    //   return
    //
    // equivalent to:
    //
    // int value = 0
    // while discrete({0: 0.5, 1: 0.5}) == 0 {
    //   value = value + 1
    // }

    let program = IRProgram(startBlock: bb1Name, basicBlocks: [bb1, bb2, bb3, bb4])
    let whileLoopBranch = IRLoop(
      conditionBlock: bb2Name,
      bodyStartBlock: bb3Name
    )
    let loopUnrolls = LoopUnrolls([whileLoopBranch: 3])

    let inferenceEngine = WPInferenceEngine(program: program)
    
    let inferred = inferenceEngine.infer(term: .probability(of: var6, equalTo: .integer(0)), loopUnrolls: loopUnrolls, inferenceStopPosition: program.returnPosition, branchingHistory: [.any(predominatedBy: program.startBlock)])
    XCTAssertEqual(inferred.value.doubleValue, 0.5)
    XCTAssertEqual(inferred.focusRate.doubleValue, 0.9375)
    XCTAssertEqual(inferred.observeAndDeliberateBranchIgnoringFocusRate.doubleValue, 0.9375)
    
    
//    XCTAssertEqual(inferenceEngine.inferProbability(of: var6, beingEqualTo: .integer(0), loopUnrolls: loopUnrolls, to: program.returnPosition, branchingHistory: [.any(predominatedBy: program.startBlock)]), 0.5)
//    XCTAssertEqual(inferenceEngine.inferProbability(of: var6, beingEqualTo: .integer(1), loopUnrolls: loopUnrolls, to: program.returnPosition, branchingHistory: [.any(predominatedBy: program.startBlock)]), 0.25)
    XCTAssertEqual(inferenceEngine.inferProbability(of: var6, beingEqualTo: .integer(2), loopUnrolls: loopUnrolls, to: program.returnPosition, branchingHistory: [.any(predominatedBy: program.startBlock)]), 0.125)
//    XCTAssertEqual(inferenceEngine.inferProbability(of: var6, beingEqualTo: .integer(3), loopUnrolls: loopUnrolls, to: program.returnPosition, branchingHistory: [.any(predominatedBy: program.startBlock)]), 0.0625)
//    XCTAssertEqual(inferenceEngine.inferProbability(of: var6, beingEqualTo: .integer(4), loopUnrolls: loopUnrolls, to: program.returnPosition, branchingHistory: [.any(predominatedBy: program.startBlock)]), 0)
  }

  func testInferWithMultiplePhiInstructions() {
    let var1 = IRVariable(name: "1", type: .int)
    let var2 = IRVariable(name: "2", type: .int)
    let var3 = IRVariable(name: "3", type: .int)

    let bb1Name = BasicBlockName("bb1")
    let bb2Name = BasicBlockName("bb2")

    let bb1 = BasicBlock(name: bb1Name, instructions: [
      AssignInstruction(assignee: var1, value: .integer(1)),
      JumpInstruction(target: bb2Name)
    ])

    let bb2 = BasicBlock(name: bb2Name, instructions: [
      PhiInstruction(assignee: var2, choices: [bb1Name: var1]),
      PhiInstruction(assignee: var3, choices: [bb1Name: var1]),
      ReturnInstruction()
    ])

    let program = IRProgram(startBlock: bb1Name, basicBlocks: [bb1, bb2])

    let inferenceEngine = WPInferenceEngine(program: program)
    XCTAssertEqual(inferenceEngine.inferProbability(of: var2, beingEqualTo: .integer(1), loopUnrolls: .empty, to: program.returnPosition, branchingHistory: []), 1)
    XCTAssertEqual(inferenceEngine.inferProbability(of: var3, beingEqualTo: .integer(1), loopUnrolls: .empty, to: program.returnPosition, branchingHistory: []), 1)
  }

  func testInferWithObserveInstruction() {
    let var1 = IRVariable(name: "1", type: .int)
    let var2 = IRVariable(name: "2", type: .bool)

    let bb1Name = BasicBlockName("bb1")

    let bb1 = BasicBlock(name: bb1Name, instructions: [
      DiscreteDistributionInstruction(assignee: var1, distribution: [1: 0.6, 2: 0.4]),
      CompareInstruction(comparison: .equal, assignee: var2, lhs: .variable(var1), rhs: .integer(1)),
      ObserveInstruction(observation: .variable(var2)),
      ReturnInstruction()
    ])

    let program = IRProgram(startBlock: bb1Name, basicBlocks: [bb1])

    let inferenceEngine = WPInferenceEngine(program: program)
    XCTAssertEqual(inferenceEngine.inferProbability(of: var1, beingEqualTo: .integer(1), loopUnrolls: .empty, to: program.returnPosition, branchingHistory: []), 1)
  }

  func testUnrollALoopAnExactNumberOfTimes() {
    let var1 = IRVariable(name: "1", type: .int)
    let var2 = IRVariable(name: "2", type: .int)
    let var3 = IRVariable(name: "3", type: .bool)
    let var4 = IRVariable(name: "4", type: .int)
    let var5 = IRVariable(name: "5", type: .int)
    let var6 = IRVariable(name: "6", type: .int)

    let bb1Name = BasicBlockName("bb1")
    let bb2Name = BasicBlockName("bb2")
    let bb3Name = BasicBlockName("bb3")
    let bb4Name = BasicBlockName("bb4")

    let bb1 = BasicBlock(name: bb1Name, instructions: [
      AssignInstruction(assignee: var1, value: .integer(0)),
      JumpInstruction(target: bb2Name)
    ])

    let bb2 = BasicBlock(name: bb2Name, instructions: [
      PhiInstruction(assignee: var6, choices: [bb1Name: var1, bb3Name: var5]),
      DiscreteDistributionInstruction(assignee: var2, distribution: [0: 0.5, 1: 0.5]),
      CompareInstruction(comparison: .equal, assignee: var3, lhs: .variable(var2), rhs: .integer(0)),
      BranchInstruction(condition: .variable(var3), targetTrue: bb3Name, targetFalse: bb4Name)
    ])

    let bb3 = BasicBlock(name: bb3Name, instructions: [
      AddInstruction(assignee: var4, lhs: .variable(var6), rhs: .integer(1)),
      AssignInstruction(assignee: var5, value: .variable(var4)),
      JumpInstruction(target: bb2Name)
    ])

    let bb4 = BasicBlock(name: bb4Name, instructions: [
      ReturnInstruction(),
    ])
    // bb1:
    //   int %1 = int 0
    //   jump bb2
    //
    // bb2:
    //   int %6 = phi bb1: int %1, bb3: int %5
    //   int %2 = discrete 1: 0.5, 0: 0.5
    //   bool %3 = cmp eq int %2 int 0
    //   br bool %3 bb3 bb4
    //
    // bb3:
    //   int %4 = add int %6 int 1
    //   int %5 = int %4
    //   jump bb2
    //
    // bb4:
    //   return
    //
    // equivalent to:
    //
    // int value = 0
    // while discrete({0: 0.5, 1: 0.5}) == 0 {
    //   value = value + 1
    // }

    let program = IRProgram(startBlock: bb1Name, basicBlocks: [bb1, bb2, bb3, bb4])
    let whileLoopBranch = IRLoop(
      conditionBlock: bb2Name,
      bodyStartBlock: bb3Name
    )
    let loopUnrolls = LoopUnrolls([whileLoopBranch: 1])
    let branchingHistory: BranchingHistory = [.choice(source: bb2Name, target: bb3Name), .choice(source: bb2Name, target: bb4Name)]

    let inferenceEngine = WPInferenceEngine(program: program)
    XCTAssertEqual(inferenceEngine.inferProbability(of: var6, beingEqualTo: .integer(0), loopUnrolls: loopUnrolls, to: program.returnPosition, branchingHistory: branchingHistory), 0)
    XCTAssertEqual(inferenceEngine.inferProbability(of: var6, beingEqualTo: .integer(1), loopUnrolls: loopUnrolls, to: program.returnPosition, branchingHistory: branchingHistory), 1.0)
    XCTAssertEqual(inferenceEngine.inferProbability(of: var6, beingEqualTo: .integer(1), loopUnrolls: loopUnrolls, to: program.returnPosition, branchingHistory: branchingHistory), 1)
    XCTAssertEqual(inferenceEngine.inferProbability(of: var6, beingEqualTo: .integer(2), loopUnrolls: loopUnrolls, to: program.returnPosition, branchingHistory: branchingHistory), 0)
    XCTAssertEqual(inferenceEngine.inferProbability(of: var6, beingEqualTo: .integer(3), loopUnrolls: loopUnrolls, to: program.returnPosition, branchingHistory: branchingHistory), 0)
    XCTAssertEqual(inferenceEngine.inferProbability(of: var6, beingEqualTo: .integer(4), loopUnrolls: loopUnrolls, to: program.returnPosition, branchingHistory: branchingHistory), 0)
  }


  func testPerformance() {
    let var1 = IRVariable(name: "1", type: .int)
    let var2 = IRVariable(name: "2", type: .int)
    let var3 = IRVariable(name: "3", type: .bool)
    let var4 = IRVariable(name: "4", type: .int)
    let var5 = IRVariable(name: "5", type: .int)
    let var6 = IRVariable(name: "6", type: .int)

    let bb1Name = BasicBlockName("bb1")
    let bb2Name = BasicBlockName("bb2")
    let bb3Name = BasicBlockName("bb3")
    let bb4Name = BasicBlockName("bb4")

    let bb1 = BasicBlock(name: bb1Name, instructions: [
      AssignInstruction(assignee: var1, value: .integer(0)),
      JumpInstruction(target: bb2Name)
    ])

    let bb2 = BasicBlock(name: bb2Name, instructions: [
      PhiInstruction(assignee: var6, choices: [bb1Name: var1, bb3Name: var5]),
      DiscreteDistributionInstruction(assignee: var2, distribution: [0: 0.5, 1: 0.5]),
      CompareInstruction(comparison: .equal, assignee: var3, lhs: .variable(var2), rhs: .integer(0)),
      BranchInstruction(condition: .variable(var3), targetTrue: bb3Name, targetFalse: bb4Name)
    ])

    let bb3 = BasicBlock(name: bb3Name, instructions: [
      AddInstruction(assignee: var4, lhs: .variable(var6), rhs: .integer(1)),
      AssignInstruction(assignee: var5, value: .variable(var4)),
      JumpInstruction(target: bb2Name)
    ])

    let bb4 = BasicBlock(name: bb4Name, instructions: [
      ReturnInstruction(),
    ])
    // bb1:
    //   int %1 = int 0
    //   jump bb2
    //
    // bb2:
    //   int %6 = phi bb1: int %1, bb3: int %5
    //   int %2 = discrete 1: 0.5, 0: 0.5
    //   bool %3 = cmp eq int %2 int 0
    //   br bool %3 bb3 bb4
    //
    // bb3:
    //   int %4 = add int %6 int 1
    //   int %5 = int %4
    //   jump bb2
    //
    // bb4:
    //   return
    //
    // equivalent to:
    //
    // int value = 0
    // while discrete({0: 0.5, 1: 0.5}) == 0 {
    //   value = value + 1
    // }

    let program = IRProgram(startBlock: bb1Name, basicBlocks: [bb1, bb2, bb3, bb4])
    let whileLoopBranch = IRLoop(
      conditionBlock: bb2Name,
      bodyStartBlock: bb3Name
    )

    let inferenceEngine = WPInferenceEngine(program: program)
    self.measure {
      let loopUnrolls = LoopUnrolls([whileLoopBranch: 50])
      _ = inferenceEngine.inferProbability(of: var6, beingEqualTo: .integer(1), loopUnrolls: loopUnrolls, to: program.returnPosition, branchingHistory: [.any(predominatedBy: program.startBlock)])
    }
  }

  func testIfInsideLoop() {
    let var1 = IRVariable(name: "1", type: .bool)
    let var2 = IRVariable(name: "2", type: .bool)
    let var3 = IRVariable(name: "3", type: .bool)

    let bb1Name = BasicBlockName("bb1")
    let bb2Name = BasicBlockName("bb2")
    let bb3Name = BasicBlockName("bb3")
    let bb4Name = BasicBlockName("bb4")
    let bb5Name = BasicBlockName("bb5")
    let bb6Name = BasicBlockName("bb6")

    let bb1 = BasicBlock(name: bb1Name, instructions: [
      AssignInstruction(assignee: var1, value: .bool(true)),
      JumpInstruction(target: bb2Name)
    ])

    let bb2 = BasicBlock(name: bb2Name, instructions: [
      PhiInstruction(assignee: var3, choices: [bb1Name: var1, bb6Name: var2]),
      BranchInstruction(condition: .variable(var3), targetTrue: bb3Name, targetFalse: bb4Name)
    ])

    let bb3 = BasicBlock(name: bb3Name, instructions: [
      BranchInstruction(condition: .variable(var3), targetTrue: bb5Name, targetFalse: bb6Name)
    ])

    let bb4 = BasicBlock(name: bb4Name, instructions: [
      ReturnInstruction()
    ])

    let bb5 = BasicBlock(name: bb5Name, instructions: [
      JumpInstruction(target: bb6Name)
    ])

    let bb6 = BasicBlock(name: bb6Name, instructions: [
      AssignInstruction(assignee: var2, value: .bool(false)),
      JumpInstruction(target: bb2Name)
    ])


    let program = IRProgram(startBlock: bb1Name, basicBlocks: [bb1, bb2, bb3, bb4, bb5, bb6])
    let inferenceEngine = WPInferenceEngine(program: program)

    let loopUnrolls = LoopUnrolls([
      IRLoop(conditionBlock: bb2Name, bodyStartBlock: bb3Name): 1
    ])
    let prob = inferenceEngine.inferProbability(of: var3, beingEqualTo: .bool(true), loopUnrolls: loopUnrolls, to: InstructionPosition(basicBlock: bb3Name, instructionIndex: 0), branchingHistory: [.any(predominatedBy: program.startBlock)])

    XCTAssertEqual(prob, 1)
  }

  func testInferFiniteDeterministicLoopAfterFixedNumberOfIterations() {
    let var1 = IRVariable(name: "1", type: .int)
    let var2 = IRVariable(name: "2", type: .bool)
    let var3 = IRVariable(name: "3", type: .int)
    let var4 = IRVariable(name: "4", type: .int)
    let var5 = IRVariable(name: "5", type: .int)
    let var6 = IRVariable(name: "6", type: .int)

    let bb1Name = BasicBlockName("bb1")
    let bb2Name = BasicBlockName("bb2")
    let bb3Name = BasicBlockName("bb3")
    let bb4Name = BasicBlockName("bb4")

    let bb1 = BasicBlock(name: bb1Name, instructions: [
      AssignInstruction(assignee: var1, value: .integer(5)),
      JumpInstruction(target: bb2Name)
    ])

    let bb2 = BasicBlock(name: bb2Name, instructions: [
      PhiInstruction(assignee: var5, choices: [bb1Name: var1, bb3Name: var4]),
      CompareInstruction(comparison: .lessThan, assignee: var2, lhs: .integer(1), rhs: .variable(var5)),
      BranchInstruction(condition: .variable(var2), targetTrue: bb3Name, targetFalse: bb4Name)
    ])

    let bb3 = BasicBlock(name: bb3Name, instructions: [
      SubtractInstruction(assignee: var3, lhs: .variable(var5), rhs: .integer(1)),
      AssignInstruction(assignee: var4, value: .variable(var3)),
      JumpInstruction(target: bb2Name)
    ])

    let bb4 = BasicBlock(name: bb4Name, instructions: [
      AssignInstruction(assignee: var6, value: .variable(var5)),
      ReturnInstruction(),
    ])
    // bb1:
    //   int %1 = int 5
    //   jump bb2
    //
    // bb2:
    //   int %5 = phi bb1: int %1, bb3: int %4
    //   bool %2 = cmp lt int 1 int %5
    //   br bool %2 bb3 bb4
    //
    // bb3:
    //   int %3 = sub int %5 int 1
    //   int %4 = int %3
    //   jump bb2
    //
    // bb4:
    //   %6 = %5
    //   return
    //
    // equivalent to:
    //
    // int x = 5
    // while 1 < x {
    //   x = x - 1
    // }

    let program = IRProgram(startBlock: bb1Name, basicBlocks: [bb1, bb2, bb3, bb4])
    let whileLoopBranch = IRLoop(
      conditionBlock: bb2Name,
      bodyStartBlock: bb3Name
    )

    let position = InstructionPosition(basicBlock: bb3Name, instructionIndex: 0)
    let inferenceEngine = WPInferenceEngine(program: program)
    // After 1 iteration
    let branchingHistory1Unroll: BranchingHistory = [.choice(source: bb2Name, target: bb3Name)]
    XCTAssertEqual(inferenceEngine.inferProbability(of: var5, beingEqualTo: .integer(0), loopUnrolls: LoopUnrolls([whileLoopBranch: 1]), to: position, branchingHistory: branchingHistory1Unroll), 0)
    XCTAssertEqual(inferenceEngine.inferProbability(of: var5, beingEqualTo: .integer(1), loopUnrolls: LoopUnrolls([whileLoopBranch: 1]), to: position, branchingHistory: branchingHistory1Unroll), 0)
    XCTAssertEqual(inferenceEngine.inferProbability(of: var5, beingEqualTo: .integer(2), loopUnrolls: LoopUnrolls([whileLoopBranch: 1]), to: position, branchingHistory: branchingHistory1Unroll), 0)
    XCTAssertEqual(inferenceEngine.inferProbability(of: var5, beingEqualTo: .integer(3), loopUnrolls: LoopUnrolls([whileLoopBranch: 1]), to: position, branchingHistory: branchingHistory1Unroll), 0)
    XCTAssertEqual(inferenceEngine.inferProbability(of: var5, beingEqualTo: .integer(4), loopUnrolls: LoopUnrolls([whileLoopBranch: 1]), to: position, branchingHistory: branchingHistory1Unroll), 0)
    XCTAssertEqual(inferenceEngine.inferProbability(of: var5, beingEqualTo: .integer(5), loopUnrolls: LoopUnrolls([whileLoopBranch: 1]), to: position, branchingHistory: branchingHistory1Unroll), 1)
    
    // After 2 iterations
    let branchingHistory2Unrolls: BranchingHistory = [.choice(source: bb2Name, target: bb3Name), .choice(source: bb2Name, target: bb3Name)]
    XCTAssertEqual(inferenceEngine.inferProbability(of: var5, beingEqualTo: .integer(0), loopUnrolls: LoopUnrolls([whileLoopBranch: 2]), to: position, branchingHistory: branchingHistory2Unrolls), 0)
    XCTAssertEqual(inferenceEngine.inferProbability(of: var5, beingEqualTo: .integer(1), loopUnrolls: LoopUnrolls([whileLoopBranch: 2]), to: position, branchingHistory: branchingHistory2Unrolls), 0)
    XCTAssertEqual(inferenceEngine.inferProbability(of: var5, beingEqualTo: .integer(2), loopUnrolls: LoopUnrolls([whileLoopBranch: 2]), to: position, branchingHistory: branchingHistory2Unrolls), 0)
    XCTAssertEqual(inferenceEngine.inferProbability(of: var5, beingEqualTo: .integer(3), loopUnrolls: LoopUnrolls([whileLoopBranch: 2]), to: position, branchingHistory: branchingHistory2Unrolls), 0)
    XCTAssertEqual(inferenceEngine.inferProbability(of: var5, beingEqualTo: .integer(4), loopUnrolls: LoopUnrolls([whileLoopBranch: 2]), to: position, branchingHistory: branchingHistory2Unrolls), 1)
    XCTAssertEqual(inferenceEngine.inferProbability(of: var5, beingEqualTo: .integer(5), loopUnrolls: LoopUnrolls([whileLoopBranch: 2]), to: position, branchingHistory: branchingHistory2Unrolls), 0)
    
    // After 3 iterations
    let branchingHistory3Unrolls: BranchingHistory = [.choice(source: bb2Name, target: bb3Name), .choice(source: bb2Name, target: bb3Name), .choice(source: bb2Name, target: bb3Name)]
    XCTAssertEqual(inferenceEngine.inferProbability(of: var5, beingEqualTo: .integer(0), loopUnrolls: LoopUnrolls([whileLoopBranch: 3]), to: position, branchingHistory: branchingHistory3Unrolls), 0)
    XCTAssertEqual(inferenceEngine.inferProbability(of: var5, beingEqualTo: .integer(1), loopUnrolls: LoopUnrolls([whileLoopBranch: 3]), to: position, branchingHistory: branchingHistory3Unrolls), 0)
    XCTAssertEqual(inferenceEngine.inferProbability(of: var5, beingEqualTo: .integer(2), loopUnrolls: LoopUnrolls([whileLoopBranch: 3]), to: position, branchingHistory: branchingHistory3Unrolls), 0)
    XCTAssertEqual(inferenceEngine.inferProbability(of: var5, beingEqualTo: .integer(3), loopUnrolls: LoopUnrolls([whileLoopBranch: 3]), to: position, branchingHistory: branchingHistory3Unrolls), 1)
    XCTAssertEqual(inferenceEngine.inferProbability(of: var5, beingEqualTo: .integer(4), loopUnrolls: LoopUnrolls([whileLoopBranch: 3]), to: position, branchingHistory: branchingHistory3Unrolls), 0)
    XCTAssertEqual(inferenceEngine.inferProbability(of: var5, beingEqualTo: .integer(5), loopUnrolls: LoopUnrolls([whileLoopBranch: 3]), to: position, branchingHistory: branchingHistory3Unrolls), 0)
    
    // After 4 iterations
    let branchingHistory4Unrolls: BranchingHistory = [.choice(source: bb2Name, target: bb3Name), .choice(source: bb2Name, target: bb3Name), .choice(source: bb2Name, target: bb3Name), .choice(source: bb2Name, target: bb3Name)]
    XCTAssertEqual(inferenceEngine.inferProbability(of: var5, beingEqualTo: .integer(0), loopUnrolls: LoopUnrolls([whileLoopBranch: 4]), to: position, branchingHistory: branchingHistory4Unrolls), 0)
    XCTAssertEqual(inferenceEngine.inferProbability(of: var5, beingEqualTo: .integer(1), loopUnrolls: LoopUnrolls([whileLoopBranch: 4]), to: position, branchingHistory: branchingHistory4Unrolls), 0)
    XCTAssertEqual(inferenceEngine.inferProbability(of: var5, beingEqualTo: .integer(2), loopUnrolls: LoopUnrolls([whileLoopBranch: 4]), to: position, branchingHistory: branchingHistory4Unrolls), 1)
    XCTAssertEqual(inferenceEngine.inferProbability(of: var5, beingEqualTo: .integer(3), loopUnrolls: LoopUnrolls([whileLoopBranch: 4]), to: position, branchingHistory: branchingHistory4Unrolls), 0)
    XCTAssertEqual(inferenceEngine.inferProbability(of: var5, beingEqualTo: .integer(4), loopUnrolls: LoopUnrolls([whileLoopBranch: 4]), to: position, branchingHistory: branchingHistory4Unrolls), 0)
    XCTAssertEqual(inferenceEngine.inferProbability(of: var5, beingEqualTo: .integer(5), loopUnrolls: LoopUnrolls([whileLoopBranch: 4]), to: position, branchingHistory: branchingHistory4Unrolls), 0)
  }
  
  func testInferWithBranchingHistory() {
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
    // bb0:
    //   int %0 = discrete 1: 0.6, 2: 0.4
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
    let inferred = inferenceEngine.infer(term: .variable(var4), loopUnrolls: .empty, inferenceStopPosition: irProgram.returnPosition, branchingHistory: [.choice(source: bb0Name, target: bb1Name)])
    XCTAssertEqual(inferred.value.doubleValue, 6)
    XCTAssertEqual(inferred.focusRate.doubleValue, 0.6)
    XCTAssertEqual(inferred.observeAndDeliberateBranchIgnoringFocusRate.doubleValue, 1)
    
//    XCTAssertEqual(inferenceEngine.inferProbability(of: var4, beingEqualTo: .integer(10), loopUnrolls: .empty, to: irProgram.returnPosition, branchingHistory: [.choice(source: bb0Name, target: bb1Name)]), 1)
  }
  
  func testInferWithBranchingHistoryInLoopAndLoopIterationBound() {
    let bb1Name = BasicBlockName("bb1")
    let bb2Name = BasicBlockName("bb2")
    let bb3Name = BasicBlockName("bb3")
    let bb4Name = BasicBlockName("bb4")
    
    let var1 = IRVariable(name: "1", type: .int)
    let var2 = IRVariable(name: "2", type: .int)
    let var3 = IRVariable(name: "3", type: .bool)
    let var4 = IRVariable(name: "4", type: .int)
    let var5 = IRVariable(name: "5", type: .int)
    let var6 = IRVariable(name: "6", type: .int)
    
    let bb1 = BasicBlock(name: bb1Name, instructions: [
      AssignInstruction(assignee: var1, value: .integer(0)),
      JumpInstruction(target: bb2Name)
    ])
    
    let bb2 = BasicBlock(name: bb2Name, instructions: [
      PhiInstruction(assignee: var6, choices: [bb1Name: var1, bb3Name: var5]),
      DiscreteDistributionInstruction(assignee: var2, distribution: [0: 0.5, 1: 0.5]),
      CompareInstruction(comparison: .equal, assignee: var3, lhs: .variable(var2), rhs: .integer(0)),
      BranchInstruction(condition: .variable(var3), targetTrue: bb3Name, targetFalse: bb4Name)
    ])
    
    let bb3 = BasicBlock(name: bb3Name, instructions: [
      AddInstruction(assignee: var4, lhs: .variable(var6), rhs: .integer(1)),
      AssignInstruction(assignee: var5, value: .variable(var4)),
      JumpInstruction(target: bb2Name)
    ])
    
    let bb4 = BasicBlock(name: bb4Name, instructions: [
      ReturnInstruction()
    ])
    
    let irProgram = IRProgram(startBlock: bb1Name, basicBlocks: [bb1, bb2, bb3, bb4])
    
    let inferenceEngine = WPInferenceEngine(program: irProgram)
    
    let inferredAfterExactly1Unroll = inferenceEngine.infer(
      term: .integer(1),
      loopUnrolls: LoopUnrolls([IRLoop(conditionBlock: bb2Name, bodyStartBlock: bb3Name): 1]),
      inferenceStopPosition: InstructionPosition(basicBlock: bb3Name, instructionIndex: 1),
      branchingHistory: [.choice(source: bb2Name, target: bb3Name)]
    )
    XCTAssertEqual(inferredAfterExactly1Unroll.focusRate.doubleValue, 0.5)
    XCTAssertEqual(inferredAfterExactly1Unroll.observeAndDeliberateBranchIgnoringFocusRate.doubleValue, 1)
    
    let inferredAfterExactly2Unrolls = inferenceEngine.infer(
      term: .integer(1),
      loopUnrolls: LoopUnrolls([IRLoop(conditionBlock: bb2Name, bodyStartBlock: bb3Name): 2]),
      inferenceStopPosition: InstructionPosition(basicBlock: bb3Name, instructionIndex: 1),
      branchingHistory: [.choice(source: bb2Name, target: bb3Name), .choice(source: bb2Name, target: bb3Name)]
    )
    XCTAssertEqual(inferredAfterExactly2Unrolls.focusRate.doubleValue, 0.25)
    XCTAssertEqual(inferredAfterExactly2Unrolls.observeAndDeliberateBranchIgnoringFocusRate.doubleValue, 1)
  }
  
  func testReachabilityProbabilityOfExitStateGeneratedSimilarToExecutionOutlineExitStates() {
    let bb1Name = BasicBlockName("bb1")
    let bb2Name = BasicBlockName("bb2")
    let bb3Name = BasicBlockName("bb3")
    let bb4Name = BasicBlockName("bb4")
    
    let var1 = IRVariable(name: "1", type: .int)
    let var2 = IRVariable(name: "2", type: .int)
    let var3 = IRVariable(name: "3", type: .bool)
    let var4 = IRVariable(name: "4", type: .int)
    let var5 = IRVariable(name: "5", type: .int)
    let var6 = IRVariable(name: "6", type: .int)
    
    let bb1 = BasicBlock(name: bb1Name, instructions: [
      AssignInstruction(assignee: var1, value: .integer(0)),
      JumpInstruction(target: bb2Name)
    ])
    
    let bb2 = BasicBlock(name: bb2Name, instructions: [
      PhiInstruction(assignee: var6, choices: [bb1Name: var1, bb3Name: var5]),
      DiscreteDistributionInstruction(assignee: var2, distribution: [0: 0.5, 1: 0.5]),
      CompareInstruction(comparison: .equal, assignee: var3, lhs: .variable(var2), rhs: .integer(0)),
      BranchInstruction(condition: .variable(var3), targetTrue: bb3Name, targetFalse: bb4Name)
    ])
    
    let bb3 = BasicBlock(name: bb3Name, instructions: [
      AddInstruction(assignee: var4, lhs: .variable(var6), rhs: .integer(1)),
      AssignInstruction(assignee: var5, value: .variable(var4)),
      JumpInstruction(target: bb2Name)
    ])
    
    let bb4 = BasicBlock(name: bb4Name, instructions: [
      ReturnInstruction()
    ])
    
    let irProgram = IRProgram(startBlock: bb1Name, basicBlocks: [bb1, bb2, bb3, bb4])
    
    let inferenceEngine = WPInferenceEngine(program: irProgram)
    
    let inferredAfterAtMostZeroUnrolls = inferenceEngine.infer(
      term: .integer(1),
      loopUnrolls: LoopUnrolls([IRLoop(conditionBlock: bb2Name, bodyStartBlock: bb3Name): 0]),
      inferenceStopPosition: InstructionPosition(basicBlock: bb4Name, instructionIndex: 0),
      branchingHistory: [.any(predominatedBy: irProgram.startBlock)]
    )
    XCTAssertEqual(inferredAfterAtMostZeroUnrolls.focusRate.doubleValue, 0.5)
    XCTAssertEqual(inferredAfterAtMostZeroUnrolls.observeAndDeliberateBranchIgnoringFocusRate.doubleValue, 0.5)
    
    let inferredAfterAtMostOneUnroll = inferenceEngine.infer(
      term: .integer(1),
      loopUnrolls: LoopUnrolls([IRLoop(conditionBlock: bb2Name, bodyStartBlock: bb3Name): 1]),
      inferenceStopPosition: InstructionPosition(basicBlock: bb4Name, instructionIndex: 0),
      branchingHistory: [.any(predominatedBy: irProgram.startBlock)]
    )
    XCTAssertEqual(inferredAfterAtMostOneUnroll.focusRate.doubleValue, 0.75)
    XCTAssertEqual(inferredAfterAtMostOneUnroll.observeAndDeliberateBranchIgnoringFocusRate.doubleValue, 0.75)
    
    let inferredAfterAtMostThreeUnrolls = inferenceEngine.infer(
      term: .integer(1),
      loopUnrolls: LoopUnrolls([IRLoop(conditionBlock: bb2Name, bodyStartBlock: bb3Name): 2]),
      inferenceStopPosition: InstructionPosition(basicBlock: bb4Name, instructionIndex: 0),
      branchingHistory: [.any(predominatedBy: irProgram.startBlock)]
    )
    XCTAssertEqual(inferredAfterAtMostThreeUnrolls.focusRate.doubleValue, 0.875)
    XCTAssertEqual(inferredAfterAtMostThreeUnrolls.observeAndDeliberateBranchIgnoringFocusRate.doubleValue, 0.875)
    
  }
  
  
  func testInferRunsNotCutOffByLoopIterationBoundsAfterLoopWithDeliberateUnrolls() {
    let bb1Name = BasicBlockName("bb1")
    let bb2Name = BasicBlockName("bb2")
    let bb3Name = BasicBlockName("bb3")
    let bb4Name = BasicBlockName("bb4")
    
    let var1 = IRVariable(name: "1", type: .int)
    let var2 = IRVariable(name: "2", type: .bool)
    let var3 = IRVariable(name: "3", type: .int)
    let var4 = IRVariable(name: "4", type: .int)
    
    let bb1 = BasicBlock(name: bb1Name, instructions: [
      AssignInstruction(assignee: var1, value: .integer(2)),
      JumpInstruction(target: bb2Name)
    ])
    
    let bb2 = BasicBlock(name: bb2Name, instructions: [
      PhiInstruction(assignee: var4, choices: [bb1Name: var1, bb3Name: var3]),
      CompareInstruction(comparison: .lessThan, assignee: var2, lhs: .integer(1), rhs: .variable(var4)),
      BranchInstruction(condition: .variable(var2), targetTrue: bb3Name, targetFalse: bb4Name)
    ])
    
    let bb3 = BasicBlock(name: bb3Name, instructions: [
      SubtractInstruction(assignee: var3, lhs: .variable(var4), rhs: .integer(1)),
      JumpInstruction(target: bb2Name)
    ])
    
    let bb4 = BasicBlock(name: bb4Name, instructions: [
      ReturnInstruction()
    ])
    
    let irProgram = IRProgram(startBlock: bb1Name, basicBlocks: [bb1, bb2, bb3, bb4])
    
    let inferenceEngine = WPInferenceEngine(program: irProgram)
    let inferred = inferenceEngine.infer(
      term: .equal(lhs: .variable(var4), rhs: .integer(1)),
      loopUnrolls: LoopUnrolls([
        IRLoop(conditionBlock: bb2Name, bodyStartBlock: bb3Name): 2
      ]),
      inferenceStopPosition: InstructionPosition(basicBlock: bb4Name, instructionIndex: 0),
      branchingHistory: [.choice(source: bb2Name, target: bb3Name), .choice(source: bb2Name, target: bb4Name)]
    )
    XCTAssertEqual(inferred.focusRate.doubleValue, 1)
    XCTAssertEqual(inferred.observeAndDeliberateBranchIgnoringFocusRate.doubleValue, 1)
  }
  
  func testInferFocusRateWithBranchingHistoryIntoNestedIfAndOutAgain() {
    let bb1Name = BasicBlockName("bb1")
    let bb2Name = BasicBlockName("bb2")
    let bb3Name = BasicBlockName("bb3")
    let bb4Name = BasicBlockName("bb4")
    let bb5Name = BasicBlockName("bb5")
    
    let var1 = IRVariable(name: "1", type: .int)
    let var2 = IRVariable(name: "2", type: .bool)
    let var3 = IRVariable(name: "3", type: .int)
    let var4 = IRVariable(name: "4", type: .bool)
    
    let bb1 = BasicBlock(name: bb1Name, instructions: [
      DiscreteDistributionInstruction(assignee: var1, distribution: [0: 0.5, 1: 0.5]),
      CompareInstruction(comparison: .equal, assignee: var2, lhs: .variable(var1), rhs: .integer(0)),
      BranchInstruction(condition: .variable(var2), targetTrue: bb2Name, targetFalse: bb5Name)
    ])
    
    let bb2 = BasicBlock(name: bb2Name, instructions: [
      DiscreteDistributionInstruction(assignee: var3, distribution: [0: 0.5, 1: 0.5]),
      CompareInstruction(comparison: .equal, assignee: var4, lhs: .variable(var3), rhs: .integer(0)),
      BranchInstruction(condition: .variable(var4), targetTrue: bb3Name, targetFalse: bb4Name)
    ])
    
    let bb3 = BasicBlock(name: bb3Name, instructions: [
      JumpInstruction(target: bb5Name)
    ])
    
    let bb4 = BasicBlock(name: bb4Name, instructions: [
      JumpInstruction(target: bb5Name)
    ])
    
    let bb5 = BasicBlock(name: bb5Name, instructions: [
      ReturnInstruction()
    ])
    
    let program = IRProgram(startBlock: bb1Name, basicBlocks: [bb1, bb2, bb3, bb4, bb5])
    
    let inferenceEngine = WPInferenceEngine(program: program)
    let inferred = inferenceEngine.infer(
      term: .integer(0),
      loopUnrolls: LoopUnrolls([:]),
      inferenceStopPosition: program.returnPosition,
      branchingHistory: [BranchingChoice(source: bb1Name, target: bb2Name), BranchingChoice(source: bb2Name, target: bb3Name)]
    )
    XCTAssertEqual(inferred.focusRate.doubleValue, 0.25)
    XCTAssertEqual(inferred.observeAndDeliberateBranchIgnoringFocusRate.doubleValue, 1)
  }
  
  func testInferInsideLoopIterationWithBranchInsideLoop() {
    let var1 = IRVariable(name: "1", type: .bool)
    let var2 = IRVariable(name: "2", type: .int)
    let var3 = IRVariable(name: "3", type: .bool)
    let var4 = IRVariable(name: "4", type: .bool)
    let var5 = IRVariable(name: "5", type: .bool)
    let var6 = IRVariable(name: "6", type: .bool)
    
    let bb1Name = BasicBlockName("bb1")
    let bb2Name = BasicBlockName("bb2")
    let bb3Name = BasicBlockName("bb3")
    let bb4Name = BasicBlockName("bb4")
    let bb5Name = BasicBlockName("bb5")
    let bb6Name = BasicBlockName("bb6")
    
    let bb1 = BasicBlock(name: bb1Name, instructions: [
      AssignInstruction(assignee: var1, value: .bool(true)),
      JumpInstruction(target: bb2Name)
    ])
    
    let bb2 = BasicBlock(name: bb2Name, instructions: [
      PhiInstruction(assignee: var6, choices: [bb1Name: var1, bb6Name: var5]),
      BranchInstruction(condition: .variable(var6), targetTrue: bb3Name, targetFalse: bb4Name)
    ])
    
    let bb3 = BasicBlock(name: bb3Name, instructions: [
      DiscreteDistributionInstruction(assignee: var2, distribution: [0: 0.5, 1: 0.5]),
      CompareInstruction(comparison: .equal, assignee: var3, lhs: .variable(var2), rhs: .integer(0)),
      BranchInstruction(condition: .variable(var3), targetTrue: bb5Name, targetFalse: bb6Name)
    ])
    
    let bb4 = BasicBlock(name: bb4Name, instructions: [
      ReturnInstruction()
    ])
    
    let bb5 = BasicBlock(name: bb5Name, instructions: [
      AssignInstruction(assignee: var4, value: .bool(false)),
      JumpInstruction(target: bb6Name)
    ])
    
    let bb6 = BasicBlock(name: bb6Name, instructions: [
      PhiInstruction(assignee: var5, choices: [bb3Name: var6, bb5Name: var4]),
      JumpInstruction(target: bb2Name)
    ])
    
    let program = IRProgram(startBlock: bb1Name, basicBlocks: [bb1, bb2, bb3, bb4, bb5, bb6])
    
    let inferenceEngine = WPInferenceEngine(program: program)
    let inferred = inferenceEngine.infer(term: .integer(0),
                          loopUnrolls: LoopUnrolls([IRLoop(conditionBlock: bb2Name, bodyStartBlock: bb3Name): 2]),
                          inferenceStopPosition: InstructionPosition(basicBlock: bb3Name, instructionIndex: 2),
                          branchingHistory: [
                            .choice(source: bb2Name, target: bb3Name),
                            .any(predominatedBy: bb3Name),
                            .choice(source: bb2Name, target: bb3Name),
                            ]
    )
    XCTAssertEqual(inferred.focusRate.doubleValue, 0.5)
    XCTAssertEqual(inferred.observeAndDeliberateBranchIgnoringFocusRate.doubleValue, 1)
  }
}
