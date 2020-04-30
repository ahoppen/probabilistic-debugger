//
//  DebuggerCentral.swift
//  ProbabilisticDebugger-UI
//
//  Created by Alex Hoppen on 09.04.20.
//  Copyright © 2020 Alex Hoppen. All rights reserved.
//

import Combine
import Foundation
import Debugger
import IR
import IRExecution
import SimpleLanguageIRGen
import Utils
import WPInference

struct EmptyValueError: Error {}

enum Failable<Value> {
  case success(Value)
  case error(Error)
  
  var success: Value? {
    switch self {
    case .success(let value):
      return value
    case .error:
      return nil
    }
  }
  
  func map<T>(_ transform: (Value) -> T) -> Failable<T> {
    switch self {
    case .success(let value):
      return .success(transform(value))
    case .error(let error):
      return .error(error)
    }
  }
  
  func tryMap<T>(_ transform: (Value) throws -> T) -> Failable<T> {
    switch self {
    case .success(let value):
      do {
        return .success(try transform(value))
      } catch {
        return .error(error)
      }
    case .error(let error):
      return .error(error)
    }
  }
}

class DebuggerCentral {
  public var sourceCodeModel: SourceCode = SourceCode(sourceCode: "") {
    didSet {
      sourceCode = sourceCodeModel.sourceCode
      sourceCodeModel.addObserver { [weak self] (newValue) in
        self?.sourceCode = newValue.sourceCode
      }
    }
  }
  
  public let initialSamples = 10_000
  
  private var debugger: Debugger?
  
  @Published public private(set) var sourceCode: String = ""
  @Published public private(set) var debuggerLocation: SourceCodeLocation? = nil
  @Published public private(set) var samples: [SourceCodeSample] = []
  @Published public private(set) var variableValuesRefinedUsingWPDroppingApproxmiationError: [String: [IRValue: Double]]? = nil
  @Published public private(set) var variableValuesRefinedUsingWPDistributingApproximationError: [String: [IRValue: Double]]? = nil
  @Published public private(set) var reachabilityProbability: Double = 0
  @Published public private(set) var approximationError: Double = 0
  @Published public private(set) var inferenceEngine: WPInferenceEngine?
  public private(set) var survivingSampleIds = PassthroughSubject<Set<Int>, Never>()
  
  public private(set) var irAndDebugInfo = PassthroughSubject<Failable<(program: IRProgram, debugInfo: DebugInfo)>, Never>()
  public private(set) var executionOutline = PassthroughSubject<Failable<ExecutionOutline>, Never>()
  
  private var cancellables: [AnyCancellable] = []
  
  init() {
    cancellables += self.$sourceCode.map { (sourceCode) in
      do {
        return .success(try SLIRGen.generateIr(for: sourceCode))
      } catch {
        return .error(error)
      }
    }.subscribe(irAndDebugInfo)
    
    cancellables += self.irAndDebugInfo.sink { [unowned self] (irOrError) in
      switch irOrError {
      case .success(let ir):
        self.debugger = Debugger(program: ir.program, debugInfo: ir.debugInfo, sampleCount: self.initialSamples)
        self.inferenceEngine = self.debugger?.inferenceEngine
        self.updatePublishedDebuggerVariables()
      case .error(let error):
        print(error.localizedDescription)
        self.debugger = nil
        self.inferenceEngine = nil
        self.updatePublishedDebuggerVariables()
      }
    }
    
    cancellables += self.irAndDebugInfo.map({ (irOrError) in
      return irOrError.tryMap { [unowned self] (ir) -> ExecutionOutline in
        let executionOutlineGenerator = ExecutionOutlineGenerator(program: ir.program, debugInfo: ir.debugInfo)
        return try executionOutlineGenerator.generateOutline(sampleCount: self.initialSamples)
      }
    }).subscribe(executionOutline)
    
    cancellables += executionOutline.map({ (outline) in
      return Set(outline.success?.entries.last?.state.samples.map({ $0.id }) ?? [])
    }).subscribe(survivingSampleIds)
  }
  
  public func stepOver() throws {
    try debugger?.stepOver()
    updatePublishedDebuggerVariables()
  }
  
  public func stepInto(branch: Bool) throws {
    try debugger?.stepInto(branch: branch)
    updatePublishedDebuggerVariables()
  }
  
  private func updatePublishedDebuggerVariables() {
    self.debuggerLocation = self.debugger?.sourceLocation
    self.samples = self.debugger?.samples ?? []
    self.variableValuesRefinedUsingWPDroppingApproxmiationError = nil
    self.variableValuesRefinedUsingWPDistributingApproximationError = nil
    self.reachabilityProbability = Double(samples.count) / Double(self.initialSamples)
    if let debugger = self.debugger {
      // Copy the debugger instance to avoid race conditions with the debugger modifying its sate
      let copiedDebugger = Debugger(debugger)
      DispatchQueue.global(qos: .userInitiated).async {
        self.variableValuesRefinedUsingWPDroppingApproxmiationError = copiedDebugger.variableValuesRefinedUsingWP(approximationErrorHandling: .drop)
        self.variableValuesRefinedUsingWPDistributingApproximationError = copiedDebugger.variableValuesRefinedUsingWP(approximationErrorHandling: .distribute)
        self.reachabilityProbability = copiedDebugger.reachingProbability
        self.approximationError = copiedDebugger.approximationError
      }
    }
  }
  
  public func jumpToExecutionState(_ executionState: IRExecutionState) {
    debugger?.jumpToState(executionState)
    updatePublishedDebuggerVariables()
  }
  
  public func slice(for variable: String) -> Set<Range<SourceCodeLocation>> {
    return (try? debugger?.slice(for: variable)) ?? []
  }
}
