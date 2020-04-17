//
//  ExecutionOutlineViewDataSource.swift
//  ProbabilisticDebugger-UI
//
//  Created by Alex Hoppen on 09.04.20.
//  Copyright © 2020 Alex Hoppen. All rights reserved.
//

import Cocoa
import Debugger
import IR
import IRExecution
import SimpleLanguageIRGen
import Combine
import WPInference

enum ExecutionOutlineRow {
  case entry(name: String? = nil, entry: ExecutionOutlineEntry)
  case sequence(name: String, children: [ExecutionOutlineRow])
  
  var state: IRExecutionState? {
    switch self {
    case .entry(name: _, let entry):
      return entry.state
    case .sequence(name: _, children: let children):
      return children.first?.state
    }
  }
}

extension Double {
  func rounded(decimalPlaces: Int) -> Double {
    let padding = pow(10, Double(decimalPlaces))
    return (self * padding).rounded() / padding
  }
}

fileprivate extension String {
  subscript(sourceCodeRange: Range<SourceCodeLocation>) -> String {
    let sourceLine = self.split(separator: "\n", omittingEmptySubsequences: false)[sourceCodeRange.lowerBound.line - 1]
    let lowerBound = sourceLine.index(sourceLine.startIndex, offsetBy: sourceCodeRange.lowerBound.column - 1)
    let upperBound: String.Index
    if sourceCodeRange.lowerBound.line == sourceCodeRange.upperBound.line {
      upperBound = sourceLine.index(sourceLine.startIndex, offsetBy: sourceCodeRange.upperBound.column - 1)
    } else {
      upperBound = sourceLine.endIndex
    }
    return String(sourceLine[lowerBound..<upperBound])
  }
}


fileprivate extension IRExecutionState {
  func reachingProbability(in program: IRProgram) -> Double {
      let inferenceEngine = WPInferenceEngine(program: program)
    let inferred = inferenceEngine.infer(term: .integer(1), loopUnrolls: self.loopUnrolls, inferenceStopPosition: self.position)
    return (inferred.value / inferred.runsNotCutOffByLoopIterationBounds).doubleValue
  }
}


struct ExecutionOutlineViewData {
  let outline: ExecutionOutline
  let survivingSampleIds: Set<Int>
  let program: IRProgram?
  let debugInfo: DebugInfo?
}

class ExecutionOutlineViewDataSource: NSObject, NSOutlineViewDelegate, NSOutlineViewDataSource {
  weak var outlineView: NSOutlineView!
  let debuggerCentral: DebuggerCentral!
  var cancellables: [AnyCancellable] = []
  let selectionChangeCallback: (IRExecutionState) -> Void
  var data: ExecutionOutlineViewData = ExecutionOutlineViewData(outline: [], survivingSampleIds: [], program: nil, debugInfo: nil) {
    didSet {
      dispatchPrecondition(condition: .onQueue(.main))
      outlineView.reloadData()
    }
  }
  
  init(debuggerCentral: DebuggerCentral, outlineView: NSOutlineView, selectionChangeCallback: @escaping (IRExecutionState) -> Void) {
    self.debuggerCentral = debuggerCentral
    self.outlineView = outlineView
    self.selectionChangeCallback = selectionChangeCallback
    
    super.init()
    
    cancellables += Publishers.CombineLatest3(debuggerCentral.executionOutline, debuggerCentral.survivingSampleIds, debuggerCentral.irAndDebugInfo).sink { [unowned self] (outline, survivingSampleIds, irAndDebugInfo) in
      self.data = ExecutionOutlineViewData(
        outline: outline.success ?? [],
        survivingSampleIds: survivingSampleIds,
        program: irAndDebugInfo.success?.program,
        debugInfo: irAndDebugInfo.success?.debugInfo
      )
    }
  }
  
  func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
    let row = item as! ExecutionOutlineRow?
    return executionOutlineView(numberOfChildrenOfItem: row)
  }
  
  func executionOutlineView(numberOfChildrenOfItem item: ExecutionOutlineRow?) -> Int {
    switch item {
    case nil:
      return data.outline.entries.count
    case .entry(name: _, entry: let entry):
      switch entry {
      case .instruction(state: _):
        return 0
      case .end(state: _):
        return 0
      case .branch(state: _, true: let trueBranch, false: let falseBranch):
        return [trueBranch, falseBranch].compactMap({ $0 }).count
      case .loop(state: _, iterations: _, exitStates: _):
        return 2
      }
    case .sequence(name: _, children: let children):
      return children.count
    }
  }
  
  func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
    let row = item as! ExecutionOutlineRow?
    return executionOutlineViewRow(child: index, ofItem: row)
  }
  
  func executionOutlineViewRow(child index: Int, ofItem item: ExecutionOutlineRow?) -> ExecutionOutlineRow {
    switch item {
    case nil:
      // Return top level entries
      return data.outline.entries.map({ ExecutionOutlineRow.entry(entry: $0) })[index]
    case .entry(name: _, entry: .instruction):
      fatalError("Does not have any children")
    case .entry(name: _, entry: .end):
      fatalError("Does not have any children")
    case .entry(name: _, entry: .branch(state: _, true: let trueBranch, false: let falseBranch)):
      switch (trueBranch, falseBranch, index) {
      case (.some(let trueBranch), .some, 0):
        return .sequence(name: "true-Branch", children: trueBranch.entries.map({ ExecutionOutlineRow.entry(entry: $0) }))
      case (.some(let trueBranch), nil, 0):
        return .sequence(name: "true-Branch", children: trueBranch.entries.map({ ExecutionOutlineRow.entry(entry: $0) }))
      case (.some, .some(let falseBranch), 1):
        return .sequence(name: "false-Branch", children: falseBranch.entries.map({ ExecutionOutlineRow.entry(entry: $0) }))
      case (nil, .some(let falseBranch), 0):
        return .sequence(name: "false-Branch", children: falseBranch.entries.map({ ExecutionOutlineRow.entry(entry: $0) }))
      default:
        fatalError()
      }
    case .entry(name: _, entry: .loop(state: _, iterations: let iterations, exitStates: let exitStates)):
      if index == 0 {
        return ExecutionOutlineRow.sequence(name: "Iterations", children: iterations.enumerated().map({ (index, iteration) in
          return ExecutionOutlineRow.sequence(name: "Iteration \(index + 1)", children: iteration.entries.map({ ExecutionOutlineRow.entry(entry: $0) }))
        }))
      } else if index == 1 {
        return ExecutionOutlineRow.sequence(name: "Exit states", children: exitStates.enumerated().map({ (index, exitState) in
          return ExecutionOutlineRow.entry(name: "≤ \(index) iterations", entry: .instruction(state: exitState))
        }))
      } else {
        fatalError("Loop rows only have two children")
      }
    case .sequence(name: _, let executionOutline):
      return executionOutline[index]
    }
  }
  
  func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
    return self.outlineView(outlineView, numberOfChildrenOfItem: item) > 0
  }
  
  func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
    let row = item as! ExecutionOutlineRow
    switch tableColumn?.identifier.rawValue {
    case "code":
      return executionOutlineCodeCell(item: row)
    case "samples":
      let label = executionOutlineSamplesCellText(item: row)
      return NSTextField(labelWithString: label)
    case "survival":
      let label = executionOutlineSurvivalCellText(item: row)
      return NSTextField(labelWithString: label)
    default:
      fatalError()
    }
    
  }
  
  func executionOutlineCodeCell(item: ExecutionOutlineRow) -> NSTextField {
    switch item {
    case .entry(name: let name, entry: let entry):
      if let name = name {
        let textField = NSTextField(labelWithString: name)
        textField.font = NSFontManager().convert(textField.font!, toHaveTrait: .italicFontMask)
        return textField
      }
      if case .end = entry {
        let textField = NSTextField(labelWithString: "end")
        textField.font = NSFontManager().convert(textField.font!, toHaveTrait: .italicFontMask)
        return textField
      }
      if let debugInfo = data.debugInfo {
        let instructionPosition = entry.state.position
        let sourceRange = debugInfo.info[instructionPosition]!.sourceCodeRange
        let sourceLine = debuggerCentral.sourceCode[sourceRange]
        let textField = NSTextField(labelWithString: sourceLine)
        textField.font = NSFontManager().convert(textField.font!, toHaveTrait: .boldFontMask)
        return textField
      } else {
        return NSTextField(labelWithString: entry.state.position.description)
      }
    case .sequence(name: let name, _):
      let textField = NSTextField(labelWithString: name)
      textField.font = NSFontManager().convert(textField.font!, toHaveTrait: .italicFontMask)
      return textField
    }
  }
  
  func executionOutlineSamplesCellText(item: ExecutionOutlineRow) -> String {
    if let state = item.state, let program = data.program {
      let reachingProbability = state.reachingProbability(in: program)
      let percentage = (reachingProbability * 100).rounded(decimalPlaces: 2)
      return "\(percentage)%"
    } else {
      return ""
    }
  }
  
  func executionOutlineSurvivalCellText(item: ExecutionOutlineRow) -> String {
    if let samples = item.state?.samples, samples.count > 0 {
      let survivingSamples = samples.filter({ data.survivingSampleIds.contains($0.id) })
      let percentage = (Double(survivingSamples.count) / Double(samples.count) * 100).rounded(decimalPlaces: 2)
      return "\(percentage)%"
    } else {
      return ""
    }
  }
  
  func outlineViewSelectionDidChange(_ notification: Notification) {
    if outlineView.selectedRow == -1 {
      return
    }
    let outlineView = notification.object as! NSOutlineView
    let selectedRow = outlineView.item(atRow: outlineView.selectedRow) as! ExecutionOutlineRow
    if let state = selectedRow.state {
      selectionChangeCallback(state)
    }
  }
}
