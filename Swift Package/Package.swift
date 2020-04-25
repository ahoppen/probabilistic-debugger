// swift-tools-version:5.2

import PackageDescription

let package = Package(
  name: "ProbabilisticDebugger",
  
  // MARK: - Products
  
  products: [
    .executable(name: "ppdb", targets: ["DebuggerConsole"]),
    .library(name: "libppdb", targets: ["Debugger", "SimpleLanguageIRGen", "WPInference"])
  ],
  
  dependencies: [
    .package(url: "https://github.com/apple/swift-argument-parser", from: "0.0.1"),
  ],
  
  // MARK: - Targets
  
  targets: [
    .target(
      name: "Debugger",
      dependencies: [
        "IR",
        "IRExecution",
        "Utils",
        "WPInference"
      ]
    ),
    .target(
      name: "DebuggerConsole",
      dependencies: [
        .product(name: "ArgumentParser", package: "swift-argument-parser"),
        "Debugger",
        "IR",
        "SimpleLanguageIRGen",
      ]
    ),
    .target(
      name: "IR",
      dependencies: [
        "Utils",
      ]
    ),
    .target(
      name: "IRExecution",
      dependencies: ["IR"]
    ),
    .target(
      name: "SimpleLanguageAST",
      dependencies: [
        "Utils"
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
    .target(
      name: "Utils",
      dependencies: []
    ),
    .target(
      name: "WPInference",
      dependencies: [
        "IR",
        "IRExecution",
        "Utils"
      ]
    ),

    
    // MARK: - Test targets
    
    .testTarget(
      name: "DebuggerTests",
      dependencies: [
        "Debugger",
        "IR",
        "IRExecution",
        "SimpleLanguageIRGen",
        "TestUtils",
      ]
    ),
    .testTarget(
      name: "IRTests",
      dependencies: [
        "IR",
      ]
    ),
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
        "SimpleLanguageAST",
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
    .testTarget(
      name: "WPInferenceTests",
      dependencies: [
        "IR",
        "IRExecution",
        "WPInference"
      ]
    ),
  ]
)
