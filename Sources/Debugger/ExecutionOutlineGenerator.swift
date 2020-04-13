import IR
import IRExecution
import Utils

/// Generate an `ExecutionOutline` for a given IR program with debug info.
public class ExecutionOutlineGenerator {
  private var program: IRProgram {
    return executor.program
  }
  private let debugInfo: DebugInfo
  private let executor: IRExecutor
  
  public init(program: IRProgram, debugInfo: DebugInfo) {
    self.executor = IRExecutor(program: program)
    self.debugInfo = debugInfo
  }
  
  // MARK: - Public outline generations

  public func generateOutline(sampleCount: Int) throws -> ExecutionOutline {
    let initialState = IRExecutionState(initialStateIn: program, sampleCount: sampleCount)
    let (outline, finalState) = try generateOutline(startingAt: initialState, finalPosition: program.returnPosition)
    if let finalState = finalState {
      return ExecutionOutline(outline.entries + [.instruction(state: finalState)])
    } else {
      return outline
    }
  }
  
  // MARK: - Outline generation implementation
  
  /// Generate the execution outline for one of the two branches of a branch instruction at the position of `branchingState`. `branch` determines which for which branch, the outline should be generated.
  /// Returns both the outline of the branch as well as the state that is reached after executing the branch and reaching the join point of the two branches (which is the first non-phi instruction in the postdominator block).
  /// If the outline is empty (because the branch did not have any instructions with debug or because there were no viable runs of this branch, its `outline` is `nil`.
  /// If there were no viable runs for this branch, `joinState` will also be `nil`
  private func generateOutlineForIfBranch(branchingState: IRExecutionState, branch: Bool) throws -> (outline: ExecutionOutline?, joinState: IRExecutionState?) {
    guard let branchInstruction = program.instruction(at: branchingState.position) as? BranchInstruction else {
      fatalError("Instruction at a branch position must be a BranchInstrucion")
    }
    
    // The instruction that is the join point of the two execution branches
    let joinPosition = firstNonPhiPostdominatorInstruction(of: branchingState.position)
    
    // Filter out any samples that don't satisfy the branching condition (and thus would end up in the other branch).
    let filteredSamplesState = branchingState.filterSamples(condition: {
      return branchInstruction.condition.evaluated(in: $0).boolValue! == branch
    })
    
    // If there are no samples that satisfy the condition, we can't execute it
    guard filteredSamplesState.hasSamples else {
      return (nil, nil)
    }
    
    // Jump into this branch
    let trueBranchState = try executor.runUntilNextInstruction(state: filteredSamplesState)!
    
    // Now that we have left the branch instruction, generate the outline for this branch until the join point
    let (branchOutline, finalState) = try self.generateOutline(startingAt: trueBranchState, finalPosition: joinPosition)
    
    if let finalState = finalState {
      assert(finalState.position == joinPosition)
    }
    
    // Check if the outline is empty. If yes, ignore it.
    if branchOutline.entries.isEmpty == true {
      return (nil, finalState)
    } else {
      return (branchOutline, finalState)
    }
  }
  
  /// Generate an outline entry for a branch instruction at the position of `branchingState`.
  /// Returns both the `outlineEntry` for the execution outline as well as the `finalState` that was reached after merging the execution two branches of the `BranchInstruction` again at their join point. (equivalent to stepping over the branch).
  private func generateOutlineEntryForBranch(branchingState: IRExecutionState) throws -> (outlineEntry: ExecutionOutlineEntry, finalState: IRExecutionState?) {

    // Generate outlines for both branches
    let (trueBranchOutline, trueBranchJoinState) = try generateOutlineForIfBranch(branchingState: branchingState, branch: true)
    let (falseBranchOutline, falseBranchJoinState) = try generateOutlineForIfBranch(branchingState: branchingState, branch: false)
    
    let outline = ExecutionOutlineEntry.branch(state: branchingState, true: trueBranchOutline, false: falseBranchOutline)
    
    // Merge the join states of the two branches
    let finalState = IRExecutionState.merged(states: [trueBranchJoinState, falseBranchJoinState].compactMap({ $0 }))
    
    return (outline, finalState)
  }
  
  private func generateOutlineEntryForLoop(branchingState: IRExecutionState) throws -> (outlineEntry: ExecutionOutlineEntry, finalState: IRExecutionState?) {
    guard let branchInstruction = program.instruction(at: branchingState.position) as? BranchInstruction else {
      fatalError("Instruction at a loop position must be a BranchInstrucion")
    }
    
    // The instruction at which the control flow of entering the loop and leaving the loop joins (i.e. the instruction that corresponds to the next statement after the while statement)
    let joinPosition = firstNonPhiPostdominatorInstruction(of: branchingState.position)
    
    // The states with which we have left the loop
    var finishedStates = [IRExecutionState]()
    // The outlines generated for the different loop iterations
    var iterationOutlines = [ExecutionOutline]()
    // The state from which we currently generate either iterationOutlines of finishedStates
    var currentState = branchingState
    
    var exitStates: [IRExecutionState] = []
    
    while true {
      assert(currentState.position == branchingState.position)
      
      // Generate the state that exits the loop
      
      // First, filter out any samples that would enter the loop.
      let stateNotSatisfyingCondition = currentState.filterSamples(condition: {
        return branchInstruction.condition.evaluated(in: $0).boolValue! == false
      })
            
      if let lastExitState = exitStates.last {
        exitStates.append(IRExecutionState.merged(states: [lastExitState, stateNotSatisfyingCondition])!)
      } else {
        exitStates.append(stateNotSatisfyingCondition)
      }
      
      // If there are no samples violating the condition, we can simply ignore this part
      if stateNotSatisfyingCondition.hasSamples {
        // The false branch of the looping instruction directly jumps to the postdominator instruction without any intermediate instructions with debug info, so we don't need to create an outline for this part of the run.
        if let loopExitState = try executor.runUntilPosition(state: stateNotSatisfyingCondition, stopPositions: [joinPosition]) {
          finishedStates.append(loopExitState)
        }
      }
      
      // Generate the outline of the loop iteration
      
      // Filter out any states that don't satisfy the loop condition
      let stateSatsifyingCondition = currentState.filterSamples(condition: {
        return branchInstruction.condition.evaluated(in: $0).boolValue! == true
      })
      
      guard stateSatsifyingCondition.hasSamples else {
        // We don't hava any states left that satisfy the loop condition. We are done looping.
        break
      }
      // Jump into the loop body
      let loopBodyState = try executor.runUntilNextInstruction(state: stateSatsifyingCondition)!
      
      // Generate the outline for the loop body
      let (iterationOutline, stateAfterIteration) = try generateOutline(startingAt: loopBodyState, finalPosition: branchingState.position)
      iterationOutlines.append(iterationOutline)
      
      // The body might have filtered out more samples through observe statements. If it did filter out all of them, we are done looping.
      guard let unwrappedStateAfterIteration = stateAfterIteration else {
        break
      }
      
      // Continue looping with the new state
      currentState = unwrappedStateAfterIteration
    }
    
    let outlineEntry = ExecutionOutlineEntry.loop(state: branchingState, iterations: iterationOutlines, exitStates: exitStates)
    let finalState = IRExecutionState.merged(states: finishedStates)
    return (outlineEntry, finalState)
  }

  /// Generate the `ExecutionOutline` for execution that starts at `startState` until it reaches `finalPosition`.
  /// Returns a `nil` `finalState` if all samples were filtered out during the execution.
  private func generateOutline(startingAt startState: IRExecutionState, finalPosition: InstructionPosition) throws -> (outline: ExecutionOutline, finalState: IRExecutionState?) {
    var currentState: IRExecutionState? = startState
    if debugInfo.info[startState.position] == nil, startState.position != finalPosition {
      currentState = try executor.runUntilPosition(state: startState, stopPositions: Set(debugInfo.info.keys).union([finalPosition]))
    }
    
    var outline = [ExecutionOutlineEntry]()

    executionLoop: while let unwrappedCurrentState = currentState, unwrappedCurrentState.position != finalPosition {
      guard let instructionDebugInfo = debugInfo.info[unwrappedCurrentState.position] else {
        fatalError("Should only have halted at instructions with debug info")
      }
      
      switch instructionDebugInfo.instructionType {
      case .simple:
        outline.append(.instruction(state: unwrappedCurrentState))
        currentState = try executor.runUntilPosition(state: unwrappedCurrentState, stopPositions: Set(debugInfo.info.keys).union([finalPosition]))
      case .ifElseBranch:
        let (outlineEntry, mergedState) = try self.generateOutlineEntryForBranch(branchingState: unwrappedCurrentState)
        outline.append(outlineEntry)
        currentState = mergedState
      case .loop:
        let (outlineEntry, mergedState) = try self.generateOutlineEntryForLoop(branchingState: unwrappedCurrentState)
        outline.append(outlineEntry)
        currentState = mergedState
      case .return:
        assert(finalPosition == unwrappedCurrentState.position, "Reached an return instruction while expecting to stop at an earlier instruction")
      }
      
      if let unwrappedCurrentState = currentState, unwrappedCurrentState.position != finalPosition {
        if debugInfo.info[unwrappedCurrentState.position] == nil {
          currentState = try executor.runUntilPosition(state: unwrappedCurrentState, stopPositions: Set(debugInfo.info.keys).union([finalPosition]))
        }
      }
    }
    
    if let currentState = currentState {
      assert(currentState.position == finalPosition)
    }
    return (ExecutionOutline(outline), currentState)
  }
  
  // MARK: Utility functions
  
  /// Return the first instruction in the immediate postdominator block of the given position which is not a `PhiInstruction`. This is the first position in the postdominator block at which an `IRExecutor` can halt.
  private func firstNonPhiPostdominatorInstruction(of position: InstructionPosition) -> InstructionPosition {
    guard let postdominatorBlock = program.immediatePostdominator[position.basicBlock]! else {
      fatalError("A branch instruction must have an immediate postdominator since it does not terminate the program")
    }
    let firstNonPhiInstructionInBlock = program.basicBlocks[postdominatorBlock]!.instructions.firstIndex(where: { !($0 is PhiInstruction) })!
    return InstructionPosition(basicBlock: postdominatorBlock, instructionIndex: firstNonPhiInstructionInBlock)
    
  }
}
