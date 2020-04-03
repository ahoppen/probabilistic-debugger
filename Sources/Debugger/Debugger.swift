import IR
import IRExecution

/// Wrapper around `IRExecutor` that keeps track of the current execution state and translates the `IRExecutionState`s into values for variables in the source code.
public class Debugger {
  // MARK: - Private members
  
  /// The executor that actually executes the IR
  private let executor: IRExecutor
  
  /// Debug information to translate IR variable values back to source variable values
  private let debugInfo: DebugInfo
  
  /// The current state of the debugger. Can be `nil` if execution of the program has filtered out all samples
  private var currentState: IRExecutionState?
  
  private func currentStateOrThrow() throws -> IRExecutionState {
    guard let currentState = currentState else {
      throw ExecutionError(message: "Execution has filtered out all samples. Either the branch that was chosen is not feasible or the path is unlikely and there were an insufficient number of samples in the beginning to assign some to this branch.")
    }
    return currentState
  }
  
  // MARK: - Operating the debugger
  
  public init(program: IRProgram, sampleCount: Int) {
    self.executor = IRExecutor(program: program)
    self.debugInfo = program.debugInfo!
    self.currentState = IRExecutionState(initialStateIn: program, sampleCount: sampleCount)
  }
  
  public var samples: [SourceCodeSample] {
    guard let currentState = currentState else {
      return []
    }
    
    guard let instructionInfo = debugInfo.info[currentState.position] else {
      fatalError("Could not find debug info for the current statement")
    }
    let sourceCodeSamples = currentState.samples.map({ (irSample) -> SourceCodeSample in
      let variableValues = instructionInfo.variables.mapValues({ (irVariable) in
        irSample.values[irVariable]!
      })
      return SourceCodeSample(values: variableValues)
    })
    return sourceCodeSamples
  }
  
  /// Run the program until the end
  public func run() throws {
    self.currentState = executor.runUntilEnd(state: try currentStateOrThrow())
  }
  
  public func step() throws {
    self.currentState = try executor.runUntilNextInstructionWithDebugInfo(state: try currentStateOrThrow())
  }
}
