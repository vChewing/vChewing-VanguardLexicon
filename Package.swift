// swift-tools-version: 5.7
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
  name: "LibVanguardChewingData",
  platforms: [.macOS(.v10_15)],
  products: [
    // Products define the executables and libraries a package produces, making them visible to other packages.
    .library(
      name: "LibVanguardChewingData",
      targets: ["LibVanguardChewingData"]
    ),
    .executable(
      name: "VCDataBuilder",
      targets: ["VCDataBuilder"]
    ),
  ],
  targets: {
    var targets: [Target] = [
      .target(
        name: "LibVanguardChewingData",
        resources: [
          .process("./Resources/"),
        ]
      ),
      .executableTarget(
        name: "VCDataBuilder",
        dependencies: ["LibVanguardChewingData"]
      ),
    ]

    #if compiler(>=6.0)
    // Swift Testing is only available in Swift 6.0 and later.
    targets.append(
      .testTarget(
        name: "LibVanguardChewingDataTests",
        dependencies: ["LibVanguardChewingData"]
      )
    )
    #endif

    return targets
  }()
)
