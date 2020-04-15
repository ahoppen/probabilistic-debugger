/// The position of an instruction in a given program
public struct InstructionPosition: CustomStringConvertible, Hashable {
  /// The basic block in which the referenced instruction resides
  public let basicBlock: BasicBlockName
  
  /// The index of the instruction inside the basic block
  public let instructionIndex: Int
  
  public init(basicBlock: BasicBlockName, instructionIndex: Int) {
    self.basicBlock = basicBlock
    self.instructionIndex = instructionIndex
  }
  
  public var description: String {
    return "\(basicBlock).\(instructionIndex)"
  }
}
