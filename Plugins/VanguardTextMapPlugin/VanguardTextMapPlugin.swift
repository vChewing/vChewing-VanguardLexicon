// (c) 2025 and onwards The vChewing Project (LGPL v3.0 License or later).
// ====================
// This code is released under the SPDX-License-Identifier: `LGPL-3.0-or-later`.

import Foundation
import PackagePlugin

// VanguardTextMap 不包括 RevLookup 資料，因為這種資料可以通過主資料表直接產生。

@main
struct VanguardTextMapPlugin: BuildToolPlugin {
  func createBuildCommands(context: PluginContext, target: Target) async throws -> [Command] {
    let tool = try context.tool(named: "VCDataBuilder")
    let buildDir = context.pluginWorkDirectoryURL.appending(path: "VanguardLexiconData/Build/Release/vanguard-textmap")
    let outputFiles = [
      buildDir.appending(path: "VanguardFactoryDict4Typing.txtMap"),
    ]

    return [
      .buildCommand(
        displayName: "VCDataBuilder: VanguardTextMap",
        executable: tool.url,
        arguments: ["vanguardTextMap"],
        environment: [
          "VANGUARD_OUTPUT_DIR": context.pluginWorkDirectoryURL.appending(path: "VanguardLexiconData").path,
        ],
        inputFiles: [],
        outputFiles: outputFiles
      ),
    ]
  }
}
