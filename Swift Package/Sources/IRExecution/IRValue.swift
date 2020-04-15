import IR

public enum IRValue: Hashable, Comparable, CustomStringConvertible {
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
  
  public static func < (lhs: IRValue, rhs: IRValue) -> Bool {
    switch (lhs, rhs) {
    case (.integer(let lhsValue), .integer(let rhsValue)):
      return lhsValue < rhsValue
    case (.bool(let lhsValue), .bool(let rhsValue)):
      switch (lhsValue, rhsValue) {
      case (false, true):
        return true
      case (true, false):
        return false
      case (true, true), (false, false):
        return false
      }
    default:
      // Values are not comparable
      return false
    }
  }
}
