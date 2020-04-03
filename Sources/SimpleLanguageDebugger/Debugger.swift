import IR
import IRExecution
import SimpleLanguageAST
import SimpleLanguageIRGen

fileprivate extension Sequence where Element: Equatable {
  var allEqual: Bool {
    guard let first = self.first(where: { _ in true }) else {
      return true
    }
    for element in self.dropFirst() {
      if element != first {
        return false
      }
    }
    return true
  }
}

public struct SLSample {
  public let values: [Variable: Value]
}

public class SLDebugger {
  private let executor: IRExecutor
  private let program: IRProgram
  
  public init(program: IRProgram, sampleCount: Int) {
    self.program = program
    self.executor = IRExecutor(program: program, sampleCount: sampleCount)
  }
  
  /// Run the program until the end
  public func run() -> [SLSample] {
    let states = executor.execute()
    assert(states.map(\.position).allEqual)
    guard let position = states.first?.position else {
      // There was no viable run in the IR
      return []
    }
    guard let debugInfo = program.debugInfo as? SLDebugInfo else {
      fatalError("Program does not have debug info for 'Simple Language'")
    }
    guard let instructionInfo = debugInfo.info[position] else {
      fatalError("No debug info for the return statement")
    }
    let slSamples = states.flatMap(\.samples).map({ (irSample) -> SLSample in
      let variableValues = instructionInfo.variables.mapValues({ (irVariable) in
        irSample.values[irVariable]!
      })
      return SLSample(values: variableValues)
    })
    return slSamples
  }
}
