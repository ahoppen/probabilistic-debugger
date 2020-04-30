import IR
import Utils

struct WPSlicingState: Hashable {
  // MARK: The current state's terms
  
  /// The (updated) term for which a program slice is being computed. Similar to `term` in `WPInferenceState`-
  private(set) var term: WPTerm
  
  /// The following properties match the values of the parent `WPInferenceState`
  private(set) var observeSatisfactionRate: WPTerm
  private(set) var focusRate: WPTerm
  private(set) var intentionalLossRate: WPTerm
  
  // MARK: Keeping track of influencing positions and dependencies
  
  /// For each result term (as built using the `buildResultTerm` function), a set of instructions that influence this term.
  /// When we encounter a new result term, we add it to the list.
  /// Should we encounter a result term that we have seen before, we know that the intermediat instructions didn't have an affect on the result term and thus don't need to be considered influencing.
  private(set) var influencingInstructionsForTerms: [WPTerm: Set<InstructionPosition>]
  
  /// Control flow points that might have influenced the value of resultTerm.
  /// Whenever a branching point is encountered, the current result term is recorded.
  /// The branch point was relevant if WP-inference had different values for two WP inference states when they were merged again at a branching point.
  /// Thus, at the end of WP-inference, all positions with more than one resultTerm had an influence on the resultTerm
  private(set) var potentialControlFlowDependencies: [InstructionPosition: Set<WPTerm>]
  
  /// For each control flow position, the variable that determined the branch, so that its influencing instructions can also be added to this state's influencing instructions.
  private(set) var controlFlowConditions: [InstructionPosition: IRVariable]
  
  /// Build the result term that is used for `potentialControlFlowDependencies` and `influencingInstructionsForTerms`.
  private static func buildResultTerm(term: WPTerm, observeSatisfactionRate: WPTerm, focusRate: WPTerm, intentionalLossRate: WPTerm) -> WPTerm {
    let intentionalFocusRate = (.integer(1) - intentionalLossRate)
    return (term / focusRate / intentionalFocusRate) ./. (observeSatisfactionRate / focusRate / intentionalFocusRate)
  }
  
  /// The current result term that is used for `potentialControlFlowDependencies` and `influencingInstructionsForTerms`.
  private var resultTerm: WPTerm {
    return Self.buildResultTerm(term: term, observeSatisfactionRate: observeSatisfactionRate, focusRate: focusRate, intentionalLossRate: intentionalLossRate)
  }
  
  // MARK: Retrieving the result
  
  /// The instructions that directly influence the slicing query that's tracked by this slicing state.
  /// This does **not** include control flow dependencies
  var influencingInstructions: Set<InstructionPosition> {
    return influencingInstructionsForTerms[self.resultTerm]!
  }
  
  /// All instruction positions that have an influence on the slice that's tracked by this slicing state.
  var controlFlowDependencies: Set<InstructionPosition> {
    let conrolFlowDependencies = potentialControlFlowDependencies.compactMap({ (key, value) -> InstructionPosition? in
      if value.count > 1 {
        return key
      } else {
        return nil
      }
    })
    return Set(conrolFlowDependencies)
  }
  
  // MARK: Constructors
  
  /// Create the initial `WPSlicingState` to create a program slice for `queryTerm`.
  init(initialStateFor sliceFor: WPTerm) {
    if case .variable(let variable) = sliceFor {
      self.term = WPTerm.boolToInt(.equal(lhs: sliceFor, rhs: .variable(IRVariable.queryVariable(type: variable.type))))
    } else {
      // We don't currently have a complex way to combine boolean values. The variable must be of type int.
      // Actually the variable type also doesn't matter
      self.term = WPTerm.boolToInt(.equal(lhs: sliceFor, rhs: .variable(IRVariable.queryVariable(type: .int))))
    }
    self.observeSatisfactionRate = .integer(1)
    self.focusRate = .integer(1)
    self.intentionalLossRate = .integer(0)
    self.influencingInstructionsForTerms = [
      Self.buildResultTerm(term: self.term, observeSatisfactionRate: self.observeSatisfactionRate, focusRate: self.focusRate, intentionalLossRate: self.intentionalLossRate): []
    ]
    self.potentialControlFlowDependencies = [:]
    self.controlFlowConditions = [:]
  }
  
  private init(
    term: WPTerm,
    observeSatisfactionRate: WPTerm,
    focusRate: WPTerm,
    intentionalLossRate: WPTerm,
    influencingInstructions: [WPTerm: Set<InstructionPosition>],
    potentialControlFlowDependencies: [InstructionPosition: Set<WPTerm>],
    controlFlowConditions: [InstructionPosition: IRVariable]
  ) {
    self.term = term
    self.observeSatisfactionRate = observeSatisfactionRate
    self.focusRate = focusRate
    self.intentionalLossRate = intentionalLossRate
    self.influencingInstructionsForTerms = influencingInstructions
    self.potentialControlFlowDependencies = potentialControlFlowDependencies
    self.controlFlowConditions = controlFlowConditions
  }
  
  /// Merge a list of slicing states
  static func merged(_ states: [WPSlicingState]) -> WPSlicingState {
    guard !states.isEmpty else {
      return WPSlicingState(
        term: .integer(0),
        observeSatisfactionRate: .integer(0),
        focusRate: .integer(0),
        intentionalLossRate: .integer(0),
        influencingInstructions: [:],
        potentialControlFlowDependencies: [:],
        controlFlowConditions: [:]
      )
    }
    if states.count == 1 {
      return states.first!
    }
    
    // If a state has both term and observeSatisfactionRate set to 0, it will not be contributing anything to the resulting state's resultTerm. We can thus safely ignore it.
    let states = states.filter({ !($0.term.isZero && $0.observeSatisfactionRate.isZero) })
    
    // Compute all term for which all states to merge have a set of influencing instructions. If one term doesn't have influencing instructions stored for a term, we can't make any statements on it.
    let mergedKeys = states.map(\.influencingInstructionsForTerms.keys).reduce(Set(states.first!.influencingInstructionsForTerms.keys), { $0.intersection($1) })
    
    // For those keys, the influencing instructions are the union of all influencing instructions of the states to merge
    var mergedInfluencingInstructions: [WPTerm: Set<InstructionPosition>] = [:]
    for key in mergedKeys {
      mergedInfluencingInstructions[key] = states.map({ $0.influencingInstructionsForTerms[key]! }).reduce(Set(), { $0 + $1 })
    }
    
    // Merge the terms by adding them
    let mergedTerm = WPTerm.add(terms: states.map(\.term))
    let mergedObserveSatisfactionRate = WPTerm.add(terms: states.map(\.observeSatisfactionRate))
    let mergedFocusRate = WPTerm.add(terms: states.map(\.focusRate))
    let mergedIntentionalLossRate = WPTerm.add(terms: states.map(\.intentionalLossRate))
    
    // Add a new entry in the influencing instructions for the merged terms by merging together their currently influencing instructions.
    let mergedKey = buildResultTerm(term: mergedTerm, observeSatisfactionRate: mergedObserveSatisfactionRate, focusRate: mergedFocusRate, intentionalLossRate: mergedIntentionalLossRate)
    if mergedInfluencingInstructions[mergedKey] == nil {
      mergedInfluencingInstructions[mergedKey] = states.map(\.influencingInstructions).reduce(Set(), { $0 + $1 })
    }
  
    // Merge the potential control flow dependencies
    var mergedPotentialControlFlowDependencies: [InstructionPosition: Set<WPTerm>] = [:]
    for state in states {
      for (position, branchingTerms) in state.potentialControlFlowDependencies {
        mergedPotentialControlFlowDependencies[position] = mergedPotentialControlFlowDependencies[position, default: Set()] + branchingTerms
      }
    }
    
    // Merge the control flow conditions. The variable for each control flow condition should be static and be equal in all states.
    let mergedControlFlowConditions = Dictionary.merged(states.map(\.controlFlowConditions), uniquingKeysWith: { assert($0 == $1); return $0 })
    
    return WPSlicingState(
      term: mergedTerm,
      observeSatisfactionRate: mergedObserveSatisfactionRate,
      focusRate: mergedFocusRate,
      intentionalLossRate: mergedIntentionalLossRate,
      influencingInstructions: mergedInfluencingInstructions,
      potentialControlFlowDependencies: mergedPotentialControlFlowDependencies,
      controlFlowConditions: mergedControlFlowConditions
    )
  }
  
  // MARK: Updating the slicing state
  
  mutating func updateTerms(position: InstructionPosition, term updateTerm: Bool, observeSatisfactionRate updateObserveSatisfactionRate: Bool, focusRate updateFocusRate: Bool, intentionalLossRate updateIntentionalLossRate: Bool, controlFlowDependency: IRVariable?, update: (WPTerm) -> WPTerm?) {
    
    // Update all terms
    let previousInfluencingInstructions = influencingInstructionsForTerms[self.resultTerm]!
    if updateTerm, let updatedTerm = update(term) {
      self.term = updatedTerm
    }
    if updateObserveSatisfactionRate, let updatedObserveSatisfactionRate = update(observeSatisfactionRate) {
      self.observeSatisfactionRate = updatedObserveSatisfactionRate
    }
    if updateFocusRate, let updatedFocusRate = update(focusRate) {
      self.focusRate = updatedFocusRate
    }
    if updateIntentionalLossRate, let updatedIntentionalLossRate = update(intentionalLossRate) {
      self.intentionalLossRate = updatedIntentionalLossRate
    }
    if updateTerm {
      self.potentialControlFlowDependencies = self.potentialControlFlowDependencies.mapValues({ branchingTerms in
        Set(branchingTerms.map({ update($0) ?? $0 }))
      })
    }
    
    // Add a new entry for influencing instructions
    let key = Self.buildResultTerm(term: term, observeSatisfactionRate: observeSatisfactionRate, focusRate: focusRate, intentionalLossRate: intentionalLossRate)
    if self.influencingInstructionsForTerms[key] == nil {
      self.influencingInstructionsForTerms[key] = previousInfluencingInstructions + [position]
    }
    
    // Record a control flow dependency if necessary
    if let controlFlowDependency = controlFlowDependency {
      controlFlowConditions[position] = controlFlowDependency
      potentialControlFlowDependencies[position] = potentialControlFlowDependencies[position, default: Set()] + [self.resultTerm]
    }
  }
}
