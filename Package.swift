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
      name: "VanguardTrieSQLPlugin",
      targets: ["VanguardTrieSQLPlugin"]
    ),
    .plugin(
      name: "VanguardSQLLegacyPlugin",
      targets: ["VanguardSQLLegacyPlugin"]
    ),
    .plugin(
      name: "TextTemplateAssetInjectorPlugin",
      targets: ["TextTemplateAssetInjectorPlugin"]
    ),
  ],
  dependencies: [
    .package(path: "CSQLite3"),
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
        dependencies: ["VanguardTrieKit", "CSQLite3"],
        resources: [
          .process("./Resources/"),
        ]
      ),
      .executableTarget(
        name: "VCDataBuilder",
        dependencies: ["LibVanguardChewingData", "CSQLite3"]
      ),
      .plugin(
        name: "VanguardTrieSQLPlugin",
        capability: .command(
          intent: .custom(
            verb: "vanguard-trie-sql",
            description: "Generates VanguardTrieSQL data and injects it into Resources"
          ),
          permissions: [
            .writeToPackageDirectory(reason: "This command injects resources into the package sources."),
          ]
        ),
        dependencies: ["VCDataBuilder"]
      ),
      .plugin(
        name: "VanguardSQLLegacyPlugin",
        capability: .command(
          intent: .custom(
            verb: "vanguard-sql-legacy",
            description: "Generates VanguardSQLLegacy data and injects it into Resources"
          ),
          permissions: [
            .writeToPackageDirectory(reason: "This command injects resources into the package sources."),
          ]
        ),
        dependencies: ["VCDataBuilder"]
      ),
      .plugin(
        name: "TextTemplateAssetInjectorPlugin",
        capability: .command(
          intent: .custom(
            verb: "inject-text-template-assets",
            description: "Injects text template assets into Resources/TextTemplateAssets"
          ),
          permissions: [
            .writeToPackageDirectory(reason: "This command injects resources into the package sources."),
          ]
        )
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
