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
}
