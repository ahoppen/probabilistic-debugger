import Foundation
import IR

public indirect enum WPTerm: Equatable, CustomStringConvertible {
  /// An IR variable that has not been replaced by a concrete value yet
  case variable(IRVariable)
  
  /// An integer literal
  case integer(Int)
  
  /// A floating-Point literal
  case double(Double)
  
  /// A boolean literal
  case bool(Bool)
  
  /// Convert a boolean value to an integer by mapping `false` to `0` and `true` to `1`.
  case boolToInt(WPTerm)
  
  /// Compare the two given terms. Returns a boolean value. The two terms must be of the same type to be considered equal
  case equal(lhs: WPTerm, rhs: WPTerm)
  
  /// Compare if `lhs` is strictly less than `rhs` (`lhs < rhs`)
  case lessThan(lhs: WPTerm, rhs: WPTerm)
  
  /// Add all the given `terms`. An empty sum has the value `0`.
  case add(terms: [WPTerm])
  
  /// Subtract `rhs` from `lhs`
  case sub(lhs: WPTerm, rhs: WPTerm)
  
  /// Multiply `lhs` with `rhs`
  case mul(lhs: WPTerm, rhs: WPTerm)
  
  /// Divide `lhs` by `rhs`
  case div(lhs: WPTerm, rhs: WPTerm)
  
  public var description: String {
    switch self {
    case .variable(let variable):
      return variable.description
    case .integer(let value):
      return value.description
    case .double(let value):
      return value.description
    case .bool(let value):
      return value.description
    case .boolToInt(let term):
      return "[\(term)]"
    case .equal(lhs: let lhs, rhs: let rhs):
      return "(\(lhs.description) = \(rhs.description))"
    case .lessThan(lhs: let lhs, rhs: let rhs):
      return "(\(lhs.description) < \(rhs.description))"
    case .add(terms: let terms):
      return terms.map({ $0.description }).joined(separator: " + ")
    case .sub(lhs: let lhs, rhs: let rhs):
      return "\(lhs.description) - \(rhs.description)"
    case .mul(lhs: let lhs, rhs: let rhs):
      return "(\(lhs.description)) * (\(rhs.description))"
    case .div(lhs: let lhs, rhs: let rhs):
      return "(\(lhs.description)) / (\(rhs.description))"
    }
  }
}

public extension WPTerm {
  func replacing(variable: IRVariable, with term: WPTerm) -> WPTerm {
    switch self {
    case .variable(let myVariable):
      if myVariable == variable {
        return term
      } else {
        return self
      }
    case .integer:
      return self
    case .double:
      return self
    case .bool:
      return self
    case .boolToInt(let wrappedBool):
      return .boolToInt(wrappedBool.replacing(variable: variable, with: term))
    case .equal(lhs: let lhs, rhs: let rhs):
      return .equal(lhs: lhs.replacing(variable: variable, with: term), rhs: rhs.replacing(variable: variable, with: term))
    case .lessThan(lhs: let lhs, rhs: let rhs):
      return .lessThan(lhs: lhs.replacing(variable: variable, with: term), rhs: rhs.replacing(variable: variable, with: term))
    case .add(terms: let terms):
      return .add(terms: terms.map({ $0.replacing(variable: variable, with: term) }))
    case .sub(lhs: let lhs, rhs: let rhs):
      return .sub(lhs: lhs.replacing(variable: variable, with: term), rhs: rhs.replacing(variable: variable, with: term))
    case .mul(lhs: let lhs, rhs: let rhs):
      return .mul(lhs: lhs.replacing(variable: variable, with: term), rhs: rhs.replacing(variable: variable, with: term))
    case .div(lhs: let lhs, rhs: let rhs):
      return .div(lhs: lhs.replacing(variable: variable, with: term), rhs: rhs.replacing(variable: variable, with: term))
    }
  }
}

internal extension WPTerm {
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

internal extension WPTerm {
  var simplified: WPTerm {
    switch self {
    case .variable:
      return self
    case .integer:
      return self
    case .double:
      return self
    case .bool:
      return self
    case .boolToInt(let term):
      switch term.simplified {
      case .bool(false):
        return .integer(0)
      case .bool(true):
        return .integer(1)
      case let simplifiedTerm:
        return .boolToInt(simplifiedTerm)
      }
    case .equal(lhs: let lhs, rhs: let rhs):
      switch (lhs.simplified, rhs.simplified) {
      case (.integer(let lhsValue), .integer(let rhsValue)):
        return .bool(lhsValue == rhsValue)
      case (.double(let lhsValue), .double(let rhsValue)):
        return .bool(lhsValue == rhsValue)
      case (.bool(let lhsValue), .bool(let rhsValue)):
        return .bool(lhsValue == rhsValue)
      case (let lhsValue, let rhsValue):
        return .equal(lhs: lhsValue, rhs: rhsValue)
      }
    case .lessThan(lhs: let lhs, rhs: let rhs):
      switch (lhs.simplified, rhs.simplified) {
      case (.integer(let lhsValue), .integer(let rhsValue)):
        return .bool(lhsValue < rhsValue)
      case (.double(let lhsValue), .double(let rhsValue)):
        return .bool(lhsValue < rhsValue)
      case (let lhsValue, let rhsValue):
        return .lessThan(lhs: lhsValue, rhs: rhsValue)
      }
    case .add(terms: let terms):
      var integerComponent = 0
      var doubleComponents: [Double] = []
      var otherComponents: [WPTerm] = []
      for term in terms {
        switch term.simplified {
        case .integer(let value):
          integerComponent += value
        case .double(let value):
          doubleComponents.append(value)
        case let simplifiedTerm:
          otherComponents.append(simplifiedTerm)
        }
      }
      var finalTerms = otherComponents
      // Sort the double components by size before adding them since this is numerically more stable
      let doubleComponent = doubleComponents.sorted().reduce(0, { $0 + $1 })
      if integerComponent != 0 && doubleComponent == 0 {
        finalTerms.append(.integer(integerComponent))
      }
      if doubleComponent != 0 {
        finalTerms.append(.double(doubleComponent + Double(integerComponent)))
      }
      if finalTerms.count == 0 {
        return .integer(0)
      } else if finalTerms.count == 1 {
        return finalTerms.first!
      } else {
        return .add(terms: finalTerms)
      }
    case .sub(lhs: let lhs, rhs: let rhs):
      switch (lhs.simplified, rhs.simplified) {
      case (let lhs, .integer(0)):
        return lhs
      case (let lhs, .double(0)):
        return lhs
      case (.integer(let lhsValue), .integer(let rhsValue)):
        return .integer(lhsValue - rhsValue)
      case (.double(let lhsValue), .double(let rhsValue)):
        return .double(lhsValue - rhsValue)
      case (.integer(let lhsValue), .double(let rhsValue)):
        return .double(Double(lhsValue) - rhsValue)
      case (.double(let lhsValue), .integer(let rhsValue)):
        return .double(lhsValue - Double(rhsValue))
      case (let lhsValue, let rhsValue):
        return .sub(lhs: lhsValue, rhs: rhsValue)
      }
    case .mul(lhs: let lhs, rhs: let rhs):
      switch (lhs.simplified, rhs.simplified) {
      case (.integer(let lhsValue), .integer(let rhsValue)):
        return .integer(lhsValue * rhsValue)
      case (.double(let lhsValue), .double(let rhsValue)):
        return .double(lhsValue * rhsValue)
      case (.double(let lhsValue), .integer(let rhsValue)):
        return .double(lhsValue * Double(rhsValue))
      case (.integer(let lhsValue), .double(let rhsValue)):
        return .double(Double(lhsValue) * rhsValue)
      case (.integer(0), _), (_, .integer(0)):
        return .integer(0)
      case (.double(0), _), (_, .double(0)):
        return .double(0)
      case (let lhsValue, let rhsValue):
        return .mul(lhs: lhsValue, rhs: rhsValue)
      }
    case .div(lhs: let lhs, rhs: let rhs):
      switch (lhs.simplified, rhs.simplified) {
      case (.integer(let lhsValue), .integer(let rhsValue)):
        return .double(Double(lhsValue) / Double(rhsValue))
      case (.double(let lhsValue), .double(let rhsValue)):
        return .double(lhsValue / rhsValue)
      case (.double(let lhsValue), .integer(let rhsValue)):
        return .double(lhsValue / Double(rhsValue))
      case (.integer(let lhsValue), .double(let rhsValue)):
        return .double(Double(lhsValue) / rhsValue)
      case (.integer(0), _):
        return .integer(0)
      case (.double(0), _):
        return .double(0)
      case (let lhsValue, let rhsValue):
        return .div(lhs: lhsValue, rhs: rhsValue)
      }
    }
  }
}

public extension WPTerm {
  var doubleValue: Double {
    switch self.simplified {
    case .integer(let value):
      return Double(value)
    case .double(let value):
      return value
    case let simplifiedTerm:
      fatalError("""
        WP evaluation term was not fully simplified
        Term:
        \(simplifiedTerm)

        Original:
        \(self)
        """)
    }
  }
}

public func +(lhs: WPTerm, rhs: WPTerm) -> WPTerm {
  return .add(terms: [lhs, rhs])
}

public func -(lhs: WPTerm, rhs: WPTerm) -> WPTerm {
  return .sub(lhs: lhs, rhs: rhs)
}

public func *(lhs: WPTerm, rhs: WPTerm) -> WPTerm {
  return .mul(lhs: lhs, rhs: rhs)
}

public func /(lhs: WPTerm, rhs: WPTerm) -> WPTerm {
  return .div(lhs: lhs, rhs: rhs)
}
