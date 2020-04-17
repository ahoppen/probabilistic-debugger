/// An execution loop in an IR program, characterised by the basic block that contains the condition and the block that starts the loop's body.
public struct IRLoop: Hashable {
  public let conditionBlock: BasicBlockName
  public let bodyStartBlock: BasicBlockName
  
  public init(conditionBlock: BasicBlockName, bodyStartBlock: BasicBlockName) {
    self.conditionBlock = conditionBlock
    self.bodyStartBlock = bodyStartBlock
  }
}
