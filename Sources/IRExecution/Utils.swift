import IR

extension Dictionary {
  /// Create a new dictionary by changing the value of the given key.
  func assiging(key: Key, value: Value) -> Self {
    var newDict = self
    newDict[key] = value
    return newDict
  }
}

extension VariableOrValue {
  /// Return the value this `VariableOrValue` has in the given sample
  func evaluated(in sample: Sample) -> Value {
    switch self {
    case .integer(let value):
      return .integer(value)
    case .bool(let value):
      return .bool(value)
    case .variable(let variable):
      return sample.values[variable]!
    }
  }
}

extension DiscreteDistributionInstr {
  /// Randomly draw a value from the distribution described by this instruction
  func drawValue() -> Int {
    let random = Double.random(in: 0..<1)
    for (cummulativeProbability, value) in self.drawDistribution {
      if random < cummulativeProbability {
        return value
      }
    }
    fatalError("Did not find a corresponding value. drawDistribution malformed?")
  }
}
