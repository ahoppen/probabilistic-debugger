import IR

/// An entry in the branching history of IR execution.
@frozen public enum BranchingChoice: Equatable, CustomStringConvertible {
  /// A deliberate branching choice. Execution was branched from `source` to `target` although another branch might also have been viable.
  case choice(source: BasicBlockName, target: BasicBlockName)
  
  /// As many non-deliberate branching choices as necessary from blocks that are predominated by `predominatedBy`.
  /// `any` can be extended arbitrarily often to all possible branching choices.
  /// It allows for a more-concicse list of branching histories if there were no deliberate branches.
  case any(predominatedBy: BasicBlockName)
  
  public init(source: BasicBlockName, target: BasicBlockName) {
    self = .choice(source: source, target: target)
  }
  
  public var description: String {
    switch self {
    case .choice(source: let source, target: let target):
      return "\(source) -> \(target)"
    case .any(predominatedBy: let predominatedBy):
      return "any(predominatedBy: \(predominatedBy))"
    }
  }
}

/// A branching history describes a path through which execution has reached a specific program point, either through explicit choices or through `any` choices where both execution branches may be taken.
/// Multiple branching histories together can describe multiple potential paths to reach the same point.
public struct BranchingHistory: Equatable, ExpressibleByArrayLiteral {
  public typealias ArrayLiteralElement = BranchingChoice
  
  public let choices: [BranchingChoice]
  
  /// Whether there are any deliberate branches in the branching history.
  public var isEmpty: Bool {
    return !choices.contains(where: {
      switch $0 {
      case .choice:
        return true
      case .any:
        return false
      }
    })
  }
  
  public var lastChoice: BranchingChoice? {
    return choices.last
  }
  
  public init(choices: [BranchingChoice]) {
    self.choices = choices
  }
  
  public init(arrayLiteral elements: BranchingChoice...) {
    self.choices = Array(elements)
  }
  
  public func addingBranchingChoice(_ branchingChoice: BranchingChoice) -> BranchingHistory {
    return BranchingHistory(choices: choices + [branchingChoice])
  }
  
  public func droppingLastChoice() -> BranchingHistory {
    return BranchingHistory(choices: choices.dropLast())
  }
}
