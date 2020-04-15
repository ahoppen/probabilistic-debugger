public struct SourceCodeLocation: Comparable, CustomStringConvertible {
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
  
  static public func <(lhs: SourceCodeLocation, rhs: SourceCodeLocation) -> Bool {
    if lhs.line < rhs.line {
      return true
    } else if lhs.line == rhs.line {
      return lhs.column < rhs.column
    } else {
      return false
    }
  }
}

public enum InstructionType {
  /// The instruction is a non-jumping one that transfers control to the next instruction in the same basic block.
  case simple
  
  /// The instruction is a branch for an if-else statement.
  /// The `true` and `false` branches of the instruction directly map to the `true` and `false` branches in the source code.
  case ifElseBranch
  
  /// The instruction is a branch for a loop. This means that:
  /// - Jumping into the `true` branch executes the loop body.
  /// - After execution of the loop body, this instruction will be executed again
  /// - Jumping into the `false` branch terminates the loop
  case loop
  
  /// A return instruction that terminates the program
  case `return`
}

/// Debug information associated to a single IR instruction
public struct InstructionDebugInfo {
  /// Mapping of the source variables (identified by names) to the IR variables that hold the values
  public let variables: [String: IRVariable]
  
  /// The type of the instruction for visualisation in the `RunOutlineGenerator`.
  public let instructionType: InstructionType
  
  public let sourceCodeRange: Range<SourceCodeLocation>
  
  /// The location in the original source code that corresponds to this instruction
  public var sourceCodeLocation: SourceCodeLocation {
    return sourceCodeRange.lowerBound
  }
  
  public init(variables: [String: IRVariable], instructionType: InstructionType, sourceCodeRange: Range<SourceCodeLocation>) {
    self.variables = variables
    self.instructionType = instructionType
    self.sourceCodeRange = sourceCodeRange
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
