public struct BasicBlockName: Hashable, CustomStringConvertible {
  public let name: String
  
  static var nextUnusedNumber = 1
  
  public init(_ name: String) {
    self.name = name
  }
  
  public var description: String {
    return name
  }
}

public struct BasicBlock: Equatable, CustomStringConvertible {
  public let name: BasicBlockName
  public let instructions: [Instruction]
  
  public init(name: BasicBlockName, instructions: [Instruction]) {
    self.name = name
    self.instructions = instructions
  }
  
  /// Create a new basic block with the same name and the given instruciton prepended at the start
  public func prepending(instruction: Instruction) -> BasicBlock {
    return BasicBlock(name: name, instructions: [instruction] + instructions)
  }
  
  /// Create a new basic block with the same name and the given instruciton appended to the end
  public func appending(instruction: Instruction) -> BasicBlock {
    return BasicBlock(name: name, instructions: instructions + [instruction])
  }
  
  public func renaming(variable: IRVariable, to newVariable: IRVariable) -> BasicBlock {
    return BasicBlock(name: name, instructions: instructions.map({ $0.renaming(variable: variable, to: newVariable) }))
  }
  
  public var description: String {
    let instructionDescription = instructions.map({ "  " + $0.description }).joined(separator: "\n")
    return """
      \(name):
      \(instructionDescription)
      """
  }
}

// MARK: - Equatable conformance helpers

/// We cannot conform `Instruction` to `Equatable` and still use it as array elements.
/// Thus we need to jump through a couple hoops to get an equality operator for `[Instruction]`.
/// First, declare a function that dispatches to the right equality operator for two instructions.
/// This cannot be named `==` since it would stop the compiler from generating equatable implementations for all instructio types.
/// Then add an `==` operator for `[Instruction]` that just calls `equal` on all instruction pairs
/// Lastly, because `[Instruction]` still doesn't conform to `Equatable`, we need to write our own implementation for `==` on `BasicBlock`.
fileprivate func equal(_ lhs: Instruction, _ rhs: Instruction) -> Bool {
  guard type(of: lhs) == type(of: rhs) else {
    return false
  }
  switch (lhs, rhs)  {
  case (let lhs as AssignInstr, let rhs as AssignInstr):
    return lhs == rhs
  case (let lhs as AddInstr, let rhs as AddInstr):
    return lhs == rhs
  case (let lhs as SubtractInstr, let rhs as SubtractInstr):
    return lhs == rhs
  case (let lhs as CompareInstr, let rhs as CompareInstr):
    return lhs == rhs
  case (let lhs as DiscreteDistributionInstr, let rhs as DiscreteDistributionInstr):
    return lhs == rhs
  case (let lhs as ObserveInstr, let rhs as ObserveInstr):
    return lhs == rhs
  case (let lhs as JumpInstr, let rhs as JumpInstr):
    return lhs == rhs
  case (let lhs as ConditionalBranchInstr, let rhs as ConditionalBranchInstr):
    return lhs == rhs
  case (let lhs as PhiInstr, let rhs as PhiInstr):
    return lhs == rhs
  case (let lhs as ReturnInstr, let rhs as ReturnInstr):
    return lhs == rhs
  default:
    fatalError("Unknown instruction type '\(type(of: lhs))'")
  }
}

extension Array where Element == Instruction {
  static func ==(lhs: [Instruction], rhs: [Instruction]) -> Bool {
    guard lhs.count == rhs.count else {
      return false
    }
    return zip(lhs, rhs).allSatisfy({ equal($0, $1) })
  }
}

extension BasicBlock {
  public static func == (lhs: BasicBlock, rhs: BasicBlock) -> Bool {
    return lhs.name == rhs.name && lhs.instructions == rhs.instructions
  }
}
