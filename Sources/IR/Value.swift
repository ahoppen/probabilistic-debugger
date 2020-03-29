/// A variable or a constant
public enum Value: Equatable, CustomStringConvertible {
  case variable(IRVariable)
  case integer(Int)
  
  public var type: IRType {
    switch self {
    case .variable(let variable):
      return variable.type
    case .integer:
      return .int
    }
  }
  
  public var description: String {
    switch self {
    case .variable(let variable):
      return variable.description
    case .integer(let int):
      return "int \(int)"
    }
  }
}
