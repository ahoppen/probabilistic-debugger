import IR
import IRExecution
@testable import WPInference

import XCTest

fileprivate extension LoopUnrolls {
  static let empty = LoopUnrolls([:])
}

class WPInferenceEngineSlicingTests: XCTestCase {
  
  func testSlicingIfNothingCanBeSlicedAway() {
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
    let returnPositionWithoutBranchingHistorySlice = inferenceEngine.slice(
      term: .variable(var4),
      loopUnrolls: LoopUnrolls([:]),
      inferenceStopPosition: InstructionPosition(basicBlock: bb3Name, instructionIndex: 1),
      branchingHistory: [.any(predominatedBy: bb0Name)]
    )
    XCTAssertEqual(returnPositionWithoutBranchingHistorySlice, [
      InstructionPosition(basicBlock: bb0Name, instructionIndex: 0),
      InstructionPosition(basicBlock: bb0Name, instructionIndex: 1),
      InstructionPosition(basicBlock: bb0Name, instructionIndex: 2),
      InstructionPosition(basicBlock: bb1Name, instructionIndex: 0),
      InstructionPosition(basicBlock: bb2Name, instructionIndex: 0),
      InstructionPosition(basicBlock: bb3Name, instructionIndex: 0),
    ])
    
    let returnPositionWithBranchingChoiceToIfBranchSlice = inferenceEngine.slice(
      term: .variable(var4),
      loopUnrolls: LoopUnrolls([:]),
      inferenceStopPosition: InstructionPosition(basicBlock: bb3Name, instructionIndex: 1),
      branchingHistory: [BranchingChoice(source: bb0Name, target: bb1Name)]
    )
    XCTAssertEqual(returnPositionWithBranchingChoiceToIfBranchSlice, [
      InstructionPosition(basicBlock: bb1Name, instructionIndex: 0),
      InstructionPosition(basicBlock: bb3Name, instructionIndex: 0),
    ])

    let ifBodyPositionSlice = inferenceEngine.slice(
      term: .variable(var2),
      loopUnrolls: LoopUnrolls([:]),
      inferenceStopPosition: InstructionPosition(basicBlock: bb1Name, instructionIndex: 1),
      branchingHistory: [BranchingChoice(source: bb0Name, target: bb1Name)]
    )
    XCTAssertEqual(ifBodyPositionSlice, [
      InstructionPosition(basicBlock: bb1Name, instructionIndex: 0),
    ])
  }
  
  func testSlicingIfBranchingConditionCanBeSlicedAway() {
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
      AssignInstruction(assignee: var3, value: .integer(10)),
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
    //   int %3 = int 10
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
    //   y = 10
    // }

    let inferenceEngine = WPInferenceEngine(program: irProgram)
    let returnPositionWithoutBranchingHistorySlice = inferenceEngine.slice(
      term: .variable(var4),
      loopUnrolls: LoopUnrolls([:]),
      inferenceStopPosition: InstructionPosition(basicBlock: bb3Name, instructionIndex: 1),
      branchingHistory: [.any(predominatedBy: bb0Name)]
    )
    XCTAssertEqual(returnPositionWithoutBranchingHistorySlice, [
      InstructionPosition(basicBlock: bb1Name, instructionIndex: 0),
      InstructionPosition(basicBlock: bb2Name, instructionIndex: 0),
      InstructionPosition(basicBlock: bb3Name, instructionIndex: 0),
    ])
  }
  
  func testSlicingWhereBranchIsRelevantButLeadsToSameResult() {
    let var1 = IRVariable(name: "1", type: .int)
    let var2 = IRVariable(name: "2", type: .bool)
    let var3 = IRVariable(name: "3", type: .int)
    let var4 = IRVariable(name: "4", type: .int)
    
    let bb1Name = BasicBlockName("bb1")
    let bb2Name = BasicBlockName("bb2")
    let bb3Name = BasicBlockName("bb3")
    
    let bb1 = BasicBlock(name: bb1Name, instructions: [
      DiscreteDistributionInstruction(assignee: var1, distribution: [0: 0.4, 1: 0.6]),
      CompareInstruction(comparison: .equal, assignee: var2, lhs: .variable(var1), rhs: .integer(1)),
      BranchInstruction(condition: .variable(var2), targetTrue: bb2Name, targetFalse: bb3Name)
    ])

    let bb2 = BasicBlock(name: bb2Name, instructions: [
      SubtractInstruction(assignee: var3, lhs: .variable(var1), rhs: .integer(1)),
      JumpInstruction(target: bb3Name)
    ])

    let bb3 = BasicBlock(name: bb3Name, instructions: [
      PhiInstruction(assignee: var4, choices: [bb1Name: var1, bb2Name: var3]),
      ReturnInstruction()
    ])
    // bb1:
    //   int %1 = discrete 0: 0.4, 1: 0.6
    //   bool %2 = cmp eq int %1 int 1
    //   br bool %2 bb2 bb3
    //
    // bb2:
    //   int %3 = sub int %1 int 1
    //   jump bb3
    //
    // bb3:
    //   int %4 = phi bb1: int %1, bb2: int %3
    //   return
    
    let program = IRProgram(startBlock: bb1Name, basicBlocks: [bb1, bb2, bb3])
    
    let inferenceEngine = WPInferenceEngine(program: program)
    let sliced = inferenceEngine.slice(
      term: .variable(var4),
      loopUnrolls: LoopUnrolls([:]),
      inferenceStopPosition: program.returnPosition,
      branchingHistory: [.any(predominatedBy: bb1Name)]
    )
    XCTAssertEqual(sliced, [
      InstructionPosition(basicBlock: bb1Name, instructionIndex: 0),
      InstructionPosition(basicBlock: bb1Name, instructionIndex: 1),
      InstructionPosition(basicBlock: bb1Name, instructionIndex: 2),
      InstructionPosition(basicBlock: bb2Name, instructionIndex: 0),
      InstructionPosition(basicBlock: bb3Name, instructionIndex: 0)
    ])
  }
  
  func testSlicingWhereLoopingBranchIsRelevantButLeadsToSameResult() {
    let var1 = IRVariable(name: "1", type: .int)
    let var2 = IRVariable(name: "2", type: .int)
    let var3 = IRVariable(name: "3", type: .bool)
    let var4 = IRVariable(name: "4", type: .int)
    
    let bb1Name = BasicBlockName("bb1")
    let bb2Name = BasicBlockName("bb2")
    let bb3Name = BasicBlockName("bb3")
    let bb4Name = BasicBlockName("bb4")
    
    let bb1 = BasicBlock(name: bb1Name, instructions: [
      DiscreteDistributionInstruction(assignee: var1, distribution: [0: 0.4, 1: 0.6]),
      JumpInstruction(target: bb2Name)
    ])
    
    let bb2 = BasicBlock(name: bb2Name, instructions: [
      PhiInstruction(assignee: var2, choices: [bb1Name: var1, bb3Name: var4]),
      CompareInstruction(comparison: .equal, assignee: var3, lhs: .variable(var2), rhs: .integer(1)),
      BranchInstruction(condition: .variable(var3), targetTrue: bb3Name, targetFalse: bb4Name)
    ])

    let bb3 = BasicBlock(name: bb3Name, instructions: [
      SubtractInstruction(assignee: var4, lhs: .variable(var2), rhs: .integer(1)),
      JumpInstruction(target: bb2Name)
    ])

    let bb4 = BasicBlock(name: bb4Name, instructions: [
      ReturnInstruction()
    ])
    
    let program = IRProgram(startBlock: bb1Name, basicBlocks: [bb1, bb2, bb3, bb4])
    
    let inferenceEngine = WPInferenceEngine(program: program)
    let sliced = inferenceEngine.slice(
      term: .variable(var2),
      loopUnrolls: LoopUnrolls([
        IRLoop(conditionBlock: bb2Name, bodyStartBlock: bb3Name): 1
      ]),
      inferenceStopPosition: program.returnPosition,
      branchingHistory: [.any(predominatedBy: bb1Name)]
    )
    XCTAssertEqual(sliced, [
      InstructionPosition(basicBlock: bb1Name, instructionIndex: 0),
      InstructionPosition(basicBlock: bb2Name, instructionIndex: 0),
      InstructionPosition(basicBlock: bb2Name, instructionIndex: 1),
      InstructionPosition(basicBlock: bb2Name, instructionIndex: 2),
      InstructionPosition(basicBlock: bb3Name, instructionIndex: 0)
    ])
  }
  
  func testSlicingWhereLoopingLessThanBranchIsRelevantButLeadsToSameResult() {
    let var1 = IRVariable(name: "1", type: .int)
    let var2 = IRVariable(name: "2", type: .int)
    let var3 = IRVariable(name: "3", type: .bool)
    let var4 = IRVariable(name: "4", type: .int)
    
    let bb1Name = BasicBlockName("bb1")
    let bb2Name = BasicBlockName("bb2")
    let bb3Name = BasicBlockName("bb3")
    let bb4Name = BasicBlockName("bb4")
    
    let bb1 = BasicBlock(name: bb1Name, instructions: [
      DiscreteDistributionInstruction(assignee: var1, distribution: [0: 0.4, 1: 0.6]),
      JumpInstruction(target: bb2Name)
    ])
    
    let bb2 = BasicBlock(name: bb2Name, instructions: [
      PhiInstruction(assignee: var2, choices: [bb1Name: var1, bb3Name: var4]),
      CompareInstruction(comparison: .lessThan, assignee: var3, lhs: .integer(0), rhs: .variable(var2)),
      BranchInstruction(condition: .variable(var3), targetTrue: bb3Name, targetFalse: bb4Name)
    ])

    let bb3 = BasicBlock(name: bb3Name, instructions: [
      SubtractInstruction(assignee: var4, lhs: .variable(var2), rhs: .integer(1)),
      JumpInstruction(target: bb2Name)
    ])

    let bb4 = BasicBlock(name: bb4Name, instructions: [
      ReturnInstruction()
    ])
    
    let program = IRProgram(startBlock: bb1Name, basicBlocks: [bb1, bb2, bb3, bb4])
    
    let inferenceEngine = WPInferenceEngine(program: program)
    let sliced = inferenceEngine.slice(
      term: .variable(var2),
      loopUnrolls: LoopUnrolls([
        IRLoop(conditionBlock: bb2Name, bodyStartBlock: bb3Name): 1
      ]),
      inferenceStopPosition: program.returnPosition,
      branchingHistory: [.any(predominatedBy: bb1Name)]
    )
    XCTAssertEqual(sliced, [
      InstructionPosition(basicBlock: bb1Name, instructionIndex: 0),
      InstructionPosition(basicBlock: bb2Name, instructionIndex: 0),
      InstructionPosition(basicBlock: bb2Name, instructionIndex: 1),
      InstructionPosition(basicBlock: bb2Name, instructionIndex: 2),
      InstructionPosition(basicBlock: bb3Name, instructionIndex: 0)
    ])
  }
  
  func testKeepBranchEvenIfOnlyOneBranchIsViable() {
    let var1 = IRVariable(name: "1", type: .int)
    let var2 = IRVariable(name: "2", type: .int)
    let var3 = IRVariable(name: "3", type: .bool)
    let var4 = IRVariable(name: "4", type: .int)
    
    let bb1Name = BasicBlockName("bb1")
    let bb2Name = BasicBlockName("bb2")
    let bb3Name = BasicBlockName("bb3")
    let bb4Name = BasicBlockName("bb4")
    
    let bb1 = BasicBlock(name: bb1Name, instructions: [
      AssignInstruction(assignee: var1, value: .integer(1)),
      JumpInstruction(target: bb2Name)
    ])
    
    let bb2 = BasicBlock(name: bb2Name, instructions: [
      PhiInstruction(assignee: var2, choices: [bb1Name: var1, bb3Name: var4]),
      CompareInstruction(comparison: .lessThan, assignee: var3, lhs: .integer(0), rhs: .variable(var2)),
      BranchInstruction(condition: .variable(var3), targetTrue: bb3Name, targetFalse: bb4Name)
    ])

    let bb3 = BasicBlock(name: bb3Name, instructions: [
      SubtractInstruction(assignee: var4, lhs: .variable(var2), rhs: .integer(1)),
      JumpInstruction(target: bb2Name)
    ])

    let bb4 = BasicBlock(name: bb4Name, instructions: [
      ReturnInstruction()
    ])
    
    let program = IRProgram(startBlock: bb1Name, basicBlocks: [bb1, bb2, bb3, bb4])
    
    let inferenceEngine = WPInferenceEngine(program: program)
    let sliced = inferenceEngine.slice(
      term: .variable(var2),
      loopUnrolls: LoopUnrolls([
        IRLoop(conditionBlock: bb2Name, bodyStartBlock: bb3Name): 1
      ]),
      inferenceStopPosition: program.returnPosition,
      branchingHistory: [.any(predominatedBy: bb1Name)]
    )
    XCTAssertEqual(sliced, [
      InstructionPosition(basicBlock: bb1Name, instructionIndex: 0),
      InstructionPosition(basicBlock: bb2Name, instructionIndex: 0),
      InstructionPosition(basicBlock: bb2Name, instructionIndex: 1),
      InstructionPosition(basicBlock: bb2Name, instructionIndex: 2),
      InstructionPosition(basicBlock: bb3Name, instructionIndex: 0)
    ])
  }
  
  func testKeepAwayLoopConditionEvenIfLoopHasAFixedNumberOfUnrolls() {
    let var1 = IRVariable(name: "1", type: .int)
    let var3 = IRVariable(name: "3", type: .bool)
    let var4 = IRVariable(name: "4", type: .int)
    let var5 = IRVariable(name: "5", type: .int)
    let var6 = IRVariable(name: "6", type: .int)
    
    let bb1Name = BasicBlockName("bb1")
    let bb2Name = BasicBlockName("bb2")
    let bb3Name = BasicBlockName("bb3")
    let bb4Name = BasicBlockName("bb4")
    
    let bb1 = BasicBlock(name: bb1Name, instructions: [
      AssignInstruction(assignee: var1, value: .integer(3)),
      JumpInstruction(target: bb2Name)
    ])
    
    let bb2 = BasicBlock(name: bb2Name, instructions: [
      PhiInstruction(assignee: var6, choices: [bb1Name: var1, bb3Name: var5]),
      CompareInstruction(comparison: .lessThan, assignee: var3, lhs: .integer(1), rhs: .variable(var6)),
      BranchInstruction(condition: .variable(var3), targetTrue: bb3Name, targetFalse: bb4Name)
    ])
    
    let bb3 = BasicBlock(name: bb3Name, instructions: [
      SubtractInstruction(assignee: var4, lhs: .variable(var6), rhs: .integer(1)),
      AssignInstruction(assignee: var5, value: .variable(var4)),
      JumpInstruction(target: bb2Name)
    ])
    
    let bb4 = BasicBlock(name: bb4Name, instructions: [
      ReturnInstruction(),
    ])
    
    let program = IRProgram(startBlock: bb1Name, basicBlocks: [bb1, bb2, bb3, bb4])
    
    let inferenceEngine = WPInferenceEngine(program: program)
    
    let valueOfXAtTheEndSlice = inferenceEngine.slice(
      term: .variable(var6),
      loopUnrolls: LoopUnrolls([
        IRLoop(conditionBlock: bb2Name, bodyStartBlock: bb3Name): 2
      ]),
      inferenceStopPosition: program.returnPosition,
      branchingHistory: [.any(predominatedBy: bb1Name)]
    )
    XCTAssertEqual(valueOfXAtTheEndSlice, [
      InstructionPosition(basicBlock: bb1Name, instructionIndex: 0),
      InstructionPosition(basicBlock: bb2Name, instructionIndex: 0),
      InstructionPosition(basicBlock: bb2Name, instructionIndex: 1),
      InstructionPosition(basicBlock: bb2Name, instructionIndex: 2),
      InstructionPosition(basicBlock: bb3Name, instructionIndex: 0),
      InstructionPosition(basicBlock: bb3Name, instructionIndex: 1),
    ])
  }
  
  func testKeepLoopConditionForLoopWithSingleIteration() {
    let var1 = IRVariable(name: "1", type: .int)
    let var2 = IRVariable(name: "2", type: .int)
    let var3 = IRVariable(name: "3", type: .bool)
    let var4 = IRVariable(name: "4", type: .int)
    let var5 = IRVariable(name: "5", type: .int)
    let var6 = IRVariable(name: "6", type: .int)
    let var7 = IRVariable(name: "7", type: .int)

    let bb1Name = BasicBlockName("bb1")
    let bb2Name = BasicBlockName("bb2")
    let bb3Name = BasicBlockName("bb3")
    let bb4Name = BasicBlockName("bb4")

    let bb1 = BasicBlock(name: bb1Name, instructions: [
      AssignInstruction(assignee: var1, value: .integer(2)),
      DiscreteDistributionInstruction(assignee: var2, distribution: [0: 0.4, 1: 0.6]),
      JumpInstruction(target: bb2Name)
    ])

    let bb2 = BasicBlock(name: bb2Name, instructions: [
      PhiInstruction(assignee: var6, choices: [bb1Name: var1, bb3Name: var5]),
      CompareInstruction(comparison: .lessThan, assignee: var3, lhs: .integer(1), rhs: .variable(var6)),
      BranchInstruction(condition: .variable(var3), targetTrue: bb3Name, targetFalse: bb4Name)
    ])

    let bb3 = BasicBlock(name: bb3Name, instructions: [
      SubtractInstruction(assignee: var4, lhs: .variable(var6), rhs: .integer(1)),
      AssignInstruction(assignee: var5, value: .variable(var4)),
      JumpInstruction(target: bb2Name)
    ])

    let bb4 = BasicBlock(name: bb4Name, instructions: [
      AssignInstruction(assignee: var7, value: .variable(var6)),
      ReturnInstruction(),
    ])
    // bb1:
    //   int %1 = int 2
    //   int %2 = discrete 0: 0.4, 1: 0.6
    //   jump bb2
    //
    // bb2:
    //   int %6 = phi bb1: int %1, bb3: int %5
    //   bool %3 = cmp lt int 1 int %6
    //   br bool %3 bb3 bb4
    //
    // bb3:
    //   int %4 = sub int %6 int 1
    //   int %5 = int %4
    //   jump bb2
    //
    // bb4:
    //   int %7 = int %6
    //   return
    //
    // equivalent to:
    //
    // int x = 2
    // int y = discrete({0: 0.4, 1: 0.6})
    // while 1 < x {
    //   x = x - 1
    // }

    let program = IRProgram(startBlock: bb1Name, basicBlocks: [bb1, bb2, bb3, bb4])

    let inferenceEngine = WPInferenceEngine(program: program)
    let returnPositionWithoutBranchingHistorySlice = inferenceEngine.slice(
      term: .variable(var2),
      loopUnrolls: LoopUnrolls([
        IRLoop(conditionBlock: bb2Name, bodyStartBlock: bb3Name): 1
      ]),
      inferenceStopPosition: program.returnPosition,
      branchingHistory: [.any(predominatedBy: bb1Name)]
    )
    XCTAssertEqual(returnPositionWithoutBranchingHistorySlice, [
      InstructionPosition(basicBlock: bb1Name, instructionIndex: 1),
    ])

    let valueOfXAtTheEndSlice = inferenceEngine.slice(
      term: .variable(var7),
      loopUnrolls: LoopUnrolls([
        IRLoop(conditionBlock: bb2Name, bodyStartBlock: bb3Name): 1
      ]),
      inferenceStopPosition: program.returnPosition,
      branchingHistory: [.any(predominatedBy: bb1Name)]
    )
    XCTAssertEqual(valueOfXAtTheEndSlice, [
      InstructionPosition(basicBlock: bb1Name, instructionIndex: 0),
      InstructionPosition(basicBlock: bb2Name, instructionIndex: 0),
      InstructionPosition(basicBlock: bb2Name, instructionIndex: 1),
      InstructionPosition(basicBlock: bb2Name, instructionIndex: 2),
      InstructionPosition(basicBlock: bb3Name, instructionIndex: 0),
      InstructionPosition(basicBlock: bb3Name, instructionIndex: 1),
      InstructionPosition(basicBlock: bb4Name, instructionIndex: 0),
    ])
  }
  
  func testKeepLoopWhenLoopHasAFixedNumberOfIterations() {
    let var1 = IRVariable(name: "1", type: .int)
    let var2 = IRVariable(name: "2", type: .int)
    let var3 = IRVariable(name: "3", type: .bool)
    let var4 = IRVariable(name: "4", type: .int)
    let var5 = IRVariable(name: "5", type: .int)
    let var6 = IRVariable(name: "6", type: .int)
    let var7 = IRVariable(name: "7", type: .int)

    let bb1Name = BasicBlockName("bb1")
    let bb2Name = BasicBlockName("bb2")
    let bb3Name = BasicBlockName("bb3")
    let bb4Name = BasicBlockName("bb4")

    let bb1 = BasicBlock(name: bb1Name, instructions: [
      DiscreteDistributionInstruction(assignee: var2, distribution: [0: 0.4, 1: 0.6]),
      AssignInstruction(assignee: var1, value: .integer(3)),
      JumpInstruction(target: bb2Name)
    ])

    let bb2 = BasicBlock(name: bb2Name, instructions: [
      PhiInstruction(assignee: var6, choices: [bb1Name: var1, bb3Name: var5]),
      CompareInstruction(comparison: .lessThan, assignee: var3, lhs: .integer(1), rhs: .variable(var6)),
      BranchInstruction(condition: .variable(var3), targetTrue: bb3Name, targetFalse: bb4Name)
    ])

    let bb3 = BasicBlock(name: bb3Name, instructions: [
      SubtractInstruction(assignee: var4, lhs: .variable(var6), rhs: .integer(1)),
      AssignInstruction(assignee: var5, value: .variable(var4)),
      JumpInstruction(target: bb2Name)
    ])

    let bb4 = BasicBlock(name: bb4Name, instructions: [
      AssignInstruction(assignee: var7, value: .variable(var6)),
      ReturnInstruction(),
    ])
    // bb1:
    //   int %2 = discrete 0: 0.4, 1: 0.6
    //   int %1 = int 3
    //   jump bb2
    //
    // bb2:
    //   int %6 = phi bb1: int %1, bb3: int %5
    //   bool %3 = cmp lt int 1 int %6
    //   br bool %3 bb3 bb4
    //
    // bb3:
    //   int %4 = sub int %6 int 1
    //   int %5 = int %4
    //   jump bb2
    //
    // bb4:
    //   int %7 = int %6
    //   return
    //
    // equivalent to:
    //
    // int y = discrete({0: 0.4, 1: 0.6})
    // int x = 3
    // while 1 < x {
    //   x = x - 1
    // }

    let program = IRProgram(startBlock: bb1Name, basicBlocks: [bb1, bb2, bb3, bb4])

    let inferenceEngine = WPInferenceEngine(program: program)
    let returnPositionWithoutBranchingHistorySlice = inferenceEngine.slice(
      term: .variable(var2),
      loopUnrolls: LoopUnrolls([
        IRLoop(conditionBlock: bb2Name, bodyStartBlock: bb3Name): 2
      ]),
      inferenceStopPosition: program.returnPosition,
      branchingHistory: [.any(predominatedBy: bb1Name)]
    )
    XCTAssertEqual(returnPositionWithoutBranchingHistorySlice, [
      InstructionPosition(basicBlock: bb1Name, instructionIndex: 0),
    ])
    
    let valueOfXAtTheEndSlice = inferenceEngine.slice(
      term: .variable(var7),
      loopUnrolls: LoopUnrolls([
        IRLoop(conditionBlock: bb2Name, bodyStartBlock: bb3Name): 2
      ]),
      inferenceStopPosition: program.returnPosition,
      branchingHistory: [.any(predominatedBy: bb1Name)]
    )
    XCTAssertEqual(valueOfXAtTheEndSlice, [
      InstructionPosition(basicBlock: bb1Name, instructionIndex: 1),
      InstructionPosition(basicBlock: bb2Name, instructionIndex: 0),
      InstructionPosition(basicBlock: bb2Name, instructionIndex: 1),
      InstructionPosition(basicBlock: bb2Name, instructionIndex: 2),
      InstructionPosition(basicBlock: bb3Name, instructionIndex: 0),
      InstructionPosition(basicBlock: bb3Name, instructionIndex: 1),
      InstructionPosition(basicBlock: bb4Name, instructionIndex: 0),
    ])
  }
  
  func testSlicingWithLoopThatTerminatesAfterANonderterministicNumberOfIterations() {
    let var1 = IRVariable(name: "1", type: .int)
    let var2 = IRVariable(name: "2", type: .int)
    let var3 = IRVariable(name: "3", type: .bool)
    let var4 = IRVariable(name: "4", type: .int)
    let var5 = IRVariable(name: "5", type: .int)
    let var6 = IRVariable(name: "6", type: .int)
    let var7 = IRVariable(name: "7", type: .int)

    let bb1Name = BasicBlockName("bb1")
    let bb2Name = BasicBlockName("bb2")
    let bb3Name = BasicBlockName("bb3")
    let bb4Name = BasicBlockName("bb4")

    let bb1 = BasicBlock(name: bb1Name, instructions: [
      AssignInstruction(assignee: var1, value: .integer(3)),
      DiscreteDistributionInstruction(assignee: var2, distribution: [1: 0.4, 2: 0.6]),
      JumpInstruction(target: bb2Name)
    ])

    let bb2 = BasicBlock(name: bb2Name, instructions: [
      PhiInstruction(assignee: var6, choices: [bb1Name: var1, bb3Name: var5]),
      CompareInstruction(comparison: .lessThan, assignee: var3, lhs: .integer(1), rhs: .variable(var6)),
      BranchInstruction(condition: .variable(var3), targetTrue: bb3Name, targetFalse: bb4Name)
    ])

    let bb3 = BasicBlock(name: bb3Name, instructions: [
      SubtractInstruction(assignee: var4, lhs: .variable(var6), rhs: .integer(1)),
      AssignInstruction(assignee: var5, value: .variable(var4)),
      JumpInstruction(target: bb2Name)
    ])

    let bb4 = BasicBlock(name: bb4Name, instructions: [
      AssignInstruction(assignee: var7, value: .variable(var6)),
      ReturnInstruction(),
    ])
    // bb1:
    //   int %1 = int 3
    //   int %2 = discrete 0: 0.4, 1: 0.6
    //   jump bb2
    //
    // bb2:
    //   int %6 = phi bb1: int %1, bb3: int %5
    //   bool %3 = cmp lt int 1 int %6
    //   br bool %3 bb3 bb4
    //
    // bb3:
    //   int %4 = sub int %6 int 1
    //   int %5 = int %4
    //   jump bb2
    //
    // bb4:
    //   int %7 = int %6
    //   return
    //
    // equivalent to:
    //
    // int x = 3
    // int y = discrete({0: 0.4, 1: 0.6})
    // while 1 < x {
    //   x = x - 1
    // }

    let program = IRProgram(startBlock: bb1Name, basicBlocks: [bb1, bb2, bb3, bb4])

    let inferenceEngine = WPInferenceEngine(program: program)
    let returnPositionWithoutBranchingHistorySlice = inferenceEngine.slice(
      term: .variable(var2),
      loopUnrolls: LoopUnrolls([
        IRLoop(conditionBlock: bb2Name, bodyStartBlock: bb3Name): 2
      ]),
      inferenceStopPosition: program.returnPosition,
      branchingHistory: [.any(predominatedBy: bb1Name)]
    )
    XCTAssertEqual(returnPositionWithoutBranchingHistorySlice, [
      InstructionPosition(basicBlock: bb1Name, instructionIndex: 1),
    ])
  }

  func testDontSliceAwayNecessaryObserve() {
    let var1 = IRVariable(name: "1", type: .int)
    let var2 = IRVariable(name: "2", type: .bool)

    let bb1Name = BasicBlockName("bb1")


    let bb1 = BasicBlock(name: bb1Name, instructions: [
      DiscreteDistributionInstruction(assignee: var1, distribution: [0: 0.4, 1: 0.6]),
      CompareInstruction(comparison: .equal, assignee: var2, lhs: .variable(var1), rhs: .integer(0)),
      ObserveInstruction(observation: .variable(var2)),
      ReturnInstruction()
    ])
    
    let program = IRProgram(startBlock: bb1Name, basicBlocks: [bb1])
    
    let inferenceEngine = WPInferenceEngine(program: program)
    let slice = inferenceEngine.slice(
      term: .variable(var1),
      loopUnrolls: LoopUnrolls([:]),
      inferenceStopPosition: program.returnPosition,
      branchingHistory: [.any(predominatedBy: bb1Name)]
    )
    XCTAssertEqual(slice, [
      InstructionPosition(basicBlock: bb1Name, instructionIndex: 0),
      InstructionPosition(basicBlock: bb1Name, instructionIndex: 1),
      InstructionPosition(basicBlock: bb1Name, instructionIndex: 2),
    ])
  }

  func testCantSliceAwayClearlyUnnecessaryObserve() {
    let var1 = IRVariable(name: "1", type: .int)
    let var2 = IRVariable(name: "2", type: .int)
    let var3 = IRVariable(name: "3", type: .bool)
    
    let bb1Name = BasicBlockName("bb1")
    
    
    let bb1 = BasicBlock(name: bb1Name, instructions: [
      AssignInstruction(assignee: var1, value: .integer(3)),
      DiscreteDistributionInstruction(assignee: var2, distribution: [0: 0.4, 1: 0.6]),
      CompareInstruction(comparison: .equal, assignee: var3, lhs: .variable(var2), rhs: .integer(0)),
      ObserveInstruction(observation: .variable(var3)),
      ReturnInstruction()
    ])
    
    let program = IRProgram(startBlock: bb1Name, basicBlocks: [bb1])
    
    let inferenceEngine = WPInferenceEngine(program: program)
    let slice = inferenceEngine.slice(
      term: .variable(var1),
      loopUnrolls: LoopUnrolls([:]),
      inferenceStopPosition: program.returnPosition,
      branchingHistory: [.any(predominatedBy: bb1Name)]
    )
    XCTAssertEqual(slice, [
      InstructionPosition(basicBlock: bb1Name, instructionIndex: 0)
    ])
  }
  
  func testSliceAwayTwoSuccessiveIfs() {
    let var1 = IRVariable(name: "1", type: .int)
    let var2 = IRVariable(name: "2", type: .int)
    let var3 = IRVariable(name: "3", type: .int)
    let var4 = IRVariable(name: "4", type: .bool)
    let var5 = IRVariable(name: "5", type: .bool)

    let bb1Name = BasicBlockName("bb1")
    let bb2Name = BasicBlockName("bb2")
    let bb3Name = BasicBlockName("bb3")
    let bb4Name = BasicBlockName("bb4")
    let bb5Name = BasicBlockName("bb5")

    let bb1 = BasicBlock(name: bb1Name, instructions: [
      DiscreteDistributionInstruction(assignee: var1, distribution: [0: 0.7, 1: 0.3]),
      AssignInstruction(assignee: var2, value: .variable(var1)),
      AssignInstruction(assignee: var3, value: .integer(0)),
      CompareInstruction(comparison: .equal, assignee: var4, lhs: .variable(var2), rhs: .integer(0)),
      BranchInstruction(condition: .variable(var4), targetTrue: bb2Name, targetFalse: bb3Name)
    ])

    let bb2 = BasicBlock(name: bb2Name, instructions: [
      JumpInstruction(target: bb3Name)
    ])

    let bb3 = BasicBlock(name: bb3Name, instructions: [
      CompareInstruction(comparison: .equal, assignee: var5, lhs: .variable(var2), rhs: .integer(0)),
      BranchInstruction(condition: .variable(var4), targetTrue: bb4Name, targetFalse: bb5Name)
    ])

    let bb4 = BasicBlock(name: bb4Name, instructions: [
      JumpInstruction(target: bb5Name)
    ])

    let bb5 = BasicBlock(name: bb5Name, instructions: [
      ReturnInstruction()
    ])

    let program = IRProgram(startBlock: bb1Name, basicBlocks: [bb1, bb2, bb3, bb4, bb5])

    let inferenceEngine = WPInferenceEngine(program: program)
    let slice = inferenceEngine.slice(
      term: .variable(var1),
      loopUnrolls: LoopUnrolls([:]),
      inferenceStopPosition: program.returnPosition,
      branchingHistory: [.any(predominatedBy: bb1Name)]
    )
    XCTAssertEqual(slice, [
      InstructionPosition(basicBlock: bb1Name, instructionIndex: 0)
    ])
  }
  
  func testDontSliceAwayObserveThatDependsOnTheSlicingVariable() {
    let var1 = IRVariable(name: "1", type: .int)
    let var2 = IRVariable(name: "2", type: .int)
    let var3 = IRVariable(name: "3", type: .int)
    let var4 = IRVariable(name: "4", type: .bool)
    let var5 = IRVariable(name: "5", type: .int)
    let var6 = IRVariable(name: "6", type: .int)
    let var7 = IRVariable(name: "7", type: .int)
    let var8 = IRVariable(name: "8", type: .bool)
  
    let bb1Name = BasicBlockName("bb1")
    let bb2Name = BasicBlockName("bb2")
    let bb3Name = BasicBlockName("bb3")
    let bb4Name = BasicBlockName("bb4")
    
    let bb1 = BasicBlock(name: bb1Name, instructions: [
      DiscreteDistributionInstruction(assignee: var1, distribution: [0: 0.7, 1: 0.3]),
      AssignInstruction(assignee: var2, value: .variable(var1)),
      AssignInstruction(assignee: var3, value: .integer(0)),
      CompareInstruction(comparison: .equal, assignee: var4, lhs: .variable(var2), rhs: .integer(1)),
      BranchInstruction(condition: .variable(var4), targetTrue: bb2Name, targetFalse: bb3Name)
    ])
    
    let bb2 = BasicBlock(name: bb2Name, instructions: [
      AssignInstruction(assignee: var5, value: .integer(1)),
      JumpInstruction(target: bb4Name)
    ])
    
    let bb3 = BasicBlock(name: bb3Name, instructions: [
      AssignInstruction(assignee: var6, value: .integer(0)),
      JumpInstruction(target: bb4Name)
    ])
    
    let bb4 = BasicBlock(name: bb4Name, instructions: [
      PhiInstruction(assignee: var7, choices: [bb2Name: var5, bb3Name: var6]),
      CompareInstruction(comparison: .equal, assignee: var8, lhs: .variable(var7), rhs: .integer(1)),
      ObserveInstruction(observation: .variable(var8)),
      ReturnInstruction()
    ])
    
    let program = IRProgram(startBlock: bb1Name, basicBlocks: [bb1, bb2, bb3, bb4])
    
    let inferenceEngine = WPInferenceEngine(program: program)
    let slice = inferenceEngine.slice(
      term: .variable(var1),
      loopUnrolls: LoopUnrolls([:]),
      inferenceStopPosition: program.returnPosition,
      branchingHistory: [.any(predominatedBy: bb1Name)]
    )
    XCTAssertEqual(slice, [
      InstructionPosition(basicBlock: bb1Name, instructionIndex: 0),
      InstructionPosition(basicBlock: bb1Name, instructionIndex: 1),
      InstructionPosition(basicBlock: bb1Name, instructionIndex: 3),
      InstructionPosition(basicBlock: bb1Name, instructionIndex: 4),
      InstructionPosition(basicBlock: bb2Name, instructionIndex: 0),
      InstructionPosition(basicBlock: bb3Name, instructionIndex: 0),
      InstructionPosition(basicBlock: bb4Name, instructionIndex: 0),
      InstructionPosition(basicBlock: bb4Name, instructionIndex: 1),
      InstructionPosition(basicBlock: bb4Name, instructionIndex: 2),
    ])
  }
  
  func testDontSliceAwayObserveThatDependsOnTheSlicingVariableInsideBranch() {
    let var1 = IRVariable(name: "1", type: .int)
    let var2 = IRVariable(name: "2", type: .int)
    let var3 = IRVariable(name: "3", type: .int)
    let var4 = IRVariable(name: "4", type: .bool)
    let var5 = IRVariable(name: "5", type: .int)
    let var6 = IRVariable(name: "6", type: .int)
    let var7 = IRVariable(name: "7", type: .int)
    let var8 = IRVariable(name: "8", type: .bool)
    let var9 = IRVariable(name: "9", type: .int)
    let var10 = IRVariable(name: "10", type: .bool)

    let bb1Name = BasicBlockName("bb1")
    let bb2Name = BasicBlockName("bb2")
    let bb3Name = BasicBlockName("bb3")
    let bb4Name = BasicBlockName("bb4")
    let bb5Name = BasicBlockName("bb5")
    let bb6Name = BasicBlockName("bb6")

    let bb1 = BasicBlock(name: bb1Name, instructions: [
      DiscreteDistributionInstruction(assignee: var1, distribution: [0: 0.7, 1: 0.3]),
      AssignInstruction(assignee: var2, value: .variable(var1)),
      AssignInstruction(assignee: var3, value: .integer(0)),
      CompareInstruction(comparison: .equal, assignee: var4, lhs: .variable(var2), rhs: .integer(1)),
      BranchInstruction(condition: .variable(var4), targetTrue: bb2Name, targetFalse: bb3Name)
    ])

    let bb2 = BasicBlock(name: bb2Name, instructions: [
      AssignInstruction(assignee: var5, value: .integer(1)),
      JumpInstruction(target: bb4Name)
    ])

    let bb3 = BasicBlock(name: bb3Name, instructions: [
      AssignInstruction(assignee: var6, value: .integer(0)),
      JumpInstruction(target: bb4Name)
    ])

    let bb4 = BasicBlock(name: bb4Name, instructions: [
      PhiInstruction(assignee: var7, choices: [bb2Name: var5, bb3Name: var6]),
      DiscreteDistributionInstruction(assignee: var9, distribution: [0: 0.5, 1: 0.5]),
      CompareInstruction(comparison: .equal, assignee: var10, lhs: .variable(var9), rhs: .integer(0)),
      BranchInstruction(condition: .variable(var10), targetTrue: bb5Name, targetFalse: bb6Name)
    ])

    let bb5 = BasicBlock(name: bb5Name, instructions: [
      CompareInstruction(comparison: .equal, assignee: var8, lhs: .variable(var7), rhs: .integer(1)),
      ObserveInstruction(observation: .variable(var8)),
      JumpInstruction(target: bb6Name)
    ])

    let bb6 = BasicBlock(name: bb6Name, instructions: [
      ReturnInstruction()
    ])

    let program = IRProgram(startBlock: bb1Name, basicBlocks: [bb1, bb2, bb3, bb4, bb5, bb6])
    
    let inferenceEngine = WPInferenceEngine(program: program)
    let slice = inferenceEngine.slice(
      term: .variable(var1),
      loopUnrolls: LoopUnrolls([:]),
      inferenceStopPosition: program.returnPosition,
      branchingHistory: [.any(predominatedBy: bb1Name)]
    )
    XCTAssertEqual(slice, [
      InstructionPosition(basicBlock: bb1Name, instructionIndex: 0),
      InstructionPosition(basicBlock: bb1Name, instructionIndex: 1),
      InstructionPosition(basicBlock: bb1Name, instructionIndex: 3),
      InstructionPosition(basicBlock: bb1Name, instructionIndex: 4),
      InstructionPosition(basicBlock: bb2Name, instructionIndex: 0),
      InstructionPosition(basicBlock: bb3Name, instructionIndex: 0),
      InstructionPosition(basicBlock: bb4Name, instructionIndex: 0),
      InstructionPosition(basicBlock: bb4Name, instructionIndex: 1),
      InstructionPosition(basicBlock: bb4Name, instructionIndex: 2),
      InstructionPosition(basicBlock: bb4Name, instructionIndex: 3),
      InstructionPosition(basicBlock: bb5Name, instructionIndex: 0),
      InstructionPosition(basicBlock: bb5Name, instructionIndex: 1),
    ])
  }
  
  func testSliceAwayObserveAfterProbabilisticBranch() {
    let var1 = IRVariable(name: "1", type: .int)
    let var2 = IRVariable(name: "2", type: .int)
    let var3 = IRVariable(name: "3", type: .bool)
    let var4 = IRVariable(name: "4", type: .int)
    let var5 = IRVariable(name: "5", type: .int)
    let var6 = IRVariable(name: "6", type: .int)
    let var7 = IRVariable(name: "7", type: .int)
    let var8 = IRVariable(name: "8", type: .bool)
    
    let bb1Name = BasicBlockName("bb1")
    let bb2Name = BasicBlockName("bb2")
    let bb3Name = BasicBlockName("bb3")
    let bb4Name = BasicBlockName("bb4")
    
    let bb1 = BasicBlock(name: bb1Name, instructions: [
      AssignInstruction(assignee: var1, value: .integer(0)),
      DiscreteDistributionInstruction(assignee: var2, distribution: [0: 0.4, 1: 0.6]),
      CompareInstruction(comparison: .equal, assignee: var3, lhs: .variable(var2), rhs: .integer(0)),
      BranchInstruction(condition: .variable(var3), targetTrue: bb2Name, targetFalse: bb3Name)
    ])

    let bb2 = BasicBlock(name: bb2Name, instructions: [
      AssignInstruction(assignee: var4, value: .integer(1)),
      JumpInstruction(target: bb4Name)
    ])

    let bb3 = BasicBlock(name: bb3Name, instructions: [
      AssignInstruction(assignee: var5, value: .integer(2)),
      JumpInstruction(target: bb4Name)
    ])

    let bb4 = BasicBlock(name: bb4Name, instructions: [
      PhiInstruction(assignee: var6, choices: [bb2Name: var4, bb3Name: var5]),
      DiscreteDistributionInstruction(assignee: var7, distribution: [0: 0.5, 1: 0.5]),
      CompareInstruction(comparison: .equal, assignee: var8, lhs: .variable(var7), rhs: .integer(0)),
      ObserveInstruction(observation: .variable(var8)),
      ReturnInstruction()
    ])

    let program = IRProgram(startBlock: bb1Name, basicBlocks: [bb1, bb2, bb3, bb4])
    
    let inferenceEngine = WPInferenceEngine(program: program)
    let slice = inferenceEngine.slice(
      term: .variable(var6),
      loopUnrolls: LoopUnrolls([:]),
      inferenceStopPosition: program.returnPosition,
      branchingHistory: [.any(predominatedBy: bb1Name)]
    )
    XCTAssertEqual(slice, [
      InstructionPosition(basicBlock: bb1Name, instructionIndex: 1),
      InstructionPosition(basicBlock: bb1Name, instructionIndex: 2),
      InstructionPosition(basicBlock: bb1Name, instructionIndex: 3),
      InstructionPosition(basicBlock: bb2Name, instructionIndex: 0),
      InstructionPosition(basicBlock: bb3Name, instructionIndex: 0),
      InstructionPosition(basicBlock: bb4Name, instructionIndex: 0),
    ])
  }
}
