/// A variable in the source code.
/// Until variable resolving, variable references only have a name and use the `UnresolvedVariable` type.
public struct Variable: Hashable, CustomDebugStringConvertible {
  public let id: Int
  public let name: String
  public let type: Type
  
  private static var nextUnusedId = 1
  
  public init(name: String, type: Type) {
    defer {
      Variable.nextUnusedId += 1
    }
    self.id = Variable.nextUnusedId
    self.name = name
    self.type = type
  }
  
  public var debugDescription: String {
    return "\(name) (\(type))"
  }
}

/// A variable that might not have been resolved yet. That is, we only know the name so far and haven't figured out which declaration it points to.
/// Once the variable has been resolved, the `resolved` case is being used.
public enum UnresolvedVariable: CustomDebugStringConvertible {
  /// We haven't resolved the variable yet, we only know its name
  case unresolved(name: String)
  /// The variable has been resolved
  case resolved(Variable)
  
  public var debugDescription: String {
    switch self {
    case .unresolved(name: let name):
      return "\(name) (unresolved)"
    case .resolved(variable: let variable):
      return variable.debugDescription
    }
  }
  
  /// Check if two `UnresolvedVariables` have the same state (resolved/unresolved) and the same name.
  /// Only for testing purposes.
  public func hasSameName(as other: UnresolvedVariable) -> Bool {
    switch (self, other) {
    case (.unresolved(let lhsName), .unresolved(name: let rhsName)):
      return lhsName == rhsName
    case (.resolved, .unresolved):
      return false
    case (.unresolved, .resolved):
      return false
    case (.resolved(variable: let lhsVar), .resolved(variable: let rhsVar)):
      return lhsVar.name == rhsVar.name
    }
  }
}
