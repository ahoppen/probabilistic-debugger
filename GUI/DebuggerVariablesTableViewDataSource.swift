//
//  DebuggerVariablesTableViewDataSource.swift
//  ProbabilisticDebugger-UI
//
//  Created by Alex Hoppen on 09.04.20.
//  Copyright © 2020 Alex Hoppen. All rights reserved.
//

import Cocoa
import Combine
import Debugger
import ObjectiveC
import IRExecution

private var InspectButtonVariableNameAsssociatedObjectHandle: UInt8 = 0

fileprivate extension Array where Element: Hashable {
  func histogram() -> [Element: Int] {
    return self.reduce(into: [:]) { counts, elem in counts[elem, default: 0] += 1 }
  }
}

class DebuggerVariablesTableViewDataSource: NSObject, NSTableViewDataSource, NSTableViewDelegate {
  let debugger: DebuggerCentral
  weak var tableView: NSTableView!
  private var displayedSamples: [SourceCodeSample] = []
  @DelayedImmutable var samplesObserver: AnyCancellable!
  
  init(debugger: DebuggerCentral, survivingSamplesOnly: Published<Bool>.Publisher, tableView: NSTableView) {
    self.debugger = debugger
    self.tableView = tableView
    super.init()
    self.samplesObserver = Publishers.CombineLatest3(self.debugger.$samples, self.debugger.survivingSampleIds, survivingSamplesOnly).sink { [unowned self] (samples, survivingSampleIds, survivingSamplesOnly) in
      DispatchQueue.main.async {
        if survivingSamplesOnly {
          self.displayedSamples = samples.filter({ survivingSampleIds.contains($0.id) })
        } else {
          self.displayedSamples = samples
        }
        self.tableView.reloadData()
      }
    }
  }

  func numberOfRows(in tableView: NSTableView) -> Int {
    guard let firstSample = displayedSamples.first else {
      return 0
    }
    return firstSample.values.count
  }
  
  @objc func showVariableDistribution(sender: NSButton) {
    let popover = NSPopover()
    
    let viewController = HistogramViewController()
    let variableName = objc_getAssociatedObject(sender, &InspectButtonVariableNameAsssociatedObjectHandle) as! String
    let histogram = displayedSamples.map({ $0.values[variableName]! }).histogram()
    let values = histogram.map({ (item: (irValue: IRValue, occurances: Int)) -> (key: String, value: Double) in
      return (item.irValue.description, Double(item.occurances) / Double(self.displayedSamples.count))
    }).sorted(by: { $0.key < $1.key })
    viewController.values = values
    
    popover.contentViewController = viewController
    popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minX)
    popover.behavior = .transient
  }

  func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
    let firstSample = displayedSamples.first!
    let variableName = firstSample.values.keys.sorted()[row]
    
    switch tableColumn?.identifier.rawValue {
    case "variable":
      let textView = NSTextField(labelWithString: variableName)
      textView.font = NSFontManager().convert(textView.font!, toHaveTrait: .boldFontMask)
      return textView
    case "average":
      let average = displayedSamples.map({ (sample) -> Double in
        switch sample.values[variableName]! {
        case .integer(let value):
          return Double(value)
        case .bool(let value):
          return value ? 1 : 0
        }
      }).reduce(0, { $0 + $1}) / Double(displayedSamples.count)
      let textView = NSTextField(labelWithString: "\(average.rounded(decimalPlaces: 4))")
      return textView
    case "value":
      let histogram = displayedSamples.map({ $0.values[variableName]! }).histogram()
      let values = histogram.sorted(by: { $0.key < $1.key }).map({ (value, frequency) in
        "\(value): \((Double(frequency) / Double(displayedSamples.count) * 100).rounded(decimalPlaces: 2))%"
      }).joined(separator: ", ")
      let textView = NSTextField(labelWithString: values)
      return textView
    case "inspect":
      let button = NSButton(title: "􀋭", target: self, action: #selector(self.showVariableDistribution(sender:)))
      button.isBordered = false
      objc_setAssociatedObject(button, &InspectButtonVariableNameAsssociatedObjectHandle, variableName, .OBJC_ASSOCIATION_RETAIN)
      return button
    default:
      fatalError("Unknown column")
    }
  }
}
