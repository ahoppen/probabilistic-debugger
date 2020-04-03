import IR
import IRExecution
import Utils

fileprivate extension Array {
  var only: Element {
    assert(self.count == 1)
    return self.first!
  }
}

public class Debugger {
  private let executor: IRExecutor
  private let program: IRProgram
  private var debugInfo: DebugInfo {
    return program.debugInfo!
  }
  
  public var samples: [SourceCodeSample] {
    return sourceCodeSamples(for: executor.finishedExecutionBranches + executor.currentExecutionBranches)
  }
  
  public init(program: IRProgram, sampleCount: Int) {
    self.executor = IRExecutor(program: program, sampleCount: sampleCount)
    self.program = program
  }
  
  private func sourceCodeSamples(for executionBranches: [ExecutionBranch]) -> [SourceCodeSample] {
    assert(executionBranches.map(\.position).allEqual, "Execution branches refer to different program positions")
    
    guard let position = executionBranches.first?.position else {
      // There was no viable run in the IR
      return []
    }
    
    guard let instructionInfo = debugInfo.info[position] else {
      fatalError("No debug info for the return statement")
    }
    let sourceCodeSamples = executionBranches.flatMap(\.samples).map({ (irSample) -> SourceCodeSample in
      let variableValues = instructionInfo.variables.mapValues({ (irVariable) in
        irSample.values[irVariable]!
      })
      return SourceCodeSample(values: variableValues)
    })
    return sourceCodeSamples
  }
  
  private var currentPosition: InstructionPosition? {
    assert(executor.currentExecutionBranches.count <= 1, "We must be focused on one execution branch during debugging")
    return executor.currentExecutionBranches.first?.position
  }
  
  private var currentInstruction: Instruction? {
    guard let currentPosition = currentPosition else {
      return nil
    }
    return program.instruction(at: currentPosition)!
  }
  
  private func checkExecutionBranchExists() throws {
    assert(executor.currentExecutionBranches.count <= 1, "We must be focused on one execution branch during debugging")
    if executor.currentExecutionBranches.count == 0 {
      throw DebuggerError(message: "No execution branch left to execute")
    }
  }
  
  /// Run the program until the end
  @discardableResult
  public func run() -> [SourceCodeSample] {
    let states = executor.execute()
    
    return sourceCodeSamples(for: states)
  }
  
  /// Run the program until the next instruction that has an associated source code location in the debug info.
  @discardableResult
  public func step() throws -> [SourceCodeSample] {
    try checkExecutionBranchExists()
    
    if currentInstruction is BranchInstruction {
      throw DebuggerError(message: "Cannot execute a branch instruction using the 'step' command")
    }
    
    while true {
      executor.executeNextInstructionInBranchOnTopOfExecutionStack()
      try checkExecutionBranchExists()
      
      let position = executor.currentExecutionBranches.only.position
      if debugInfo.info[position] != nil {
        break
      }
    }
    
    return sourceCodeSamples(for: [executor.currentExecutionBranches.only])
  }
}
