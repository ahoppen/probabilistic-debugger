import IR
import IRExecution

internal struct WPInferenceState: Hashable {
  /// WPInferenceState is a copy on write container for performance reasons. `Storage` stores the actual data of the struct.
  private class Storage: Hashable {
    var position: InstructionPosition
    var term: WPTerm
    var observeSatisfactionRate: WPTerm
    var focusRate: WPTerm
    var intentionalLossRate: WPTerm
    var generateLostStatesForBlocks: Set<BasicBlockName>
    var remainingLoopUnrolls: LoopUnrolls
    var branchingHistories: [BranchingHistory]
    
    init(
      position: InstructionPosition,
      term: WPTerm,
      observeSatisfactionRate: WPTerm,
      focusRate: WPTerm,
      intentionalLossRate: WPTerm,
      generateLostStatesForBlocks: Set<BasicBlockName>,
      remainingLoopUnrolls: LoopUnrolls,
      branchingHistories: [BranchingHistory]
    ) {
      self.position = position
      self.term = term
      self.observeSatisfactionRate = observeSatisfactionRate
      self.focusRate = focusRate
      self.intentionalLossRate = intentionalLossRate
      self.generateLostStatesForBlocks = generateLostStatesForBlocks
      self.remainingLoopUnrolls = remainingLoopUnrolls
      self.branchingHistories = branchingHistories
    }
    
    init(_ other: Storage) {
      self.position = other.position
      self.term = other.term
      self.observeSatisfactionRate = other.observeSatisfactionRate
      self.focusRate = other.focusRate
      self.intentionalLossRate = other.intentionalLossRate
      self.generateLostStatesForBlocks = other.generateLostStatesForBlocks
      self.remainingLoopUnrolls = other.remainingLoopUnrolls
      self.branchingHistories = other.branchingHistories
    }
    
    func hash(into hasher: inout Hasher) {
      position.hash(into: &hasher)
      term.hash(into: &hasher)
      observeSatisfactionRate.hash(into: &hasher)
      focusRate.hash(into: &hasher)
      intentionalLossRate.hash(into: &hasher)
      generateLostStatesForBlocks.hash(into: &hasher)
      remainingLoopUnrolls.hash(into: &hasher)
      branchingHistories.hash(into: &hasher)
    }
    
    static func ==(lhs: WPInferenceState.Storage, rhs: WPInferenceState.Storage) -> Bool {
      return lhs.position == rhs.position &&
        lhs.term == rhs.term &&
        lhs.observeSatisfactionRate == rhs.observeSatisfactionRate &&
        lhs.focusRate == rhs.focusRate &&
        lhs.intentionalLossRate == rhs.intentionalLossRate &&
        lhs.generateLostStatesForBlocks == rhs.generateLostStatesForBlocks &&
        lhs.remainingLoopUnrolls == rhs.remainingLoopUnrolls &&
        lhs.branchingHistories == rhs.branchingHistories
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
  
  /// The rate of all potential runs for which all observe instructions have been satisified.
  /// Dividing this by the `focusRate` gives the proportion of runs that satisfied all observes relative to the runs that this inference state is focused on.
  var observeSatisfactionRate: WPTerm {
    get {
      return storage.observeSatisfactionRate
    }
    set {
      if !isKnownUniquelyReferenced(&storage) {
        storage = Storage(storage)
      }
      storage.observeSatisfactionRate = newValue
    }
  }
  
  /// The rate of all potential runs on which this run is focused.
  /// The `focusRate` is not reduced if an `observe` is violated.
  /// When forking WP-inference at a branching point, two `WPInferenceStates` are created, each with a reduced `focusRate`. The sum of the two `focusRate`s is the `focusRate` before branching.
  /// Some `focusRate` is lost when limiting the number of loop iterations and reaching the upper iteration limit.
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
  
  /// The proportion of all possible runs that were intentionally lost due du deliberate branching choices.
  /// In practice, this is either equal to `focusRate` or `0`.
  var intentionalLossRate: WPTerm {
    get {
      return storage.intentionalLossRate
    }
    set {
      if !isKnownUniquelyReferenced(&storage) {
        storage = Storage(storage)
      }
      storage.intentionalLossRate = newValue
    }
  }
  
  /// Blocks for which lost states should be created if a branch into them is being taken.
  /// 
  /// When infering from the last instruction in a program, we can always expect that both the false and the true branch of a branch instruction will be tried.
  /// Should we have focused on one of the branches, the other branch will generate the `intentionalLossRate` when being tried.
  /// If the instruction until which inference should be run is, however, inside e.g. the true branch already, we will never try the false branch and thus create lost states for it.
  /// To fix this issue, such block can be listed in `generateLostStatesForBlocks` and every time a `true` branch into this block is taken, the lost states corresponding `false` branch will be automatically synthesized.
  var generateLostStatesForBlocks: Set<BasicBlockName> {
    get {
      return storage.generateLostStatesForBlocks
    }
    set {
      if !isKnownUniquelyReferenced(&storage) {
        storage = Storage(storage)
      }
      storage.generateLostStatesForBlocks = newValue
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
  var branchingHistories: [BranchingHistory] {
    get {
      return storage.branchingHistories
    }
    set {
      if !isKnownUniquelyReferenced(&storage) {
        storage = Storage(storage)
      }
      storage.branchingHistories = newValue
    }
  }
  
  // MARK: - Initialization
  
  init(position: InstructionPosition, term: WPTerm, observeSatisfactionRate: WPTerm, focusRate: WPTerm, intentionalLossRate: WPTerm, generateLostStatesForBlocks: Set<BasicBlockName>, remainingLoopUnrolls: LoopUnrolls, branchingHistories: [BranchingHistory]) {
    self.storage = Storage(
      position: position,
      term: term,
      observeSatisfactionRate: observeSatisfactionRate,
      focusRate: focusRate,
      intentionalLossRate: intentionalLossRate,
      generateLostStatesForBlocks: generateLostStatesForBlocks,
      remainingLoopUnrolls: remainingLoopUnrolls,
      branchingHistories: branchingHistories
    )
  }
  
  static func merged(states: [WPInferenceState], remainingLoopUnrolls: LoopUnrolls, branchingHistories: [BranchingHistory]) -> WPInferenceState? {
    guard let firstState = states.first else {
      return nil
    }
    
    assert(states.map(\.generateLostStatesForBlocks).allEqual)
    assert(states.map(\.position).allEqual)
    assert(states.map(\.generateLostStatesForBlocks).allEqual)
    
    return WPInferenceState(
      position: firstState.position,
      term: WPTerm.add(terms: states.map(\.term)),
      observeSatisfactionRate: WPTerm.add(terms: states.map(\.observeSatisfactionRate)),
      focusRate: WPTerm.add(terms: states.map(\.focusRate)),
      intentionalLossRate: WPTerm.add(terms: states.map(\.intentionalLossRate)),
      generateLostStatesForBlocks: firstState.generateLostStatesForBlocks,
      remainingLoopUnrolls: remainingLoopUnrolls,
      branchingHistories: branchingHistories
    )
  }
  
  // MARK: - Mutating the state
  
  mutating func replace(variable: IRVariable, by replacementTerm: WPTerm) {
    self.updateTerms(term: true, observeSatisfactionRate: true, focusRate: true, intentionalLossRate: true) {
      return $0.replacing(variable: variable, with: replacementTerm)
    }
  }
  
  mutating func updateTerms(term updateTerm: Bool, observeSatisfactionRate updateObserveSatisfactionRate: Bool, focusRate updateFocusRate: Bool, intentionalLossRate updateIntentionalLossRate: Bool, update: (WPTerm) -> WPTerm?) {
    if updateTerm, let updatedTerm = update(self.term) {
      self.term = updatedTerm
    }
    if updateObserveSatisfactionRate, let updatedObserveSatisfactionRate = update(self.observeSatisfactionRate) {
      self.observeSatisfactionRate = updatedObserveSatisfactionRate
    }
    if updateFocusRate, let updatedFocusRate = update(self.focusRate) {
      self.focusRate = updatedFocusRate
    }
    if updateIntentionalLossRate, let updatedIntentionalLossRate = update(self.intentionalLossRate) {
      self.intentionalLossRate = updatedIntentionalLossRate
    }
  }
  
  // MARK: - Non-mutating update funtions
  
  func replacing(variable: IRVariable, by replacementTerm: WPTerm) -> WPInferenceState {
    var modifiedState = self
    modifiedState.replace(variable: variable, by: replacementTerm)
    return modifiedState
  }
  
  func updatingTerms(term: Bool, observeSatisfactionRate: Bool, focusRate: Bool, intentionalLossRate: Bool, update: (WPTerm) -> WPTerm) -> WPInferenceState {
    var modifiedState = self
    modifiedState.updateTerms(term: term, observeSatisfactionRate: observeSatisfactionRate, focusRate: focusRate, intentionalLossRate: intentionalLossRate, update: update)
    return modifiedState
  }
  
  func withPosition(_ newPosition: InstructionPosition) -> WPInferenceState {
    var modifiedState = self
    modifiedState.position = newPosition
    return modifiedState
  }
  
  func withRemainingLoopUnrolls(_ remainingLoopUnrolls: LoopUnrolls) -> WPInferenceState {
    var modifiedState = self
    modifiedState.remainingLoopUnrolls = remainingLoopUnrolls
    return modifiedState
  }
  
  func withBranchingHistories(_ branchingHistories: [BranchingHistory]) -> WPInferenceState {
    var modifiedState = self
    modifiedState.branchingHistories = branchingHistories
    return modifiedState
  }
}
