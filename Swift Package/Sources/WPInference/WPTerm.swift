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
  case _boolToInt(WPTerm)
  
  /// Compare the two given terms. Returns a boolean value. The two terms must be of the same type to be considered equal
  case _equal(lhs: WPTerm, rhs: WPTerm)
  
  /// Compare if `lhs` is strictly less than `rhs` (`lhs < rhs`)
  case _lessThan(lhs: WPTerm, rhs: WPTerm)
  
  /// Add all the given `terms`. An empty sum has the value `0`.
  case _add(terms: [WPTerm])
  
  /// Subtract `rhs` from `lhs`
  case _sub(lhs: WPTerm, rhs: WPTerm)
  
  /// Multiply `lhs` with `rhs`
  case _mul(lhs: WPTerm, rhs: WPTerm)
  
  /// Divide `lhs` by `rhs`
  case _div(lhs: WPTerm, rhs: WPTerm)
  
  public static func boolToInt(_ wrapped: WPTerm) -> WPTerm {
    return _boolToInt(wrapped).simplified(recursively: false)
  }
  
  public static func equal(lhs: WPTerm, rhs: WPTerm) -> WPTerm {
    return _equal(lhs: lhs, rhs: rhs).simplified(recursively: false)
  }
  
  public static func lessThan(lhs: WPTerm, rhs: WPTerm) -> WPTerm {
    return _lessThan(lhs: lhs, rhs: rhs).simplified(recursively: false)
  }
  
  public static func add(terms: [WPTerm]) -> WPTerm {
    return _add(terms: terms).simplified(recursively: false)
  }
  
  public static func sub(lhs: WPTerm, rhs: WPTerm) -> WPTerm {
    return _sub(lhs: lhs, rhs: rhs).simplified(recursively: false)
  }
  
  public static func mul(lhs: WPTerm, rhs: WPTerm) -> WPTerm {
    return _mul(lhs: lhs, rhs: rhs).simplified(recursively: false)
  }
  
  public static func div(lhs: WPTerm, rhs: WPTerm) -> WPTerm {
    return _div(lhs: lhs, rhs: rhs).simplified(recursively: false)
  }
  
  
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
    case ._boolToInt(let term):
      return "[\(term)]"
    case ._equal(lhs: let lhs, rhs: let rhs):
      return "(\(lhs.description) = \(rhs.description))"
    case ._lessThan(lhs: let lhs, rhs: let rhs):
      return "(\(lhs.description) < \(rhs.description))"
    case ._add(terms: let terms):
      return terms.map({ $0.description }).joined(separator: " + ")
    case ._sub(lhs: let lhs, rhs: let rhs):
      return "\(lhs.description) - \(rhs.description)"
    case ._mul(lhs: let lhs, rhs: let rhs):
      return "(\(lhs.description)) * (\(rhs.description))"
    case ._div(lhs: let lhs, rhs: let rhs):
      return "(\(lhs.description)) / (\(rhs.description))"
    }
  }
}

public extension WPTerm {
  func replacing(variable: IRVariable, with term: WPTerm) -> WPTerm {
    return replacingImpl(variable: variable, with: term) ?? self
  }
  
  private func replacingImpl(variable: IRVariable, with term: WPTerm) -> WPTerm? {
    switch self {
    case .variable(let myVariable):
      if myVariable == variable {
        return term
      } else {
        return nil
      }
    case .integer:
      return nil
    case .double:
      return nil
    case .bool:
      return nil
    case ._boolToInt(let wrappedBool):
      if let replaced = wrappedBool.replacingImpl(variable: variable, with: term) {
        return WPTerm._boolToInt(replaced).simplified(recursively: false)
      }
      return nil
    case ._equal(lhs: let lhs, rhs: let rhs):
      let lhsReplaced = lhs.replacingImpl(variable: variable, with: term)
      let rhsReplaced = rhs.replacingImpl(variable: variable, with: term)
      if lhsReplaced == nil && rhsReplaced == nil {
        return nil
      }
      return WPTerm._equal(lhs: lhsReplaced ?? lhs, rhs: rhsReplaced ?? rhs).simplified(recursively: false)
    case ._lessThan(lhs: let lhs, rhs: let rhs):
      let lhsReplaced = lhs.replacingImpl(variable: variable, with: term)
      let rhsReplaced = rhs.replacingImpl(variable: variable, with: term)
      if lhsReplaced == nil && rhsReplaced == nil {
        return nil
      }
      return WPTerm._lessThan(lhs: lhsReplaced ?? lhs, rhs: rhsReplaced ?? rhs).simplified(recursively: false)
    case ._add(terms: let terms):
      var hasPerformedReplacement = false
      let replacedTerms = terms.map({ (summand) -> WPTerm in
        if let replaced = summand.replacingImpl(variable: variable, with: term) {
          hasPerformedReplacement = true
          return replaced
        } else {
          return summand
        }
      })
      if hasPerformedReplacement {
        return WPTerm._add(terms: replacedTerms).simplified(recursively: false)
      } else {
        return self
      }
    case ._sub(lhs: let lhs, rhs: let rhs):
      let lhsReplaced = lhs.replacingImpl(variable: variable, with: term)
      let rhsReplaced = rhs.replacingImpl(variable: variable, with: term)
      if lhsReplaced == nil && rhsReplaced == nil {
        return nil
      }
      return WPTerm._sub(lhs: lhsReplaced ?? lhs, rhs: rhsReplaced ?? rhs).simplified(recursively: false)
    case ._mul(lhs: let lhs, rhs: let rhs):
      let lhsReplaced = lhs.replacingImpl(variable: variable, with: term)
      let rhsReplaced = rhs.replacingImpl(variable: variable, with: term)
      if lhsReplaced == nil && rhsReplaced == nil {
        return nil
      }
      return WPTerm._mul(lhs: lhsReplaced ?? lhs, rhs: rhsReplaced ?? rhs).simplified(recursively: false)
    case ._div(lhs: let lhs, rhs: let rhs):
      let lhsReplaced = lhs.replacingImpl(variable: variable, with: term)
      let rhsReplaced = rhs.replacingImpl(variable: variable, with: term)
      if lhsReplaced == nil && rhsReplaced == nil {
        return nil
      }
      return WPTerm._div(lhs: lhsReplaced ?? lhs, rhs: rhsReplaced ?? rhs).simplified(recursively: false)
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
  private func selfOrSimplified(simplified: Bool) -> WPTerm {
    if simplified {
      return self.simplified(recursively: true)
    } else {
      return self
    }
  }
  
  func simplified(recursively: Bool) -> WPTerm {
    switch self {
    case .variable:
      return self
    case .integer:
      return self
    case .double:
      return self
    case .bool:
      return self
    case ._boolToInt(let term):
      switch term.selfOrSimplified(simplified: recursively) {
      case .bool(false):
        return .integer(0)
      case .bool(true):
        return .integer(1)
      case let simplifiedTerm:
        return ._boolToInt(simplifiedTerm)
      }
    case ._equal(lhs: let lhs, rhs: let rhs):
      switch (lhs.selfOrSimplified(simplified: recursively), rhs.selfOrSimplified(simplified: recursively)) {
      case (.integer(let lhsValue), .integer(let rhsValue)):
        return .bool(lhsValue == rhsValue)
      case (.double(let lhsValue), .double(let rhsValue)):
        return .bool(lhsValue == rhsValue)
      case (.bool(let lhsValue), .bool(let rhsValue)):
        return .bool(lhsValue == rhsValue)
      case (let lhsValue, let rhsValue):
        return ._equal(lhs: lhsValue, rhs: rhsValue)
      }
    case ._lessThan(lhs: let lhs, rhs: let rhs):
      switch (lhs.selfOrSimplified(simplified: recursively), rhs.selfOrSimplified(simplified: recursively)) {
      case (.integer(let lhsValue), .integer(let rhsValue)):
        return .bool(lhsValue < rhsValue)
      case (.double(let lhsValue), .double(let rhsValue)):
        return .bool(lhsValue < rhsValue)
      case (let lhsValue, let rhsValue):
        return ._lessThan(lhs: lhsValue, rhs: rhsValue)
      }
    case ._add(terms: let terms):
      var integerComponent = 0
      var doubleComponents: [Double] = []
      var otherComponents: [WPTerm] = []
      for term in terms {
        switch term.selfOrSimplified(simplified: recursively) {
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
        return ._add(terms: finalTerms)
      }
    case ._sub(lhs: let lhs, rhs: let rhs):
      switch (lhs.selfOrSimplified(simplified: recursively), rhs.selfOrSimplified(simplified: recursively)) {
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
        return ._sub(lhs: lhsValue, rhs: rhsValue)
      }
    case ._mul(lhs: let lhs, rhs: let rhs):
      switch (lhs.selfOrSimplified(simplified: recursively), rhs.selfOrSimplified(simplified: recursively)) {
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
        return ._mul(lhs: lhsValue, rhs: rhsValue)
      }
    case ._div(lhs: let lhs, rhs: let rhs):
      switch (lhs.selfOrSimplified(simplified: recursively), rhs.selfOrSimplified(simplified: recursively)) {
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
        return ._div(lhs: lhsValue, rhs: rhsValue)
      }
    }
  }
}

public extension WPTerm {
  var doubleValue: Double {
    switch self {
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
  return WPTerm.add(terms: [lhs, rhs])
}

public func -(lhs: WPTerm, rhs: WPTerm) -> WPTerm {
  return WPTerm.sub(lhs: lhs, rhs: rhs)
}

public func *(lhs: WPTerm, rhs: WPTerm) -> WPTerm {
  return WPTerm.mul(lhs: lhs, rhs: rhs)
}

public func /(lhs: WPTerm, rhs: WPTerm) -> WPTerm {
  return WPTerm.div(lhs: lhs, rhs: rhs)
}
