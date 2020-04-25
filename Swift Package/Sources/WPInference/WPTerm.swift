import Foundation
import IR
import Utils

public indirect enum WPTerm: Hashable, CustomStringConvertible {
  /// An IR variable that has not been replaced by a concrete value yet
  case variable(IRVariable)
  
  /// An integer literal
  case integer(Int)
  
  /// A floating-Point literal
  case double(Double)
  
  /// A boolean literal
  case bool(Bool)
  
  /// Negate a boolean value
  case _not(WPTerm)
  
  /// Convert a boolean value to an integer by mapping `false` to `0` and `true` to `1`.
  case _boolToInt(WPTerm)
  
  /// Compare the two given terms. Returns a boolean value. The two terms must be of the same type to be considered equal
  case _equal(lhs: WPTerm, rhs: WPTerm)
  
  /// Compare if `lhs` is strictly less than `rhs` (`lhs < rhs`)
  case _lessThan(lhs: WPTerm, rhs: WPTerm)
  
  /// Add all the given `terms`. An empty sum has the value `0`.
  case _additionList(WPAdditionList)
  
  /// Subtract `rhs` from `lhs`
  case _sub(lhs: WPTerm, rhs: WPTerm)
  
  /// Multiply `terms`.
  case _mul(terms: [WPTerm])
  
  /// Divide `lhs` by `rhs`
  case _div(lhs: WPTerm, rhs: WPTerm)
  
  public static func not(_ wrapped: WPTerm) -> WPTerm {
    return _not(wrapped).simplified(recursively: false)
  }
  
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
    return _additionList(WPAdditionList(terms.map({ WPTermAdditionListEntry(factor: 1, conditions: [], term: $0) }))).simplified(recursively: false)
  }
  
  public static func sub(lhs: WPTerm, rhs: WPTerm) -> WPTerm {
    return _sub(lhs: lhs, rhs: rhs).simplified(recursively: false)
  }
  
  public static func mul(terms: [WPTerm]) -> WPTerm {
    return _mul(terms: terms).simplified(recursively: false)
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
    case ._not(let term):
      return "!(\(term))"
    case ._boolToInt(let term):
      return "[\(term)]"
    case ._equal(lhs: let lhs, rhs: let rhs):
      return "(\(lhs.description) = \(rhs.description))"
    case ._lessThan(lhs: let lhs, rhs: let rhs):
      return "(\(lhs.description) < \(rhs.description))"
    case ._additionList(let list):
      return "(\(list.entries.map({ "(\($0.factor) (*) [\($0.conditions.map({ $0.description }).joined(separator: " && "))] (*) \($0.term.description)" }).joined(separator: " + ")))"
    case ._sub(lhs: let lhs, rhs: let rhs):
      return "\(lhs.description) - \(rhs.description)"
    case ._mul(terms: let terms):
      return "(\(terms.map({ $0.description }).joined(separator: " * ")))"
    case ._div(lhs: let lhs, rhs: let rhs):
      return "(\(lhs.description)) / (\(rhs.description))"
    }
  }
  
  public var treeDescription: String {
    switch self {
    case .variable(let variable):
      return "▷ \(variable.description)"
    case .integer(let value):
      return "▷ \(value.description)"
    case .double(let value):
      return "▷ \(value.description)"
    case .bool(let value):
      return "▷ \(value.description)"
    case ._not(let term):
      return """
      ▽ Negated
      \(term.treeDescription.indented())
      """
    case ._boolToInt(let term):
      return """
      ▽ Bool to int
      \(term.treeDescription.indented())
      """
    case ._equal(lhs: let lhs, rhs: let rhs):
      return """
      ▽ =
      \(lhs.treeDescription.indented())
      \(rhs.treeDescription.indented())
      """
    case ._lessThan(lhs: let lhs, rhs: let rhs):
      return """
      ▽ <
      \(lhs.treeDescription.indented())
      \(rhs.treeDescription.indented())
      """
    case ._additionList(let list):
      var description = "▽ +"
      for entry in list.entries {
        description += """
          
            ▽ (*)
              ▷ \(entry.factor)
              ▷ \(entry.conditions.map({ $0.description }).joined(separator: " && "))
          \(entry.term.treeDescription.indented(2))
          """
      }
      return description
    case ._sub(lhs: let lhs, rhs: let rhs):
      return """
      ▽ -
      \(lhs.treeDescription.indented())
      \(rhs.treeDescription.indented())
      """
    case ._mul(terms: let terms):
      return "▽ *\n\(terms.map({ $0.treeDescription.indented() }).joined(separator: "\n"))"
    case ._div(lhs: let lhs, rhs: let rhs):
      return """
      ▽ /
      \(lhs.treeDescription.indented())
      \(rhs.treeDescription.indented())
      """
    }
  }
}

public extension WPTerm {
  func replacing(variable: IRVariable, with term: WPTerm) -> WPTerm {
    return replacingImpl(variable: variable, with: term) ?? self
  }
  
  internal func replacingImpl(variable: IRVariable, with term: WPTerm) -> WPTerm? {
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
    case ._not(let wrappedBool):
      if let replaced = wrappedBool.replacingImpl(variable: variable, with: term) {
        return WPTerm._not(replaced).simplified(recursively: false)
      }
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
    case ._additionList(var list):
      let performedReplacement = list.replace(variable: variable, with: term)
      if performedReplacement {
        return WPTerm._additionList(list).simplified(recursively: false)
      } else {
        return nil
      }
    case ._sub(lhs: let lhs, rhs: let rhs):
      let lhsReplaced = lhs.replacingImpl(variable: variable, with: term)
      let rhsReplaced = rhs.replacingImpl(variable: variable, with: term)
      if lhsReplaced == nil && rhsReplaced == nil {
        return nil
      }
      return WPTerm._sub(lhs: lhsReplaced ?? lhs, rhs: rhsReplaced ?? rhs).simplified(recursively: false)
    case ._mul(terms: let terms):
      var hasPerformedReplacement = false
      let replacedTerms = terms.map({ (factor) -> WPTerm in
        if let replaced = factor.replacingImpl(variable: variable, with: term) {
          hasPerformedReplacement = true
          return replaced
        } else {
          return factor
        }
      })
      if hasPerformedReplacement {
        return WPTerm._mul(terms: replacedTerms).simplified(recursively: false)
      } else {
        return self
      }
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
    case ._not(let term):
      switch term.selfOrSimplified(simplified: recursively) {
      case .bool(false):
        return .bool(true)
      case .bool(true):
        return .bool(false)
      case ._not(let doubleNegated):
        return doubleNegated
      case let simplifiedTerm:
        return ._not(simplifiedTerm)
      }
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
      case (.double(let doubleValue), .integer(let integerValue)), (.integer(let integerValue), .double(let doubleValue)):
        return .bool(Double(integerValue) == doubleValue)
      case (.bool(let lhsValue), .bool(let rhsValue)):
        return .bool(lhsValue == rhsValue)
      case (let value, .bool(true)), (.bool(true), let value):
        return value
      case (let value, .bool(false)), (.bool(false), let value):
        return ._not(value)
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
    case ._additionList(var list):
      if recursively {
        for (index, entry) in list.entries.enumerated() {
          list.entries[index] = WPTermAdditionListEntry(
            factor: entry.factor,
            conditions: Set(entry.conditions.map({ $0.simplified(recursively: recursively) })),
            term: entry.term.simplified(recursively: recursively)
          )
        }
      }
      list.simplify()
      
      if list.entries.count == 0 {
        return .integer(0)
      } else if list.entries.count == 1 {
        let entry = list.entries.first!
        var factors: [WPTerm] = []
        if entry.factor != 1 {
          factors.append(.double(entry.factor))
        }
        for condition in entry.conditions {
          factors.append(.boolToInt(condition))
        }
        if entry.term != .integer(1) {
          factors.append(entry.term)
        }
        return .mul(terms: factors)
      } else {
        return ._additionList(list)
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
    case ._mul(terms: let terms):
      var integerComponent = 1
      var doubleComponent = 1.0
      var otherComponents: [WPTerm] = []
      for term in terms {
        switch term.selfOrSimplified(simplified: recursively) {
        case .integer(let value):
          integerComponent *= value
        case .double(let value):
          doubleComponent *= value
        case ._mul(terms: let subTerms):
          // Flatten nested multiplications
          for subTerm in subTerms {
            switch subTerm {
            case .integer(let value):
              integerComponent *= value
            case .double(let value):
              doubleComponent *= value
            case let simplifiedTerm:
              otherComponents.append(simplifiedTerm)
            }
          }
        case let simplifiedTerm:
          otherComponents.append(simplifiedTerm)
        }
      }
      var finalTerms = otherComponents
      if integerComponent == 0 || doubleComponent == 0 {
        return .integer(0)
      }
      // Sort the double components by size before adding them since this is numerically more stable
      if integerComponent != 1 && doubleComponent == 1 {
        finalTerms.append(.integer(integerComponent))
      }
      if doubleComponent != 1 {
        finalTerms.append(.double(doubleComponent * Double(integerComponent)))
      }
      if finalTerms.count == 0 {
        return .integer(1)
      } else if finalTerms.count == 1 {
        return finalTerms.first!
      } else {
        return ._mul(terms: finalTerms)
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
  return WPTerm.mul(terms: [lhs, rhs])
}

public func /(lhs: WPTerm, rhs: WPTerm) -> WPTerm {
  return WPTerm.div(lhs: lhs, rhs: rhs)
}
