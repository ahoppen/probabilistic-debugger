import IR
import IRExecution
import TestUtils

import XCTest

extension Array {
  var only: Element {
    assert(self.count == 1)
    return self.first!
  }
}

class IRExecutorTests: XCTestCase {
  func testDeterministicExecutionWithoutBranch() {
    let bb0Name = BasicBlockName("bb0")
    
    let var0 = IRVariable(name: "0", type: .int)
    let var1 = IRVariable(name: "1", type: .int)
    
    let bb0 = BasicBlock(name: bb0Name, instructions: [
      AssignInstruction(assignee: var0, value: .integer(1)),
      AddInstruction(assignee: var1, lhs: .variable(var0), rhs: .integer(1)),
      ReturnInstruction(),
    ])
    
    let irProgram = IRProgram(startBlock: bb0Name, basicBlocks: [bb0], debugInfo: nil)
    // bb0:
    //   int %0 = int 1
    //   int %1 = add int %0 int 1
    //   return
  
    let executor = IRExecutor(program: irProgram, sampleCount: 1)
    let executedSamples = executor.execute()
    let onlySample = executedSamples.only.samples.only
    
    XCTAssertEqual(onlySample.values[var0], .integer(1))
    XCTAssertEqual(onlySample.values[var1], .integer(2))
  }
  
  func testDeterministicExecutionWithJump() {
    let bb0Name = BasicBlockName("bb0")
    let bb1Name = BasicBlockName("bb1")
    
    let var0 = IRVariable(name: "0", type: .int)
    let var1 = IRVariable(name: "1", type: .int)
    
    let bb0 = BasicBlock(name: bb0Name, instructions: [
      AssignInstruction(assignee: var0, value: .integer(1)),
      JumpInstruction(target: bb1Name)
    ])
    
    let bb1 = BasicBlock(name: bb1Name, instructions: [
      AddInstruction(assignee: var1, lhs: .variable(var0), rhs: .integer(41)),
      ReturnInstruction(),
    ])
    
    let irProgram = IRProgram(startBlock: bb0Name, basicBlocks: [bb0, bb1], debugInfo: nil)
    // bb0:
    //   int %0 = int 1
    //   jump bb1
    // 
    // bb1:
    //   int %1 = add int %0 int 41
    //   return
  
    let executor = IRExecutor(program: irProgram, sampleCount: 1)
    let executedSamples = executor.execute()
    let onlySample = executedSamples.only.samples.only
    
    XCTAssertEqual(onlySample.values[var0], .integer(1))
    XCTAssertEqual(onlySample.values[var1], .integer(42))
  }
  
  func testDeterministicExecutionWithBranchAndTrueBranchTaken() {
    let bb0Name = BasicBlockName("bb0")
    let bb1Name = BasicBlockName("bb1")
    let bb2Name = BasicBlockName("bb2")
    
    let var0 = IRVariable(name: "0", type: .int)
    let var1 = IRVariable(name: "1", type: .bool)
    let var2 = IRVariable(name: "2", type: .int)
    let var3 = IRVariable(name: "3", type: .int)
    
    let bb0 = BasicBlock(name: bb0Name, instructions: [
      AssignInstruction(assignee: var0, value: .integer(5)),
      AssignInstruction(assignee: var1, value: .bool(true)),
      BranchInstruction(condition: .variable(var1), targetTrue: bb1Name, targetFalse: bb2Name)
    ])
    
    let bb1 = BasicBlock(name: bb1Name, instructions: [
      SubtractInstruction(assignee: var2, lhs: .variable(var0), rhs: .integer(1)),
      JumpInstruction(target: bb2Name)
    ])
    
    let bb2 = BasicBlock(name: bb2Name, instructions: [
      PhiInstruction(assignee: var3, choices: [bb0Name: var0, bb1Name: var2]),
      ReturnInstruction(),
    ])
    
    let irProgram = IRProgram(startBlock: bb0Name, basicBlocks: [bb0, bb1, bb2], debugInfo: nil)
    // bb0:
    //   int %0 = int 5
    //   bool %1 = bool true
    //   br bool %1 bb1 bb2
    //
    // bb1:
    //   int %2 = sub int %0 int 1
    //   jump bb2
    //
    // bb2:
    //   int %3 = phi bb0: int %0, bb1: int %2
    //   return
    
    let executor = IRExecutor(program: irProgram, sampleCount: 1)
    let executedSamples = executor.execute()
    let onlySample = executedSamples.only.samples.only
    
    XCTAssertEqual(onlySample.values[var3], .integer(4))
  }
  
  func testDeterministicExecutionWithBranchAndFalseBranchTaken() {
    let bb0Name = BasicBlockName("bb0")
    let bb1Name = BasicBlockName("bb1")
    let bb2Name = BasicBlockName("bb2")
    
    let var0 = IRVariable(name: "0", type: .int)
    let var1 = IRVariable(name: "1", type: .bool)
    let var2 = IRVariable(name: "2", type: .int)
    let var3 = IRVariable(name: "3", type: .int)
    
    let bb0 = BasicBlock(name: bb0Name, instructions: [
      AssignInstruction(assignee: var0, value: .integer(5)),
      AssignInstruction(assignee: var1, value: .bool(false)),
      BranchInstruction(condition: .variable(var1), targetTrue: bb1Name, targetFalse: bb2Name)
    ])
    
    let bb1 = BasicBlock(name: bb1Name, instructions: [
      SubtractInstruction(assignee: var2, lhs: .variable(var0), rhs: .integer(1)),
      JumpInstruction(target: bb2Name)
    ])
    
    let bb2 = BasicBlock(name: bb2Name, instructions: [
      PhiInstruction(assignee: var3, choices: [bb0Name: var0, bb1Name: var2]),
      ReturnInstruction(),
    ])
    
    // bb0:
    //   int %0 = int 5
    //   bool %1 = bool false
    //   br bool %1 bb1 bb2
    //
    // bb1:
    //   int %2 = sub int %0 int 1
    //   jump bb2
    //
    // bb2:
    //   int %3 = phi bb0: int %0, bb1: int %2
    //   return
    
    let irProgram = IRProgram(startBlock: bb0Name, basicBlocks: [bb0, bb1, bb2], debugInfo: nil)
  
    let executor = IRExecutor(program: irProgram, sampleCount: 1)
    let executedSamples = executor.execute()
    let onlySample = executedSamples.only.samples.only
    
    XCTAssertEqual(onlySample.values[var3], .integer(5))
  }
  
  func testDeterministicExecutionWithLoop() {
    let bb0Name = BasicBlockName("bb0")
    let bb1Name = BasicBlockName("bb1")
    let bb2Name = BasicBlockName("bb2")
    let bb3Name = BasicBlockName("bb3")
    
    let var0 = IRVariable(name: "0", type: .int)
    let var1 = IRVariable(name: "1", type: .int)
    let var2 = IRVariable(name: "2", type: .bool)
    let var3 = IRVariable(name: "3", type: .int)
    
    let bb0 = BasicBlock(name: bb0Name, instructions: [
      AssignInstruction(assignee: var0, value: .integer(2)),
      JumpInstruction(target: bb1Name)
    ])
    
    let bb1 = BasicBlock(name: bb1Name, instructions: [
      PhiInstruction(assignee: var1, choices: [bb0Name: var0, bb2Name: var3]),
      CompareInstruction(comparison: .lessThan, assignee: var2, lhs: .integer(1), rhs: .variable(var1)),
      BranchInstruction(condition: .variable(var2), targetTrue: bb2Name, targetFalse: bb3Name)
    ])
    
    let bb2 = BasicBlock(name: bb2Name, instructions: [
      SubtractInstruction(assignee: var3, lhs: .variable(var1), rhs: .integer(1)),
      JumpInstruction(target: bb1Name)
    ])
    
    let bb3 = BasicBlock(name: bb3Name, instructions: [
      ReturnInstruction(),
    ])
    
    let irProgram = IRProgram(startBlock: bb0Name, basicBlocks: [bb0, bb1, bb2, bb3], debugInfo: nil)
    // bb0:
    //   int %0 = int 2
    //   jump bb1
    //
    // bb1:
    //   int %1 = phi bb0: int %0, bb2: int %3
    //   bool %2 = cmp lt int 1 int %1
    //   br bool %2 bb2 bb3
    //
    // bb2:
    //   int %3 = sub int %1 int 1
    //   jump bb1
    //
    // bb3:
    //   return

    
    let executor = IRExecutor(program: irProgram, sampleCount: 1)
    let executedSamples = executor.execute()
    let onlySample = executedSamples.only.samples.only
    
    XCTAssertEqual(onlySample.values[var1], .integer(1))
  }
  
  func testProbabilisticSingleBlockExecution() {
    let bb0Name = BasicBlockName("bb0")
    
    let var0 = IRVariable(name: "0", type: .int)
    
    let bb0 = BasicBlock(name: bb0Name, instructions: [
      DiscreteDistributionInstruction(assignee: var0, distribution: [1: 0.5, 2: 0.5]),
      ReturnInstruction(),
    ])
    
    let irProgram = IRProgram(startBlock: bb0Name, basicBlocks: [bb0], debugInfo: nil)
    // bb0:
    //   int %0 = discrete 1: 0.5, 2: 0.5
    //   return
    
    let executor = IRExecutor(program: irProgram, sampleCount: 10000)
    let executedSamples = executor.execute().flatMap(\.samples)
    
    let var0Values = executedSamples.map( { $0.values[var0]!.integerValue! })
    XCTAssertEqual(var0Values.average, 1.5, accuracy: 0.1)
  }
  
  func testProbabilisticExecutionWithBranch() {
    let bb0Name = BasicBlockName("bb0")
    let bb1Name = BasicBlockName("bb1")
    let bb2Name = BasicBlockName("bb2")
    
    let var0 = IRVariable(name: "0", type: .int)
    let var1 = IRVariable(name: "1", type: .int)
    let var2 = IRVariable(name: "2", type: .bool)
    let var3 = IRVariable(name: "3", type: .int)
    let var4 = IRVariable(name: "4", type: .int)
    
    let bb0 = BasicBlock(name: bb0Name, instructions: [
      AssignInstruction(assignee: var0, value: .integer(0)),
      DiscreteDistributionInstruction(assignee: var1, distribution: [
        1: 0.7,
        2: 0.3
      ]),
      CompareInstruction(comparison: .equal, assignee: var2, lhs: .variable(var1), rhs: .integer(2)),
      BranchInstruction(condition: .variable(var2), targetTrue: bb1Name, targetFalse: bb2Name)
    ])
    
    let bb1 = BasicBlock(name: bb1Name, instructions: [
      AssignInstruction(assignee: var3, value: .integer(10)),
      JumpInstruction(target: bb2Name)
    ])
    
    let bb2 = BasicBlock(name: bb2Name, instructions: [
      PhiInstruction(assignee: var4, choices: [bb0Name: var0, bb1Name: var3]),
      ReturnInstruction(),
    ])
    
    let irProgram = IRProgram(startBlock: bb0Name, basicBlocks: [bb0, bb1, bb2], debugInfo: nil)
    // bb0:
    //   int %0 = int 0
    //   int %1 = discrete 1: 0.7, 2: 0.3
    //   bool %2 = cmp eq int %1 int 2
    //   br bool %2 bb1 bb2
    //
    // bb1:
    //   int %3 = int 10
    //   jump bb2
    //
    // bb2:
    //   int %4 = phi bb0: int %0, bb1: int %3
    //   return
    
    let executor = IRExecutor(program: irProgram, sampleCount: 10000)
    let executedSamples = executor.execute().flatMap(\.samples)
    
    let var0Values = executedSamples.map( { $0.values[var4]!.integerValue! })
    XCTAssertEqual(var0Values.average, 3, accuracy: 0.5)
  }
  
  func testObserve() {
    let bb0Name = BasicBlockName("bb0")
    
    let var0 = IRVariable(name: "0", type: .int)
    let var1 = IRVariable(name: "1", type: .bool)
    
    let bb0 = BasicBlock(name: bb0Name, instructions: [
      DiscreteDistributionInstruction(assignee: var0, distribution: [
        1: 0.5,
        2: 0.5
      ]),
      CompareInstruction(comparison: .equal, assignee: var1, lhs: .variable(var0), rhs: .integer(1)),
      ObserveInstruction(observation: .variable(var1)),
      ReturnInstruction(),
    ])
    
    let irProgram = IRProgram(startBlock: bb0Name, basicBlocks: [bb0], debugInfo: nil)
    // bb0:
    //   int %0 = discrete 1: 0.5, 2: 0.5
    //   bool %1 = cmp eq int %0 int 1
    //   observe bool %1
    //   return
    
    let executor = IRExecutor(program: irProgram, sampleCount: 10000)
    let executedSamples = executor.execute().flatMap(\.samples)
    
    XCTAssert(executedSamples.allSatisfy({ $0.values[var0]!.integerValue! == 1 }))
    XCTAssertEqual(Double(executedSamples.count), 5000, accuracy: 500)
  }
}
