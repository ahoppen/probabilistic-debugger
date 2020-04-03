import IR
import SimpleLanguageIRGen
import SimpleLanguageParser
import SimpleLanguageTypeChecker

import XCTest

class IRGenTests: XCTestCase {
  func testSimpleIRGen() {
    let sourceCode = """
      int x = 2
      x = x + 1
      int y = x + 3
      """
    let file = try! Parser(sourceCode: sourceCode).parseFile()
    let typeCheckedFile = try! TypeCheckPipeline.typeCheck(stmts: file)
    
    let ir = IRGen().generateIR(for: typeCheckedFile)
    
    let bb1Name = BasicBlockName("bb1")
    
    let var1 = IRVariable(name: "1", type: .int)
    let var2 = IRVariable(name: "2", type: .int)
    let var3 = IRVariable(name: "3", type: .int)
    let var4 = IRVariable(name: "4", type: .int)
    let var5 = IRVariable(name: "5", type: .int)
    
    let bb1 = BasicBlock(name: bb1Name, instructions: [
      AssignInstr(assignee: var1, value: .integer(2)),
      AddInstr(assignee: var2, lhs: .variable(var1), rhs: .integer(1)),
      AssignInstr(assignee: var3, value: .variable(var2)),
      AddInstr(assignee: var4, lhs: .variable(var3), rhs: .integer(3)),
      AssignInstr(assignee: var5, value: .variable(var4)),
      ReturnInstr(),
    ])
    let expectedProgram = IRProgram(startBlock: bb1Name, basicBlocks: [bb1], debugInfo: nil)
    
    XCTAssertEqual(ir, expectedProgram)
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
    let ir = IRGen().generateIR(for: typeCheckedFile)
    
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
      AssignInstr(assignee: var1, value: .integer(2)),
      CompareInstr(comparison: .lessThan, assignee: var2, lhs: .variable(var1), rhs: .integer(1)),
      ConditionalBranchInstr(condition: .variable(var2), targetTrue: bb2Name, targetFalse: bb3Name)
    ])
    
    let bb2 = BasicBlock(name: bb2Name, instructions: [
      AddInstr(assignee: var3, lhs: .variable(var1), rhs: .integer(1)),
      AssignInstr(assignee: var4, value: .variable(var3)),
      JumpInstr(target: bb3Name)
    ])
    
    let bb3 = BasicBlock(name: bb3Name, instructions: [
      PhiInstr(assignee: var5, choices: [bb1Name: var1, bb2Name: var4]),
      AssignInstr(assignee: var6, value: .variable(var5)),
      ReturnInstr(),
    ])
    
    let expectedProgram = IRProgram(startBlock: bb1Name, basicBlocks: [bb1, bb2, bb3], debugInfo: nil)
    
    XCTAssertEqual(ir, expectedProgram)
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
    let ir = IRGen().generateIR(for: typeCheckedFile)
    
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
      AssignInstr(assignee: var1, value: .integer(5)),
      JumpInstr(target: bb2Name)
    ])
    
    let bb2 = BasicBlock(name: bb2Name, instructions: [
      PhiInstr(assignee: var5, choices: [bb1Name: var1, bb3Name: var4]),
      CompareInstr(comparison: .lessThan, assignee: var2, lhs: .integer(1), rhs: .variable(var5)),
      ConditionalBranchInstr(condition: .variable(var2), targetTrue: bb3Name, targetFalse: bb4Name)
    ])
    
    let bb3 = BasicBlock(name: bb3Name, instructions: [
      SubtractInstr(assignee: var3, lhs: .variable(var5), rhs: .integer(1)),
      AssignInstr(assignee: var4, value: .variable(var3)),
      JumpInstr(target: bb2Name)
    ])
    
    let bb4 = BasicBlock(name: bb4Name, instructions: [
      AssignInstr(assignee: var6, value: .variable(var5)),
      ReturnInstr(),
    ])
    
    let expectedProgram = IRProgram(startBlock: bb1Name, basicBlocks: [bb1, bb2, bb3, bb4], debugInfo: nil)
    
    XCTAssertEqual(ir, expectedProgram)
  }
}
