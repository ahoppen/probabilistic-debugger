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
import IR
import IRExecution
import WPInference
import Utils

private var InspectButtonVariableNameAsssociatedObjectHandle: UInt8 = 0

fileprivate extension Array where Element: Hashable {
  func histogram() -> [Element: Int] {
    return self.reduce(into: [:]) { counts, elem in counts[elem, default: 0] += 1 }
  }
}

fileprivate extension IRValue {
  var doubleValue: Double {
    switch self {
    case .integer(let value):
      return Double(value)
    case .bool(let value):
      return value ? 1 : 0
    }
  }
}

fileprivate struct DataSourceData {
  let displayedSamples: [SourceCodeSample]
  let variableValuesRefinedUsingWPDistributingApproximationError: [String: [IRValue: Double]]?
  let variableValuesRefinedUsingWPDroppingApproxmiationError: [String: [IRValue: Double]]?
  let refineProbabilitiesUsingWpInference: Bool
  let distributeApproximationError: Bool
  
  var variableValuesRefinedUsingWP: [String: [IRValue: Double]]? {
    if distributeApproximationError {
      return variableValuesRefinedUsingWPDistributingApproximationError
    } else {
      return variableValuesRefinedUsingWPDroppingApproxmiationError
    }
  }
}

class DebuggerVariablesTableViewDataSource: NSObject, NSTableViewDataSource, NSTableViewDelegate {
  let debugger: DebuggerCentral
  weak var tableView: NSTableView!
  private var data = DataSourceData(
    displayedSamples: [],
    variableValuesRefinedUsingWPDistributingApproximationError: nil,
    variableValuesRefinedUsingWPDroppingApproxmiationError: nil,
    refineProbabilitiesUsingWpInference: false,
    distributeApproximationError: false
  ) {
    didSet {
      Dispatch.dispatchPrecondition(condition: .onQueue(.main))
      tableView.reloadData()
    }
  }
  var cancellables: [AnyCancellable] = []
  
  init(debugger: DebuggerCentral, survivingSamplesOnly: Published<Bool>.Publisher, refineProbabilitiesUsingWpInference: Published<Bool>.Publisher, distributeApproximationError: Published<Bool>.Publisher, tableView: NSTableView) {
    self.debugger = debugger
    self.tableView = tableView
    super.init()
    let combinedPublisher = Publishers.CombineLatest4(debugger.$samples, debugger.survivingSampleIds,  Publishers.CombineLatest(debugger.$variableValuesRefinedUsingWPDroppingApproxmiationError, debugger.$variableValuesRefinedUsingWPDistributingApproximationError), Publishers.CombineLatest3(survivingSamplesOnly, refineProbabilitiesUsingWpInference, distributeApproximationError))
    let delayedLatest = DelayedLatest(upstream: combinedPublisher, wait: .milliseconds(50), queue: .global(qos: .userInitiated))
    cancellables += delayedLatest.sink { [unowned self] (samples, survivingSampleIds, variableValuesRefinedUsingWP, options) in
      let survivingSamplesOnly = options.0
      let refineProbabilitiesUsingWpInference = options.1
      let distributeApproximationError = options.2
      
      let variableValuesRefinedUsingWPDroppingApproxmiationError = variableValuesRefinedUsingWP.0
      let variableValuesRefinedUsingWPDistributingApproximationError = variableValuesRefinedUsingWP.1
      
      let displayedSamples: [SourceCodeSample]
      if survivingSamplesOnly {
        displayedSamples = samples.filter({ survivingSampleIds.contains($0.id) })
      } else {
        displayedSamples = samples
      }
      
      DispatchQueue.main.async {
        self.data = DataSourceData(
          displayedSamples: displayedSamples,
          variableValuesRefinedUsingWPDistributingApproximationError: variableValuesRefinedUsingWPDistributingApproximationError,
          variableValuesRefinedUsingWPDroppingApproxmiationError: variableValuesRefinedUsingWPDroppingApproxmiationError,
          refineProbabilitiesUsingWpInference: refineProbabilitiesUsingWpInference,
          distributeApproximationError: distributeApproximationError
        )
      }
    }
  }

  func numberOfRows(in tableView: NSTableView) -> Int {
    guard let firstSample = data.displayedSamples.first else {
      return 0
    }
    return firstSample.values.count
  }
  
  @objc func showVariableDistribution(sender: NSButton) {
    let popover = NSPopover()
    
    let viewController = HistogramViewController()
    let variableName = objc_getAssociatedObject(sender, &InspectButtonVariableNameAsssociatedObjectHandle) as! String
    let histogram = data.displayedSamples.map({ $0.values[variableName]! }).histogram()
    let values = histogram.sorted(by: { $0.key.description.localizedStandardCompare($1.key.description) == .orderedAscending }).map({ (irValue: IRValue, occurances: Int) -> (key: String, value: Double) in
      let probability: Double
      if data.refineProbabilitiesUsingWpInference, let variableValuesRefinedUsingWP = data.variableValuesRefinedUsingWP {
        probability = variableValuesRefinedUsingWP[variableName]?[irValue] ?? 0
      } else {
        probability = Double(occurances) / Double(data.displayedSamples.count)
      }
      return (irValue.description, probability)
    }).sorted(by: { $0.key.description.localizedStandardCompare($1.key.description) == .orderedAscending })
    viewController.values = values
    
    popover.contentViewController = viewController
    popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minX)
    popover.behavior = .transient
  }

  func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
    let firstSample = data.displayedSamples.first!
    let variableName = firstSample.values.keys.sorted()[row]
    
    switch tableColumn?.identifier.rawValue {
    case "variable":
      let textView = NSTextField(labelWithString: variableName)
      textView.font = NSFontManager().convert(textView.font!, toHaveTrait: .boldFontMask)
      return textView
    case "average":
      let average: Double
      if data.refineProbabilitiesUsingWpInference, let variableValuesRefinedUsingWP = data.variableValuesRefinedUsingWPDistributingApproximationError {
        average = variableValuesRefinedUsingWP[variableName]!.map({ value, probability in
          return value.doubleValue * probability
        }).reduce(0, { $0 + $1 })
      } else {
        average = data.displayedSamples.map({ (sample) -> Double in
          return sample.values[variableName]!.doubleValue
        }).reduce(0, { $0 + $1}) / Double(data.displayedSamples.count)
      }
      let textView = NSTextField(labelWithString: "\(average.rounded(decimalPlaces: 4))")
      return textView
    case "value":
      let histogram = data.displayedSamples.map({ $0.values[variableName]! }).histogram()
      let values = histogram.sorted(by: { $0.key.description.localizedStandardCompare($1.key.description) == .orderedAscending }).map({ (value, numSamples) in
        let probability: Double
        if data.refineProbabilitiesUsingWpInference, let variableValuesRefinedUsingWP = data.variableValuesRefinedUsingWP {
          probability = variableValuesRefinedUsingWP[variableName]?[value] ?? 0
        } else {
          probability = Double(numSamples) / Double(data.displayedSamples.count)
        }
        return "\(value): \((probability * 100).rounded(decimalPlaces: 2))%"
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
