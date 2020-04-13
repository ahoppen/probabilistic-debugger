import IR
import IRExecution

// MARK: - ExecutionOutline

/// The execution outline represent all possible runs of a proram.
/// For example the following program is represented by the following execution outline:
/// ```
/// int x = discrete({1: 0.25, 2: 0.25, 3: 0.25, 4: 0.25})
/// while 1 < x {
///   x = x - 1
/// }
/// ```
///
/// Execution outline:
/// ```
/// ▷ int x = discrete({1: 0.25, 2: 0.25, 3: 0.25, 4: 0.25}), 1000 samples
/// ▽ while 1 < x, 1000 samples
///   ▽ Iteration 1
///     ▷ x = x - 1, 750 samples
///   ▽ Iteration 2
///     ▷ x = x - 1, 500 samples
///   ▽ Iteration 3
///     ▷ x = x - 1, 250 samples
/// ▷ end, 1000 samples
/// ```
///
/// For each entry in the execution outline, the `IRExecutionState` is stored, so that a debugger may be directly pointed to that location.
public struct ExecutionOutline: CustomStringConvertible, ExpressibleByArrayLiteral {
  public typealias ArrayLiteralElement = ExecutionOutlineEntry
  
  public let entries: [ExecutionOutlineEntry]
  
  internal init(_ entries: [ExecutionOutlineEntry]) {
    self.entries = entries
  }
  
  public init(arrayLiteral elements: ExecutionOutlineEntry...) {
    self.entries = elements
  }
}

// MARK: - ExecutionOutlineEntry

/// A single entry in the execution outline.
public enum ExecutionOutlineEntry: CustomStringConvertible {
  /// A normal instruction that transfers conrol flow to the next instruction in the basic block.
  /// This might still be an `observe` statement and filter out some or all samples
  case instruction(state: IRExecutionState)
  
  /// An if/else branch. Not both branches need to be viable. If a branch is not viable it is `nil`.
  case branch(state: IRExecutionState, true: ExecutionOutline?, false: ExecutionOutline?)
  
  /// A loop in the source code. Each iteration is represented by an `ExecutionOutline`, consisting of the statements that were executed in the loop body.
  /// The exit states represent the states that are reached after executing **at most** 0, 1, etc. iterations.
  case loop(state: IRExecutionState, iterations: [ExecutionOutline], exitStates: [IRExecutionState])
  
  public var state: IRExecutionState {
    switch self {
    case .instruction(state: let state):
      return state
    case .branch(state: let state, true: _, false: _):
      return state
    case .loop(state: let state, iterations: _, exitStates: _):
      return state
    }
  }
}

// MARK: - Descriptions

extension ExecutionOutline {
  public var description: String {
    return description(sourceCode: nil, debugInfo: nil)
  }
  
  public func description(sourceCode: String?, debugInfo: DebugInfo?) -> String {
    return entries.map({
      return $0.description(sourceCode: sourceCode, debugInfo: debugInfo)
    }).joined(separator: "\n")
  }
}

extension IRExecutionState {
  public func description(sourceCode: String?, debugInfo: DebugInfo?) -> String {
    let instructionDescription: String
    if let sourceCode = sourceCode, let debugInfo = debugInfo {
      let instructionPosition = self.position
      let sourcePosition = debugInfo.info[instructionPosition]!.sourceCodeLocation
      if debugInfo.info[instructionPosition]!.instructionType == .return {
        instructionDescription = "end"
      } else {
        instructionDescription = String(sourceCode.split(separator: "\n")[sourcePosition.line - 1]).trimmingCharacters(in: .whitespaces)
      }
    } else {
      instructionDescription = self.position.description
    }
    return "\(instructionDescription), \(self.samples.count) samples"
  }
}

extension ExecutionOutlineEntry {
  public var description: String {
    return description(sourceCode: nil, debugInfo: nil)
  }
  
  public func description(sourceCode: String?, debugInfo: DebugInfo?) -> String {
    
    switch self {
    case .instruction(state: let state):
      return "▷ \(state.description(sourceCode: sourceCode, debugInfo: debugInfo))"
    case .branch(state: let state, true: let trueBranch, false: let falseBranch):
      var descriptionPieces: [String] = []
      descriptionPieces.append("▽ \(state.description(sourceCode: sourceCode, debugInfo: debugInfo))")
      if let trueBranch = trueBranch {
        descriptionPieces.append("""
          ▽ true-Branch
        \(trueBranch.description(sourceCode: sourceCode, debugInfo: debugInfo).indented(2))
        """)
      }
      if let falseBranch = falseBranch {
        descriptionPieces.append("""
          ▽ false-Branch
        \(falseBranch.description(sourceCode: sourceCode, debugInfo: debugInfo).indented(2))
        """)
      }
      return descriptionPieces.joined(separator: "\n")
    case .loop(state: let state, iterations: let iterations, exitStates: let exitStates):
      var descriptionPieces: [String] = []
      descriptionPieces.append("▽ \(state.description(sourceCode: sourceCode, debugInfo: debugInfo))")
      for (index, iteration) in iterations.enumerated() {
        descriptionPieces.append("""
            ▽ Iteration \(index + 1)
          \(iteration.description(sourceCode: sourceCode, debugInfo: debugInfo).indented(2))
          """)
      }
      for (index, exitState) in exitStates.enumerated() {
        descriptionPieces.append("""
            ▽ Exit after at most \(index) iterations
              ▷ \(exitState.description(sourceCode: sourceCode, debugInfo: debugInfo))
          """)
      }
      return descriptionPieces.joined(separator: "\n")
    }
  }
}
