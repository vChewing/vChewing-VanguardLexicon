#!/usr/bin/env swift

// Copyright (c) 2021 and onwards The vChewing Project (MIT-NTL License).
// ====================
// This code is released under the MIT license (SPDX-License-Identifier: MIT)
// ... with NTL restriction stating that:
// No trademark license is granted to use the trade names, trademarks, service
// marks, or product names of Contributor, except as required to fulfill notice
// requirements defined in MIT License.

import Foundation

let strDataPath = "../components"

func handleFiles(_ handler: @escaping ((url: URL, fileName: String)) -> Void) {
  let rawURLs = FileManager.default.enumerator(at: URL(fileURLWithPath: strDataPath), includingPropertiesForKeys: nil)?.compactMap { $0 as? URL }
  rawURLs?.forEach { url in
    guard let fileName = url.pathComponents.last, fileName.suffix(4).lowercased() == ".txt", fileName.prefix(8) == "phrases-" else { return }
    guard !fileName.contains("custom") else { return }
    handler((url, fileName))
  }
}

handleFiles { url, fileName in
  guard let rawStr = try? String(contentsOf: url, encoding: .utf8) else { return }
  var headerLines = [String]()
  var contentLines = [String]()
  rawStr.enumerateLines { currentLine, _ in
    guard !currentLine.isEmpty else { return }
    switch currentLine.prefix(2) {
    case "#=", "# ": headerLines.append(currentLine)
    default: contentLines.append(currentLine)
    }
  }
  let locale = Locale(identifier: "zh@collation=stroke")
  headerLines.append("")
  contentLines.sort {
    $0.compare($1, locale: locale) == .orderedAscending
  }
  do {
    try (headerLines + contentLines)
      .joined(separator: "\n")
      .description.appending("\n")
      .write(to: url, atomically: false, encoding: .utf8)
  } catch {
    print("!! Error writing to \(fileName)")
  }
}
