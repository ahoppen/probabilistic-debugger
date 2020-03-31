public protocol Instruction: CustomStringConvertible {
  func renaming(variable: IRVariable, to newVariable: IRVariable) -> Instruction
  
  var assignedVariable: IRVariable? { get }
  var usedVariables: Set<IRVariable> { get }
}

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
  
  public func renaming(variable: IRVariable, to newVariable: IRVariable) -> Instruction {
    return AssignInstr(
      assignee: assignee,
      value: value.renaming(variable: variable, to: newVariable)
    )
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
  
  public func renaming(variable: IRVariable, to newVariable: IRVariable) -> Instruction {
    return AddInstr(
      assignee: assignee,
      lhs: lhs.renaming(variable: variable, to: newVariable),
      rhs: rhs.renaming(variable: variable, to: newVariable)
    )
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
  
  public func renaming(variable: IRVariable, to newVariable: IRVariable) -> Instruction {
    return SubtractInstr(
      assignee: assignee,
      lhs: lhs.renaming(variable: variable, to: newVariable),
      rhs: rhs.renaming(variable: variable, to: newVariable)
    )
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
  
  public func renaming(variable: IRVariable, to newVariable: IRVariable) -> Instruction {
    return CompareInstr(
      comparison: comparison,
      assignee: assignee,
      lhs: lhs.renaming(variable: variable, to: newVariable),
      rhs: rhs.renaming(variable: variable, to: newVariable)
    )
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
  
  public func renaming(variable: IRVariable, to newVariable: IRVariable) -> Instruction {
    return self
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
  
  public func renaming(variable: IRVariable, to newVariable: IRVariable) -> Instruction {
    return ObserveInstr(
      observation: observation.renaming(variable: variable, to: newVariable)
    )
  }
}

public struct JumpInstr: Equatable, Instruction {
  /// The basic block to jump to, unconditionally
  public let target: BasicBlockName
  
  public init(target: BasicBlockName) {
    self.target = target
  }
  
  public func renaming(variable: IRVariable, to newVariable: IRVariable) -> Instruction {
    return self
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
  
  public func renaming(variable: IRVariable, to newVariable: IRVariable) -> Instruction {
    return ConditionalBranchInstr(
      condition: condition.renaming(variable: variable, to: newVariable),
      targetTrue: targetTrue,
      targetFalse: targetFalse
    )
  }
}

public struct PhiInstr: Equatable, Instruction {
  public let assignee: IRVariable
  public let choices: [BasicBlockName: IRVariable]
  
  public init(assignee: IRVariable, choices: [BasicBlockName: IRVariable]) {
    self.assignee = assignee
    self.choices = choices
  }
  
  public func renaming(variable: IRVariable, to newVariable: IRVariable) -> Instruction {
    let newChoices = choices.mapValues({ (choice) -> IRVariable in
      if choice == variable {
        return newVariable
      } else {
        return choice
      }
    })
    
    return PhiInstr(
      assignee: assignee,
      choices: newChoices
    )
  }
}

// MARK: - Used and assigned variables

fileprivate extension Value {
  var asVariable: IRVariable? {
    if case .variable(let variable) = self {
      return variable
    } else {
      return nil
    }
  }
}

public extension AssignInstr {
  var assignedVariable: IRVariable? {
    return assignee
  }
  var usedVariables: Set<IRVariable> {
    return Set([value.asVariable].compactMap({ $0 }))
  }
}

public extension AddInstr {
  var assignedVariable: IRVariable? {
    return assignee
  }
  var usedVariables: Set<IRVariable> {
    return Set([lhs.asVariable, rhs.asVariable].compactMap({ $0 }))
  }
}

public extension SubtractInstr {
  var assignedVariable: IRVariable? {
    return assignee
  }
  var usedVariables: Set<IRVariable> {
    return Set([lhs.asVariable, rhs.asVariable].compactMap({ $0 }))
  }
}

public extension CompareInstr {
  var assignedVariable: IRVariable? {
    return assignee
  }
  var usedVariables: Set<IRVariable> {
    return Set([lhs.asVariable, rhs.asVariable].compactMap({ $0 }))
  }
}

public extension DiscreteDistributionInstr {
  var assignedVariable: IRVariable? {
    return assignee
  }
  var usedVariables: Set<IRVariable> {
    return []
  }
}

public extension ObserveInstr {
  var assignedVariable: IRVariable? {
    return nil
  }
  var usedVariables: Set<IRVariable> {
    return Set([observation.asVariable].compactMap({ $0 }))
  }
}

public extension JumpInstr {
  var assignedVariable: IRVariable? {
    return nil
  }
  var usedVariables: Set<IRVariable> {
    return []
  }
}

public extension ConditionalBranchInstr {
  var assignedVariable: IRVariable? {
    return nil
  }
  var usedVariables: Set<IRVariable> {
    return Set([condition.asVariable].compactMap({ $0 }))
  }
}

public extension PhiInstr {
  var assignedVariable: IRVariable? {
    return assignee
  }
  var usedVariables: Set<IRVariable> {
    return Set(choices.values.compactMap({ $0 }))
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
