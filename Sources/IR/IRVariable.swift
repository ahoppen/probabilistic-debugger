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

public struct IRVariable: Equatable, CustomStringConvertible {
  public let name: String
  public let type: IRType
  
  public init(name: String, type: IRType) {
    self.name = "%\(name)"
    self.type = type
  }
  
  public var description: String {
    return "\(type) \(name)"
  }
}
