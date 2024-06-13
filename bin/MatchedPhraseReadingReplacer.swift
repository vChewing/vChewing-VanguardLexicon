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

func handleFiles(_ handler: @escaping ((url: URL, fileName: String)) -> ()) {
  let rawURLs = FileManager.default.enumerator(
    at: URL(fileURLWithPath: strDataPath),
    includingPropertiesForKeys: nil
  )?.compactMap { $0 as? URL }
  rawURLs?.forEach { url in
    guard let fileName = url.pathComponents.last, fileName.suffix(4).lowercased() == ".txt",
          fileName.prefix(8) == "phrases-" else { return }
    // guard !fileName.contains("custom") else { return }
    handler((url, fileName))
  }
}

var cmdParameters = Array(CommandLine.arguments.dropFirst(1))

guard cmdParameters.count == 3 else { exit(1) }
print("即將查找包含该字音配對的内容、且将您计划修改成的内容列印出来: \(cmdParameters)")
let kanjiToMatch = cmdParameters[0]
let readingToMatch = cmdParameters[1]
let newReading = cmdParameters[2]

guard kanjiToMatch.count == 1, !readingToMatch.isEmpty else { exit(1) }

func shouldOmit(line givenLine: inout String) -> Bool {
  guard givenLine.prefix(3) != "## " else { return true }
  var cells = givenLine.split(separator: " ").map(\.description)
  guard let valueCell = cells.first, cells.count >= 3 else {
    print("skipping line: \(givenLine)")
    return true
  }
  var valueAndFreq: [String] = []
  valueAndFreq.append(cells[0])
  cells.removeFirst(1)
  valueAndFreq.append(cells[0])
  cells.removeFirst(1)
  if let cellsLast = cells.last, cellsLast.hasPrefix("#") {
    cells.removeLast()
  }
  guard cells.count == valueCell.count else {
    print("skipping line: \(givenLine)")
    return true
  }
  var altered = false
  for (theID, theChar) in valueCell.enumerated() {
    if cells[theID] == readingToMatch, theChar.description == kanjiToMatch {
      cells[theID] = newReading
      altered = true
    }
  }
  if altered {
    givenLine = (valueAndFreq + cells).joined(separator: " ")
  }
  return !altered
}

handleFiles { url, fileName in
  guard let rawStr = try? String(contentsOf: url, encoding: .utf8) else { return }
  print("// \(fileName)")
  rawStr.enumerateLines { currentLine, _ in
    guard !currentLine.isEmpty else { return }
    switch currentLine.prefix(2) {
    case "# ", "#=": return
    default:
      var currentLineToWrite = currentLine
      if shouldOmit(line: &currentLineToWrite) { return }
      print(currentLineToWrite)
    }
  }
}
