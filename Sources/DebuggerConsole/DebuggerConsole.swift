import Debugger

class DebuggerConsole {
  /// The debugger that this console operates
  private let debugger: Debugger
  
  /// The source code that is being debuged
  private let sourceCode: String
  
  /// The number of samples that were initially used
  private let initialSampleCount: Int
  
  /// The commands available in the debuger console. Initialised in `init` because it needs access to `self`
  private var commands: DebuggerCommand! = nil
  
  /// If set to `true`, the run loop stops prompting for new commands
  private var stopRunLoop = false
  
  
  internal init(sourceCode: String, debugger: Debugger, initialSampleCount: Int) {
    self.debugger = debugger
    self.sourceCode = sourceCode
    self.initialSampleCount = initialSampleCount
    
    self.commands = DebuggerCommand(
      description: "Probabilistic Debugger Console",
      subCommands: [
      ["show", "p"]: DebuggerCommand(
        description: "Show information about the current execution state",
        subCommands: [
          ["position", "p"]: DebuggerCommand(
            description: "Print the source code annoted with the position the debugger is currently halted at",
            action: { [unowned self] in try self.showSourceCode(arguments: $0) }
          ),
          ["variables", "v"]: DebuggerCommand(
            description: "Show the average values of all variables in the program",
            action: { [unowned self] in try self.showAverageVariableValues(arguments: $0) }
          )
        ]
      ),
      ["step", "s"]: DebuggerCommand(
        description: "Advance execution of the program",
        action: { [unowned self] in try self.stepOver(arguments: $0) },
        subCommands: [
          ["over", "o"]: DebuggerCommand(
            description: "Step to the next statement if the current position is not a branching point. See 'step into' for branching points",
            action: { [unowned self] in try self.stepOver(arguments: $0) }
          ),
          ["into", "i"]: DebuggerCommand(
            description: "If execution is currently at a branching point (if, while), either step into the true or false branch",
            action: { [unowned self] in try self.stepInto(arguments: $0) }
          )
        ]
      )
    ])
  }
  
  /// Execute the given command
  internal func execute(command rawCommand: String) {
    // If we are executing multiple commands separated by ';' (or a single command terminated by a ';'), print the executed command before executing it
    let printCommands = rawCommand.contains(";")
    for commandString in rawCommand.split(separator: ";") {
      let command = commandString.split(separator: " ")
      if printCommands {
        print("> \(command.joined(separator: " "))")
      }
      if command.first == "exit" {
        self.stopRunLoop = true
        break
      }
      do {
        try self.commands.execute(arguments: command.map(String.init))
      } catch {
        print("\(error.localizedDescription)")
      }
    }
  }
  
  /// Prompt the user for input on the command line and execute the entered command
  internal func runLoop() {
    while !stopRunLoop {
      print("> ", terminator: "")
      guard let command = readLine() else {
        stopRunLoop = true
        break
      }
      execute(command: command)
    }
  }
  
  // MARK: - Debugger actions
  
  private func stepOver(arguments: [String]) throws {
    if !arguments.isEmpty {
      throw ConsoleError(unrecognisedArguments: arguments)
    }
    try debugger.step()
    try showSourceCode(arguments: [])
  }
  
  private func stepInto(arguments: [String]) throws {
    if arguments.count > 1 {
      throw ConsoleError(unrecognisedArguments: arguments)
    }
    guard let branchName = arguments.first else {
      throw ConsoleError(message: "Must specify which branch to execute by appending 'step into' with 'true' (short: 't') or 'false' (short: 'f')")
    }
    switch branchName {
    case "true", "t":
      try debugger.stepInto(branch: true)
      try showSourceCode(arguments: [])
    case "false", "f":
      try debugger.stepInto(branch: false)
      try showSourceCode(arguments: [])
    default:
      throw ConsoleError(message: "Invalid branch name '\(branchName)'. Valid values are 'true', 'false', 't' (short for true), 'f' (short for false)")
    }
  }
  
  private func showSourceCode(arguments: [String]) throws {
    if !arguments.isEmpty {
      throw ConsoleError(unrecognisedArguments: arguments)
    }
    let currentLine = debugger.sourceLocation?.line
    for (zeroBasedLineNumber, line) in sourceCode.split(separator: "\n").enumerated() {
      let lineNumber = zeroBasedLineNumber + 1
      if lineNumber == currentLine {
        print("--> \(line)")
      } else {
        print("    \(line)")
      }
    }
  }
  
  private func showAverageVariableValues(arguments: [String]) throws {
    if !arguments.isEmpty {
      throw ConsoleError(unrecognisedArguments: arguments)
    }
    guard let firstSample = debugger.samples.first else {
      throw ConsoleError(message: "The current execution branch does not have any samples")
    }
    let focusedOnRuns = Double(debugger.samples.count) / Double(initialSampleCount)
    if focusedOnRuns != 1 {
      print("Currently focused on \(focusedOnRuns * 100)% of all initially started runs.")
    }
    print("Variable values:")
    for variable in firstSample.values.keys.sorted() {
      let histogram = debugger.samples.map({ $0.values[variable]! }).histogram()
      
      let value: String
      if histogram.count == 1 {
        // We only have a single value. Don't bother printing probabilities
        value = histogram.first!.key.description
      } else {
        // Print the frequencies of the values
        value = histogram.map({ (value, frequency) in
          "\(value): \(Double(frequency) / Double(debugger.samples.count) * 100)%"
        }).joined(separator: ", ")
      }
      print("\(variable) | \(value)")
    }
    print("")
  }
}