import IR

/// A sample during execution of a probabilistic program execution that assigns variables concrete values.
/// The probability distribution of a program can be described through a series of samples.
/// In deterministic programs, a single sample is continuously modified by simultaneously advancing the program position to retrieve the program's final variable assignment.
/// In probabilistic programs, a program can simultaneously be at different *program positions* and each program position does not have single variable assignment, but a distribution of variable assignments.
/// The purpose of this struct is to define a sample for a single program position so that, together with other samples, it can describe the probability distribution of the variables at a given program position.
/// During a set of `ExecutionState`s takes care of modelling the different program positions at which execution may simultaneously be.
public struct IRSample {
  /// The values assigned to the variables in a sample.
  public let values: [IRVariable: IRValue]
  
  /// Get a new `IRSample` by assigning the given variable the value of the given `variableOrValue`.
  internal func assigning(variable: IRVariable, variableOrValue: VariableOrValue) -> IRSample {
    #if DEBUG
    if let previousValue = values[variable] {
      assert(previousValue.type == variableOrValue.type)
    }
    #endif
    return IRSample(values: values.assiging(key: variable, value: variableOrValue.evaluated(in: self)))
  }
  
  /// Get a new `IRSample` by assigning the given variable a given `value`.
  internal func assigning(variable: IRVariable, value: IRValue) -> IRSample {
    #if DEBUG
    if let previousValue = values[variable] {
      assert(previousValue.type == value.type)
    }
    #endif
    return IRSample(values: values.assiging(key: variable, value: value))
  }
  
  /// Return a new sample by changing the variable values through the execution of the given instruction.
  /// The instruction cannot be a control-flow instruction since there is no meaningful execution for it.
  /// If an `observe` is violated through the execution `nil` is returned.
  internal func executeNonControlFlowInstruction(_ instruction: Instruction) -> IRSample? {
    switch instruction {
    case let instruction as AssignInstruction:
      return self.assigning(variable: instruction.assignee, variableOrValue: instruction.value)
    case let instruction as AddInstruction:
      let lhsValue = instruction.lhs.evaluated(in: self).integerValue!
      let rhsValue = instruction.rhs.evaluated(in: self).integerValue!
      return self.assigning(variable: instruction.assignee, value: .integer(lhsValue + rhsValue))
    case let instruction as SubtractInstruction:
      let lhsValue = instruction.lhs.evaluated(in: self).integerValue!
      let rhsValue = instruction.rhs.evaluated(in: self).integerValue!
      return self.assigning(variable: instruction.assignee, value: .integer(lhsValue - rhsValue))
    case let instruction as CompareInstruction:
      let lhsValue = instruction.lhs.evaluated(in: self).integerValue!
      let rhsValue = instruction.rhs.evaluated(in: self).integerValue!
      switch instruction.comparison {
      case .lessThan:
        return self.assigning(variable: instruction.assignee, value: .bool(lhsValue < rhsValue))
      case .equal:
        return self.assigning(variable: instruction.assignee, value: .bool(lhsValue == rhsValue))
      }
    case let instruction as DiscreteDistributionInstruction:
      return self.assigning(variable: instruction.assignee, value: .integer(instruction.drawValue()))
    case let instruction as ObserveInstruction:
      let observation = instruction.observation.evaluated(in: self).boolValue!
      if observation {
        return self
      } else {
        return nil
      }
    case is JumpInstruction, is BranchInstruction, is PhiInstruction:
      fatalError("Control-flow instructions cannot be handled on the sample level")
    default:
      fatalError("Unknown instruction \(type(of: instruction))")
    }
  }
}
