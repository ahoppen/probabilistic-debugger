import IR

internal struct WPInferenceState {
  /// WPInferenceState is a copy on write container for performance reasons. `Storage` stores the actual data of the struct.
  private class Storage {
    var position: InstructionPosition
    var term: WPTerm
    var runsWithSatisifiedObserves: WPTerm
    var runsNotCutOffByLoopIterationBounds: WPTerm
    var remainingLoopUnrolls: [LoopingBranch: LoopUnrolling]
    
    init(
      position: InstructionPosition,
      term: WPTerm,
      runsWithSatisifiedObserves: WPTerm,
      runsNotCutOffByLoopIterationBounds: WPTerm,
      remainingLoopUnrolls: [LoopingBranch: LoopUnrolling]
    ) {
      self.position = position
      self.term = term
      self.runsWithSatisifiedObserves = runsWithSatisifiedObserves
      self.runsNotCutOffByLoopIterationBounds = runsNotCutOffByLoopIterationBounds
      self.remainingLoopUnrolls = remainingLoopUnrolls
    }
    
    init(_ other: Storage) {
      self.position = other.position
      self.term = other.term
      self.runsWithSatisifiedObserves = other.runsWithSatisifiedObserves
      self.runsNotCutOffByLoopIterationBounds = other.runsNotCutOffByLoopIterationBounds
      self.remainingLoopUnrolls = other.remainingLoopUnrolls
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
  
  /// A term that after full inference determines the fraction of all runs that satisfies all observes in the program.
  /// This is a normalization term that boost the sum of the probability distribution up to 1 again after samples have been lost through `observe`s.
  var runsWithSatisifiedObserves: WPTerm {
    get {
      return storage.runsWithSatisifiedObserves
    }
    set {
      if !isKnownUniquelyReferenced(&storage) {
        storage = Storage(storage)
      }
      storage.runsWithSatisifiedObserves = newValue
    }
  }
  
  /// A term that after full inference determines the fraction of all runs that were not discareded because we bounded the number of loop iterations.
  /// If using `runsWithSatisifiedObserves` as a normalization factor, we always end up at a probability sum of `1`.
  /// If we have discarded runs because of the maximum number of loop iterations, we don't, however, want to end up at a probability sum of `1` but want to explicitly state which percentag of all runs was not considered.
  /// Hence this normalization term pushes the probability sum down below `1` again if runs were discared.
  /// The final normalized value is determined by `term / runsWithSatisfiedObserves * runsNotCutOffByLoopIterationBounds`
  var runsNotCutOffByLoopIterationBounds: WPTerm {
    get {
      return storage.runsNotCutOffByLoopIterationBounds
    }
    set {
      if !isKnownUniquelyReferenced(&storage) {
        storage = Storage(storage)
      }
      storage.runsNotCutOffByLoopIterationBounds = newValue
    }
  }
  
  /// To allow WP-inference of loops without finding fixpoints for finding loop invariants, we unroll the loops to
  /// This dictionary keeps track of how many iterations we have left in each loop before aborting WP-inference.
  var remainingLoopUnrolls: [LoopingBranch: LoopUnrolling] {
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
  
  // MARK: - Initialization
  
  init(position: InstructionPosition, term: WPTerm, runsWithSatisifiedObserves: WPTerm, runsNotCutOffByLoopIterationBounds: WPTerm, remainingLoopUnrolls: [LoopingBranch: LoopUnrolling]) {
    self.storage = Storage(
      position: position,
      term: term,
      runsWithSatisifiedObserves: runsWithSatisifiedObserves,
      runsNotCutOffByLoopIterationBounds: runsNotCutOffByLoopIterationBounds,
      remainingLoopUnrolls: remainingLoopUnrolls
    )
  }
  
  // MARK: - Mutating the state
  
  mutating func replace(variable: IRVariable, by replacementTerm: WPTerm) {
    self.updateTerms({
      return $0.replacing(variable: variable, with: replacementTerm)
    })
  }
  
  mutating func updateTerms(keepingRunsNotCutOffByLoopIterationBounds: Bool = false, _ update: (WPTerm) -> WPTerm) {
    self.term = update(term).simplified
    self.runsWithSatisifiedObserves = update(runsWithSatisifiedObserves).simplified
    self.runsNotCutOffByLoopIterationBounds =  keepingRunsNotCutOffByLoopIterationBounds ? runsNotCutOffByLoopIterationBounds : update(runsNotCutOffByLoopIterationBounds).simplified
  }
  
  // MARK: - Non-mutating update funtions
  
  func replacing(variable: IRVariable, by replacementTerm: WPTerm) -> WPInferenceState {
    return self.updatingTerms({
      return $0.replacing(variable: variable, with: replacementTerm)
    })
  }
  
  func updatingTerms(keepingRunsNotCutOffByLoopIterationBounds: Bool = false, _ update: (WPTerm) -> WPTerm) -> WPInferenceState {
    var modifiedState = self
    modifiedState.updateTerms(keepingRunsNotCutOffByLoopIterationBounds: keepingRunsNotCutOffByLoopIterationBounds, update)
    return modifiedState
  }
  
  func withPosition(_ newPosition: InstructionPosition) -> WPInferenceState {
    var modifiedState = self
    modifiedState.position = newPosition
    return modifiedState
  }
  
  func withRemainingLoopUnrolls(_ remainingLoopUnrolls: [LoopingBranch: LoopUnrolling]) -> WPInferenceState {
    var modifiedState = self
    modifiedState.remainingLoopUnrolls = remainingLoopUnrolls
    return modifiedState
  }
}
