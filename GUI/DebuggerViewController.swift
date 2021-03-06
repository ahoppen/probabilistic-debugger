//
//  DebuggerViewController.swift
//  ProbabilisticDebugger-UI
//
//  Created by Alex Hoppen on 08.04.20.
//  Copyright © 2020 Alex Hoppen. All rights reserved.
//

import Cocoa
import Debugger
import IR
import IRExecution
import SimpleLanguageIRGen
import Combine
import Utils


class DebuggerViewController: NSViewController, NSTextViewDelegate {
  // MARK: IBOutlets
  
  @IBOutlet var stepOverButton: NSButton!
  @IBOutlet var textView: NSTextView!
  @IBOutlet var variablesTableView: NSTableView!
  @IBOutlet var executionOutlineView: NSOutlineView!
  @IBOutlet var samplesTextField: NSTextField!
  @IBOutlet var survivingTextField: NSTextField!
  @IBOutlet var approximationErrorTextField: NSTextField!
  
  private var cancellables: [AnyCancellable] = []
  
  @Published @objc var survivingSamplesOnlyInVariablesView: Bool = false
  @Published @objc var refineProbabilitiesUsingWpInference: Bool = true
  
  @DelayedImmutable private var debuggerCentral: DebuggerCentral
  @DelayedImmutable private var variablesDataSource: DebuggerVariablesTableViewDataSource!
  @DelayedImmutable private var executionOutlineDataSource: ExecutionOutlineViewDataSource!
  
  // MARK: View lifecycle
  
  override func viewDidLoad() {
    super.viewDidLoad()
    textView.font = NSFont(name: "Menlo", size: 13)
    self.debuggerCentral = DebuggerCentral()
    self.debuggerCentral.sourceCodeModel = sourceCode
    
    cancellables += Publishers.CombineLatest(debuggerCentral.$sourceCode, debuggerCentral.$debuggerLocation).map({ (sourceCode, debuggerPosition) -> NSAttributedString in
      let lines = sourceCode.components(separatedBy: "\n").map({
        return NSMutableAttributedString.init(string: "\($0)\n", attributes: [
          .font: NSFont(name: "Menlo", size: 13)!
        ])
      })
      if let currentLine = debuggerPosition?.line, (currentLine - 1) < lines.count {
        let line = lines[currentLine - 1]
        line.addAttribute(.backgroundColor, value: #colorLiteral(red: 0.8431372549, green: 0.9098039216, blue: 0.8549019608, alpha: 1) as NSColor, range: NSRange(location: 0, length: line.length))
      }

      let highlightedSourceCode = NSMutableAttributedString()
      for line in lines {
        highlightedSourceCode.append(line)
      }
      return highlightedSourceCode
    }).sink(receiveValue: {
      self.textView.textStorage?.setAttributedString($0)
    })
    
    cancellables += debuggerCentral.$reachabilityProbability.map({ (reachabilityProbability) -> String in
      let percentage = (reachabilityProbability * 100).rounded(decimalPlaces: 2)
      return "Samples: \(percentage)%"
    }).receive(on: DispatchQueue.main).assign(to: \.stringValue, on: samplesTextField)
    cancellables += debuggerCentral.$approximationError.map({ (approximationError) -> String in
      let errorString: String
      if approximationError == 0 {
        errorString = "0%"
      } else if approximationError > 0.001 {
        errorString = "\((approximationError * 100).rounded(decimalPlaces: 1))%"
      } else {
        let formatter = NumberFormatter()
        formatter.numberStyle = .scientific
        formatter.positiveFormat = "0.#E0"
        formatter.exponentSymbol = " × 10^"
        errorString = formatter.string(for: approximationError)!
      }
      return "Error: \(errorString)"
    }).receive(on: DispatchQueue.main).assign(to: \.stringValue, on: approximationErrorTextField)
    cancellables += Publishers.CombineLatest(debuggerCentral.$samples, debuggerCentral.survivingSampleIds).map({ (samples, survivingSampleIds) -> String in
      let percentage: Double
      if samples.count > 0 {
        let survivingSamples = samples.filter({ survivingSampleIds.contains($0.id) })
        percentage = (Double(survivingSamples.count) / Double(samples.count) * 100).rounded(decimalPlaces: 2)
      } else {
        percentage = 0
      }
      return "Surviving: \(percentage)%"
    }).assign(to: \.stringValue, on: survivingTextField)
    
    variablesDataSource = DebuggerVariablesTableViewDataSource(
      debugger: self.debuggerCentral,
      survivingSamplesOnly: self.$survivingSamplesOnlyInVariablesView,
      refineProbabilitiesUsingWpInference: self.$refineProbabilitiesUsingWpInference,
      tableView: self.variablesTableView
    )
    self.variablesTableView.dataSource = variablesDataSource
    self.variablesTableView.delegate = variablesDataSource
    
    executionOutlineDataSource = ExecutionOutlineViewDataSource(
      debuggerCentral: debuggerCentral,
      outlineView: executionOutlineView,
      selectionChangeCallback: { [weak self] in
        self?.runOutlineViewDidSelectExecutionState($0)
      }
    )
    self.executionOutlineView.dataSource = executionOutlineDataSource
    self.executionOutlineView.delegate = executionOutlineDataSource
  }
  
  func runOutlineViewDidSelectExecutionState(_ executionState: IRExecutionState) {
    debuggerCentral.jumpToExecutionState(executionState)
  }
  
  // MARK: Managing the source code
  
  override var representedObject: Any? {
    didSet {
      debuggerCentral.sourceCodeModel = sourceCode
    }
  }
  
  var sourceCode: SourceCode {
    return representedObject as? SourceCode ?? SourceCode(sourceCode: "")
  }
  
  // MARK: Managing the debugger
  
  func clearExecutionOutlineSelection() {
    executionOutlineView.selectRowIndexes([], byExtendingSelection: false)
  }

  @IBAction func stepOver(_ sender: Any) {
    do {
      try debuggerCentral.stepOver()
      clearExecutionOutlineSelection()
    } catch {}
  }
  
  @IBAction func stepIntoTrue(_ sender: Any) {
    do {
      try debuggerCentral.stepInto(branch: true)
      clearExecutionOutlineSelection()
    } catch {}
  }
  
  @IBAction func stepIntoFalse(_ sender: Any) {
    do {
      try debuggerCentral.stepInto(branch: false)
      clearExecutionOutlineSelection()
    } catch {}
  }
}

