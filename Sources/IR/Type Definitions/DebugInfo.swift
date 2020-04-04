public struct SourceCodeLocation: Equatable, CustomStringConvertible {
  /// The line of this position (1-based)
  public let line: Int
  
  /// The column of this position (1-based)
  public let column: Int
  
  public init(line: Int, column: Int) {
    self.line = line
    self.column = column
  }
  
  public var description: String {
    return "\(line):\(column)"
  }
}

/// Debug information associated to a single IR instruction
public struct InstructionDebugInfo {
  /// Mapping of the source variables (identified by names) to the IR variables that hold the values
  public let variables: [String: IRVariable]
  
  /// The location in the original source code that corresponds to this instruction
  public let sourceCodeLocation: SourceCodeLocation
  
  public init(variables: [String: IRVariable], sourceCodeLocation: SourceCodeLocation) {
    self.variables = variables
    self.sourceCodeLocation = sourceCodeLocation
  }
}

/// Debug info consisting of `InstructionDebugInfo`s for all instructions in the IR that correspond to statements in the source code.
public struct DebugInfo {
  /// Mapping of the instructions corresponding to a statement in the source code to their debug info
  public let info: [InstructionPosition: InstructionDebugInfo]
  
  public init(_ info: [InstructionPosition: InstructionDebugInfo]) {
    self.info = info
  }
}
