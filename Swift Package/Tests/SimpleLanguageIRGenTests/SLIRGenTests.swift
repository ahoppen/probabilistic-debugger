import IR
import SimpleLanguageIRGen
import SimpleLanguageParser
import SimpleLanguageTypeChecker

import XCTest

class SLIRGenTests: XCTestCase {
  func testSimpleIRGen() {
    let sourceCode = """
      int x = 2
      x = x + 1
      int y = x + 3
      """
    let file = try! Parser(sourceCode: sourceCode).parseFile()
    let typeCheckedFile = try! TypeCheckPipeline.typeCheck(stmts: file)
    
    let ir = SLIRGen().generateIR(for: typeCheckedFile).program
    
    let bb1Name = BasicBlockName("bb1")
    
    let var1 = IRVariable(name: "1", type: .int)
    let var2 = IRVariable(name: "2", type: .int)
    let var3 = IRVariable(name: "3", type: .int)
    let var4 = IRVariable(name: "4", type: .int)
    let var5 = IRVariable(name: "5", type: .int)
    
    let bb1 = BasicBlock(name: bb1Name, instructions: [
      AssignInstruction(assignee: var1, value: .integer(2)),
      AddInstruction(assignee: var2, lhs: .variable(var1), rhs: .integer(1)),
      AssignInstruction(assignee: var3, value: .variable(var2)),
      AddInstruction(assignee: var4, lhs: .variable(var3), rhs: .integer(3)),
      AssignInstruction(assignee: var5, value: .variable(var4)),
      ReturnInstruction(),
    ])
    
    XCTAssertEqual(ir.startBlock, bb1Name)
    XCTAssertEqual(ir.basicBlocks, [bb1Name: bb1])
  }
  
  func testIRWithIf() {
    let sourceCode = """
      int x = 2
      if x < 1 {
        x = x + 1
      }
      int y = x
      """
    let file = try! Parser(sourceCode: sourceCode).parseFile()
    let typeCheckedFile = try! TypeCheckPipeline.typeCheck(stmts: file)
    let ir = SLIRGen().generateIR(for: typeCheckedFile).program
    
    let var1 = IRVariable(name: "1", type: .int)
    let var2 = IRVariable(name: "2", type: .bool)
    let var3 = IRVariable(name: "3", type: .int)
    let var4 = IRVariable(name: "4", type: .int)
    let var5 = IRVariable(name: "5", type: .int)
    let var6 = IRVariable(name: "6", type: .int)
    
    let bb1Name = BasicBlockName("bb1")
    let bb2Name = BasicBlockName("bb2")
    let bb3Name = BasicBlockName("bb3")
    
    
    let bb1 = BasicBlock(name: bb1Name, instructions: [
      AssignInstruction(assignee: var1, value: .integer(2)),
      CompareInstruction(comparison: .lessThan, assignee: var2, lhs: .variable(var1), rhs: .integer(1)),
      BranchInstruction(condition: .variable(var2), targetTrue: bb2Name, targetFalse: bb3Name)
    ])
    
    let bb2 = BasicBlock(name: bb2Name, instructions: [
      AddInstruction(assignee: var3, lhs: .variable(var1), rhs: .integer(1)),
      AssignInstruction(assignee: var4, value: .variable(var3)),
      JumpInstruction(target: bb3Name)
    ])
    
    let bb3 = BasicBlock(name: bb3Name, instructions: [
      PhiInstruction(assignee: var5, choices: [bb1Name: var1, bb2Name: var4]),
      AssignInstruction(assignee: var6, value: .variable(var5)),
      ReturnInstruction(),
    ])
    
    XCTAssertEqual(ir.startBlock, bb1Name)
    XCTAssertEqual(ir.basicBlocks, [bb1Name: bb1, bb2Name: bb2, bb3Name: bb3])
  }
  
  func testLoop() {
    let sourceCode = """
      int x = 5
      while 1 < x {
        x = x - 1
      }
      int y = x
      """
    let file = try! Parser(sourceCode: sourceCode).parseFile()
    let typeCheckedFile = try! TypeCheckPipeline.typeCheck(stmts: file)
    let ir = SLIRGen().generateIR(for: typeCheckedFile).program
    
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
    
    XCTAssertEqual(ir.startBlock, bb1Name)
    XCTAssertEqual(ir.basicBlocks, [bb1Name: bb1, bb2Name: bb2, bb3Name: bb3, bb4Name: bb4])
  }
  
  func testIfInsideWhile() {
    let sourceCode = """
      int x = 5
      int y = x
      while 1 < x {
        if true {
          x = x - 1
        }
      }
      """
    
    let file = try! Parser(sourceCode: sourceCode).parseFile()
    let typeCheckedFile = try! TypeCheckPipeline.typeCheck(stmts: file)
    let ir = SLIRGen().generateIR(for: typeCheckedFile).program
    
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
    let bb5Name = BasicBlockName("bb5")
    let bb6Name = BasicBlockName("bb6")
    
    let bb1 = BasicBlock(name: bb1Name, instructions: [
      AssignInstruction(assignee: var1, value: .integer(5)),
      AssignInstruction(assignee: var2, value: .variable(var1)),
      JumpInstruction(target: bb2Name)
    ])

    let bb2 = BasicBlock(name: bb2Name, instructions: [
      PhiInstruction(assignee: var7, choices: [bb1Name: var1, bb6Name: var6]),
      CompareInstruction(comparison: .lessThan, assignee: var3, lhs: .integer(1), rhs: .variable(var7)),
      BranchInstruction(condition: .variable(var3), targetTrue: bb3Name, targetFalse: bb4Name)
    ])

    let bb3 = BasicBlock(name: bb3Name, instructions: [
      BranchInstruction(condition: .bool(true), targetTrue: bb5Name, targetFalse: bb6Name)
    ])
    
    let bb4 = BasicBlock(name: bb4Name, instructions: [
      ReturnInstruction()
    ])
    
    let bb5 = BasicBlock(name: bb5Name, instructions: [
      SubtractInstruction(assignee: var4, lhs: .variable(var7), rhs: .integer(1)),
      AssignInstruction(assignee: var5, value: .variable(var4)),
      JumpInstruction(target: bb6Name)
    ])
    
    let bb6 = BasicBlock(name: bb6Name, instructions: [
      PhiInstruction(assignee: var6, choices: [bb3Name: var7, bb5Name: var5]),
      JumpInstruction(target: bb2Name)
    ])
    
    XCTAssertEqual(ir, IRProgram(startBlock: bb1Name, basicBlocks: [bb1, bb2, bb3, bb4, bb5, bb6]))
  }
  
  func testNestedIfs() {
    let sourceCode = """
      int turn = 1
      if false {
        if true {
          turn = 2
        }
      }
      """
    
    let file = try! Parser(sourceCode: sourceCode).parseFile()
    let typeCheckedFile = try! TypeCheckPipeline.typeCheck(stmts: file)
    // Test that we don't hit any verification errors when generating the above program
    _ = SLIRGen().generateIR(for: typeCheckedFile).program
  }
  
  func testCowboyDuel() {
    let sourceCode = """
      int turn = discrete({1: 0.5, 2: 0.5})
      bool alive = true
      while alive {
        if turn == 1 {
          int coin = discrete({0: 0.5, 1: 0.5})
          if coin == 0 {
            turn = 2
          }
          if coin == 1 {
            alive = false
          }
        }
        if turn == 2 {
          int coin = discrete({0: 0.5, 1: 0.5})
          if coin == 0 {
            turn = 1
          }
          if coin == 1 {
            alive = false
          }
        }
      }
      """
    
    let file = try! Parser(sourceCode: sourceCode).parseFile()
    let typeCheckedFile = try! TypeCheckPipeline.typeCheck(stmts: file)
    // Test that we don't hit any verification errors when generating the above program
    _ = SLIRGen().generateIR(for: typeCheckedFile).program
  }
  
  func testGenerateIfElse() {
    let sourceCode = """
      int x = 1
      if true {
        x = 2
      } else {
        x = 3
      }
      """
    
    let file = try! Parser(sourceCode: sourceCode).parseFile()
    let typeCheckedFile = try! TypeCheckPipeline.typeCheck(stmts: file)
    let ir = SLIRGen().generateIR(for: typeCheckedFile).program
    
    let var1 = IRVariable(name: "1", type: .int)
    let var2 = IRVariable(name: "2", type: .int)
    let var3 = IRVariable(name: "3", type: .int)
    let var4 = IRVariable(name: "4", type: .int)
    
    let bb1Name = BasicBlockName("bb1")
    let bb2Name = BasicBlockName("bb2")
    let bb3Name = BasicBlockName("bb3")
    let bb4Name = BasicBlockName("bb4")
    
    let bb1 = BasicBlock(name: bb1Name, instructions: [
      AssignInstruction(assignee: var1, value: .integer(1)),
      BranchInstruction(condition: .bool(true), targetTrue: bb2Name, targetFalse: bb3Name),
    ])
    
    let bb2 = BasicBlock(name: bb2Name, instructions: [
      AssignInstruction(assignee: var2, value: .integer(2)),
      JumpInstruction(target: bb4Name)
    ])
    
    let bb3 = BasicBlock(name: bb3Name, instructions: [
      AssignInstruction(assignee: var3, value: .integer(3)),
      JumpInstruction(target: bb4Name)
    ])
    
    let bb4 = BasicBlock(name: bb4Name, instructions: [
      PhiInstruction(assignee: var4, choices: [bb2Name: var2, bb3Name: var3]),
      ReturnInstruction()
    ])
    
    XCTAssertEqual(ir, IRProgram(startBlock: bb1Name, basicBlocks: [bb1, bb2, bb3, bb4]))
  }
  
  func testNestedIfElse() {
    let sourceCode = """
    int x = discrete({1: 0.25, 2: 0.25, 3: 0.25, 4: 0.25})
    int y = x
    if 2 < x {
      if x == 3 {
        x = 3
      } else {
        x = 4
      }
    } else {
      if x == 1 {
        x = 1
      } else {
        x = 2
      }
    }
    """
    
    let file = try! Parser(sourceCode: sourceCode).parseFile()
    let typeCheckedFile = try! TypeCheckPipeline.typeCheck(stmts: file)
    // Test that we don't hit any verification errors when generating the above program
    _ = SLIRGen().generateIR(for: typeCheckedFile).program
  }
  
  func testDebugInfoGetsAdjustedForPhiInstructionsInsideWhileLoop() {
    let sourceCode = """
      int turn = 2
      bool alive = true
      while alive {
        if turn == 1 {
          alive = false
        }
        turn = 1
      }
      """
    
    let ir = try! SLIRGen.generateIr(for: sourceCode)
    
    let var1 = IRVariable(name: "1", type: .int)
    let var2 = IRVariable(name: "2", type: .bool)
    let var3 = IRVariable(name: "3", type: .bool)
    let var4 = IRVariable(name: "4", type: .bool)
    let var5 = IRVariable(name: "5", type: .bool)
    let var6 = IRVariable(name: "6", type: .int)
    let var7 = IRVariable(name: "7", type: .int)
    let var8 = IRVariable(name: "8", type: .bool)
    
    let bb1Name = BasicBlockName("bb1")
    let bb2Name = BasicBlockName("bb2")
    let bb3Name = BasicBlockName("bb3")
    let bb4Name = BasicBlockName("bb4")
    let bb5Name = BasicBlockName("bb5")
    let bb6Name = BasicBlockName("bb6")
    
    let bb1 = BasicBlock(name: bb1Name, instructions: [
      AssignInstruction(assignee: var1, value: .integer(2)),
      AssignInstruction(assignee: var2, value: .bool(true)),
      JumpInstruction(target: bb2Name)
    ])
    
    let bb2 = BasicBlock(name: bb2Name, instructions: [
      PhiInstruction(assignee: var8, choices: [bb1Name: var2, bb6Name: var5]),
      PhiInstruction(assignee: var7, choices: [bb1Name: var1, bb6Name: var6]),
      BranchInstruction(condition: .variable(var8), targetTrue: bb3Name, targetFalse: bb4Name)
    ])
    
    let bb3 = BasicBlock(name: bb3Name, instructions: [
      CompareInstruction(comparison: .equal, assignee: var3, lhs: .variable(var7), rhs: .integer(1)),
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
      PhiInstruction(assignee: var5, choices: [bb3Name: var8, bb5Name: var4]),
      AssignInstruction(assignee: var6, value: .integer(1)),
      JumpInstruction(target: bb2Name)
    ])
    
    let expectedIr = IRProgram(startBlock: bb1Name, basicBlocks: [bb1, bb2, bb3, bb4, bb5, bb6])
    XCTAssertEqual(ir.program, expectedIr)
    
    XCTAssertEqual(ir.debugInfo.info[InstructionPosition(basicBlock: BasicBlockName("bb3"), instructionIndex: 1)]!.variables["turn"]!, IRVariable(name: "7", type: .int))
  }
}
