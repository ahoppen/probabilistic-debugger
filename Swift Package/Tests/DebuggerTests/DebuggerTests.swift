import Debugger
import IR
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
    XCTAssertNoThrow(try debugger.runUntilEnd())
    XCTAssertEqual(debugger.samples.count, 1)
    let sample = debugger.samples.first!
    XCTAssertEqual(sample.values, [
      "x": .integer(42)
    ])
    XCTAssertEqual(debugger.variableValuesRefinedUsingWP["x"], [
      .integer(42): 1
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
    XCTAssertNoThrow(try debugger.runUntilEnd())
    XCTAssertEqual(debugger.samples.count, 1)
    let sample = debugger.samples.first!
    XCTAssertEqual(sample.values, [
      "x": .integer(41),
      "y": .integer(52),
    ])
    XCTAssertEqual(debugger.variableValuesRefinedUsingWP["x"], [
      .integer(41): 1
    ])
    XCTAssertEqual(debugger.variableValuesRefinedUsingWP["y"], [
      .integer(52): 1
    ])
  }
  
  func testRunProbabilisticProgram() {
    let sourceCode = """
      int x = discrete({1: 0.5, 2: 0.5})
      """
    
    let ir = try! SLIRGen.generateIr(for: sourceCode)
    
    let debugger = Debugger(program: ir.program, debugInfo: ir.debugInfo, sampleCount: 10000)
    XCTAssertNoThrow(try debugger.runUntilEnd())
    let xValues = debugger.samples.map {
      return $0.values["x"]!.integerValue!
    }
    
    XCTAssertEqual(xValues.average, 1.5, accuracy: 0.2)
    XCTAssertEqual(debugger.variableValuesRefinedUsingWP["x"], [
      .integer(1): 0.5,
      .integer(2): 0.5,
    ])
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
    XCTAssertNoThrow(try debugger.runUntilEnd())
    let yValues = debugger.samples.map {
      return $0.values["y"]!.integerValue!
    }
    
    XCTAssertEqual(yValues.average, 15, accuracy: 1)
    XCTAssertEqual(debugger.variableValuesRefinedUsingWP["x"], [
      .integer(1): 0.5,
      .integer(2): 0.5,
    ])
    XCTAssertEqual(debugger.variableValuesRefinedUsingWP["y"], [
      .integer(10): 0.5,
      .integer(20): 0.5,
    ])
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
    XCTAssertNoThrow(try debugger.runUntilEnd())
    XCTAssertEqual(debugger.samples.count, 1)
    let sample = debugger.samples.first!
    
    XCTAssertEqual(sample.values, [
      "x": .integer(1),
      "x#2": .integer(2),
    ])
    XCTAssertEqual(debugger.variableValuesRefinedUsingWP["x"], [
      .integer(1): 1,
    ])
    XCTAssertEqual(debugger.variableValuesRefinedUsingWP["x#2"], [
      .integer(2): 1,
    ])
  }
  
  func testRunProgramWithoutViableRun() {
    let sourceCode = """
      int x = 1
      observe(x == 2)
      """
    
    
    let ir = try! SLIRGen.generateIr(for: sourceCode)
    
    let debugger = Debugger(program: ir.program, debugInfo: ir.debugInfo, sampleCount: 1)
    XCTAssertNoThrow(try debugger.runUntilEnd())
    XCTAssertEqual(debugger.samples.count, 0)
    XCTAssertEqual(debugger.variableValuesRefinedUsingWP, [:])
  }
  
  func testSteppingThroughStraightLineProgram() {
    let sourceCode = """
      int x = 42
      x = x - 1
      int y = x + 11
      """
    
    let ir = try! SLIRGen.generateIr(for: sourceCode)
    let debugger = Debugger(program: ir.program, debugInfo: ir.debugInfo, sampleCount: 1)
    
    XCTAssertNoThrow(try debugger.stepOver())
    XCTAssertEqual(debugger.sourceLocation, SourceCodeLocation(line: 2, column: 1))
    XCTAssertEqual(debugger.samples.count, 1)
    XCTAssertEqual(debugger.samples.first!.values, [
      "x": .integer(42),
    ])
    XCTAssertEqual(debugger.variableValuesRefinedUsingWP["x"], [
      .integer(42): 1,
    ])
    
    XCTAssertNoThrow(try debugger.stepOver())
    XCTAssertEqual(debugger.sourceLocation, SourceCodeLocation(line: 3, column: 1))
    XCTAssertEqual(debugger.samples.count, 1)
    XCTAssertEqual(debugger.samples.first!.values, [
      "x": .integer(41),
    ])
    XCTAssertEqual(debugger.variableValuesRefinedUsingWP["x"], [
      .integer(41): 1,
    ])
    
    XCTAssertNoThrow(try debugger.stepOver())
    XCTAssertEqual(debugger.sourceLocation, SourceCodeLocation(line: 3, column: 15))
    XCTAssertEqual(debugger.samples.count, 1)
    XCTAssertEqual(debugger.samples.first!.values, [
      "x": .integer(41),
      "y": .integer(52)
    ])
    XCTAssertEqual(debugger.variableValuesRefinedUsingWP["x"], [
      .integer(41): 1,
    ])
    XCTAssertEqual(debugger.variableValuesRefinedUsingWP["y"], [
      .integer(52): 1,
    ])
    
    XCTAssertThrowsError(try debugger.stepOver())
  }
  
  func testStepIntoBranch() {
    let sourceCode = """
      int x = discrete({1: 0.3, 2: 0.7})
      if x == 1 {
        x = x + 1
      }
      """

    let ir = try! SLIRGen.generateIr(for: sourceCode)
    let debugger = Debugger(program: ir.program, debugInfo: ir.debugInfo, sampleCount: 10_000)

    XCTAssertNoThrow(try debugger.stepOver())
    XCTAssertEqual(debugger.sourceLocation, SourceCodeLocation(line: 2, column: 1))
    XCTAssertEqual(debugger.samples.count, 10_000)
    XCTAssertEqual(debugger.samples.map({ $0.values["x"]!.integerValue! }).average, 1.7, accuracy: 0.1)
    XCTAssertEqual(debugger.variableValuesRefinedUsingWP["x"], [
      .integer(1): 0.3,
      .integer(2): 0.7,
    ])
    
    XCTAssertNoThrow(try debugger.stepInto(branch: true))
    XCTAssertEqual(debugger.sourceLocation, SourceCodeLocation(line: 3, column: 3))
    XCTAssertEqual(Double(debugger.samples.count), 3_000, accuracy: 300)
    XCTAssertEqual(debugger.samples.map({ $0.values["x"]!.integerValue! }).average, 1)
    XCTAssertEqual(debugger.variableValuesRefinedUsingWP["x"], [
      .integer(1): 1,
    ])
    
    XCTAssertNoThrow(try debugger.stepOver())
    XCTAssertEqual(debugger.sourceLocation, SourceCodeLocation(line: 4, column: 2))
    XCTAssertEqual(Double(debugger.samples.count), 3_000, accuracy: 300)
    XCTAssertEqual(debugger.samples.map({ $0.values["x"]!.integerValue! }).average, 2)
    XCTAssertEqual(debugger.variableValuesRefinedUsingWP["x"], [
      .integer(2): 1,
    ])
  }
  
  func testStepIntoFalseBranch() {
    let sourceCode = """
      int x = discrete({1: 0.3, 2: 0.7})
      if x == 1 {
        x = x - 1
      }
      """

    let ir = try! SLIRGen.generateIr(for: sourceCode)
    let debugger = Debugger(program: ir.program, debugInfo: ir.debugInfo, sampleCount: 10_000)

    XCTAssertNoThrow(try debugger.stepOver())
    XCTAssertEqual(debugger.sourceLocation, SourceCodeLocation(line: 2, column: 1))
    XCTAssertEqual(debugger.samples.count, 10_000)
    XCTAssertEqual(debugger.samples.map({ $0.values["x"]!.integerValue! }).average, 1.7, accuracy: 0.1)
    XCTAssertEqual(debugger.variableValuesRefinedUsingWP["x"], [
      .integer(1): 0.3,
      .integer(2): 0.7,
    ])

    XCTAssertNoThrow(try debugger.stepInto(branch: false))
    XCTAssertEqual(debugger.sourceLocation, SourceCodeLocation(line: 4, column: 2))
    XCTAssertEqual(Double(debugger.samples.count), 7_000, accuracy: 300)
    XCTAssertEqual(debugger.samples.map({ $0.values["x"]!.integerValue! }).average, 2)
    XCTAssertEqual(debugger.variableValuesRefinedUsingWP["x"], [
      .integer(2): 1,
    ])
  }
  
  func testStepOverBranch() {
    let sourceCode = """
      int x = discrete({1: 0.3, 2: 0.7})
      if x == 1 {
        x = x + 2
      }
      """

    let ir = try! SLIRGen.generateIr(for: sourceCode)
    let debugger = Debugger(program: ir.program, debugInfo: ir.debugInfo, sampleCount: 10_000)

    XCTAssertNoThrow(try debugger.stepOver())
    XCTAssertEqual(debugger.sourceLocation, SourceCodeLocation(line: 2, column: 1))
    XCTAssertEqual(debugger.samples.count, 10_000)
    XCTAssertEqual(debugger.samples.map({ $0.values["x"]!.integerValue! }).average, 1.7, accuracy: 0.1)
    XCTAssertEqual(debugger.variableValuesRefinedUsingWP["x"], [
      .integer(1): 0.3,
      .integer(2): 0.7,
    ])

    XCTAssertNoThrow(try debugger.stepOver())
    XCTAssertEqual(debugger.sourceLocation, SourceCodeLocation(line: 4, column: 2))
    XCTAssertEqual(debugger.samples.count, 10_000)
    XCTAssertEqual(debugger.samples.map({ $0.values["x"]!.integerValue! }).average, 2.3, accuracy: 0.2)
    XCTAssertEqual(debugger.variableValuesRefinedUsingWP["x"], [
      .integer(2): 0.7,
      .integer(3): 0.3,
    ])
  }
  
  func testStepThroughLoopBranch() {
    let sourceCode = """
      int x = 2
      while 1 < x {
        x = x - 1
      }
      """

    let ir = try! SLIRGen.generateIr(for: sourceCode)
    let debugger = Debugger(program: ir.program, debugInfo: ir.debugInfo, sampleCount: 1)

    XCTAssertNoThrow(try debugger.stepOver())
    XCTAssertEqual(debugger.sourceLocation, SourceCodeLocation(line: 2, column: 1))
    XCTAssertEqual(debugger.samples.first?.values, [
      "x": .integer(2)
    ])
    XCTAssertEqual(debugger.variableValuesRefinedUsingWP["x"], [
      .integer(2): 1,
    ])
    
    XCTAssertNoThrow(try debugger.stepInto(branch: true))
    XCTAssertEqual(debugger.sourceLocation, SourceCodeLocation(line: 3, column: 3))
    XCTAssertEqual(debugger.samples.count, 1)
    XCTAssertEqual(debugger.samples.first?.values, [
      "x": .integer(2)
    ])
    XCTAssertEqual(debugger.variableValuesRefinedUsingWP["x"], [
      .integer(2): 1,
    ])

    XCTAssertNoThrow(try debugger.stepOver())
    XCTAssertEqual(debugger.sourceLocation, SourceCodeLocation(line: 2, column: 1))
    XCTAssertEqual(debugger.samples.count, 1)
    XCTAssertEqual(debugger.samples.first?.values, [
      "x": .integer(1)
    ])
    XCTAssertEqual(debugger.variableValuesRefinedUsingWP["x"], [
      .integer(1): 1,
    ])

    XCTAssertNoThrow(try debugger.stepInto(branch: false))
    XCTAssertEqual(debugger.sourceLocation, SourceCodeLocation(line: 4, column: 2))
    XCTAssertEqual(debugger.samples.count, 1)
    XCTAssertEqual(debugger.samples.first?.values, [
      "x": .integer(1)
    ])
    XCTAssertEqual(debugger.variableValuesRefinedUsingWP["x"], [
      .integer(1): 1,
    ])
  }
  
  func testStepOverProbabilisticLoop() {
    let sourceCode = """
      int x = discrete({3: 0.25, 4: 0.25, 5: 0.25, 6: 0.25})
      while 1 < x {
        x = x - 1
      }
      """

    let ir = try! SLIRGen.generateIr(for: sourceCode)
    let debugger = Debugger(program: ir.program, debugInfo: ir.debugInfo, sampleCount: 10_000)

    XCTAssertNoThrow(try debugger.stepOver())
    XCTAssertEqual(debugger.sourceLocation, SourceCodeLocation(line: 2, column: 1))
    XCTAssertEqual(debugger.samples.count, 10_000)
    XCTAssertEqual(debugger.samples.map({ $0.values["x"]!.integerValue! }).average, 4.5, accuracy: 0.2)
    XCTAssertEqual(debugger.variableValuesRefinedUsingWP["x"], [
      .integer(3): 0.25,
      .integer(4): 0.25,
      .integer(5): 0.25,
      .integer(6): 0.25,
    ])
    
    XCTAssertNoThrow(try debugger.stepOver())
    XCTAssertEqual(debugger.sourceLocation, SourceCodeLocation(line: 4, column: 2))
    XCTAssertEqual(debugger.samples.count, 10_000)
    XCTAssertEqual(debugger.samples.map({ $0.values["x"]!.integerValue! }).average, 1)
    XCTAssertEqual(debugger.variableValuesRefinedUsingWP["x"], [
      .integer(1): 1,
    ])
  }
  
  func testSaveAndRestoreState() {
    let sourceCode = """
      int x = discrete({1: 0.3, 2: 0.7})
      if x == 1 {
        x = x + 1
      }
      """

    let ir = try! SLIRGen.generateIr(for: sourceCode)
    let debugger = Debugger(program: ir.program, debugInfo: ir.debugInfo, sampleCount: 10_000)

    XCTAssertNoThrow(try debugger.stepOver())
    XCTAssertEqual(debugger.sourceLocation, SourceCodeLocation(line: 2, column: 1))
    XCTAssertEqual(debugger.samples.count, 10_000)
    XCTAssertEqual(debugger.samples.map({ $0.values["x"]!.integerValue! }).average, 1.7, accuracy: 0.1)
    XCTAssertEqual(debugger.variableValuesRefinedUsingWP["x"]![.integer(1)]!, 0.3)
    XCTAssertEqual(debugger.variableValuesRefinedUsingWP["x"]![.integer(2)]!, 0.7)
    
    debugger.saveState()
    
    XCTAssertNoThrow(try debugger.stepInto(branch: true))
    XCTAssertEqual(debugger.sourceLocation, SourceCodeLocation(line: 3, column: 3))
    XCTAssertEqual(Double(debugger.samples.count), 3_000, accuracy: 300)
    XCTAssertEqual(debugger.samples.map({ $0.values["x"]!.integerValue! }).average, 1)
    XCTAssertEqual(debugger.variableValuesRefinedUsingWP["x"], [
      .integer(1): 1,
    ])
    
    XCTAssertNoThrow(try debugger.restoreState())

    XCTAssertEqual(debugger.sourceLocation, SourceCodeLocation(line: 2, column: 1))
    XCTAssertEqual(debugger.samples.count, 10_000)
    XCTAssertEqual(debugger.samples.map({ $0.values["x"]!.integerValue! }).average, 1.7, accuracy: 0.1)
    XCTAssertEqual(debugger.variableValuesRefinedUsingWP["x"], [
      .integer(1): 0.3,
      .integer(2): 0.7,
    ])

    XCTAssertNoThrow(try debugger.stepOver())
    XCTAssertEqual(debugger.sourceLocation, SourceCodeLocation(line: 4, column: 2))
    XCTAssertEqual(debugger.samples.count, 10_000)
    XCTAssertEqual(debugger.samples.map({ $0.values["x"]!.integerValue! }).average, 2)
        XCTAssertEqual(debugger.variableValuesRefinedUsingWP["x"], [
      .integer(2): 1,
    ])
  }
  
  func testConditionValueStoredInBooleanVariable() {
    let sourceCode = """
      int x = discrete({1: 0.3, 2: 0.7})
      bool isOne = (x == 1)
      if isOne {
        x = x + 1
      }
      """

    let ir = try! SLIRGen.generateIr(for: sourceCode)
    let debugger = Debugger(program: ir.program, debugInfo: ir.debugInfo, sampleCount: 10_000)

    XCTAssertNoThrow(try debugger.runUntilEnd())
    XCTAssertEqual(debugger.sourceLocation, SourceCodeLocation(line: 5, column: 2))
    XCTAssertEqual(debugger.samples.count, 10_000)
    XCTAssertEqual(debugger.samples.map({ $0.values["x"]!.integerValue! }).average, 2)
    XCTAssertEqual(debugger.variableValuesRefinedUsingWP["x"], [
      .integer(2): 1,
    ])
  }
  
  func testCowbodyDuelWithOnlyIf() {
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
    
    let ir = try! SLIRGen.generateIr(for: sourceCode)
    let debugger = Debugger(program: ir.program, debugInfo: ir.debugInfo, sampleCount: 10_000)

    XCTAssertNoThrow(try debugger.runUntilEnd())
    XCTAssertEqual(debugger.samples.map({ $0.values["turn"]!.integerValue! }).average, 1.5, accuracy: 0.1)
    
    // Assert using accuracy since there are some numerical instabilities in the calculation of the WP.
    XCTAssertEqual(debugger.variableValuesRefinedUsingWP["turn"]![.integer(1)]!, 0.5, accuracy: 0.001)
    XCTAssertEqual(debugger.variableValuesRefinedUsingWP["turn"]![.integer(2)]!, 0.5, accuracy: 0.001)
    XCTAssertEqual(debugger.variableValuesRefinedUsingWP["turn"]![.integer(3)], nil)
  }
  
  func testCowbodyDuelWithOnlyIfElse() {
    let sourceCode = """
      int turn = discrete({1: 0.5, 2: 0.5})
      bool alive = true
      while alive {
        if discrete({0: 0.5, 1: 0.5}) == 0 {
          if turn == 1 {
            turn = 2
          } else {
            turn = 1
          }
        } else {
          alive = false
        }
      }
      """
    
    let ir = try! SLIRGen.generateIr(for: sourceCode)
    let debugger = Debugger(program: ir.program, debugInfo: ir.debugInfo, sampleCount: 10_000)

    XCTAssertNoThrow(try debugger.runUntilEnd())
    XCTAssertEqual(debugger.samples.map({ $0.values["turn"]!.integerValue! }).average, 1.5, accuracy: 0.1)
    
    // Assert using accuracy since there are some numerical instabilities in the calculation of the WP.
    XCTAssertEqual(debugger.variableValuesRefinedUsingWP["turn"]![.integer(1)]!, 0.5, accuracy: 0.001)
    XCTAssertEqual(debugger.variableValuesRefinedUsingWP["turn"]![.integer(2)]!, 0.5, accuracy: 0.001)
  }
  
  func testStepOverBranchIfPostdominatorHasNoDebugInfo() {
    let sourceCode = """
      int turn = 1
      if true {
        if true {
          turn = 2
        }
      }
      turn = 3
      """
    
    let ir = try! SLIRGen.generateIr(for: sourceCode)
    let debugger = Debugger(program: ir.program, debugInfo: ir.debugInfo, sampleCount: 10_000)

    XCTAssertNoThrow(try debugger.stepOver())
    XCTAssertNoThrow(try debugger.stepInto(branch: true))
    XCTAssertNoThrow(try debugger.stepOver())
    XCTAssertEqual(debugger.sourceLocation, SourceCodeLocation(line: 7, column: 1))
  }
  
  func testWPRefinementIfDifferentIfBranchesWereTakenInDifferentLoopIterations() {
    let sourceCode = """
      int x = discrete({1: 0.25, 2: 0.25, 3: 0.25, 4: 0.25})
      while 1 < x {
        if x == 4 {
          x = 2
        } else {
          x = x - 1
        }
      }
      """
    
    let ir = try! SLIRGen.generateIr(for: sourceCode)
    let debugger = Debugger(program: ir.program, debugInfo: ir.debugInfo, sampleCount: 10_000)

    XCTAssertNoThrow(try debugger.stepOver())
    XCTAssertEqual(debugger.variableValuesRefinedUsingWP["x"]!, [
      .integer(1): 0.25,
      .integer(2): 0.25,
      .integer(3): 0.25,
      .integer(4): 0.25,
    ])
    // Step into the loop
    XCTAssertNoThrow(try debugger.stepInto(branch: true))
    XCTAssertEqual(debugger.variableValuesRefinedUsingWP["x"]!, [
      .integer(2): 1.0 / 3,
      .integer(3): 1.0 / 3,
      .integer(4): 1.0 / 3,
    ])
    // Step into the if branch
    XCTAssertNoThrow(try debugger.stepInto(branch: true))
    XCTAssertEqual(debugger.variableValuesRefinedUsingWP["x"]!, [
      .integer(4): 1,
    ])
    // Step out of the if branch
    XCTAssertNoThrow(try debugger.stepOver())
    XCTAssertEqual(debugger.variableValuesRefinedUsingWP["x"]!, [
      .integer(2): 1,
    ])
    // Step into the loop
    XCTAssertNoThrow(try debugger.stepInto(branch: true))
    XCTAssertEqual(debugger.variableValuesRefinedUsingWP["x"]!, [
      .integer(2): 1,
    ])
    // Step over the if-else block
    XCTAssertNoThrow(try debugger.stepOver())
    XCTAssertEqual(debugger.variableValuesRefinedUsingWP["x"]!, [
      .integer(1): 1,
    ])
  }
  
  func testWPRefinementAfterRunUntilEndIfABranchWasTakenInsideALoop() {
    let sourceCode = """
      int x = discrete({1: 0.25, 2: 0.25, 3: 0.25, 4: 0.25})
      while 1 < x {
        if x == 4 {
          x = 2
        } else {
          x = x - 1
        }
      }
      """
    
    let ir = try! SLIRGen.generateIr(for: sourceCode)
    let debugger = Debugger(program: ir.program, debugInfo: ir.debugInfo, sampleCount: 10_000)

    XCTAssertNoThrow(try debugger.stepOver())
    XCTAssertEqual(debugger.variableValuesRefinedUsingWP["x"]!, [
      .integer(1): 0.25,
      .integer(2): 0.25,
      .integer(3): 0.25,
      .integer(4): 0.25,
    ])
    XCTAssertNoThrow(try debugger.stepInto(branch: true))
    XCTAssertEqual(debugger.variableValuesRefinedUsingWP["x"]!, [
      .integer(2): 1.0 / 3,
      .integer(3): 1.0 / 3,
      .integer(4): 1.0 / 3,
    ])
    XCTAssertNoThrow(try debugger.stepInto(branch: true))
    XCTAssertEqual(debugger.variableValuesRefinedUsingWP["x"]!, [
      .integer(4): 1,
    ])
    XCTAssertNoThrow(try debugger.stepOver())
    XCTAssertEqual(debugger.variableValuesRefinedUsingWP["x"]!, [
      .integer(2): 1,
    ])
    XCTAssertNoThrow(try debugger.runUntilEnd())
    XCTAssertEqual(debugger.variableValuesRefinedUsingWP["x"]!, [
      .integer(1): 1,
    ])
  }
}
