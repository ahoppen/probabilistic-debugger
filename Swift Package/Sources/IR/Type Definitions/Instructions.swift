import Utils

public protocol Instruction: CustomStringConvertible {
  /// Rename any usages of the given `variable` to `newVariable` in the instruction.
  /// Any assigned variables are **not** renamed
  func renaming(variable: IRVariable, to newVariable: IRVariable) -> Instruction
  
  /// The variable to which this instruction assigns a value or `nil` if the instruction does not assign a value to a variable
  var assignedVariable: IRVariable? { get }
  
  /// All the variables whose value is used by this instruction
  var usedVariables: Set<IRVariable> { get }
}

// MARK: - Instructions

// MARK: Computing instructions

/// Assigns a value to a variable
public struct AssignInstruction: Equatable, Instruction {
  public let assignee: IRVariable
  public let value: VariableOrValue
  
  public init(assignee: IRVariable, value: VariableOrValue) {
    assert(assignee.type == value.type)
    
    self.assignee = assignee
    self.value = value
  }
  
  public func renaming(variable: IRVariable, to newVariable: IRVariable) -> Instruction {
    return AssignInstruction(
      assignee: assignee,
      value: value.renaming(variable: variable, to: newVariable)
    )
  }
}

/// Add two integers and assign the result to an integer variable
public struct AddInstruction: Equatable, Instruction {
  public let assignee: IRVariable
  public let lhs: VariableOrValue
  public let rhs: VariableOrValue
  
  
  /// - Parameters:
  ///   - assignee: Must be of type `int`
  ///   - lhs: Must be of type `int`
  ///   - rhs: Must be of type `int`
  public init(assignee: IRVariable, lhs: VariableOrValue, rhs: VariableOrValue) {
    assert(assignee.type == .int)
    assert(lhs.type == .int)
    assert(rhs.type == .int)
    
    self.assignee = assignee
    self.lhs = lhs
    self.rhs = rhs
  }
  
  public func renaming(variable: IRVariable, to newVariable: IRVariable) -> Instruction {
    return AddInstruction(
      assignee: assignee,
      lhs: lhs.renaming(variable: variable, to: newVariable),
      rhs: rhs.renaming(variable: variable, to: newVariable)
    )
  }
}

/// Subtract one integer from another and assign the result to an integer variable
public struct SubtractInstruction: Equatable, Instruction {
  public let assignee: IRVariable
  public let lhs: VariableOrValue
  public let rhs: VariableOrValue
  
  /// - Parameters:
  ///   - assignee: Must be of type `int`
  ///   - lhs: Must be of type `int`
  ///   - rhs: Must be of type `int`
  public init(assignee: IRVariable, lhs: VariableOrValue, rhs: VariableOrValue) {
    assert(assignee.type == .int)
    assert(lhs.type == .int)
    assert(rhs.type == .int)
    
    self.assignee = assignee
    self.lhs = lhs
    self.rhs = rhs
  }
  
  public func renaming(variable: IRVariable, to newVariable: IRVariable) -> Instruction {
    return SubtractInstruction(
      assignee: assignee,
      lhs: lhs.renaming(variable: variable, to: newVariable),
      rhs: rhs.renaming(variable: variable, to: newVariable)
    )
  }
}

/// Compare two integers and assign the result to a boolean variable.
public struct CompareInstruction: Equatable, Instruction {
  public enum Comparison: CustomStringConvertible {
    case equal
    case lessThan
  }
  
  public let comparison: Comparison
  public let assignee: IRVariable
  public let lhs: VariableOrValue
  public let rhs: VariableOrValue
  
  /// - Parameters:
  ///   - comparison: The comparison operation to be performed
  ///   - assignee: Must be of type `bool`
  ///   - lhs: Must be of type `int`
  ///   - rhs: Must be of type `int`
  public init(comparison: Comparison, assignee: IRVariable, lhs: VariableOrValue, rhs: VariableOrValue) {
    assert(assignee.type == .bool)
    assert(lhs.type == .int)
    assert(rhs.type == .int)
    
    self.comparison = comparison
    self.assignee = assignee
    self.lhs = lhs
    self.rhs = rhs
  }
  
  public func renaming(variable: IRVariable, to newVariable: IRVariable) -> Instruction {
    return CompareInstruction(
      comparison: comparison,
      assignee: assignee,
      lhs: lhs.renaming(variable: variable, to: newVariable),
      rhs: rhs.renaming(variable: variable, to: newVariable)
    )
  }
}

// MARK: Probabilistic instructions

public struct DiscreteDistributionInstruction: Equatable, Instruction {
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
    
    var drawDistribution: [(cummulativeProbability: Double, value: Int)] = []
    var cummulativeProbability = 0.0
    for (value, probability) in distribution {
      cummulativeProbability += probability
      drawDistribution.append((cummulativeProbability: cummulativeProbability, value: value))
    }
    assert(cummulativeProbability == 1)
    self.drawDistribution = drawDistribution
  }
  
  public func renaming(variable: IRVariable, to newVariable: IRVariable) -> Instruction {
    return self
  }
  
  public static func == (lhs: DiscreteDistributionInstruction, rhs: DiscreteDistributionInstruction) -> Bool {
    // drawDistribution is synthesized and doesn't need to be compared
    return lhs.assignee == rhs.assignee && lhs.distribution == rhs.distribution
  }
  
  /// A synthesized dictionary to draw values from this distribution during execution. See `drawValue`.
  private let drawDistribution: [(cummulativeProbability: Double, value: Int)]
  
  /// Randomly draw a value from the distribution described by this instruction
  public func drawValue() -> Int {
    let random = Double.random(in: 0..<1)
    for (cummulativeProbability, value) in self.drawDistribution {
      if random < cummulativeProbability {
        return value
      }
    }
    fatalError("Did not find a corresponding value. drawDistribution malformed?")
  }
}

public struct ObserveInstruction: Equatable, Instruction {
  /// The variable that holds the observation that is to be checked. I.e. the result of the observe check is stored in this variable
  public let observation: VariableOrValue
  
  /// - Parameter observation: Must be of type `bool`
  public init(observation: VariableOrValue) {
    assert(observation.type == .bool)
    self.observation = observation
  }
  
  public func renaming(variable: IRVariable, to newVariable: IRVariable) -> Instruction {
    return ObserveInstruction(
      observation: observation.renaming(variable: variable, to: newVariable)
    )
  }
}

// MARK: Control flow instruction

public struct JumpInstruction: Equatable, Instruction {
  /// The basic block to jump to, unconditionally
  public let target: BasicBlockName
  
  public init(target: BasicBlockName) {
    self.target = target
  }
  
  public func renaming(variable: IRVariable, to newVariable: IRVariable) -> Instruction {
    return self
  }
}

public struct BranchInstruction: Equatable, Instruction {
  public let condition: VariableOrValue
  
  /// The basic block to which to jump if the condition is `true`.
  public let targetTrue: BasicBlockName
  
  /// The basic block to which to jump if the condition is `false`.
  public let targetFalse: BasicBlockName
  
  public init(condition: VariableOrValue, targetTrue: BasicBlockName, targetFalse: BasicBlockName) {
    assert(condition.type == .bool)
    self.condition = condition
    self.targetTrue = targetTrue
    self.targetFalse = targetFalse
  }
  
  public func renaming(variable: IRVariable, to newVariable: IRVariable) -> Instruction {
    return BranchInstruction(
      condition: condition.renaming(variable: variable, to: newVariable),
      targetTrue: targetTrue,
      targetFalse: targetFalse
    )
  }
}

/// Finish program execution. Must only occur once in every program
public struct ReturnInstruction: Equatable, Instruction {
  public init() {}
  
  public func renaming(variable: IRVariable, to newVariable: IRVariable) -> Instruction {
    return self
  }
}

public struct PhiInstruction: Equatable, Instruction {
  public let assignee: IRVariable
  public let choices: [BasicBlockName: IRVariable]
  
  public init(assignee: IRVariable, choices: [BasicBlockName: IRVariable]) {
    assert(!choices.isEmpty)
    assert(choices.map(\.value.type).allEqual)
    assert(assignee.type == choices.first!.value.type)
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
    
    return PhiInstruction(assignee: assignee, choices: newChoices)
  }
}



// MARK: - Used and assigned variables

fileprivate extension VariableOrValue {
  var asVariable: IRVariable? {
    if case .variable(let variable) = self {
      return variable
    } else {
      return nil
    }
  }
}

public extension AssignInstruction {
  var assignedVariable: IRVariable? {
    return assignee
  }
  var usedVariables: Set<IRVariable> {
    return Set([value.asVariable].compactMap({ $0 }))
  }
}

public extension AddInstruction {
  var assignedVariable: IRVariable? {
    return assignee
  }
  var usedVariables: Set<IRVariable> {
    return Set([lhs.asVariable, rhs.asVariable].compactMap({ $0 }))
  }
}

public extension SubtractInstruction {
  var assignedVariable: IRVariable? {
    return assignee
  }
  var usedVariables: Set<IRVariable> {
    return Set([lhs.asVariable, rhs.asVariable].compactMap({ $0 }))
  }
}

public extension CompareInstruction {
  var assignedVariable: IRVariable? {
    return assignee
  }
  var usedVariables: Set<IRVariable> {
    return Set([lhs.asVariable, rhs.asVariable].compactMap({ $0 }))
  }
}

public extension DiscreteDistributionInstruction {
  var assignedVariable: IRVariable? {
    return assignee
  }
  var usedVariables: Set<IRVariable> {
    return []
  }
}

public extension ObserveInstruction {
  var assignedVariable: IRVariable? {
    return nil
  }
  var usedVariables: Set<IRVariable> {
    return Set([observation.asVariable].compactMap({ $0 }))
  }
}

public extension JumpInstruction {
  var assignedVariable: IRVariable? {
    return nil
  }
  var usedVariables: Set<IRVariable> {
    return []
  }
}

public extension BranchInstruction {
  var assignedVariable: IRVariable? {
    return nil
  }
  var usedVariables: Set<IRVariable> {
    return Set([condition.asVariable].compactMap({ $0 }))
  }
}

public extension PhiInstruction {
  var assignedVariable: IRVariable? {
    return assignee
  }
  var usedVariables: Set<IRVariable> {
    return Set(choices.values.compactMap({ $0 }))
  }
}

public extension ReturnInstruction {
  var assignedVariable: IRVariable? {
    return nil
  }
  var usedVariables: Set<IRVariable> {
    return []
  }
}

// MARK: - Debug Descriptions

extension AssignInstruction {
  public var description: String {
    return "\(assignee) = \(value)"
  }
}

extension AddInstruction {
  public var description: String {
    return "\(assignee) = add \(lhs) \(rhs)"
  }
}

extension SubtractInstruction {
  public var description: String {
    return "\(assignee) = sub \(lhs) \(rhs)"
  }
}

extension CompareInstruction.Comparison {
  public var description: String {
    switch self {
    case .equal:
      return "eq"
    case .lessThan:
      return "lt"
    }
  }
}

extension CompareInstruction {
  public var description: String {
    return "\(assignee) = cmp \(comparison) \(lhs) \(rhs)"
  }
}

extension DiscreteDistributionInstruction {
  public var description: String {
    let distributionDescription = distribution.map({ "\($0.key): \($0.value)"}).joined(separator: ", ")
    return "\(assignee) = discrete \(distributionDescription)"
  }
}

extension ObserveInstruction {
  public var description: String {
    return "observe \(observation)"
  }
}

extension JumpInstruction {
  public var description: String {
    return "jump \(target)"
  }
}

extension BranchInstruction {
  public var description: String {
    return "br \(condition) \(targetTrue) \(targetFalse)"
  }
}

extension PhiInstruction {
  public var description: String {
    let choicesDescription = choices.sorted(by: { $0.key < $1.key }).map({ "\($0.key): \($0.value)"}).joined(separator: ", ")
    return "\(assignee) = phi \(choicesDescription)"
  }
}

extension ReturnInstruction {
  public var description: String {
    return "return"
  }
}
