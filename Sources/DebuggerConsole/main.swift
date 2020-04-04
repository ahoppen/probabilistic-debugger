import ArgumentParser
import Debugger
import Foundation
import SimpleLanguageIRGen
import SimpleLanguageParser

extension Array where Element: Hashable {
    func histogram() -> [Element: Int] {
        return self.reduce(into: [:]) { counts, elem in counts[elem, default: 0] += 1 }
    }
}

extension URL: ExpressibleByArgument {
  public init?(argument: String) {
    self.init(fileURLWithPath: argument)
  }
}


struct DebuggerConsoleCommand: ParsableCommand {
  @Argument(help: "The file to debug")
  var sourceFilePath: URL
  
  @Option(name: .customLong("samples"), default: 10_000, help: "The number of samples to use initially")
  var sampleCount: Int
  
  @Option(default: nil, help: "Commands to automatically execute in the debugger when it starts")
  var commands: String?
  
  func run() throws {
    let sourceCode = try String(contentsOf: sourceFilePath)
    let ir = try SLIRGen.generateIr(for: sourceCode)
    
    let debugger = Debugger(program: ir.program, debugInfo: ir.debugInfo, sampleCount: sampleCount)
    
    let console = DebuggerConsole(sourceCode: sourceCode, debugger: debugger, initialSampleCount: sampleCount)
    
    if let commands = commands {
      console.execute(command: "\(commands);")
    }
    console.runLoop()
  }
}

DebuggerConsoleCommand.main()