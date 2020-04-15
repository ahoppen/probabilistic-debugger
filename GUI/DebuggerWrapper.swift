//
//  DebuggerWrapper.swift
//  ProbabilisticDebugger-UI
//
//  Created by Alex Hoppen on 09.04.20.
//  Copyright © 2020 Alex Hoppen. All rights reserved.
//

import Cocoa
import Debugger
import IR
import SimpleLanguageIRGen

class DebuggerWrapper {
  /// The underlying debugger
  var debugger: Debugger? = nil
  
  /// The source code that the `debugger` debugs.
  var sourceCode: SourceCode {
    didSet {
      sourceCodeDidChanage(sourceCode: sourceCode)
    }
  }
  
//  private var _executionOutline: ExecutionOutline?
//  var executionOutline: ExecutionOutline {
//    if let outline = _executionOutline {
//      return outline
//    } else {
//      _executionOutline = ExecutionOutline(
//    }
//  }
  
  /// An observer that is called when the debugger state or the source code changes.
  var observers: [() -> Void] = []
  
  func addObserver(_ observer: @escaping () -> Void) {
    observers.append(observer)
  }
  
  private func notifyObservers() {
    for observer in observers {
      observer()
    }
  }
  
  // MARK: Re-exposed properties
  
  var sourceLocation: SourceCodeLocation? {
    return debugger?.sourceLocation
  }
  
  var samples: [SourceCodeSample] {
    return debugger?.samples ?? []
  }
  
  // MARK: Initialiser
  
  init(sourceCode: SourceCode) {
    self.sourceCode = sourceCode
    sourceCode.addObserver({ [weak self] in
      self?.sourceCodeDidChanage(sourceCode: $0)
    })
    self.sourceCodeDidChanage(sourceCode: sourceCode)
  }

  // MARK: Observers
  
  func sourceCodeDidChanage(sourceCode: SourceCode) {
    do {
      let ir = try SLIRGen.generateIr(for: sourceCode.sourceCode)
      self.debugger = Debugger(program: ir.program, debugInfo: ir.debugInfo, sampleCount: 10_000)
      notifyObservers()
    } catch {
      debugger = nil
      // FIXME: Show parser errors
    }
  }
  
  // MARK: Debugger commands
  
  func stepOver() {
    do {
      try debugger?.stepOver()
      notifyObservers()
    } catch {
      handle(error: error)
    }
  }
  
  // MARK: Error handling
  
  func handle(error: Error) {
    print(error)
  }
}
