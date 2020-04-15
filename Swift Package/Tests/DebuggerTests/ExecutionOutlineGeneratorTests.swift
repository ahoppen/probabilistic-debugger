import Debugger
import IR
import IRExecution
import SimpleLanguageIRGen
import TestUtils

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
      emptySamples: sampleCount
    )
  }
  
  init(returnPositionIn irProgram: IRProgram, sampleCount: Int) {
    self.init(
      position: irProgram.returnPosition,
      emptySamples: sampleCount
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

    let ir = try! SLIRGen.generateIr(for: sourceCode)
    
    
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
          IRExecutionState(sourceLine: 2, sampleCount: 0, debugInfo: ir.debugInfo),
          IRExecutionState(sourceLine: 2, sampleCount: 0, debugInfo: ir.debugInfo),
          IRExecutionState(sourceLine: 2, sampleCount: 1, debugInfo: ir.debugInfo),
        ]),
        .end(state: IRExecutionState(returnPositionIn: ir.program, sampleCount: 1))
      ])
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
      print(outline.description(sourceCode: sourceCode, debugInfo: ir.debugInfo))

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
          IRExecutionState(sourceLine: 2, sampleCount: 250, debugInfo: ir.debugInfo),
          IRExecutionState(sourceLine: 2, sampleCount: 500, debugInfo: ir.debugInfo),
          IRExecutionState(sourceLine: 2, sampleCount: 750, debugInfo: ir.debugInfo),
          IRExecutionState(sourceLine: 2, sampleCount: 1000, debugInfo: ir.debugInfo),
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
          IRExecutionState(sourceLine: 2, sampleCount: 0, debugInfo: ir.debugInfo),
          IRExecutionState(sourceLine: 2, sampleCount: 0, debugInfo: ir.debugInfo),
          IRExecutionState(sourceLine: 2, sampleCount: 1, debugInfo: ir.debugInfo),
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
          IRExecutionState(sourceLine: 2, sampleCount: 0, debugInfo: ir.debugInfo),
          IRExecutionState(sourceLine: 2, sampleCount: 0, debugInfo: ir.debugInfo),
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
            IRExecutionState(sourceLine: 2, sampleCount: 0, debugInfo: ir.debugInfo),
            IRExecutionState(sourceLine: 2, sampleCount: 5_000, debugInfo: ir.debugInfo),
            IRExecutionState(sourceLine: 2, sampleCount: 7_500, debugInfo: ir.debugInfo),
            IRExecutionState(sourceLine: 2, sampleCount: 8_625, debugInfo: ir.debugInfo),
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
    print(ir.program)
    print(ir.debugInfo)
    
    let outlineGenerator = ExecutionOutlineGenerator(program: ir.program, debugInfo: ir.debugInfo)
    
    XCTAssertNoThrow(try {
      let sampleCount = 1
      let outline = try outlineGenerator.generateOutline(sampleCount: sampleCount)
      
      print(outline)
      
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
}
