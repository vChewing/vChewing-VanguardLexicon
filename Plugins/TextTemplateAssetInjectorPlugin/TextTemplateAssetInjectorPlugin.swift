// (c) 2025 and onwards The vChewing Project (LGPL v3.0 License or later).
// ====================
// This code is released under the SPDX-License-Identifier: `LGPL-3.0-or-later`.

import Foundation
import PackagePlugin

@main
struct TextTemplateAssetInjectorPlugin: CommandPlugin {
  func performCommand(context: PluginContext, arguments: [String]) async throws {
    let packageRoot = context.package.directoryURL

    // Define source paths relative to package root
    let componentsFolderPathStem = "Sources/LibVanguardChewingData/Resources/components"
    let sourcesToInject: [String] = [
      "\(componentsFolderPathStem)/cht/template-associatedPhrases-cht.txt",
      "\(componentsFolderPathStem)/chs/template-associatedPhrases-chs.txt",
    ]

    var extractor = ArgumentExtractor(arguments)
    let targetNames = extractor.extractOption(named: "target")
    let targetsToProcess: [Target] = targetNames.isEmpty
      ? context.package.targets
      : context.package.targets.filter { targetNames.contains($0.name) }

    for target in targetsToProcess {
      guard let sourceTarget = target as? SourceModuleTarget else { continue }
      let targetDir = sourceTarget.directoryURL
      let resourcesDir = targetDir.appendingPathComponent("Resources")
      let destinationDir = resourcesDir.appendingPathComponent("TextTemplateAssets")

      if !FileManager.default.fileExists(atPath: destinationDir.path) {
        try? FileManager.default.createDirectory(
          at: destinationDir,
          withIntermediateDirectories: true
        )
      }

      for relativePath in sourcesToInject {
        let sourceFile = packageRoot.appendingPathComponent(relativePath)
        let fileName = sourceFile.lastPathComponent
        let destFile = destinationDir.appendingPathComponent(fileName)

        guard FileManager.default.fileExists(atPath: sourceFile.path) else {
          Diagnostics.warning("Source file not found at \(sourceFile.path)")
          continue
        }

        if FileManager.default.fileExists(atPath: destFile.path) {
          try FileManager.default.removeItem(at: destFile)
        }
        try FileManager.default.copyItem(at: sourceFile, to: destFile)
        print("Injected \(fileName) into \(target.name)/Resources/TextTemplateAssets")
      }
    }
  }
}
