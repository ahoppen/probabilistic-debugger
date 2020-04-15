//
//  SourceCodeDocument.swift
//  ProbabilisticDebugger-UI
//
//  Created by Alex Hoppen on 08.04.20.
//  Copyright © 2020 Alex Hoppen. All rights reserved.
//

import Cocoa

class SourceCodeDocument: NSDocument {
  
  var sourceCode = SourceCode(sourceCode: "")
  weak var viewController: DebuggerViewController? = nil
  
  override class var autosavesInPlace: Bool {
    return true
  }
  
  override func canAsynchronouslyWrite(to url: URL, ofType typeName: String, for saveOperation: NSDocument.SaveOperationType) -> Bool {
      return true
  }
  
  override class func canConcurrentlyReadDocuments(ofType: String) -> Bool {
      return ofType == "public.plain-text"
  }
  
  override func makeWindowControllers() {
    // Returns the Storyboard that contains your Document window.
    let storyboard = NSStoryboard(name: NSStoryboard.Name("Main"), bundle: nil)
    let windowController = storyboard.instantiateController(withIdentifier: NSStoryboard.SceneIdentifier("DebuggerWindow")) as! NSWindowController
    self.addWindowController(windowController)
    
    viewController = windowController.contentViewController as! DebuggerViewController?
    viewController?.representedObject = sourceCode
  }
  
  override func data(ofType typeName: String) throws -> Data {
    return self.sourceCode.sourceCode.data(using: .utf8)!
  }
  
  override func read(from data: Data, ofType typeName: String) throws {
    self.sourceCode.sourceCode = String(data: data, encoding: .utf8)!
  }
}

