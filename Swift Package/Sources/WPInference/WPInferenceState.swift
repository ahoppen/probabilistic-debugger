import IR
import IRExecution
import Utils

internal struct WPInferenceState: Hashable {
  /// WPInferenceState is a copy on write container for performance reasons. `Storage` stores the actual data of the struct.
  private class Storage: Hashable {
    var position: InstructionPosition
    var term: WPTerm
    var focusRate: WPTerm
    var observeAndDeliberateBranchIgnoringFocusRate: WPTerm
    var remainingLoopUnrolls: LoopUnrolls
    var branchingHistory: BranchingHistory
    var previousBlock: BasicBlockName?
    
    init(
      position: InstructionPosition,
      term: WPTerm,
      focusRate: WPTerm,
      observeAndDeliberateBranchIgnoringFocusRate: WPTerm,
      remainingLoopUnrolls: LoopUnrolls,
      branchingHistory: BranchingHistory,
      previousBlock: BasicBlockName?
    ) {
      self.position = position
      self.term = term
      self.focusRate = focusRate
      self.observeAndDeliberateBranchIgnoringFocusRate = observeAndDeliberateBranchIgnoringFocusRate
      self.remainingLoopUnrolls = remainingLoopUnrolls
      self.branchingHistory = branchingHistory
      self.previousBlock = previousBlock
    }
    
    init(_ other: Storage) {
      self.position = other.position
      self.term = other.term
      self.focusRate = other.focusRate
      self.observeAndDeliberateBranchIgnoringFocusRate = other.observeAndDeliberateBranchIgnoringFocusRate
      self.remainingLoopUnrolls = other.remainingLoopUnrolls
      self.branchingHistory = other.branchingHistory
      self.previousBlock = other.previousBlock
    }
    
    func hash(into hasher: inout Hasher) {
      position.hash(into: &hasher)
      term.hash(into: &hasher)
      focusRate.hash(into: &hasher)
      observeAndDeliberateBranchIgnoringFocusRate.hash(into: &hasher)
      remainingLoopUnrolls.hash(into: &hasher)
      branchingHistory.hash(into: &hasher)
    }
    
    static func ==(lhs: WPInferenceState.Storage, rhs: WPInferenceState.Storage) -> Bool {
      return lhs.position == rhs.position &&
        lhs.term == rhs.term &&
        lhs.focusRate == rhs.focusRate &&
        lhs.observeAndDeliberateBranchIgnoringFocusRate == rhs.observeAndDeliberateBranchIgnoringFocusRate &&
        lhs.remainingLoopUnrolls == rhs.remainingLoopUnrolls &&
        lhs.branchingHistory == rhs.branchingHistory
    }
  }
  
  // MARK: - Properties
  
  private var storage: Storage
  
  /// The position up to which WP-inference has run.
  /// This means that the instruction at this position **has already been inferred**.
  var position: InstructionPosition {
    get {
      return storage.position
    }
    set {
      if !isKnownUniquelyReferenced(&storage) {
        storage = Storage(storage)
      }
      storage.position = newValue
    }
  }
  
  /// The term that has been inferred so far up to this program position.
  var term: WPTerm {
    get {
      return storage.term
    }
    set {
      if !isKnownUniquelyReferenced(&storage) {
        storage = Storage(storage)
      }
      storage.term = newValue
    }
  }
  
  /// The rate of all potential runs on which this run is focused.
  /// This rate is being reduced by branches that are taken (both deliberate and not deliberate) as well as violated `observe` instructions. It will also be reduced by loops that are prematurely halted due to loop iteration bounds.
  var focusRate: WPTerm {
    get {
      return storage.focusRate
    }
    set {
      if !isKnownUniquelyReferenced(&storage) {
        storage = Storage(storage)
      }
      storage.focusRate = newValue
    }
  }
  
  /// The rate of all runs that were not lost due to loop iteration bounds.
  /// This value is similar to `focusRate` but does **not** get reduced by violated `observe` instructions or branches that are deliberate in the branching history.
  var observeAndDeliberateBranchIgnoringFocusRate: WPTerm {
    get {
      return storage.observeAndDeliberateBranchIgnoringFocusRate
    }
    set {
      if !isKnownUniquelyReferenced(&storage) {
        storage = Storage(storage)
      }
      storage.observeAndDeliberateBranchIgnoringFocusRate = newValue
    }
  }
  
  /// To allow WP-inference of loops without finding fixpoints for finding loop invariants, we unroll the loops up to a fixed number of iterations.
  /// The number of loop iterations to unrolled is usually estimated by doing a forward execution pass using sampling and determining the maximum number of iterations performed during the execution.
  /// During WP-inference, we take the `LoopUnrolls` taken during forward execution and count them backwards until we have unrolled the loop sufficiently often so we can exit it towards its predominator state.
  var remainingLoopUnrolls: LoopUnrolls {
    get {
      return storage.remainingLoopUnrolls
    }
    set {
      if !isKnownUniquelyReferenced(&storage) {
        storage = Storage(storage)
      }
      storage.remainingLoopUnrolls = newValue
    }
  }
  
  /// The deliberate branching choices that have not been taken care of yet. All of these must be taken care of before WP-inference reaches the top of the program.
  var branchingHistory: BranchingHistory {
    get {
      return storage.branchingHistory
    }
    set {
      if !isKnownUniquelyReferenced(&storage) {
        storage = Storage(storage)
      }
      storage.branchingHistory = newValue
    }
  }
  
  /// The name of the basic block from that was previously inferred. `nil` if no block was previously inferred.
  var previousBlock: BasicBlockName? {
    get {
      return storage.previousBlock
    }
    set {
      if !isKnownUniquelyReferenced(&storage) {
        storage = Storage(storage)
      }
      storage.previousBlock = newValue
    }
  }
  
  // MARK: - Initialization
  
  private init(
    position: InstructionPosition,
    term: WPTerm,
    focusRate: WPTerm,
    observeAndDeliberateBranchIgnoringFocusRate: WPTerm,
    remainingLoopUnrolls: LoopUnrolls,
    branchingHistory: BranchingHistory,
    previousBlock: BasicBlockName?
  ) {
    self.storage = Storage(
      position: position,
      term: term,
      focusRate: focusRate,
      observeAndDeliberateBranchIgnoringFocusRate: observeAndDeliberateBranchIgnoringFocusRate,
      remainingLoopUnrolls: remainingLoopUnrolls,
      branchingHistory: branchingHistory,
      previousBlock: previousBlock
    )
  }
  
  /// Create a state with which WP-inference can be started.
  init(
    initialInferenceStateAtPosition position: InstructionPosition,
    term: WPTerm,
    loopUnrolls: LoopUnrolls,
    branchingHistory: BranchingHistory
  ) {
    self.init(
      position: position,
      term: term,
      focusRate: .integer(1),
      observeAndDeliberateBranchIgnoringFocusRate: .integer(1),
      remainingLoopUnrolls: loopUnrolls,
      branchingHistory: branchingHistory,
      previousBlock: nil
    )
  }
  
  static func merged(states: [WPInferenceState], remainingLoopUnrolls: LoopUnrolls, branchingHistory: BranchingHistory) -> WPInferenceState? {
    guard let firstState = states.first else {
      return nil
    }
    
    assert(states.map(\.position).allEqual)
    
    return WPInferenceState(
      position: firstState.position,
      term: WPTerm.add(terms: states.map(\.term)),
      focusRate: WPTerm.add(terms: states.map(\.focusRate)),
      observeAndDeliberateBranchIgnoringFocusRate: WPTerm.add(terms: states.map(\.observeAndDeliberateBranchIgnoringFocusRate)),
      remainingLoopUnrolls: remainingLoopUnrolls,
      branchingHistory: branchingHistory,
      previousBlock: nil
    )
  }
  
  // MARK: - Updating the terms
  
  mutating func replace(variable: IRVariable, by replacementTerm: WPTerm) {
    self.updateTerms(term: true, focusRate: true, observeAndDeliberateBranchIgnoringFocusRate: true) {
      return $0.replacing(variable: variable, with: replacementTerm)
    }
  }
  
  mutating func updateTerms(term updateTerm: Bool, focusRate updatefocusRate: Bool, observeAndDeliberateBranchIgnoringFocusRate updateObserveAndDeliberateBranchIgnoringFocusRate: Bool, update: (WPTerm) -> WPTerm?) {
    if updateTerm, let updatedTerm = update(self.term) {
      self.term = updatedTerm
    }
    if updatefocusRate, let updatedfocusRate = update(self.focusRate) {
      self.focusRate = updatedfocusRate
    }
    if updateObserveAndDeliberateBranchIgnoringFocusRate, let updatedobserveAndDeliberateBranchIgnoringFocusRate = update(self.observeAndDeliberateBranchIgnoringFocusRate) {
      self.observeAndDeliberateBranchIgnoringFocusRate = updatedobserveAndDeliberateBranchIgnoringFocusRate
    }
  }
}
