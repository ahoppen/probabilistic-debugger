import IR
import IRExecution
import Utils

public struct SourceCodeSample {
  public let values: [String: IRValue]
}

public class Debugger {
  private let executor: IRExecutor
  private let program: IRProgram
  
  public init(program: IRProgram, sampleCount: Int) {
    self.program = program
    self.executor = IRExecutor(program: program, sampleCount: sampleCount)
  }
  
  /// Run the program until the end
  public func run() -> [SourceCodeSample] {
    let states = executor.execute()
    assert(states.map(\.position).allEqual)
    guard let position = states.first?.position else {
      // There was no viable run in the IR
      return []
    }
    guard let debugInfo = program.debugInfo else {
      fatalError("Program does not have debug info")
    }
    guard let instructionInfo = debugInfo.info[position] else {
      fatalError("No debug info for the return statement")
    }
    let slSamples = states.flatMap(\.samples).map({ (irSample) -> SourceCodeSample in
      let variableValues = instructionInfo.variables.mapValues({ (irVariable) in
        irSample.values[irVariable]!
      })
      return SourceCodeSample(values: variableValues)
    })
    return slSamples
  }
}
