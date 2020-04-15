//
//  HistogramView.swift
//  ProbabilisticDebugger-UI
//
//  Created by Alex Hoppen on 14.04.20.
//  Copyright © 2020 Alex Hoppen. All rights reserved.
//

import Cocoa

class HistogramViewController: NSViewController {
  var values: [(key: String, value: Double)] {
    get {
      histogramView.values
    }
    set {
      histogramView.values = newValue
    }
  }
  
  private var histogramView: HistogramView = HistogramView()
  
  override func loadView() {
    self.view = histogramView
    self.view.frame = CGRect(x: 0, y: 0, width: 200, height: 200)
    histogramView.makeHistogram()
  }
}

fileprivate class HistogramView: NSView {
  var values: [(key: String, value: Double)] = [] {
    didSet {
      makeHistogram()
    }
  }
  private var histogramSubviews: [NSView] = []
  
  fileprivate func makeHistogram() {
    for view in histogramSubviews {
      view.removeFromSuperview()
    }
    if values.isEmpty {
      return
    }
    
    let barWidth = self.bounds.width / CGFloat(values.count)
    let leftRightSpacing: CGFloat = 0.1
    let labelHeight: CGFloat = 30
    let topBottomSpacing: CGFloat = 10
    
    for (index, (histogramKey, value)) in values.enumerated() {
      assert(value <= 1)
      let frame = NSRect(
        x: CGFloat(index) * barWidth + leftRightSpacing * barWidth,
        y: labelHeight + topBottomSpacing,
        width: barWidth - (2 * leftRightSpacing * barWidth),
        height: CGFloat(value) * (self.bounds.height - labelHeight - 2 * topBottomSpacing)
      )
      let bar = NSView(frame: frame)
      bar.wantsLayer = true
      bar.layer?.backgroundColor = CGColor.init(red: 0, green: 0, blue: 1, alpha: 1)
      self.addSubview(bar)
      self.histogramSubviews.append(bar)
      
      let label = NSTextField(labelWithString: histogramKey)
      label.frame = NSRect(
        x: CGFloat(index) * barWidth + leftRightSpacing * barWidth,
        y: topBottomSpacing,
        width: barWidth - (2 * leftRightSpacing * barWidth),
        height: 20
      )
      label.alignment = .center
      self.addSubview(label)
      self.histogramSubviews.append(label)
    }
  }
}