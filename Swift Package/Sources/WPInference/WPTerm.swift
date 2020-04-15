import IR

public indirect enum WPTerm: Equatable, CustomStringConvertible {
  case variable(IRVariable)
  case integer(Int)
  case bool(Bool)
  case equal(lhs: WPTerm, rhs: WPTerm)
  case add(lhs: WPTerm, rhs: WPTerm)
  case sub(lhs: WPTerm, rhs: WPTerm)
  
  public func replacing(variable: IRVariable, with term: WPTerm) -> WPTerm {
    switch self {
    case .variable(let myVariable):
      if myVariable == variable {
        return term
      } else {
        return self
      }
    case .integer:
      return self
    case .bool:
      return self
    case .equal(lhs: let lhs, rhs: let rhs):
      return .equal(lhs: lhs.replacing(variable: variable, with: term), rhs: rhs.replacing(variable: variable, with: term))
    case .add(lhs: let lhs, rhs: let rhs):
      return .add(lhs: lhs.replacing(variable: variable, with: term), rhs: rhs.replacing(variable: variable, with: term))
    case .sub(lhs: let lhs, rhs: let rhs):
      return .sub(lhs: lhs.replacing(variable: variable, with: term), rhs: rhs.replacing(variable: variable, with: term))
    }
  }
  
  public var description: String {
    switch self {
    case .variable(let variable):
      return variable.description
    case .integer(let value):
      return value.description
    case .bool(let value):
      return value.description
    case .equal(lhs: let lhs, rhs: let rhs):
      return "[\(lhs.description) = \(rhs.description)]"
    case .add(lhs: let lhs, rhs: let rhs):
      return "\(lhs.description) + \(rhs.description)"
    case .sub(lhs: let lhs, rhs: let rhs):
      return "\(lhs.description) - \(rhs.description)"
    }
  }
}

extension WPTerm {
  init(_ variableOrValue: VariableOrValue) {
    switch variableOrValue {
    case .variable(let variable):
      self = .variable(variable)
    case .integer(let value):
      self = .integer(value)
    case .bool(let value):
      self = .bool(value)
    }
  }
}

extension WPTerm {
  var simplified: WPTerm {
    switch self {
    case .variable:
      return self
    case .integer:
      return self
    case .bool:
      return self
    case .equal(lhs: let lhs, rhs: let rhs):
      switch (lhs.simplified, rhs.simplified) {
      case (.integer(let lhsValue), .integer(let rhsValue)):
        return .bool(lhsValue == rhsValue)
      case (.bool(let lhsValue), .bool(let rhsValue)):
        return .bool(lhsValue == rhsValue)
      case (let lhsValue, let rhsValue):
        return .equal(lhs: lhsValue, rhs: rhsValue)
      }
    case .add(lhs: let lhs, rhs: let rhs):
      switch (lhs, rhs) {
      case (.integer(let lhsValue), .integer(let rhsValue)):
        return .integer(lhsValue + rhsValue)
      case (let lhsValue, let rhsValue):
        return .add(lhs: lhsValue, rhs: rhsValue)
      }
    case .sub(lhs: let lhs, rhs: let rhs):
      switch (lhs, rhs) {
      case (.integer(let lhsValue), .integer(let rhsValue)):
        return .integer(lhsValue - rhsValue)
      case (let lhsValue, let rhsValue):
        return .sub(lhs: lhsValue, rhs: rhsValue)
      }
    }
  }
}
