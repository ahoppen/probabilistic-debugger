import Foundation
import IR
import Utils

extension Array where Element == WPTerm {
  internal func replacing(variable: IRVariable, with replacementTerm: WPTerm) -> [WPTerm]? {
    var hasPerformedReplacement = false
    let replacedTerms = self.map({ (term) -> WPTerm in
      if let replaced = term.replacing(variable: variable, with: replacementTerm) {
        hasPerformedReplacement = true
        return replaced
      } else {
        return term
      }
    })
    if hasPerformedReplacement {
      return replacedTerms
    } else {
      return nil
    }
  }
}

public indirect enum WPTerm: Hashable, CustomStringConvertible {
  // MARK: Cases and constructors
  
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
  
  /// Divide `term` by `divisors`
  /// The result of `0 / 0` is undefined. It can be `0`, `nan` or something completely different.
  case _div(term: WPTerm, divisors: [WPTerm])
  
  /// Divide `term` by `divisors` with the additional semantics that `0 / 0` is well-defined as `0`.
  case _zeroDiv(term: WPTerm, divisors: [WPTerm])
  
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
    return _div(term: lhs, divisors: [rhs]).simplified(recursively: false)
  }
  
  public static func zeroDiv(lhs: WPTerm, rhs: WPTerm) -> WPTerm {
    return _zeroDiv(term: lhs, divisors: [rhs]).simplified(recursively: false)
  }
  
  public init(_ variableOrValue: VariableOrValue) {
    switch variableOrValue {
    case .variable(let variable):
      self = .variable(variable)
    case .integer(let value):
      self = .integer(value)
    case .bool(let value):
      self = .bool(value)
    }
  }
  
  // MARK: Descriptions
  
  
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
    case ._div(term: let term, divisors: let divisors):
      return "(\(term.description)) / \(divisors.map(\.description).joined(separator: " / "))"
    case ._zeroDiv(term: let term, divisors: let divisors):
      return "(\(term.description)) ./. \(divisors.map(\.description).joined(separator: " ./. "))"
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
    case ._div(term: let term, divisors: let divisors):
      return """
      ▽ /
      \(term.treeDescription.indented())
      \(divisors.map({ $0.treeDescription.indented() }).joined(separator: "\n"))
      """
    case ._zeroDiv(term: let term, divisors: let divisors):
      return """
      ▽ */*
      \(term.treeDescription.indented())
      \(divisors.map({ $0.treeDescription.indented() }).joined(separator: "\n"))
      """
    }
  }
}

// MARK: - Replacing terms

public extension WPTerm {
  /// Replace the `variable` with the given `term`.
  /// Returns the updated term or `nil` if no replacement was performed.
  func replacing(variable: IRVariable, with replacementTerm: WPTerm) -> WPTerm? {
    switch self {
    case .variable(let myVariable):
      if myVariable == variable {
        return replacementTerm
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
      if let replaced = wrappedBool.replacing(variable: variable, with: replacementTerm) {
        return WPTerm._not(replaced).simplified(recursively: false)
      }
      return nil
    case ._boolToInt(let wrappedBool):
      if let replaced = wrappedBool.replacing(variable: variable, with: replacementTerm) {
        return WPTerm._boolToInt(replaced).simplified(recursively: false)
      }
      return nil
    case ._equal(lhs: let lhs, rhs: let rhs):
      let lhsReplaced = lhs.replacing(variable: variable, with: replacementTerm)
      let rhsReplaced = rhs.replacing(variable: variable, with: replacementTerm)
      if lhsReplaced == nil && rhsReplaced == nil {
        return nil
      }
      return WPTerm._equal(lhs: lhsReplaced ?? lhs, rhs: rhsReplaced ?? rhs).simplified(recursively: false)
    case ._lessThan(lhs: let lhs, rhs: let rhs):
      let lhsReplaced = lhs.replacing(variable: variable, with: replacementTerm)
      let rhsReplaced = rhs.replacing(variable: variable, with: replacementTerm)
      if lhsReplaced == nil && rhsReplaced == nil {
        return nil
      }
      return WPTerm._lessThan(lhs: lhsReplaced ?? lhs, rhs: rhsReplaced ?? rhs).simplified(recursively: false)
    case ._additionList(var list):
      let performedReplacement = list.replace(variable: variable, with: replacementTerm)
      if performedReplacement {
        return WPTerm._additionList(list).simplified(recursively: false)
      } else {
        return nil
      }
    case ._sub(lhs: let lhs, rhs: let rhs):
      let lhsReplaced = lhs.replacing(variable: variable, with: replacementTerm)
      let rhsReplaced = rhs.replacing(variable: variable, with: replacementTerm)
      if lhsReplaced == nil && rhsReplaced == nil {
        return nil
      }
      return WPTerm._sub(lhs: lhsReplaced ?? lhs, rhs: rhsReplaced ?? rhs).simplified(recursively: false)
    case ._mul(terms: let terms):
      var hasPerformedReplacement = false
      let replacedTerms = terms.map({ (factor) -> WPTerm in
        if let replaced = factor.replacing(variable: variable, with: replacementTerm) {
          hasPerformedReplacement = true
          return replaced
        } else {
          return factor
        }
      })
      if hasPerformedReplacement {
        return WPTerm._mul(terms: replacedTerms).simplified(recursively: false)
      } else {
        return nil
      }
    case ._div(term: let term, divisors: let divisors):
      let termReplaced = term.replacing(variable: variable, with: replacementTerm)
      let divisorsReplaced = divisors.replacing(variable: variable, with: replacementTerm)
      if termReplaced == nil, divisorsReplaced == nil {
        return nil
      }
      return WPTerm._div(term: termReplaced ?? term, divisors: divisorsReplaced ?? divisors).simplified(recursively: false)
    case ._zeroDiv(term: let term, divisors: let divisors):
      let termReplaced = term.replacing(variable: variable, with: replacementTerm)
      let divisorsReplaced = divisors.replacing(variable: variable, with: replacementTerm)
      if termReplaced == nil, divisorsReplaced == nil {
        return nil
      }
      return WPTerm._zeroDiv(term: termReplaced ?? term, divisors: divisorsReplaced ?? divisors).simplified(recursively: false)
    }
  }
}

// MARK: Simplifying terms

internal extension WPTerm {
  private func selfOrSimplified(simplified: Bool) -> WPTerm {
    if simplified {
      return self.simplified(recursively: true)
    } else {
      return self
    }
  }
  
  private static func simplifyNot(term: WPTerm, recursively: Bool) -> WPTerm {
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
  }
  
  private static func simplifyBoolToInt(term: WPTerm, recursively: Bool) -> WPTerm {
    switch term.selfOrSimplified(simplified: recursively) {
    case .bool(false):
      return .integer(0)
    case .bool(true):
      return .integer(1)
    case let simplifiedTerm:
      return ._boolToInt(simplifiedTerm)
    }
  }
  
  private static func simplifyEqual(lhs: WPTerm, rhs: WPTerm, recursively: Bool) -> WPTerm {
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
  }
  
  private static func simplifyLessThan(lhs: WPTerm, rhs: WPTerm, recursively: Bool) -> WPTerm {
    switch (lhs.selfOrSimplified(simplified: recursively), rhs.selfOrSimplified(simplified: recursively)) {
    case (.integer(let lhsValue), .integer(let rhsValue)):
      return .bool(lhsValue < rhsValue)
    case (.double(let lhsValue), .double(let rhsValue)):
      return .bool(lhsValue < rhsValue)
    case (let lhsValue, let rhsValue):
      return ._lessThan(lhs: lhsValue, rhs: rhsValue)
    }
  }
  
  private static func simplifyAdditionList(list: WPAdditionList, recursively: Bool) -> WPTerm {
    var list = list
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
  }
  
  private static func simplifySub(lhs: WPTerm, rhs: WPTerm, recursively: Bool) -> WPTerm {
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
  }
  
  private static func simplifyMul(terms: [WPTerm], recursively: Bool) -> WPTerm {
    var terms = terms
    var singleAdditionListIndex: Int?
    
    // Flatten nested multiplications and check if the multiplication contains a single addition list
    for index in (0..<terms.count).reversed() {
      let term = terms[index]
      if case ._mul(terms: let subTerms) = term {
        terms.remove(at: index)
        terms.append(contentsOf: subTerms)
      }
      if case ._additionList = term {
        if singleAdditionListIndex == nil {
          singleAdditionListIndex = index
        } else {
          singleAdditionListIndex = nil
        }
      }
    }
    
    if let singleAdditionListIndex = singleAdditionListIndex {
      guard case ._additionList(var additionList) = terms[singleAdditionListIndex] else {
        fatalError()
      }
      terms.remove(at: singleAdditionListIndex)
      additionList.multiply(with: terms)
      return WPTerm._additionList(additionList)
    }
    
    var integerComponent = 1
    var doubleComponent = 1.0
    var otherComponents: [WPTerm] = []
    for term in terms {
      switch term.selfOrSimplified(simplified: recursively) {
      case .integer(let value):
        integerComponent *= value
      case .double(let value):
        doubleComponent *= value
      case ._boolToInt(let subTerm):
        if otherComponents.contains(.boolToInt(.not(subTerm))) {
          return .integer(0)
        } else if !otherComponents.contains(term) {
          otherComponents.append(term)
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
  }
  
  func simplifyDiv(term: WPTerm, divisors: [WPTerm], zeroDiv: Bool, recursively: Bool) -> WPTerm {
    var term = term.selfOrSimplified(simplified: recursively)
    var divisors = divisors
    if recursively {
      divisors = divisors.map({ $0.simplified(recursively: recursively) })
    }
    
    var integerComponent = 1
    var doubleComponent = 1.0
    var otherComponents: [WPTerm] = []
    
    // Flatten term
    switch term {
    case ._div(term: let nestedTerm, divisors: let nestedDivisors):
      term = nestedTerm
      divisors += nestedDivisors
    default:
      break
    }
    
    // Flatten the divisors
    for divisor in divisors {
      switch divisor {
      case .integer(let value):
        integerComponent *= value
      case .double(let value):
        doubleComponent *= value
      case ._mul(terms: let terms):
        otherComponents.append(contentsOf: terms)
      default:
        otherComponents.append(divisor)
      }
    }
    
    /// If possible, cancel this term from the division's `term` with entries in `otherComponents` or combine it with the `integerComponent` or `doubleComponent`.
    /// If the term could be (partially) cancelled, returns the new term. If no cancellation was performed, returns `nil`.
    /// `otherComponents` etc. are updated by this function.
    func tryToCancelTerm(termToCancel: WPTerm) -> WPTerm? {
      switch termToCancel {
      case .integer(let value) where value != 0:
        doubleComponent /= Double(value)
        return .integer(1)
      case .double(let value) where value != 0:
        doubleComponent /= value
        return .integer(1)
      case ._boolToInt where zeroDiv:
        // If we want to have 0 / 0 = 0, and have a condition in both the term and divisors, we can remove it from the divisors but not from the term.
        // Otherwise, we can cancel the terms in the default case
        if let otherComponentsIndex = otherComponents.firstIndex(of: termToCancel) {
          otherComponents.remove(at: otherComponentsIndex)
        }
        return nil
      case ._additionList(var additionList):
        otherComponents = additionList.tryDividing(by: otherComponents)
        if integerComponent != 1 || doubleComponent != 1 {
          additionList.divide(by: Double(integerComponent) * doubleComponent)
          integerComponent = 1
          doubleComponent = 1
        }
        return WPTerm._additionList(additionList).simplified(recursively: false)
      case _ where !zeroDiv:
        // We can only cancel terms if we don't define 0 / 0 = 0
        if let otherComponentsIndex = otherComponents.firstIndex(of: termToCancel) {
          otherComponents.remove(at: otherComponentsIndex)
          return .integer(1)
        } else {
          return nil
        }
      default:
        return nil
      }
    }
    
    // Perform simplifications on term that don't completely evaluate it
    switch term {
    case ._mul(terms: var multiplicationTerms):
      for multiplicationTermIndex in (0..<multiplicationTerms.count).reversed() {
        let multiplicationTerm = multiplicationTerms[multiplicationTermIndex]
        if let cancelledTerm = tryToCancelTerm(termToCancel: multiplicationTerm) {
          multiplicationTerms[multiplicationTermIndex] = cancelledTerm
        }
      }
      term = WPTerm._mul(terms: multiplicationTerms).simplified(recursively: false)
    default:
      if let cancelledTerm = tryToCancelTerm(termToCancel: term) {
        term = cancelledTerm
      }
    }
    
    // Evaluate the term if it has been sufficiently simplified
    if otherComponents.isEmpty {
      switch term {
      case .integer(0):
        return .integer(0)
      case .integer(let value):
        return .double(Double(value) / Double(integerComponent) / doubleComponent)
      case .double(0):
        return .double(0)
      case .double(let value):
        return .double(value / Double(integerComponent) / doubleComponent)
      default:
        switch (integerComponent, doubleComponent) {
        case (1, 1):
          return term
        case (_, 1):
          return ._div(term: term, divisors: [.integer(integerComponent)])
        case (_, _):
          return ._div(term: term, divisors: [.double(Double(integerComponent) * doubleComponent)])
        }
      }
    } else {
      return ._div(term: term, divisors: divisors)
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
      return Self.simplifyNot(term: term, recursively: recursively)
    case ._boolToInt(let term):
      return Self.simplifyBoolToInt(term: term, recursively: recursively)
    case ._equal(lhs: let lhs, rhs: let rhs):
      return Self.simplifyEqual(lhs: lhs, rhs: rhs, recursively: recursively)
    case ._lessThan(lhs: let lhs, rhs: let rhs):
      return Self.simplifyLessThan(lhs: lhs, rhs: rhs, recursively: recursively)
    case ._additionList(let list):
      return Self.simplifyAdditionList(list: list, recursively: recursively)
    case ._sub(lhs: let lhs, rhs: let rhs):
      return Self.simplifySub(lhs: lhs, rhs: rhs, recursively: recursively)
    case ._mul(terms: let terms):
      return Self.simplifyMul(terms: terms, recursively: recursively)
    case ._div(term: let term, divisors: let divisors):
      return simplifyDiv(term: term, divisors: divisors, zeroDiv: false, recursively: recursively)
    case ._zeroDiv(term: let term, divisors: let divisors):
      return simplifyDiv(term: term, divisors: divisors, zeroDiv: true, recursively: recursively)
    }
  }
}

// MARK: - Contains Variable

public extension WPTerm {
  func contains(variable: IRVariable) -> Bool {
    switch self {
    case .variable(let specifiedVariable):
      return specifiedVariable == variable
    case .integer, .double, .bool:
      return false
    case ._not(let wrapped), ._boolToInt(let wrapped):
      return wrapped.contains(variable: variable)
    case ._equal(lhs: let lhs, rhs: let rhs), ._lessThan(lhs: let lhs, rhs: let rhs), ._sub(lhs: let lhs, rhs: let rhs):
      return lhs.contains(variable: variable) || rhs.contains(variable: variable)
    case ._additionList(let additionList):
      return additionList.contains(variable: variable)
    case ._mul(terms: let terms):
      return terms.contains(where: { $0.contains(variable: variable) })
    case ._div(term: let term, divisors: let divisors):
      return term.contains(variable: variable) || divisors.contains(where: { $0.contains(variable: variable) })
    case ._zeroDiv(term: let term, divisors: let divisors):
      return term.contains(variable: variable) || divisors.contains(where: { $0.contains(variable: variable) })
    }
  }
}

// MARK: - Utility functions

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

public extension WPTerm {
  /// Convenience function to construct a term of the form `[variable = value]`
  static func probability(of variable: IRVariable, equalTo value: WPTerm) -> WPTerm {
    return .boolToInt(.equal(lhs: .variable(variable), rhs: value))
  }
  
  /// Convenience function to construct a term of the form `[variable = value]`
  static func probability(of variable: VariableOrValue, equalTo value: WPTerm) -> WPTerm {
    return .boolToInt(.equal(lhs: WPTerm(variable), rhs: value))
  }
}

// MARK: - Operators

infix operator ./.: MultiplicationPrecedence

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

public func ./.(lhs: WPTerm, rhs: WPTerm) -> WPTerm {
  return WPTerm.zeroDiv(lhs: lhs, rhs: rhs)
}
