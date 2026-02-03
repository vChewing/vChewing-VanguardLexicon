// (c) 2025 and onwards The vChewing Project (LGPL v3.0 License or later).
// ====================
// This code is released under the SPDX-License-Identifier: `LGPL-3.0-or-later`.

import Foundation
import PackagePlugin

@main
struct TextTemplateAssetInjectorPlugin: BuildToolPlugin {
  func createBuildCommands(context: PluginContext, target: Target) async throws -> [Command] {
    let tool = try context.tool(named: "VCDataBuilder")
    let outputDir = context.pluginWorkDirectoryURL.appending(path: "TextTemplateAssets")
    // Ensure output directory is clean/exists? The tool does createDirectory.

    let outputFiles = [
      outputDir.appending(path: "template-associatedPhrases-cht.txt"),
      outputDir.appending(path: "template-associatedPhrases-chs.txt"),
    ]

    return [
      .buildCommand(
        displayName: "Extracting Text Template Assets",
        executable: tool.url,
        arguments: ["extract-text-templates", outputDir.path],
        environment: [:],
        inputFiles: [],
        outputFiles: outputFiles
      ),
    ]
  }
}
