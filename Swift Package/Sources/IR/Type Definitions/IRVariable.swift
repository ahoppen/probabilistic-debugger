/// The type a variable in the IR can have
public enum IRType: CustomStringConvertible {
  case int
  case bool
  
  public var description: String {
    switch self {
    case .int:
      return "int"
    case .bool:
      return "bool"
    }
  }
}

/// A variable in the IR
public struct IRVariable: Hashable, CustomStringConvertible {
  /// The name of the variable in the IR. Always starts with a `%`
  public let name: String
  /// The type of this variable
  public let type: IRType
  
  /// Create a new IR variable. `name` is automatically prepended with `%`
  public init(name: String, type: IRType) {
    self.name = "%\(name)"
    self.type = type
  }
  
  public static func queryVariable(type: IRType) -> IRVariable {
    return IRVariable(name: "$query", type: type)
  }
  
  public var description: String {
    return "\(type) \(name)"
  }
}
