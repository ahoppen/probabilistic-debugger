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
