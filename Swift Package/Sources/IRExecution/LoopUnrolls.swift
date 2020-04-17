import IR

/// Keeps track of how many times a loop has been unrolled (which is equivalent to the number of times the loop has been traversed during forward execution) in a given program.
/// For deterministic program, each loop is unrolled a fixed number of times.
/// For probabilistic programs, the number of loop unrolls is not clearly defined and a loop can be simultaneously unrolled e.g. 1, 2 and 3 times because there are execution branches that iterate the loop exactly this number of times
public struct LoopUnrolls: CustomStringConvertible {
  private let context: [IRLoop: LoopUnrollEntry]
  
  /// The loops for which the number of unrolls is known
  public var loops: Dictionary<IRLoop, LoopUnrollEntry>.Keys {
    return context.keys
  }
  
  // MARK: Initialization
  
  /// Create a new `LoopUnrolls` in which the given `loops` have not been unrolled at all.
  public init(noIterationsForLoops loops: [IRLoop]) {
    var context: [IRLoop: LoopUnrollEntry] = [:]
    for loop in loops {
      assert(!context.keys.contains(where: { $0.conditionBlock == loop.conditionBlock }), "Cannot have two loops with the same condition block")
      context[loop] = [0]
    }
    self.context = context
  }
  
  public init(_ context: [IRLoop: LoopUnrollEntry]) {
    self.context = context
  }
  
  public static func merged<SequenceType: Sequence>(_ contexts: SequenceType) -> LoopUnrolls where SequenceType.Element == LoopUnrolls {
    var mergedContext: [IRLoop: LoopUnrollEntry] = [:]
    for contextToMerge in contexts {
      mergedContext.merge(contextToMerge.context, uniquingKeysWith: { (lhs, rhs) -> LoopUnrollEntry in
        return lhs + rhs
      })
    }
    return LoopUnrolls(mergedContext)
  }
  
  // MARK: Querying for loop unrolls
  
  public subscript(conditionBlock conditionBlock: BasicBlockName) -> LoopUnrollEntry? {
    let unrollsWithThisConditionBlock = context.filter({ $0.key.conditionBlock == conditionBlock })
    assert(unrollsWithThisConditionBlock.count <= 1)
    return unrollsWithThisConditionBlock.first?.value
  }
  
  public subscript(loop: IRLoop) -> LoopUnrollEntry? {
    return context[loop]
  }
  
  // MARK: Modifying the context
  
  /// During forward execution, record that the branch from the `loop`'s condition block to the `loop`'s body has been taken, increasing the loop unrolling for this loop by 1.
  /// If no loop is being tracked at `loop`, this operation does nothing.
  public func recordingJumpToBodyBlock(for loop: IRLoop) -> LoopUnrolls {
    if let currentUnrolls = self[loop] {
      var newContext = self.context
      newContext[loop] = currentUnrolls.increased()
      return LoopUnrolls(newContext)
    } else {
      return self
    }
  }
  
  /// During WP-inference (backwards execution), record that the `loop`'s body has been traversed once, decreasing the number of loop unrolls by 1.
  /// If no loop is being tracked at `loop`, this operation does nothing
  public func recordingTraversalOfUnrolledLoopBody(_ loop: IRLoop) -> LoopUnrolls {
    if let currentUnrolls = self[loop] {
      var newContext = self.context
      newContext[loop] = currentUnrolls.decreased()
      return LoopUnrolls(newContext)
    } else {
      return self
    }
  }
  
  public func settingLoopUnrolls(for loop: IRLoop, unrolls: LoopUnrollEntry) -> LoopUnrolls {
    var newContext = self.context
    newContext[loop] = unrolls
    return LoopUnrolls(newContext)
  }
  
  public var description: String {
    return context.sorted(by: { $0.key.conditionBlock < $1.key.conditionBlock }).map({ (key, unrolling) in
      return "\(key.conditionBlock) -> \(key.bodyStartBlock): \(unrolling)"
    }).joined(separator: "\n")
  }
}

/// For a given loop, keeps track of how many times the loop has been unrolled
public struct LoopUnrollEntry: Equatable, CustomStringConvertible, ExpressibleByArrayLiteral {
  public typealias ArrayLiteralElement = Int
  
  private let unrolls: Set<Int>
  
  // MARK: Initialization
  
  public init(arrayLiteral elements: Int...) {
    unrolls = Set(elements)
    assert(!unrolls.isEmpty)
  }
  
  public init<SequenceType: Sequence>(_ sequence: SequenceType) where SequenceType.Element == Int {
    unrolls = Set(sequence)
    assert(!unrolls.isEmpty)
  }
  
  // MARK: Querying if unrolls are possible
  
  /// During WP-inference (backwards execution), check if the loop has been unrolled sufficiently often that we can leave the loop to it predominator block.
  public var canStopUnrolling: Bool {
    return unrolls.contains(0)
  }
  
  /// During WP-inference (backwards execution), check if we can traverse the loop's body once more.
  public var canUnrollOnceMore: Bool {
    return unrolls.contains(where: { $0 > 0 })
  }
  
  public var max: Int {
    return unrolls.max()!
  }
  
  // MARK: Increasing and decreasing the counts
  
  fileprivate func increased() -> LoopUnrollEntry {
    return LoopUnrollEntry(unrolls.map({ $0 + 1 }))
  }
  
  fileprivate func decreased() -> LoopUnrollEntry {
    return LoopUnrollEntry(unrolls.map({ $0 - 1 }).filter({ $0 >= 0 }))
  }
  
  // MARK: Miscellaneous
  
  public var description: String {
    return unrolls.sorted().description
  }
  
  public static func +(lhs: LoopUnrollEntry, rhs: LoopUnrollEntry) -> LoopUnrollEntry {
    return LoopUnrollEntry(lhs.unrolls.union(rhs.unrolls))
  }
}

