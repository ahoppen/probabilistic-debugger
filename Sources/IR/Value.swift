/// A variable or a constant
public enum Value: Equatable, CustomStringConvertible {
  case variable(IRVariable)
  case integer(Int)
  
  /// If the value is a variable, rename it to the new variable. For constants, return self.
  func renaming(variable: IRVariable, to newVariable: IRVariable) -> Value {
    switch self {
    case .variable(let selfVariable) where selfVariable == variable:
      return .variable(newVariable)
    default:
      return self
    }
  }
  
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
