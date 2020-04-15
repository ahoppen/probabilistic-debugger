//
//  SourceCode.swift
//  ProbabilisticDebugger-UI
//
//  Created by Alex Hoppen on 08.04.20.
//  Copyright © 2020 Alex Hoppen. All rights reserved.
//

import Foundation
import Cocoa

class SourceCode: NSObject {
  var sourceCode = "" {
    didSet {
      for observer in observers {
        observer(self)
      }
    }
  }
  
  var lines: [String] {
    return sourceCode.components(separatedBy: .newlines)
  }
  
  private var observers: [(SourceCode) -> Void] = []
  
  public init(sourceCode: String) {
    self.sourceCode = sourceCode
  }
  
  func addObserver(_ observer: @escaping (SourceCode) -> Void) {
    observers.append(observer)
  }
}
