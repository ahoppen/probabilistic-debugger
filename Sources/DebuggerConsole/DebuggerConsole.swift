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
      description: """
        Probabilistic Debugger Console
        
        Type any of the following commands followed by 'help' to get more information.
        Type multiple commands separated by ';' to execute all of them.
        """,
      subCommands: [
      ["display", "d"]: DebuggerCommand(
        description: "Display information about the current execution state",
        action: { [unowned self] in try self.showSourceCodeAndVariableValues(arguments: $0) },
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
            description: """
              If execution is currently at a branching point (if, while), either step into the true or false branch.
              This filters out any samples that don't satisfy the condition that is necessary to reach the true/false branch.
              Saves the current state on the state stack before stepping into the branch (see the 'state' command).
              """,
            action: { [unowned self] in try self.stepInto(arguments: $0) }
          ),
          ["out"]: DebuggerCommand(
            description: """
              After stepping into a branch, undo the filtering of states and jump to the statement after the branch that was switched into.
              Equivalent to 'state restore; step over'
              """,
            action: { [unowned self] in try self.stepOut(arguments: $0) }
          )
        ]
      ),
      ["run", "r"]: DebuggerCommand(
        description: "Run the program until the end",
        action: { [unowned self ] in try self.runUntilEnd(arguments: $0) }
      ),
      ["state", "st"]: DebuggerCommand(
        description: """
          Save or restore debugger states.
          The debugger has a notion of saving the current states and later restoring them. This is particularly useful to experimentally step into branch of a if/while statement which filters out samples and later return to the unfiltered state.
          """,
        subCommands: [
          ["save", "s"]: DebuggerCommand(
            description: "Save the current execution state on the states stack.",
            action: { [unowned self] in try self.saveState(arguments: $0) }
          ),
          ["restore", "r"]: DebuggerCommand(
            description: "Restore the execution state that was last saved.",
            action: { [unowned self] in try self.restoreState(arguments: $0) }
          ),
          ["display", "d"]: DebuggerCommand(
            description: "Show the states that have been saved. These can be restored in the order they were saved.",
            action: { [unowned self] in try self.displaySavedStates(arguments: $0) }
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
    try debugger.stepOver()
    try showSourceCode(arguments: [])
  }
  
  private func stepInto(arguments: [String]) throws {
    if arguments.count > 1 {
      throw ConsoleError(unrecognisedArguments: arguments)
    }
    guard let branchName = arguments.first else {
      throw ConsoleError(message: "Must specify which branch to execute by appending 'step into' with 'true' (short: 't') or 'false' (short: 'f')")
    }
    debugger.saveState()
    do {
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
    } catch {
      try? debugger.restoreState()
      throw error
    }
  }
  
  private func stepOut(arguments: [String]) throws {
    if !arguments.isEmpty {
      throw ConsoleError(unrecognisedArguments: arguments)
    }
    try debugger.restoreState()
    try debugger.stepOver()
  }
  
  private func runUntilEnd(arguments: [String]) throws {
    if !arguments.isEmpty {
      throw ConsoleError(unrecognisedArguments: arguments)
    }
    try debugger.runUntilEnd()
  }
  
  private func showSourceCodeAndVariableValues(arguments: [String]) throws {
    if !arguments.isEmpty {
      throw ConsoleError(unrecognisedArguments: arguments)
    }
    try showSourceCode(arguments: [])
    try showAverageVariableValues(arguments: [])
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
        value = histogram.sorted(by: { $0.key < $1.key }).map({ (value, frequency) in
          "\(value): \(Double(frequency) / Double(debugger.samples.count) * 100)%"
        }).joined(separator: ", ")
      }
      print("\(variable) | \(value)")
    }
    print("")
  }
  
  private func saveState(arguments: [String]) throws {
    if !arguments.isEmpty {
      throw ConsoleError(unrecognisedArguments: arguments)
    }
    debugger.saveState()
  }
  
  private func restoreState(arguments: [String]) throws {
    if !arguments.isEmpty {
      throw ConsoleError(unrecognisedArguments: arguments)
    }
    try debugger.restoreState()
  }
  
  private func displaySavedStates(arguments: [String]) throws {
    if !arguments.isEmpty {
      throw ConsoleError(unrecognisedArguments: arguments)
    }
    for (index, state) in debugger.stateStack.enumerated() {
      let name = (index == 0) ? "Current" : String(index)
      let positionDescription: String
      if let state = state, let sourceLocation = debugger.sourceLocation(of: state) {
        positionDescription = "line \(sourceLocation.line)"
      } else if state == nil {
        positionDescription = "<no samples left>"
      } else {
        positionDescription = "<unknown>"
      }
      print("\(name): \(positionDescription)")
    }
  }
}
