/// A variable or a constant
public enum VariableOrValue: Equatable, CustomStringConvertible {
  case variable(IRVariable)
  case integer(Int)
  case bool(Bool)
  
  /// If the value is a variable, rename it to the new variable. For constants, return self.
  func renaming(variable: IRVariable, to newVariable: IRVariable) -> VariableOrValue {
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
    case .bool:
      return .bool
    }
  }
  
  public var description: String {
    switch self {
    case .variable(let variable):
      return variable.description
    case .integer(let int):
      return "int \(int)"
    case .bool(let bool):
      return "bool \(bool)"
    }
  }
}
