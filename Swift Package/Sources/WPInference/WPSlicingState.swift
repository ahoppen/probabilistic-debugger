import IR
import Utils

struct WPResultTerm: Hashable {
  private(set) var term: WPTerm
  private(set) var observeSatisfactionRate: WPTerm
  private(set) var focusRate: WPTerm
  private(set) var intentionalLossRate: WPTerm
  
  static func merged(_ terms: [WPResultTerm]) -> WPResultTerm {
    return WPResultTerm(
      term: WPTerm.add(terms: terms.map(\.term)),
      observeSatisfactionRate: WPTerm.add(terms: terms.map(\.observeSatisfactionRate)),
      focusRate: WPTerm.add(terms: terms.map(\.focusRate)),
      intentionalLossRate: WPTerm.add(terms: terms.map(\.intentionalLossRate))
    )
  }
  
  mutating func updateTerms(term updateTerm: Bool, observeSatisfactionRate updateObserveSatisfactionRate: Bool, focusRate updateFocusRate: Bool, intentionalLossRate updateIntentionalLossRate: Bool, update: (WPTerm) -> WPTerm?) {
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
  }
  
  var isZeroInBothComponents: Bool {
    return term.isZero && observeSatisfactionRate.isZero
  }
  
  var value: WPTerm {
    let intentionalFocusRate = (.integer(1) - intentionalLossRate)
    return (term / focusRate / intentionalFocusRate) ./. (observeSatisfactionRate / focusRate / intentionalFocusRate)
  }
  
  var normalizedTerm: WPTerm {
    let intentionalFocusRate = (.integer(1) - intentionalLossRate)
    return term / focusRate / intentionalFocusRate
  }
  
  var normalizedObserveSatisfactionRate: WPTerm {
    let intentionalFocusRate = (.integer(1) - intentionalLossRate)
    return observeSatisfactionRate / focusRate / intentionalFocusRate
  }
  
  func hash(into hasher: inout Hasher) {
    self.value.hash(into: &hasher)
  }
  
  static func ==(lhs: WPResultTerm, rhs: WPResultTerm) -> Bool {
    return lhs.value == rhs.value
  }
}

struct WPSlicingState: Hashable {
  // MARK: The current state's terms
  
  var resultTerm: WPResultTerm
  
  // MARK: Keeping track of influencing positions and dependencies
  
  /// For each result term (as built using the `buildResultTerm` function), a set of instructions that influence this term.
  /// When we encounter a new result term, we add it to the list.
  /// Should we encounter a result term that we have seen before, we know that the intermediat instructions didn't have an affect on the result term and thus don't need to be considered influencing.
  private var influencingInstructionsForTerms: [WPResultTerm: Set<InstructionPosition>]
  
  /// Control flow points that might have influenced the value of resultTerm.
  /// Whenever a branching point is encountered, the current result term is recorded.
  /// The branch point was relevant if WP-inference had different values for two WP inference states when they were merged again at a branching point.
  /// Thus, at the end of WP-inference, all positions with more than one resultTerm had an influence on the resultTerm
  private var potentialControlFlowDependencies: [InstructionPosition: Set<WPResultTerm>]
  
  /// For each control flow position, the variable that determined the branch, so that its influencing instructions can also be added to this state's influencing instructions.
  private(set) var controlFlowConditions: [InstructionPosition: IRVariable]
  
  /// Build the result term that is used for `potentialControlFlowDependencies` and `influencingInstructionsForTerms`.
  private static func buildResultTerm(term: WPResultTerm) -> WPTerm {
    return term.value
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
    let queryVariableType: IRType
    if case .variable(let variable) = sliceFor {
      queryVariableType = variable.type
    } else {
      // We don't currently have a complex way to combine boolean values. The variable must be of type int.
      // Actually the variable type also doesn't matter
      queryVariableType = .int
    }
    self.resultTerm = WPResultTerm(
      term: WPTerm.boolToInt(.equal(lhs: sliceFor, rhs: .variable(IRVariable.queryVariable(type: queryVariableType)))),
      observeSatisfactionRate: .integer(1),
      focusRate: .integer(1),
      intentionalLossRate: .integer(0)
    )
    self.influencingInstructionsForTerms = [
      self.resultTerm: []
    ]
    self.potentialControlFlowDependencies = [:]
    self.controlFlowConditions = [:]
  }
  
  private init(
    term: WPResultTerm,
    influencingInstructions: [WPResultTerm: Set<InstructionPosition>],
    potentialControlFlowDependencies: [InstructionPosition: Set<WPResultTerm>],
    controlFlowConditions: [InstructionPosition: IRVariable]
  ) {
    self.resultTerm = term
    self.influencingInstructionsForTerms = influencingInstructions
    self.potentialControlFlowDependencies = potentialControlFlowDependencies
    self.controlFlowConditions = controlFlowConditions
  }
  
  /// Merge a list of slicing states
  static func merged(_ lhs: WPSlicingState, _ rhs: WPSlicingState) -> WPSlicingState {
    // If a state has both term and observeSatisfactionRate set to 0, it will not be contributing anything to the resulting state's resultTerm. We can thus safely ignore it.
    let states = states.filter({ !$0.resultTerm.isZeroInBothComponents })
    
    // Compute all term for which all states to merge have a set of influencing instructions. If one term doesn't have influencing instructions stored for a term, we can't make any statements on it.
    let mergedKeys = Set(lhs.influencingInstructionsForTerms.keys).intersection(rhs.influencingInstructionsForTerms.keys)
    
    // For those keys, the influencing instructions are the union of all influencing instructions of the states to merge
    var mergedInfluencingInstructions: [WPResultTerm: Set<InstructionPosition>] = [:]
    for key in mergedKeys {
      mergedInfluencingInstructions[key] = lhs.influencingInstructionsForTerms[key]! + rhs.influencingInstructionsForTerms[key]!
    }
    
    let mergedResultTerm = WPResultTerm.merged([lhs.resultTerm, rhs.resultTerm])
    
    // Add a new entry in the influencing instructions for the merged terms by merging together their currently influencing instructions.
    if mergedInfluencingInstructions[mergedResultTerm] == nil {
      mergedInfluencingInstructions[mergedResultTerm] = lhs.influencingInstructions + rhs.influencingInstructions
    }
  
    // Merge the potential control flow dependencies
    var mergedPotentialControlFlowDependencies: [InstructionPosition: Set<WPResultTerm>] = [:]
    for state in [lhs, rhs] {
      for (position, branchingTerms) in state.potentialControlFlowDependencies {
        mergedPotentialControlFlowDependencies[position] = mergedPotentialControlFlowDependencies[position, default: Set()] + branchingTerms
      }
    }
    
    // Merge the control flow conditions. The variable for each control flow condition should be static and be equal in all states.
    let mergedControlFlowConditions = lhs.controlFlowConditions.merging(rhs.controlFlowConditions, uniquingKeysWith: { assert($0 == $1); return $0 })
    
    
    return WPSlicingState(
      term: mergedResultTerm,
      influencingInstructions: mergedInfluencingInstructions,
      potentialControlFlowDependencies: mergedPotentialControlFlowDependencies,
      controlFlowConditions: mergedControlFlowConditions
    )
  }
  
  // MARK: Updating the slicing state
  
  mutating func updateTerms(position: InstructionPosition, term updateTerm: Bool, observeSatisfactionRate updateObserveSatisfactionRate: Bool, focusRate updateFocusRate: Bool, intentionalLossRate updateIntentionalLossRate: Bool, controlFlowDependency: IRVariable?, update: (WPTerm) -> WPTerm?) {
    
    let termBeforeUpdate = self.resultTerm
    
    // Update all terms
    let previousInfluencingInstructions = influencingInstructionsForTerms[self.resultTerm]!
    self.resultTerm.updateTerms(term: updateTerm, observeSatisfactionRate: updateObserveSatisfactionRate, focusRate: updateFocusRate, intentionalLossRate: updateIntentionalLossRate, update: update)
    self.potentialControlFlowDependencies = self.potentialControlFlowDependencies.mapValues({ branchingTerms in
      Set(branchingTerms.map({ (term: WPResultTerm) -> WPResultTerm in
        var term = term
        term.updateTerms(term: updateTerm, observeSatisfactionRate: updateObserveSatisfactionRate, focusRate: updateFocusRate, intentionalLossRate: updateIntentionalLossRate, update: update)
        return term
      }))
    })
    
    // Add a new entry for influencing instructions
    if self.influencingInstructionsForTerms[resultTerm] == nil {
      self.influencingInstructionsForTerms[resultTerm] = previousInfluencingInstructions + [position]
    }
    
    // Record a control flow dependency if necessary
    if let controlFlowDependency = controlFlowDependency {
      controlFlowConditions[position] = controlFlowDependency
      potentialControlFlowDependencies[position] = potentialControlFlowDependencies[position, default: Set()] + [termBeforeUpdate]
    }
  }
}
