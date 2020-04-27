// MARK: - IR Program

public class IRProgram: Equatable, CustomStringConvertible {
  public let basicBlocks: [BasicBlockName: BasicBlock]
  public let startBlock: BasicBlockName
  
  /// Create a new IR program that consists of the given basic blocks and verify that it is syntactically correct.
  public init(startBlock: BasicBlockName, basicBlocks: [BasicBlock]) {
    self.startBlock = startBlock
    self.basicBlocks = Dictionary(uniqueKeysWithValues: zip(basicBlocks.map(\.name), basicBlocks))
    assert(self.basicBlocks[startBlock] != nil)
    
    IRVerifier.verify(ir: self)
  }
  
  /// Returns the instruction at the given `position` or `nil` if the program does not have an instruction at this position.
  public func instruction(at position: InstructionPosition) -> Instruction? {
    guard let block = self.basicBlocks[position.basicBlock], block.instructions.count > position.instructionIndex else {
      return nil
    }
    return block.instructions[position.instructionIndex]
  }
  
  public var description: String {
    return basicBlocks.values.sorted(by: { $0.name < $1.name }).map(\.description).joined(separator: "\n\n")
  }
  
  public static func == (lhs: IRProgram, rhs: IRProgram) -> Bool {
    return lhs.basicBlocks == rhs.basicBlocks && lhs.startBlock == rhs.startBlock
  }
 
  // MARK: - Analysis results
  // These could be cached if computation is a performance bottleneck

  private var _directPredecessors: [BasicBlockName: Set<BasicBlockName>]? = nil
  public var directPredecessors: [BasicBlockName: Set<BasicBlockName>] {
    if _directPredecessors == nil {
      _directPredecessors = IRAnalysis.directPredecessors(basicBlocks: basicBlocks.values)
    }
    return _directPredecessors!
  }
  
  private var _transitivePredecessors: [BasicBlockName: Set<BasicBlockName>]? = nil
  public var transitivePredecessors: [BasicBlockName: Set<BasicBlockName>] {
    if _transitivePredecessors == nil {
      _transitivePredecessors = IRAnalysis.transitivePredecessors(directPredecessors: directPredecessors)
    }
    return _transitivePredecessors!
  }
  
  private var _loops: Set<[BasicBlockName]>? = nil
  public var loops: Set<[BasicBlockName]> {
    if _loops == nil {
      _loops = IRAnalysis.loops(directSuccessors: directSuccessors)
    }
    return _loops!
  }
  
  private var _directSuccessors: [BasicBlockName: Set<BasicBlockName>]? = nil
  public var directSuccessors: [BasicBlockName: Set<BasicBlockName>] {
    if _directSuccessors == nil {
      _directSuccessors = IRAnalysis.directSuccessors(basicBlocks: basicBlocks.values)
    }
    return _directSuccessors!
  }
  
  private var _predominators: [BasicBlockName: Set<BasicBlockName>]? = nil
  public var predominators: [BasicBlockName: Set<BasicBlockName>] {
    if _predominators == nil {
      _predominators = IRAnalysis.predominators(directPredecessors: directPredecessors, startBlock: startBlock)
    }
    return _predominators!
  }
  
  private var _postdominators: [BasicBlockName: Set<BasicBlockName>]? = nil
  public var postdominators: [BasicBlockName: Set<BasicBlockName>] {
    if _postdominators == nil {
      _postdominators = IRAnalysis.postdominators(directSuccessors: directSuccessors, startBlock: startBlock)
    }
    return _postdominators!
  }
  
  private var _properPredominators: [BasicBlockName: Set<BasicBlockName>]? = nil
  public var properPredominators: [BasicBlockName: Set<BasicBlockName>] {
    if _properPredominators == nil {
      _properPredominators = IRAnalysis.properDominators(dominators: predominators)
    }
    return _properPredominators!
  }
  
  private var _properPostdominators: [BasicBlockName: Set<BasicBlockName>]? = nil
  public var properPostdominators: [BasicBlockName: Set<BasicBlockName>] {
    if _properPostdominators == nil {
      _properPostdominators = IRAnalysis.properDominators(dominators: postdominators)
    }
    return _properPostdominators!
  }
  
  private var _immediatePostdominator: [BasicBlockName: BasicBlockName?]?
  public var immediatePostdominator: [BasicBlockName: BasicBlockName?] {
    if _immediatePostdominator == nil {
      _immediatePostdominator = IRAnalysis.immediateDominator(properDominators: properPostdominators)
    }
    return _immediatePostdominator!
  }
  
  private var _loopInducingBlocks: Set<BasicBlockName>?
  public var loopInducingBlocks: Set<BasicBlockName> {
    if _loopInducingBlocks == nil {
      _loopInducingBlocks = IRAnalysis.loopInducingBlocks(properPredominators: properPredominators, transitivePredecessors: transitivePredecessors)
    }
    return _loopInducingBlocks!
  }
}

// MARK: - Utility functions

public extension IRProgram {
  /// The position of the (only) return instruction in the program
  var returnPosition: InstructionPosition {
    for basicBlock in self.basicBlocks.values {
      for (instructionIndex, instruction) in basicBlock.instructions.enumerated() {
        if instruction is ReturnInstruction {
          return InstructionPosition(basicBlock: basicBlock.name, instructionIndex: instructionIndex)
        }
      }
    }
    fatalError("Could not find a ReturnInstruction in the program")
  }
}
