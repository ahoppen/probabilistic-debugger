import IR

public enum IRValue: Hashable, CustomStringConvertible {
  case integer(Int)
  case bool(Bool)
  
  public var type: IRType {
    switch self {
    case .integer:
      return .int
    case .bool:
      return .bool
    }
  }
  
  public var integerValue: Int? {
    switch self {
    case .integer(let value):
      return value
    default:
      return nil
    }
  }
  
  public var boolValue: Bool? {
    switch self {
    case .bool(let value):
      return value
    default:
      return nil
    }
  }
  
  public var description: String {
    switch self {
    case .integer(let value):
      return value.description
    case .bool(let value):
      return value.description
    }
  }
}