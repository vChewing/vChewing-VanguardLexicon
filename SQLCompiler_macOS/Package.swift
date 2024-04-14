// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
  name: "SQLCompiler_macOS",
  platforms: [
    .macOS(.v14),
  ],
  products: [
    // Products define the executables and libraries a package produces, making them visible to other packages.
    .executable(
      name: "SQLCompiler_macOS",
      targets: ["SQLCompiler_macOS"]
    ),
  ],
  targets: [
    // Targets are the basic building blocks of a package, defining a module or a test suite.
    // Targets can depend on other targets in this package and products from dependencies.
    .executableTarget(
      name: "SQLCompiler_macOS",
      linkerSettings: [.unsafeFlags([
        "-Xlinker", "-sectcreate",
        "-Xlinker", "__TEXT",
        "-Xlinker", "__info_plist",
        "-Xlinker", "Sources/Resources/Info.plist",
      ])]
    ),
    .testTarget(
      name: "SQLCompiler_macOSTests",
      dependencies: ["SQLCompiler_macOS"]
    ),
  ]
)
