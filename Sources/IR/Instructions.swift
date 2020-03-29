public protocol Instruction: CustomStringConvertible {}

// MARK: - Instructions

/// Assigns a value to a variable
public struct AssignInstr: Equatable, Instruction {
  public let assignee: IRVariable
  public let value: Value
  
  public init(assignee: IRVariable, value: Value) {
    assert(assignee.type == value.type)
    
    self.assignee = assignee
    self.value = value
  }
}

/// Add two integers and assign the result to an integer variable
public struct AddInstr: Equatable, Instruction {
  public let assignee: IRVariable
  public let lhs: Value
  public let rhs: Value
  
  
  /// - Parameters:
  ///   - assignee: Must be of type `int`
  ///   - lhs: Must be of type `int`
  ///   - rhs: Must be of type `int`
  public init(assignee: IRVariable, lhs: Value, rhs: Value) {
    assert(assignee.type == .int)
    assert(lhs.type == .int)
    assert(rhs.type == .int)
    
    self.assignee = assignee
    self.lhs = lhs
    self.rhs = rhs
  }
}

/// Subtract one integer from another and assign the result to an integer variable
public struct SubtractInstr: Equatable, Instruction {
  public let assignee: IRVariable
  public let lhs: Value
  public let rhs: Value
  
  /// - Parameters:
  ///   - assignee: Must be of type `int`
  ///   - lhs: Must be of type `int`
  ///   - rhs: Must be of type `int`
  public init(assignee: IRVariable, lhs: Value, rhs: Value) {
    assert(assignee.type == .int)
    assert(lhs.type == .int)
    assert(rhs.type == .int)
    
    self.assignee = assignee
    self.lhs = lhs
    self.rhs = rhs
  }
}

/// Compare two integers and assign the result to a boolean variable.
public struct CompareInstr: Equatable, Instruction {
  public enum Comparison: CustomStringConvertible {
    case equal
    case lessThan
  }
  
  public let comparison: Comparison
  public let assignee: IRVariable
  public let lhs: Value
  public let rhs: Value
  
  /// - Parameters:
  ///   - comparison: The comparison operation to be performed
  ///   - assignee: Must be of type `bool`
  ///   - lhs: Must be of type `int`
  ///   - rhs: Must be of type `int`
  public init(comparison: Comparison, assignee: IRVariable, lhs: Value, rhs: Value) {
    assert(assignee.type == .bool)
    assert(lhs.type == .int)
    assert(rhs.type == .int)
    
    self.comparison = comparison
    self.assignee = assignee
    self.lhs = lhs
    self.rhs = rhs
  }
}

public struct DiscreteDistributionInstr: Equatable, Instruction {
  public let assignee: IRVariable
  public let distribution: [Int: Double]
  
  /// - Parameters:
  ///   - assignee: Must be of type `int`
  ///   - distribution: The distribution to assign to the variable
  public init(assignee: IRVariable, distribution: [Int: Double]) {
    assert(assignee.type == .int)
    assert(distribution.values.reduce(0, +) == 1)
    self.assignee = assignee
    self.distribution = distribution
  }
}

public struct ObserveInstr: Equatable, Instruction {
  /// The variable that holds the observation that is to be checked. I.e. the result of the observe check is stored in this variable
  public let observation: Value
  
  /// - Parameter observation: Must be of type `bool`
  public init(observation: Value) {
    assert(observation.type == .bool)
    self.observation = observation
  }
}

public struct JumpInstr: Equatable, Instruction {
  /// The basic block to jump to, unconditionally
  public let target: BasicBlockName
  
  public init(target: BasicBlockName) {
    self.target = target
  }
}

public struct ConditionalBranchInstr: Equatable, Instruction {
  public let condition: Value
  
  /// The basic block to which to jump if the condition is `true`.
  public let targetTrue: BasicBlockName
  
  /// The basic block to which to jump if the condition is `false`.
  public let targetFalse: BasicBlockName
  
  public init(condition: Value, targetTrue: BasicBlockName, targetFalse: BasicBlockName) {
    self.condition = condition
    self.targetTrue = targetTrue
    self.targetFalse = targetFalse
  }
}

public struct PhiInstr: Equatable, Instruction {
  public let assignee: IRVariable
  public let choices: [BasicBlockName: IRVariable]
  
  public init(assignee: IRVariable, choices: [BasicBlockName: IRVariable]) {
    self.assignee = assignee
    self.choices = choices
  }
}

// MARK: - Debug Descriptions

extension AssignInstr {
  public var description: String {
    return "\(assignee) = \(value)"
  }
}

extension AddInstr {
  public var description: String {
    return "\(assignee) = add \(lhs) \(rhs)"
  }
}

extension SubtractInstr {
  public var description: String {
    return "\(assignee) = sub \(lhs) \(rhs)"
  }
}

extension CompareInstr.Comparison {
  public var description: String {
    switch self {
    case .equal:
      return "eq"
    case .lessThan:
      return "lt"
    }
  }
}

extension CompareInstr {
  public var description: String {
    return "\(assignee) = cmp \(comparison) \(lhs) \(rhs)"
  }
}

extension DiscreteDistributionInstr {
  public var description: String {
    let distributionDescription = distribution.map({ "\($0.key): \($0.value)"}).joined(separator: ", ")
    return "\(assignee) = discrete \(distributionDescription)"
  }
}

extension ObserveInstr {
  public var description: String {
    return "observe \(observation)"
  }
}

extension JumpInstr {
  public var description: String {
    return "jump \(target)"
  }
}

extension ConditionalBranchInstr {
  public var description: String {
    return "br \(condition) \(targetTrue) \(targetFalse)"
  }
}

extension PhiInstr {
  public var description: String {
    let choicesDescription = choices.sorted(by: { $0.key.name < $1.key.name }).map({ "\($0.key): \($0.value)"}).joined(separator: ", ")
    return "\(assignee) = phi \(choicesDescription)"
  }
}
