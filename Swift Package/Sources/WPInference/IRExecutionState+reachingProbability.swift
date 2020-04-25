import IR
import IRExecution

public extension IRExecutionState {
  func reachingProbability(in program: IRProgram) -> Double {
    let inferenceEngine = WPInferenceEngine(program: program)
    let inferred = inferenceEngine.infer(term: .integer(0), loopUnrolls: self.loopUnrolls, inferenceStopPosition: self.position, branchingHistories: self.branchingHistories)
    return (inferred.runsNotCutOffByLoopIterationBounds).doubleValue
  }
}
