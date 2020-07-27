//
//  WPTerm+EquivalenceUsingSymPy.swift
//  
//
//  Created by Alex Hoppen on 18.06.20.
//

import Foundation

public extension WPTerm {
  /// Print the `WPTerm` in a way that is compatible with a Python expression for SymPy.
  /// Iverson brackets (i.e. `boolToInt`) cannot be represented in SymPy, so they are approximated by a free variable.
  /// `variableNameMap` collects the variable names that SymPy uses for IRVariables and the iverson brackets that are approximated by free variables as described above.
  fileprivate func descriptionForSymPy(variableNameMap: inout [WPTerm: Int]) -> String {
    func getOrGenerateVariableName(for term: WPTerm) -> String {
      if variableNameMap[term] == nil {
        let newVariableNumber = (variableNameMap.values.max() ?? 0) + 1
        variableNameMap[term] = newVariableNumber
      }
      return "var\(variableNameMap[term]!)"
    }
    
    switch self {
    case .variable:
      return getOrGenerateVariableName(for: self)
    case .integer(let value):
      return value.description
    case .double(let value):
      return value.description
    case .bool, ._not, ._equal, ._lessThan:
      fatalError("Should not be reachable sind boolToInt should have been converted to a variable")
    case ._boolToInt:
      return getOrGenerateVariableName(for: self)
    case ._additionList(let additionList):
      var stringifiedEntries = [String]()
      for entry in additionList.entries {
        var string = "\(entry.factor)"
        for condition in entry.conditions {
          string += " * " + getOrGenerateVariableName(for: .boolToInt(condition))
        }
        string += " * (\(entry.term.descriptionForSymPy(variableNameMap: &variableNameMap)))"
        stringifiedEntries.append(string)
      }
      return stringifiedEntries.joined(separator: " + ")
    case ._sub(lhs: let lhs, rhs: let rhs):
      return [lhs, rhs].map({ "(\($0.descriptionForSymPy(variableNameMap: &variableNameMap)))" }).joined(separator: " - ")
    case ._mul(terms: let terms):
      return terms.map({ "(\($0.descriptionForSymPy(variableNameMap: &variableNameMap)))" }).joined(separator: " * ")
    case ._div(term: let term, divisors: let divisors):
      return ([term] + divisors).map({ "(\($0.descriptionForSymPy(variableNameMap: &variableNameMap)))" }).joined(separator: " / ")
    case ._zeroDiv(term: let term, divisors: let divisors):
      return ([term] + divisors).map({ "(\($0.descriptionForSymPy(variableNameMap: &variableNameMap)))" }).joined(separator: " / ")
    }
  }
  
  func equalsUsingSymPy(_ other: WPTerm) -> Bool {
    return WPTermSymPyComparisonEngine.instance.equal(lhs: self, rhs: other)
  }
}

fileprivate struct WPTermPair: Hashable {
  let lhs: WPTerm
  let rhs: WPTerm
}

fileprivate class WPTermSymPyComparisonEngine {
  private let pythonProcess: Process
  private let stdOutPipe: Pipe
  private let stdErrPipe: Pipe
  private let stdInPipe: Pipe
  
  private var cache: [WPTermPair: Bool] = [:]
  
  public static var instance = WPTermSymPyComparisonEngine()
  
  private init() {
    // Start a long-running Python process which we can feed our queries.
    // This is more efficient than starting a new Python process for every query because the SymPy library needs fairly long to initialise (~500ms whereas queries only take ~50ms).
    pythonProcess = Process()
    stdOutPipe = Pipe()
    stdErrPipe = Pipe()
    stdInPipe = Pipe()
    pythonProcess.standardOutput = stdOutPipe
    pythonProcess.standardError = stdErrPipe
    pythonProcess.standardInput = stdInPipe
    
    let pythonCode = """
    from sympy import *
    import sys
    
    for line in sys.stdin:
      exec(line)
      sys.stdout.flush()
    """
    
    pythonProcess.launchPath = "/usr/local/bin/python3"
    pythonProcess.arguments = ["-c", pythonCode]
    pythonProcess.launch()
  }
  
  @discardableResult
  private func exec(_ command: String, resultLength: Int) -> String {
    stdInPipe.fileHandleForWriting.write((command + "\n").data(using: .utf8)!)
    let data = stdOutPipe.fileHandleForReading.readData(ofLength: resultLength)
    return String(data: data, encoding: .utf8)!
  }

  fileprivate func equal(lhs: WPTerm, rhs: WPTerm) -> Bool {
    if let cacheHit = cache[WPTermPair(lhs: lhs, rhs: rhs)] {
      return cacheHit
    }
    var variableNameMap: [WPTerm: Int] = [:]
    let lhsTermForSymPy = lhs.descriptionForSymPy(variableNameMap: &variableNameMap)
    let rhsTermForSymPy = rhs.descriptionForSymPy(variableNameMap: &variableNameMap)
    let varNames = (1...(variableNameMap.values.max() ?? 0)).map({ "var\($0)" })
    
    exec("\(varNames.joined(separator: ", ")) = symbols('\(varNames.joined(separator: " "))')", resultLength: 0)
    exec("lhsEq = \(lhsTermForSymPy)", resultLength: 0)
    exec("rhsEq = \(rhsTermForSymPy)", resultLength: 0)
    let output = exec("print(1 if simplify(Eq(lhsEq, rhsEq)) == True else 0)", resultLength: 2)
    
    let result = (output == "1\n")
    cache[WPTermPair(lhs: lhs, rhs: rhs)] = result
    return result
  }
}
