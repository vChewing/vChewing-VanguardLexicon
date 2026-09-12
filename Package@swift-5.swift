// swift-tools-version: 5.10
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
  name: "VanguardLexicon",
  platforms: [
    .macOS(.v10_15),
  ],
  products: [
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
  targets: [
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
)
