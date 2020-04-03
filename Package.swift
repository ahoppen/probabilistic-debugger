// swift-tools-version:5.2

import PackageDescription

let package = Package(
  name: "ProbabilisticDebugger",
  
  // MARK: - Products
  
  products: [],
  
  // MARK: - Targets
  
  targets: [
    .target(
      name: "IR",
      dependencies: []
    ),
    .target(
      name: "IRExecution",
      dependencies: ["IR"]
    ),
    .target(
      name: "SimpleLanguageAST",
      dependencies: []
    ),
    .target(
      name: "SimpleLanguageDebugger",
      dependencies: [
        "IR",
        "IRExecution",
        "SimpleLanguageAST",
        "SimpleLanguageIRGen",
      ]
    ),
    
    .target(
      name: "SimpleLanguageIRGen",
      dependencies: [
        "IR",
        "SimpleLanguageAST",
        "SimpleLanguageParser",
        "SimpleLanguageTypeChecker"
    ]),
    .target(
      name: "SimpleLanguageParser",
      dependencies: [
        "SimpleLanguageAST"
    ]),
    .target(
      name: "SimpleLanguageTypeChecker",
      dependencies: [
        "SimpleLanguageAST",
        "SimpleLanguageParser",
    ]),
    .target(
      name: "TestUtils",
      dependencies: [
        "SimpleLanguageAST"
      ]
    ),

    
    // MARK: - Test targets
    
    .testTarget(
      name: "IRExecutionTests",
      dependencies: [
        "IR",
        "IRExecution",
        "TestUtils"
      ]
    ),
    .testTarget(
      name: "SimpleLanguageASTTests",
      dependencies: [
        "SimpleLanguageAST"
      ]
    ),
    .testTarget(
      name: "SimpleLanguageDebuggerTests",
      dependencies: [
        "SimpleLanguageAST",
        "SimpleLanguageDebugger",
        "SimpleLanguageIRGen",
        "TestUtils",
      ]
    ),
    .testTarget(
      name: "SimpleLanguageIRGenTests",
      dependencies: [
        "SimpleLanguageAST",
        "SimpleLanguageIRGen",
        "SimpleLanguageParser",
        "SimpleLanguageTypeChecker",
      ]
    ),
    .testTarget(
      name: "SimpleLanguageParserTests",
      dependencies: [
        "SimpleLanguageAST",
        "SimpleLanguageParser",
        "TestUtils",
      ]
    ),
    .testTarget(
      name: "SimpleLanguageTypeCheckerTests",
      dependencies: [
        "SimpleLanguageAST",
        "SimpleLanguageParser",
        "SimpleLanguageTypeChecker",
        "TestUtils",
      ]
    ),
  ]
)
