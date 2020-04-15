import Foundation

public struct DebuggerError: LocalizedError {
  public let message: String
  
  internal init(message: String) {
    self.message = message
  }
  
  public var errorDescription: String? {
    return message
  }
}
