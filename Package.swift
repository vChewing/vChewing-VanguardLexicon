// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
  name: "VanguardLexicon",
  platforms: [
    .macOS(.v10_15),
  ],
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
    .plugin(
      name: "TextTemplateAssetInjectorPlugin",
      targets: ["TextTemplateAssetInjectorPlugin"]
    ),
    .plugin(
      name: "VanguardTextMapPlugin",
      targets: ["VanguardTextMapPlugin"]
    ),
  ],
  targets: {
    let targets: [Target] = [
      .target(
        name: "VanguardTrieKit",
        resources: [
          .process("Licenses/"),
        ]
      ),
      .target(
        name: "LibVanguardChewingData",
        dependencies: ["VanguardTrieKit"],
        resources: [
          .process("./Resources/"),
        ]
      ),
      .executableTarget(
        name: "VCDataBuilder",
        dependencies: ["LibVanguardChewingData"]
      ),
      .plugin(
        name: "TextTemplateAssetInjectorPlugin",
        capability: .buildTool(),
        dependencies: ["VCDataBuilder"]
      ),
      .plugin(
        name: "VanguardTextMapPlugin",
        capability: .buildTool(),
        dependencies: ["VCDataBuilder"]
      ),
    ]

    #if compiler(>=6.0)
      // Swift Testing is only available in Swift 6.0 and later.
      return targets + [
        .testTarget(
          name: "LibVanguardChewingDataTests",
          dependencies: ["LibVanguardChewingData"]
        ),
      ]
    #else
      return targets
    #endif
  }()
)
