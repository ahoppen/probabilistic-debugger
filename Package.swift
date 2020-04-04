// swift-tools-version:5.2

import PackageDescription

let package = Package(
  name: "ProbabilisticDebugger",
  
  // MARK: - Products
  
  products: [
    .executable(name: "ppdb", targets: ["DebuggerConsole"])
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
      ]
    ),
    .target(
      name: "DebuggerConsole",
      dependencies: [
        .product(name: "ArgumentParser", package: "swift-argument-parser"),
        "Debugger",
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
      dependencies: []
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

    
    // MARK: - Test targets
    
    .testTarget(
      name: "DebuggerTests",
      dependencies: [
        "Debugger",
        "IR",
        "SimpleLanguageIRGen",
        "TestUtils",
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
  ]
)
