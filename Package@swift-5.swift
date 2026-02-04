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
  targets: [
    .target(
      name: "CSQLite3",
      path: "CSQLite3/Sources/CSQLite3",
      cSettings: buildCSQLiteSettings()
    ),
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
      capability: .buildTool(),
      dependencies: ["VCDataBuilder"]
    ),
    .plugin(
      name: "VanguardSQLLegacyPlugin",
      capability: .buildTool(),
      dependencies: ["VCDataBuilder"]
    ),
    .plugin(
      name: "TextTemplateAssetInjectorPlugin",
      capability: .buildTool(),
      dependencies: ["VCDataBuilder"]
    ),
  ]
)

func buildCSQLiteSettings() -> [CSetting] {
  var settings: [CSetting] = [
    .unsafeFlags(["-w"]),
    // Common performance optimizations
    .define("SQLITE_THREADSAFE", to: "2"), // Multi-thread safe
    .define("SQLITE_DEFAULT_CACHE_SIZE", to: "-64000"), // 64MB cache
    .define("SQLITE_DEFAULT_PAGE_SIZE", to: "4096"), // 4KB pages
    .define("SQLITE_DEFAULT_TEMP_CACHE_SIZE", to: "-32000"), // 32MB temp cache
    .define("SQLITE_OMIT_DEPRECATED"), // Remove deprecated APIs
    .define("SQLITE_OMIT_LOAD_EXTENSION"), // No dynamic loading
    .define("SQLITE_OMIT_SHARED_CACHE"), // No shared cache (read-only DB)
    .define("SQLITE_OMIT_UTF16"), // Only UTF-8 support
    .define("SQLITE_OMIT_PROGRESS_CALLBACK"), // No progress callbacks
    .define("SQLITE_MAX_EXPR_DEPTH", to: "0"), // No expression depth limit
    .define("SQLITE_USE_ALLOCA"), // Use alloca for small allocations
    .define("SQLITE_ENABLE_MEMORY_MANAGEMENT"), // Better memory management
    .define("SQLITE_ENABLE_FAST_SECURE_DELETE"), // Faster deletes
  ]

  #if os(Windows)
    settings.append(.define("SQLITE_WIN32_MALLOC"))
    settings.append(.define("SQLITE_WIN32_MALLOC_VALIDATE"))
  #endif

  #if canImport(Darwin)
    settings.append(.define("SQLITE_ENABLE_LOCKING_STYLE", to: "1"))
  #endif

  return settings
}
