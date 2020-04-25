import ArgumentParser
import Debugger
import Foundation
import SimpleLanguageIRGen
import SimpleLanguageParser

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
    
    let console = try DebuggerConsole(sourceCode: sourceCode, initialSampleCount: sampleCount)
    
    if let commands = commands {
      console.execute(command: "\(commands);")
    }
    console.runLoop()
  }
}

DebuggerConsoleCommand.main()
