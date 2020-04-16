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
    
    XCTAssertEqual(inferenceEngine.inferProbability(of: var1, beingEqualTo: .integer(2), loopUnrolls: [:]), 1)
    XCTAssertEqual(inferenceEngine.inferProbability(of: var1, beingEqualTo: .integer(1), loopUnrolls: [:]), 0)
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
    XCTAssertEqual(inferenceEngine.inferProbability(of: var1, beingEqualTo: .integer(2), loopUnrolls: [:]), 0.6)
    XCTAssertEqual(inferenceEngine.inferProbability(of: var1, beingEqualTo: .integer(3), loopUnrolls: [:]), 0.4)
    XCTAssertEqual(inferenceEngine.inferProbability(of: var1, beingEqualTo: .integer(4), loopUnrolls: [:]), 0)
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
    XCTAssertEqual(inferenceEngine.inferProbability(of: var1, beingEqualTo: .integer(2), loopUnrolls: [:]), 0.6)
    XCTAssertEqual(inferenceEngine.inferProbability(of: var1, beingEqualTo: .integer(3), loopUnrolls: [:]), 0.4)
    XCTAssertEqual(inferenceEngine.inferProbability(of: var1, beingEqualTo: .integer(4), loopUnrolls: [:]), 0)
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
    XCTAssertEqual(inferenceEngine.inferProbability(of: var1, beingEqualTo: .integer(2), loopUnrolls: [:]), 0.6)
    XCTAssertEqual(inferenceEngine.inferProbability(of: var1, beingEqualTo: .integer(3), loopUnrolls: [:]), 0.4)
    XCTAssertEqual(inferenceEngine.inferProbability(of: var1, beingEqualTo: .integer(4), loopUnrolls: [:]), 0)
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
    XCTAssertEqual(inferenceEngine.inferProbability(of: var4, beingEqualTo: .integer(10), loopUnrolls: [:]), 0.6)
    XCTAssertEqual(inferenceEngine.inferProbability(of: var4, beingEqualTo: .integer(20), loopUnrolls: [:]), 0.4)
    XCTAssertEqual(inferenceEngine.inferProbability(of: var4, beingEqualTo: .integer(16), loopUnrolls: [:]), 0)
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
    let whileLoopBranch = LoopingBranch(
      conditionBlock: bb2Name,
      bodyBlock: bb3Name
    )
    let loopUnrolls = [whileLoopBranch: LoopUnrolling.normal(5)]
    
    let inferenceEngine = WPInferenceEngine(program: program)
    XCTAssertEqual(inferenceEngine.inferProbability(of: var6, beingEqualTo: .integer(0), loopUnrolls: loopUnrolls), 0)
    XCTAssertEqual(inferenceEngine.inferProbability(of: var6, beingEqualTo: .integer(1), loopUnrolls: loopUnrolls), 1)
    XCTAssertEqual(inferenceEngine.inferProbability(of: var6, beingEqualTo: .integer(2), loopUnrolls: loopUnrolls), 0)
    XCTAssertEqual(inferenceEngine.inferProbability(of: var6, beingEqualTo: .integer(3), loopUnrolls: loopUnrolls), 0)
    XCTAssertEqual(inferenceEngine.inferProbability(of: var6, beingEqualTo: .integer(4), loopUnrolls: loopUnrolls), 0)
    XCTAssertEqual(inferenceEngine.inferProbability(of: var6, beingEqualTo: .integer(5), loopUnrolls: loopUnrolls), 0)
    XCTAssertEqual(inferenceEngine.inferProbability(of: var6, beingEqualTo: .integer(6), loopUnrolls: loopUnrolls), 0)
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
    let whileLoopBranch = LoopingBranch(
      conditionBlock: bb2Name,
      bodyBlock: bb3Name
    )
    let loopUnrolls = [whileLoopBranch: LoopUnrolling.normal(3)]
    
    let inferenceEngine = WPInferenceEngine(program: program)
    XCTAssertEqual(inferenceEngine.inferProbability(of: var6, beingEqualTo: .integer(0), loopUnrolls: loopUnrolls), 0.5)
    XCTAssertEqual(inferenceEngine.inferProbability(of: var6, beingEqualTo: .integer(1), loopUnrolls: loopUnrolls), 0.25)
    XCTAssertEqual(inferenceEngine.inferProbability(of: var6, beingEqualTo: .integer(2), loopUnrolls: loopUnrolls), 0.125)
    XCTAssertEqual(inferenceEngine.inferProbability(of: var6, beingEqualTo: .integer(3), loopUnrolls: loopUnrolls), 0.0625)
    XCTAssertEqual(inferenceEngine.inferProbability(of: var6, beingEqualTo: .integer(4), loopUnrolls: loopUnrolls), 0)
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
    XCTAssertEqual(inferenceEngine.inferProbability(of: var2, beingEqualTo: .integer(1), loopUnrolls: [:]), 1)
    XCTAssertEqual(inferenceEngine.inferProbability(of: var3, beingEqualTo: .integer(1), loopUnrolls: [:]), 1)
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
    XCTAssertEqual(inferenceEngine.inferProbability(of: var1, beingEqualTo: .integer(1), loopUnrolls: [:]), 1)
  }
  
  func testUnrollALoopAnExactNumberOftimes() {
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
    let whileLoopBranch = LoopingBranch(
      conditionBlock: bb2Name,
      bodyBlock: bb3Name
    )
    let loopUnrolls = [whileLoopBranch: LoopUnrolling.exactly(1)]
    
    let inferenceEngine = WPInferenceEngine(program: program)
    XCTAssertEqual(inferenceEngine.inferProbability(of: var6, beingEqualTo: .integer(0), loopUnrolls: loopUnrolls), 0)
    XCTAssertEqual(inferenceEngine.inferProbability(of: var6, beingEqualTo: .integer(1), loopUnrolls: loopUnrolls), 0.25)
    XCTAssertEqual(inferenceEngine.inferProbability(of: var6, beingEqualTo: .integer(2), loopUnrolls: loopUnrolls), 0)
    XCTAssertEqual(inferenceEngine.inferProbability(of: var6, beingEqualTo: .integer(3), loopUnrolls: loopUnrolls), 0)
    XCTAssertEqual(inferenceEngine.inferProbability(of: var6, beingEqualTo: .integer(4), loopUnrolls: loopUnrolls), 0)
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
    let whileLoopBranch = LoopingBranch(
      conditionBlock: bb2Name,
      bodyBlock: bb3Name
    )
    
    let inferenceEngine = WPInferenceEngine(program: program)
    self.measure {
      let loopUnrolls = [whileLoopBranch: LoopUnrolling.normal(50)]
      _ = inferenceEngine.inferProbability(of: var6, beingEqualTo: .integer(1), loopUnrolls: loopUnrolls)
    }
  }
}
