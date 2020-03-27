// swift-tools-version:5.2

import PackageDescription

let package = Package(
  name: "ProbabilisticDebugger",
  products: [
    .library(
      name: "ProbabilisticDebugger",
      targets: ["ProbabilisticDebugger"]),
  ],
  targets: [
    .target(
      name: "ProbabilisticDebugger",
      dependencies: []),
    .testTarget(
      name: "ProbabilisticDebuggerTests",
      dependencies: ["ProbabilisticDebugger"]),
  ]
)
