import Debugger
import IR
import IRExecution
import SimpleLanguageIRGen
import TestUtils
import WPInference

import XCTest

fileprivate func equalWithAccuracy(_ lhs: Int, _ rhs: Int, accuracy: Double) -> Bool {
  assert(accuracy >= 0 && accuracy <= 1)
  return (Double(lhs) * (1 - accuracy) <= Double(rhs)) && (Double(lhs) * (1 + accuracy) >= Double(rhs))
}

fileprivate func statesEqual(_ lhs: IRExecutionState, _ rhs: IRExecutionState, accuracy: Double) -> Bool {
  return lhs.position == rhs.position &&
    equalWithAccuracy(lhs.samples.count, rhs.samples.count, accuracy: accuracy)
}

fileprivate func outlinesEqual(_ lhs: ExecutionOutline?, _ rhs: ExecutionOutline?, accuracy: Double, maxLoopIterations: Int) -> Bool {
  if lhs == nil && rhs == nil {
    return true
  }
  guard let lhs = lhs, let rhs = rhs else {
    return false
  }
  if lhs.entries.count != rhs.entries.count {
    return false
  }
  return zip(lhs.entries, rhs.entries).allSatisfy({ (lhsEntry, rhsEntry) in
    switch (lhsEntry, rhsEntry) {
    case (.instruction(let lhsState),
          .instruction(let rhsState)):
      return statesEqual(lhsState, rhsState, accuracy: accuracy)
    case (.branch(state: let lhsState, true: let lhsTrue, false: let lhsFalse),
          .branch(state: let rhsState, true: let rhsTrue, false: let rhsFalse)):
      return statesEqual(lhsState, rhsState, accuracy: accuracy) &&
        outlinesEqual(lhsTrue, rhsTrue, accuracy: accuracy, maxLoopIterations: maxLoopIterations) &&
        outlinesEqual(lhsFalse, rhsFalse, accuracy: accuracy, maxLoopIterations: maxLoopIterations)
    case (.loop(let lhsState, let lhsIterations, let lhsExitStates),
          .loop(let rhsState, let rhsIterations, let rhsExitStates)):
      let lhsIterationsToInspect = lhsIterations.prefix(maxLoopIterations)
      let rhsIterationsToInspect = rhsIterations.prefix(maxLoopIterations)
      let lhsExitStatesToInspect = lhsExitStates.prefix(maxLoopIterations)
      let rhsExitStatesToInspect = rhsExitStates.prefix(maxLoopIterations)
      return statesEqual(lhsState, rhsState, accuracy: accuracy) &&
        lhsIterationsToInspect.count == rhsIterationsToInspect.count &&
        zip(lhsIterationsToInspect, rhsIterationsToInspect).allSatisfy({
          return outlinesEqual($0, $1, accuracy: accuracy, maxLoopIterations: maxLoopIterations)
        }) &&
        lhsExitStatesToInspect.count == rhsExitStatesToInspect.count &&
        zip(lhsExitStatesToInspect, rhsExitStatesToInspect).allSatisfy({
          return statesEqual($0, $1, accuracy: accuracy)
        })
    case (.end(let lhsState), .end(let rhsState)):
      return statesEqual(lhsState, rhsState, accuracy: accuracy)
    default:
      return false
    }
  })
}

fileprivate extension DebugInfo {
  func instructionPosition(forLine line: Int) -> InstructionPosition {
    let matchingPositions = info.compactMap({ (position, debugInfo) -> InstructionPosition? in
      if debugInfo.sourceCodeLocation.line == line && debugInfo.instructionType != .return {
        return position
      } else {
        return nil
      }
    })
    if matchingPositions.count > 1 {
      fatalError("Found multiple instruction positions for line \(line)")
    }
    guard let position = matchingPositions.first else {
      fatalError("Could not find instruction position for line \(line)")
    }
    return position
  }
}

fileprivate func XCTAssertEqualOutline(_ lhs: ExecutionOutline, _ rhs: ExecutionOutline, accuracy: Double = 0, maxLoopIterations: Int = Int.max) {
  XCTAssert(outlinesEqual(lhs, rhs, accuracy: accuracy, maxLoopIterations: maxLoopIterations), """
    
    \(lhs.description)
    
    is not equal to
    
    \(rhs.description)
    """)
}

fileprivate extension IRExecutionState {
  init(sourceLine: Int, sampleCount: Int, debugInfo: DebugInfo) {
    self.init(
      position: debugInfo.instructionPosition(forLine: sourceLine),
      emptySamples: sampleCount,
      loops: []
    )
  }
  
  init(returnPositionIn irProgram: IRProgram, sampleCount: Int) {
    self.init(
      position: irProgram.returnPosition,
      emptySamples: sampleCount,
      loops: []
    )
  }
}

class ExecutionOutlineGeneratorTests: XCTestCase {
  func testSingleAssignment() {
    let sourceCode = """
      int x = 42
       
      """
    
    let ir = try! SLIRGen.generateIr(for: sourceCode)
    
    let outlineGenerator = ExecutionOutlineGenerator(program: ir.program, debugInfo: ir.debugInfo)
    XCTAssertNoThrow(try {
      let outline = try outlineGenerator.generateOutline(sampleCount: 1)
      
      XCTAssertEqualOutline(outline, [
        .instruction(state: IRExecutionState(sourceLine: 1, sampleCount: 1, debugInfo: ir.debugInfo)),
        .end(state: IRExecutionState(returnPositionIn: ir.program, sampleCount: 1))
      ])
    }())
  }
  
  func testDeterministicComputationAndGetVariableValues() {
    let sourceCode = """
      int x = 42
      x = x - 1
      int y = x + 11
      """

    let ir = try! SLIRGen.generateIr(for: sourceCode)
    
    let outlineGenerator = ExecutionOutlineGenerator(program: ir.program, debugInfo: ir.debugInfo)
    XCTAssertNoThrow(try {
      let outline = try outlineGenerator.generateOutline(sampleCount: 1)
      
      XCTAssertEqualOutline(outline, [
        .instruction(state: IRExecutionState(sourceLine: 1, sampleCount: 1, debugInfo: ir.debugInfo)),
        .instruction(state: IRExecutionState(sourceLine: 2, sampleCount: 1, debugInfo: ir.debugInfo)),
        .instruction(state: IRExecutionState(sourceLine: 3, sampleCount: 1, debugInfo: ir.debugInfo)),
        .end(state: IRExecutionState(returnPositionIn: ir.program, sampleCount: 1)),
      ])
    }())
  }

  func testProbabilisticProgramWithBranch() {
    let sourceCode = """
      int x = discrete({1: 0.5, 2: 0.5})
      if x == 2 {
        int y = 20
      }
      """

    let ir = try! SLIRGen.generateIr(for: sourceCode)

    let outlineGenerator = ExecutionOutlineGenerator(program: ir.program, debugInfo: ir.debugInfo)
    XCTAssertNoThrow(try {
      let outline = try outlineGenerator.generateOutline(sampleCount: 1000)

      XCTAssertEqualOutline(outline, [
        .instruction(state: IRExecutionState(sourceLine: 1, sampleCount: 1000, debugInfo: ir.debugInfo)),
        .branch(state: IRExecutionState(sourceLine: 2, sampleCount: 1000, debugInfo: ir.debugInfo),
                true: [
                  .instruction(state: IRExecutionState(sourceLine: 3, sampleCount: 500, debugInfo: ir.debugInfo))
                ],
                false: nil),
        .end(state: IRExecutionState(returnPositionIn: ir.program, sampleCount: 1000))
      ], accuracy: 0.1)
    }())
  }

  func testRunProgramWithoutViableRun() {
    let sourceCode = """
      int x = 1
      observe(x == 2)
      int y = 2
      """


    let ir = try! SLIRGen.generateIr(for: sourceCode)

    let outlineGenerator = ExecutionOutlineGenerator(program: ir.program, debugInfo: ir.debugInfo)
    XCTAssertNoThrow(try {
      let outline = try outlineGenerator.generateOutline(sampleCount: 1)

      XCTAssertEqualOutline(outline, [
        .instruction(state: IRExecutionState(sourceLine: 1, sampleCount: 1, debugInfo: ir.debugInfo)),
        .instruction(state: IRExecutionState(sourceLine: 2, sampleCount: 1, debugInfo: ir.debugInfo))
      ])
    }())
  }

  func testDeterministicLoop() {
    let sourceCode = """
      int x = 3
      while 1 < x {
        x = x - 1
      }
      """

    // We assert things based on the IR basic block, so check that the IR looks like we expect it to
    let var1 = IRVariable(name: "1", type: .int)
    let var2 = IRVariable(name: "2", type: .bool)
    let var3 = IRVariable(name: "3", type: .int)
    let var4 = IRVariable(name: "4", type: .int)
    let var5 = IRVariable(name: "5", type: .int)
    
    let bb1Name = BasicBlockName("bb1")
    let bb2Name = BasicBlockName("bb2")
    let bb3Name = BasicBlockName("bb3")
    let bb4Name = BasicBlockName("bb4")
    
    let bb1 = BasicBlock(name: bb1Name, instructions: [
      AssignInstruction(assignee: var1, value: .integer(3)),
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
      ReturnInstruction()
    ])
    
    let expectedIR = IRProgram(startBlock: bb1Name, basicBlocks: [bb1, bb2, bb3, bb4])
    
    let ir = try! SLIRGen.generateIr(for: sourceCode)
    // If the IR is not like we expect it, this is a bug in our test and the test needs to be updated
    assert(ir.program == expectedIR)
    
    let outlineGenerator = ExecutionOutlineGenerator(program: ir.program, debugInfo: ir.debugInfo)
    XCTAssertNoThrow(try {
      let outline = try outlineGenerator.generateOutline(sampleCount: 1)

      XCTAssertEqualOutline(outline, [
        .instruction(state: IRExecutionState(sourceLine: 1, sampleCount: 1, debugInfo: ir.debugInfo)),
        .loop(state: IRExecutionState(sourceLine: 2, sampleCount: 1, debugInfo: ir.debugInfo), iterations: [
          [
            .instruction(state: IRExecutionState(sourceLine: 3, sampleCount: 1, debugInfo: ir.debugInfo)),
            .end(state: IRExecutionState(sourceLine: 2, sampleCount: 1, debugInfo: ir.debugInfo))
          ],
          [
            .instruction(state: IRExecutionState(sourceLine: 3, sampleCount: 1, debugInfo: ir.debugInfo)),
            .end(state: IRExecutionState(sourceLine: 2, sampleCount: 1, debugInfo: ir.debugInfo))
          ],
        ], exitStates: [
          IRExecutionState(returnPositionIn: ir.program, sampleCount: 0),
          IRExecutionState(returnPositionIn: ir.program, sampleCount: 0),
          IRExecutionState(returnPositionIn: ir.program, sampleCount: 1),
        ]),
        .end(state: IRExecutionState(returnPositionIn: ir.program, sampleCount: 1))
      ])
      guard case .loop(let state, let iterations, let exitStates) = outline.entries[1] else {
        XCTFail()
        return
      }
      XCTAssertEqual(state.branchingHistories, [[]])
      XCTAssertEqual(iterations[0].entries[0].state.branchingHistories, [[.choice(source: bb2Name, target: bb3Name)]])
      XCTAssertEqual(iterations[1].entries[0].state.branchingHistories, [[
        .choice(source: bb2Name, target: bb3Name),
        .choice(source: bb2Name, target: bb3Name)
      ]])
      XCTAssertEqual(exitStates[0].branchingHistories, [[.any(predominatedBy: bb2Name)]])
      XCTAssertEqual(exitStates[1].branchingHistories, [[.any(predominatedBy: bb2Name)]])
      XCTAssertEqual(outline.entries[2].state.branchingHistories, [[.any(predominatedBy: bb2Name)]])
    }())
  }

  func testProbabilisticLoop() {
    let sourceCode = """
      int x = discrete({1: 0.25, 2: 0.25, 3: 0.25, 4: 0.25})
      while 1 < x {
        x = x - 1
      }
      """

    let ir = try! SLIRGen.generateIr(for: sourceCode)

    let outlineGenerator = ExecutionOutlineGenerator(program: ir.program, debugInfo: ir.debugInfo)
    XCTAssertNoThrow(try {
      let outline = try outlineGenerator.generateOutline(sampleCount: 1000)
      
      XCTAssertEqualOutline(outline, [
        .instruction(state: IRExecutionState(sourceLine: 1, sampleCount: 1000, debugInfo: ir.debugInfo)),
        .loop(state: IRExecutionState(sourceLine: 2, sampleCount: 1000, debugInfo: ir.debugInfo), iterations: [
          [
            .instruction(state: IRExecutionState(sourceLine: 3, sampleCount: 750, debugInfo: ir.debugInfo)),
            .end(state: IRExecutionState(sourceLine: 2, sampleCount: 750, debugInfo: ir.debugInfo)),
          ],
          [
            .instruction(state: IRExecutionState(sourceLine: 3, sampleCount: 500, debugInfo: ir.debugInfo)),
            .end(state: IRExecutionState(sourceLine: 2, sampleCount: 500, debugInfo: ir.debugInfo)),
          ],
          [
            .instruction(state: IRExecutionState(sourceLine: 3, sampleCount: 250, debugInfo: ir.debugInfo)),
            .end(state: IRExecutionState(sourceLine: 2, sampleCount: 250, debugInfo: ir.debugInfo)),
          ],
        ], exitStates: [
          IRExecutionState(returnPositionIn: ir.program, sampleCount: 250),
          IRExecutionState(returnPositionIn: ir.program, sampleCount: 500),
          IRExecutionState(returnPositionIn: ir.program, sampleCount: 750),
          IRExecutionState(returnPositionIn: ir.program, sampleCount: 1000),
        ]),
        .end(state: IRExecutionState(returnPositionIn: ir.program, sampleCount: 1000))
      ], accuracy: 0.2)
    }())
  }
  
  func testObserve() {
    let sourceCode = """
      int x = discrete({1: 0.75, 2: 0.25})
      observe x == 2
      x = x + 1
      """

    let ir = try! SLIRGen.generateIr(for: sourceCode)

    let outlineGenerator = ExecutionOutlineGenerator(program: ir.program, debugInfo: ir.debugInfo)
    XCTAssertNoThrow(try {
      let outline = try outlineGenerator.generateOutline(sampleCount: 1000)

      XCTAssertEqualOutline(outline, [
        .instruction(state: IRExecutionState(sourceLine: 1, sampleCount: 1000, debugInfo: ir.debugInfo)),
        .instruction(state: IRExecutionState(sourceLine: 2, sampleCount: 1000, debugInfo: ir.debugInfo)),
        .instruction(state: IRExecutionState(sourceLine: 3, sampleCount: 250, debugInfo: ir.debugInfo)),
        .end(state: IRExecutionState(returnPositionIn: ir.program, sampleCount: 250))
      ], accuracy: 0.2)
    }())
  }
  
  func testIfElseStmt() {
    let sourceCode = """
      int x = discrete({1: 0.75, 2: 0.25})
      if x == 1 {
        x = 2
      } else {
        x = 1
      }
      """

    let ir = try! SLIRGen.generateIr(for: sourceCode)

    let outlineGenerator = ExecutionOutlineGenerator(program: ir.program, debugInfo: ir.debugInfo)
    XCTAssertNoThrow(try {
      let outline = try outlineGenerator.generateOutline(sampleCount: 1000)

      XCTAssertEqualOutline(outline, [
        .instruction(state: IRExecutionState(sourceLine: 1, sampleCount: 1000, debugInfo: ir.debugInfo)),
        .branch(state: IRExecutionState(sourceLine: 2, sampleCount: 1000, debugInfo: ir.debugInfo),
                true: [.instruction(state: IRExecutionState(sourceLine: 3, sampleCount: 750, debugInfo: ir.debugInfo))],
                false: [.instruction(state: IRExecutionState(sourceLine: 5, sampleCount: 250, debugInfo: ir.debugInfo))]),
        .end(state: IRExecutionState(returnPositionIn: ir.program, sampleCount: 1000))
      ], accuracy: 0.2)
    }())
  }
  
  func testIfNestedInWhile() {
    let sourceCode = """
      int x = 5
      while 1 < x {
        if x == 5 {
          x = 2
        } else {
          x = x - 1
        }
      }
      """

    let ir = try! SLIRGen.generateIr(for: sourceCode)

    let outlineGenerator = ExecutionOutlineGenerator(program: ir.program, debugInfo: ir.debugInfo)
    XCTAssertNoThrow(try {
      let outline = try outlineGenerator.generateOutline(sampleCount: 1)

      XCTAssertEqualOutline(outline, [
        .instruction(state: IRExecutionState(sourceLine: 1, sampleCount: 1, debugInfo: ir.debugInfo)),
        .loop(state: IRExecutionState(sourceLine: 2, sampleCount: 1, debugInfo: ir.debugInfo), iterations: [
          [
            .branch(state: IRExecutionState(sourceLine: 3, sampleCount: 1, debugInfo: ir.debugInfo),
                   true: [.instruction(state: IRExecutionState(sourceLine: 4, sampleCount: 1, debugInfo: ir.debugInfo))],
                   false: nil),
            .end(state: IRExecutionState(sourceLine: 2, sampleCount: 1, debugInfo: ir.debugInfo)),
          ],
          [
            .branch(state: IRExecutionState(sourceLine: 3, sampleCount: 1, debugInfo: ir.debugInfo),
                   true: nil,
                   false: [.instruction(state: IRExecutionState(sourceLine: 6, sampleCount: 1, debugInfo: ir.debugInfo))]),
            .end(state: IRExecutionState(sourceLine: 2, sampleCount: 1, debugInfo: ir.debugInfo)),
          ]
        ], exitStates: [
          IRExecutionState(returnPositionIn: ir.program, sampleCount: 0),
          IRExecutionState(returnPositionIn: ir.program, sampleCount: 0),
          IRExecutionState(returnPositionIn: ir.program, sampleCount: 1),
        ]),
        .end(state: IRExecutionState(returnPositionIn: ir.program, sampleCount: 1))
      ], accuracy: 0.1)
    }())
  }
  
  func testFilterOutAllSamplesInsideWhile() {
    let sourceCode = """
    int x = 5
    while 1 < x {
      observe x == 5
      x = x - 1
    }
    """
    
    let ir = try! SLIRGen.generateIr(for: sourceCode)
    
    let outlineGenerator = ExecutionOutlineGenerator(program: ir.program, debugInfo: ir.debugInfo)
    XCTAssertNoThrow(try {
      let outline = try outlineGenerator.generateOutline(sampleCount: 1)
      
      XCTAssertEqualOutline(outline, [
        .instruction(state: IRExecutionState(sourceLine: 1, sampleCount: 1, debugInfo: ir.debugInfo)),
        .loop(state: IRExecutionState(sourceLine: 2, sampleCount: 1, debugInfo: ir.debugInfo), iterations: [
          [
            .instruction(state: IRExecutionState(sourceLine: 3, sampleCount: 1, debugInfo: ir.debugInfo)),
            .instruction(state: IRExecutionState(sourceLine: 4, sampleCount: 1, debugInfo: ir.debugInfo)),
            .end(state: IRExecutionState(sourceLine: 2, sampleCount: 1, debugInfo: ir.debugInfo))
          ],
          [
            .instruction(state: IRExecutionState(sourceLine: 3, sampleCount: 1, debugInfo: ir.debugInfo)),
          ]
        ], exitStates: [
          IRExecutionState(returnPositionIn: ir.program, sampleCount: 0),
          IRExecutionState(returnPositionIn: ir.program, sampleCount: 0),
        ]),
      ], accuracy: 0.1)
      }())
  }
  
  func testGenerateGeometricDistributionDuel() {
    let sourceCode = """
      bool run = true
      while run {
        if discrete({0: 0.5, 1: 0.5}) == 0 {
          run = false
        }
      }
      """
    
    let ir = try! SLIRGen.generateIr(for: sourceCode)
    
    let outlineGenerator = ExecutionOutlineGenerator(program: ir.program, debugInfo: ir.debugInfo)
    
    XCTAssertNoThrow(try {
      let outline = try outlineGenerator.generateOutline(sampleCount: 10_000)
      
      XCTAssertEqualOutline(outline, [
        .instruction(state: IRExecutionState(sourceLine: 1, sampleCount: 10_000, debugInfo: ir.debugInfo)),
        .loop(state: IRExecutionState(sourceLine: 2, sampleCount: 10_000, debugInfo: ir.debugInfo), iterations: [
          [
            .branch(state: IRExecutionState(sourceLine: 3, sampleCount: 10_000, debugInfo: ir.debugInfo),
                    true: [.instruction(state: IRExecutionState(sourceLine: 4, sampleCount: 5_000, debugInfo: ir.debugInfo))],
                    false: nil),
            .end(state: IRExecutionState(sourceLine: 2, sampleCount: 10_000, debugInfo: ir.debugInfo))
          ],
          [
            .branch(state: IRExecutionState(sourceLine: 3, sampleCount: 5_000, debugInfo: ir.debugInfo),
                    true: [.instruction(state: IRExecutionState(sourceLine: 4, sampleCount: 2_500, debugInfo: ir.debugInfo))],
                    false: nil),
            .end(state: IRExecutionState(sourceLine: 2, sampleCount: 5_000, debugInfo: ir.debugInfo))
          ],
          [
            .branch(state: IRExecutionState(sourceLine: 3, sampleCount: 2_500, debugInfo: ir.debugInfo),
                    true: [.instruction(state: IRExecutionState(sourceLine: 4, sampleCount: 1_250, debugInfo: ir.debugInfo))],
                    false: nil),
            .end(state: IRExecutionState(sourceLine: 2, sampleCount: 2_500, debugInfo: ir.debugInfo))
          ]
          ], exitStates: [
            IRExecutionState(returnPositionIn: ir.program, sampleCount: 0),
            IRExecutionState(returnPositionIn: ir.program, sampleCount: 5_000),
            IRExecutionState(returnPositionIn: ir.program, sampleCount: 7_500),
            IRExecutionState(returnPositionIn: ir.program, sampleCount: 8_625),
        ]),
        .end(state: IRExecutionState(returnPositionIn: ir.program, sampleCount: 10_000)),
      ], accuracy: 0.1, maxLoopIterations: 3)
      }())
  }
  
  func testJumpDebuggerToExecutionStateState() {
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
    
    let outlineGenerator = ExecutionOutlineGenerator(program: ir.program, debugInfo: ir.debugInfo)
    
    XCTAssertNoThrow(try {
      let sampleCount = 1
      let outline = try outlineGenerator.generateOutline(sampleCount: sampleCount)
      
      guard case .loop(_, let iterations, _) = outline.entries[2] else {
        XCTFail()
        return
      }
      
      let state = iterations[1].entries.first!.state
      
      let debugger = Debugger(program: ir.program, debugInfo: ir.debugInfo, sampleCount: sampleCount)
      debugger.jumpToState(state)
      XCTAssertEqual(debugger.samples.map({ $0.values["turn"]!.integerValue! }).average, 1)
      }())
  }
  
  func testBranchingHistoryOfLoopExitStates() {
    let sourceCode = """
        int x = 0
        while discrete({0: 0.5, 1: 0.5}) == 0 {
          x = x + 1
        }
        """
    
    let ir = try! SLIRGen.generateIr(for: sourceCode)
    
    let outlineGenerator = ExecutionOutlineGenerator(program: ir.program, debugInfo: ir.debugInfo)
    
    XCTAssertNoThrow(try {
      let sampleCount = 100
      let outline = try outlineGenerator.generateOutline(sampleCount: sampleCount)
      guard case .loop(_, _, let exitStates) = outline.entries[1] else {
        XCTFail()
        return
      }
      
      let bb2Name = BasicBlockName("bb2")
      
      XCTAssertEqual(exitStates[0].branchingHistories, [[.any(predominatedBy: bb2Name)]])
      XCTAssertEqual(exitStates[1].branchingHistories, [[.any(predominatedBy: bb2Name)]])
      XCTAssertEqual(exitStates[3].branchingHistories, [[.any(predominatedBy: bb2Name)]])
      
      guard case .end(let endState) = outline.entries[2] else {
        XCTFail()
        return
      }
      XCTAssertEqual(endState.branchingHistories, [[.any(predominatedBy: bb2Name)]])
    }())
  }
  
  func testApproximationErrorIsGreaterThanZeroIfLoopIsCutOffWithFewSamples() {
    let sourceCode = """
        int x = 0
        while discrete({0: 0.5, 1: 0.5}) == 0 {
          x = x + 1
        }
        """
    
    let ir = try! SLIRGen.generateIr(for: sourceCode)
    
    let outlineGenerator = ExecutionOutlineGenerator(program: ir.program, debugInfo: ir.debugInfo)
    
    XCTAssertNoThrow(try {
      let sampleCount = 10
      let outline = try outlineGenerator.generateOutline(sampleCount: sampleCount)
      let returnState = outline.entries.last!.state
      
      let debugger = Debugger(program: ir.program, debugInfo: ir.debugInfo, sampleCount: sampleCount)
      debugger.jumpToState(returnState)
      XCTAssertGreaterThan(debugger.approximationError, 0)
    }())
  }
  
  func testApproximationErrorIsZeroInsideLoopIterationAndApproachesZeroInExitStates() {
    let sourceCode = """
        int x = 0
        while discrete({0: 0.5, 1: 0.5}) == 0 {
          x = x + 1
        }
        """
    
    let ir = try! SLIRGen.generateIr(for: sourceCode)
    
    let outlineGenerator = ExecutionOutlineGenerator(program: ir.program, debugInfo: ir.debugInfo)
    
    XCTAssertNoThrow(try {
      let sampleCount = 40
      let outline = try outlineGenerator.generateOutline(sampleCount: sampleCount)
      guard case .loop(_, let iterations, let exitStates) = outline.entries[1] else {
        XCTFail()
        return
      }
      
      let debugger = Debugger(program: ir.program, debugInfo: ir.debugInfo, sampleCount: sampleCount)
      
      debugger.jumpToState(iterations[0].entries.first!.state)
      XCTAssertEqual(debugger.approximationError, 0)
      
      debugger.jumpToState(iterations[1].entries.first!.state)
      XCTAssertEqual(debugger.approximationError, 0)
      
      debugger.jumpToState(iterations[2].entries.first!.state)
      XCTAssertEqual(debugger.approximationError, 0)
      
      debugger.jumpToState(exitStates[0])
      XCTAssertEqual(debugger.approximationError, 0.5)
      
      debugger.jumpToState(exitStates[1])
      XCTAssertEqual(debugger.approximationError, 0.25)
      
      debugger.jumpToState(exitStates[2])
      XCTAssertEqual(debugger.approximationError, 0.125)
    }())
  }
  
  func testApproximationErrorIsZeroInsideLoopIterationWithCondition() {
    let sourceCode = """
        int x = 0
        while discrete({0: 0.5, 1: 0.5}) == 0 {
          if true {
            x = x + 1
          } else {
            x = x + 1
          }
        }
        """
    
    let ir = try! SLIRGen.generateIr(for: sourceCode)
    
    let outlineGenerator = ExecutionOutlineGenerator(program: ir.program, debugInfo: ir.debugInfo)
    
    XCTAssertNoThrow(try {
      let sampleCount = 20
      let outline = try outlineGenerator.generateOutline(sampleCount: sampleCount)
      guard case .loop(_, let iterations, let exitStates) = outline.entries[1] else {
        XCTFail()
        return
      }
      
      let debugger = Debugger(program: ir.program, debugInfo: ir.debugInfo, sampleCount: sampleCount)
      
      let firstLoopIterationEntryState = iterations[0].entries.first!.state
      debugger.jumpToState(firstLoopIterationEntryState)
      XCTAssertEqual(debugger.approximationError, 0)
      
      let secondLoopIterationEntryState = iterations[1].entries.first!.state
      debugger.jumpToState(secondLoopIterationEntryState)
      XCTAssertEqual(debugger.approximationError, 0)
      
      debugger.jumpToState(exitStates[0])
      XCTAssertEqual(debugger.approximationError, 0.5)
      
      debugger.jumpToState(exitStates[1])
      XCTAssertEqual(debugger.approximationError, 0.25)
    }())
  }
  
  func testCowboyDuel() {
    let sourceCode = """
        int initialCowboy = discrete({1: 0.5, 2: 0.5})
        int turn = initialCowboy
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
        observe(turn == 2)
        """
    
    let ir = try! SLIRGen.generateIr(for: sourceCode)
    
    let outlineGenerator = ExecutionOutlineGenerator(program: ir.program, debugInfo: ir.debugInfo)
    
    XCTAssertNoThrow(try {
      let sampleCount = 10_000
      let outline = try outlineGenerator.generateOutline(sampleCount: sampleCount)
      guard case .loop(_, let iterations, _) = outline.entries[3] else {
        XCTFail()
        return
      }
      let iterationEntryState = iterations[2].entries.first!.state
      let inferenceEngine = WPInferenceEngine(program: ir.program)
      XCTAssertEqual(inferenceEngine.reachingProbability(of: iterationEntryState), 0.25)
      
      guard case .branch(_, let trueBranch, _) = iterations[1].entries.first! else {
        XCTFail()
        return
      }
      XCTAssertEqual(inferenceEngine.reachingProbability(of: trueBranch!.entries.first!.state), 0.25)
    }())
  }
}
