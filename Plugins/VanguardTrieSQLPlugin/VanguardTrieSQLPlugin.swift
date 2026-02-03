// (c) 2025 and onwards The vChewing Project (LGPL v3.0 License or later).
// ====================
// This code is released under the SPDX-License-Identifier: `LGPL-3.0-or-later`.

import Foundation
import PackagePlugin

@main
struct VanguardTrieSQLPlugin: CommandPlugin {
  func performCommand(context: PluginContext, arguments: [String]) async throws {
    let tool = try context.tool(named: "VCDataBuilder")
    let packageRoot = context.package.directoryURL
    let buildDir = packageRoot.appendingPathComponent("Build/Release/vanguard-trie-sql")
    let fileNames = ["VanguardFactoryDict4Typing.sqlite", "VanguardFactoryDict4RevLookup.sqlite"]

    let process = Process()
    process.executableURL = tool.url
    process.arguments = ["vanguardTrieSQL"]
    process.currentDirectoryURL = packageRoot
    try process.run()
    process.waitUntilExit()

    guard process.terminationStatus == 0 else {
      Diagnostics.error("VCDataBuilder failed.")
      return
    }

    var extractor = ArgumentExtractor(arguments)
    let targetNames = extractor.extractOption(named: "target")
    let targetsToProcess: [Target] = targetNames.isEmpty
      ? context.package.targets
      : context.package.targets.filter { targetNames.contains($0.name) }

    for target in targetsToProcess {
      guard let sourceTarget = target as? SourceModuleTarget else { continue }
      let targetDir = sourceTarget.directoryURL
      let resourcesDir = targetDir.appendingPathComponent("Resources")
      let destinationDir = resourcesDir.appendingPathComponent("VanguardLexiconData")

      if !FileManager.default.fileExists(atPath: destinationDir.path) {
        try? FileManager.default.createDirectory(
          at: destinationDir,
          withIntermediateDirectories: true
        )
      }

      for fileName in fileNames {
        let sourceFile = buildDir.appendingPathComponent(fileName)
        let destFile = destinationDir.appendingPathComponent(fileName)

        if FileManager.default.fileExists(atPath: sourceFile.path) {
          if FileManager.default.fileExists(atPath: destFile.path) {
            try FileManager.default.removeItem(at: destFile)
          }
          try FileManager.default.copyItem(at: sourceFile, to: destFile)
          print("Injected \(fileName) into \(target.name)/Resources/VanguardLexiconData")
        } else {
          Diagnostics.warning("Expected output file \(fileName) not found at \(sourceFile.path)")
        }
      }
    }
  }
}
