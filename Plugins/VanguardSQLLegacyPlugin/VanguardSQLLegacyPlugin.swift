// (c) 2025 and onwards The vChewing Project (LGPL v3.0 License or later).
// ====================
// This code is released under the SPDX-License-Identifier: `LGPL-3.0-or-later`.

import Foundation
import PackagePlugin

@main
struct VanguardSQLLegacyPlugin: BuildToolPlugin {
  func createBuildCommands(context: PluginContext, target: Target) async throws -> [Command] {
    let tool = try context.tool(named: "VCDataBuilder")
    #if compiler(>=6.0)
      let buildDir = context.pluginWorkDirectoryURL
        .appending(path: "VanguardLexiconData/Build/Release/vanguardSQL-Legacy")
      let outputFiles = [
        buildDir.appending(path: "vChewingFactoryDatabase.sqlite"),
      ]

      return [
        .buildCommand(
          displayName: "VCDataBuilder: VanguardSQLLegacy",
          executable: tool.url,
          arguments: ["vanguardSQLLegacy"],
          environment: [
            "VANGUARD_OUTPUT_DIR": context.pluginWorkDirectoryURL.appending(path: "VanguardLexiconData").path,
          ],
          inputFiles: [],
          outputFiles: outputFiles
        ),
      ]
    #else
      let buildDir = context.pluginWorkDirectory
        .appending("VanguardLexiconData/Build/Release/vanguardSQL-Legacy")
      let outputFiles = [
        buildDir.appending("vChewingFactoryDatabase.sqlite"),
      ]

      return [
        .buildCommand(
          displayName: "VCDataBuilder: VanguardSQLLegacy",
          executable: tool.path,
          arguments: ["vanguardSQLLegacy"],
          environment: [
            "VANGUARD_OUTPUT_DIR": context.pluginWorkDirectory.appending("VanguardLexiconData").string,
          ],
          inputFiles: [],
          outputFiles: outputFiles
        ),
      ]
    #endif
  }
}
