import IR
import SimpleLanguageAST

/// Debug information associated to a single IR instruction
public struct InstructionDebugInfo {
  /// Mapping of the source variables to the IR variables that hold the values
  public let variables: [Variable: IRVariable]
  
  /// The location in the original source code that corresponds to this instruction
  public let sourceLocation: Position?
}

/// Debug info for a *Simple Language* program, consisting of `InstructionDebugInfo`s for all instructions in the IR that correspond to statements in the source code.
public struct SLDebugInfo: DebugInfo {
  /// Mapping of the instructions corresponding to a statement in the source code to their debug info
  public let info: [InstructionPosition: InstructionDebugInfo]
  
  public init(_ info: [InstructionPosition: InstructionDebugInfo]) {
    self.info = info
  }
}
