import Debugger
import SimpleLanguageIRGen
import TestUtils

import XCTest

class DebuggerTests: XCTestCase {
  func testRunSingleAssignmentAndGetVariableValues() {
    let sourceCode = """
      int x = 42
      """
    
    let ir = try! SLIRGen.generateIr(for: sourceCode)
    
    let debugger = Debugger(program: ir.program, debugInfo: ir.debugInfo, sampleCount: 1)
    XCTAssertNoThrow(try debugger.run())
    XCTAssertEqual(debugger.samples.count, 1)
    let sample = debugger.samples.first!
    XCTAssertEqual(sample.values, [
      "x": .integer(42)
    ])
  }
  
  func testRunDeterministicComputationAndGetVariableValues() {
    let sourceCode = """
      int x = 42
      x = x - 1
      int y = x + 11
      """
    
    let ir = try! SLIRGen.generateIr(for: sourceCode)
    
    let debugger = Debugger(program: ir.program, debugInfo: ir.debugInfo, sampleCount: 1)
    XCTAssertNoThrow(try debugger.run())
    XCTAssertEqual(debugger.samples.count, 1)
    let sample = debugger.samples.first!
    XCTAssertEqual(sample.values, [
      "x": .integer(41),
      "y": .integer(52),
    ])
  }
  
  func testRunProbabilisticProgram() {
    let sourceCode = """
      int x = discrete({1: 0.5, 2: 0.5})
      """
    
    let ir = try! SLIRGen.generateIr(for: sourceCode)
    
    let debugger = Debugger(program: ir.program, debugInfo: ir.debugInfo, sampleCount: 10000)
    XCTAssertNoThrow(try debugger.run())
    let xValues = debugger.samples.map {
      return $0.values["x"]!.integerValue!
    }
    
    XCTAssertEqual(xValues.average, 1.5, accuracy: 0.2)
  }
  
  func testRunProbabilisticProgramWithBranch() {
    let sourceCode = """
      int x = discrete({1: 0.5, 2: 0.5})
      int y = 10
      if x == 2 {
        y = 20
      }
      """
    
    
    let ir = try! SLIRGen.generateIr(for: sourceCode)
    
    let debugger = Debugger(program: ir.program, debugInfo: ir.debugInfo, sampleCount: 10000)
    XCTAssertNoThrow(try debugger.run())
    let yValues = debugger.samples.map {
      return $0.values["y"]!.integerValue!
    }
    
    XCTAssertEqual(yValues.average, 15, accuracy: 1)
  }
  
  func testRunProgramWithVariableShadowing() {
    let sourceCode = """
      int x = 1
      {
        int x = 2
      }
      """
    
    
    let ir = try! SLIRGen.generateIr(for: sourceCode)
    
    let debugger = Debugger(program: ir.program, debugInfo: ir.debugInfo, sampleCount: 1)
    XCTAssertNoThrow(try debugger.run())
    XCTAssertEqual(debugger.samples.count, 1)
    let sample = debugger.samples.first!
    
    XCTAssertEqual(sample.values, [
      "x": .integer(1),
      "x#2": .integer(2),
    ])
  }
  
  func testRunProgramWithoutViableRun() {
    let sourceCode = """
      int x = 1
      observe(x == 2)
      """
    
    
    let ir = try! SLIRGen.generateIr(for: sourceCode)
    
    let debugger = Debugger(program: ir.program, debugInfo: ir.debugInfo, sampleCount: 1)
    XCTAssertNoThrow(try debugger.run())
    XCTAssertEqual(debugger.samples.count, 0)
  }
  
  func testSteppingThroughStraightLineProgram() {
    let sourceCode = """
      int x = 42
      x = x - 1
      int y = x + 11
      """
    
    let ir = try! SLIRGen.generateIr(for: sourceCode)
    let debugger = Debugger(program: ir.program, debugInfo: ir.debugInfo, sampleCount: 1)
    
    XCTAssertNoThrow(try debugger.step())
    XCTAssertEqual(debugger.samples.count, 1)
    XCTAssertEqual(debugger.samples.first!.values, [
      "x": .integer(42),
    ])
    XCTAssertNoThrow(try debugger.step())
    XCTAssertEqual(debugger.samples.count, 1)
    XCTAssertEqual(debugger.samples.first!.values, [
      "x": .integer(41),
    ])
    XCTAssertNoThrow(try debugger.step())
    XCTAssertEqual(debugger.samples.count, 1)
    XCTAssertEqual(debugger.samples.first!.values, [
      "x": .integer(41),
      "y": .integer(52)
    ])
    
    XCTAssertThrowsError(try debugger.step())
  }
}
