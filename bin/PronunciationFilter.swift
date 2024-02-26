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

let cmdParameters = CommandLine.arguments.dropFirst(1)

guard cmdParameters.count == 2 else { exit(1) }
print("即將濾除字音配對: \(cmdParameters)")
let filteredKanji = cmdParameters.first ?? ""
let filteredReading = cmdParameters.last ?? ""

guard filteredKanji.count == 1, !filteredReading.isEmpty else { exit(1) }

func shouldKeep(line givenLine: inout String) -> Bool {
  var cells = givenLine.split(separator: " ")
  guard let valueCell = cells.first, cells.count >= 3 else {
    print("skipping line: \(givenLine)")
    return true
  }
  cells.removeFirst(2)
  if let cellsLast = cells.last, cellsLast.hasPrefix("#") {
    cells.removeLast()
  }
  guard cells.count == valueCell.count else {
    print("skipping line: \(givenLine)")
    return true
  }
  for (theID, theChar) in valueCell.enumerated() {
    if cells[theID] == filteredReading, theChar.description == filteredKanji {
      return false
    }
  }
  return true
}

handleFiles { url, fileName in
  guard let rawStr = try? String(contentsOf: url, encoding: .utf8) else { return }
  var headerLines = [String]()
  var contentLines = [String]()
  rawStr.enumerateLines { currentLine, _ in
    guard !currentLine.isEmpty else { return }
    switch currentLine.prefix(2) {
    case "#=", "# ": headerLines.append(currentLine)
    default:
      var currentLineToWrite = currentLine
      guard shouldKeep(line: &currentLineToWrite) else { return }
      contentLines.append(currentLineToWrite)
    }
  }
  headerLines.append("")
  do {
    try (headerLines + contentLines)
      .joined(separator: "\n")
      .description.appending("\n")
      .write(to: url, atomically: false, encoding: .utf8)
  } catch {
    print("!! Error writing to \(fileName)")
  }
}
