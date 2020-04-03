public struct DebuggerError: Error {
  let message: String
  
  internal init(message: String) {
    self.message = message
  }
}
