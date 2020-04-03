import Debugger
import SimpleLanguageIRGen
import TestUtils

import XCTest

class DebuggerTests: XCTestCase {
  func testRunSingleAssignmentAndGetVariableValues() {
    let sourceCode = """
      int x = 42
      """
    
    let program = try! SLIRGen.generateIr(for: sourceCode)
    
    let debugger = Debugger(program: program, sampleCount: 1)
    let samples = debugger.run()
    XCTAssertEqual(samples.count, 1)
    let sample = samples.first!
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
    
    let program = try! SLIRGen.generateIr(for: sourceCode)
    
    let debugger = Debugger(program: program, sampleCount: 1)
    let samples = debugger.run()
    XCTAssertEqual(samples.count, 1)
    let sample = samples.first!
    XCTAssertEqual(sample.values, [
      "x": .integer(41),
      "y": .integer(52),
    ])
  }
  
  func testRunProbabilisticProgram() {
    let sourceCode = """
      int x = discrete({1: 0.5, 2: 0.5})
      """
    
    let program = try! SLIRGen.generateIr(for: sourceCode)
    
    let debugger = Debugger(program: program, sampleCount: 10000)
    let samples = debugger.run()
    let xValues = samples.map {
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
    
    
    let program = try! SLIRGen.generateIr(for: sourceCode)
    
    let debugger = Debugger(program: program, sampleCount: 10000)
    let samples = debugger.run()
    let yValues = samples.map {
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
    
    
    let program = try! SLIRGen.generateIr(for: sourceCode)
    
    let debugger = Debugger(program: program, sampleCount: 1)
    let samples = debugger.run()
    XCTAssertEqual(samples.count, 1)
    let sample = samples.first!
    
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
    
    
    let program = try! SLIRGen.generateIr(for: sourceCode)
    
    let debugger = Debugger(program: program, sampleCount: 1)
    let samples = debugger.run()
    XCTAssertEqual(samples.count, 0)
  }
}
