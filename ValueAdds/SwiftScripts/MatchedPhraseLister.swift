#!/usr/bin/env swift

// (c) 2021 and onwards The vChewing Project (BSD-3-Clause).
// ====================
// This code is released under the SPDX-License-Identifier: `BSD-3-Clause`.

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

let cmdParameters = CommandLine.arguments.dropFirst(1)

guard cmdParameters.count == 2 else { exit(1) }
print("即將查找包含该字音配對的内容: \(cmdParameters)")
let filteredKanji = cmdParameters.first ?? ""
let filteredReading = cmdParameters.last ?? ""

guard filteredKanji.count == 1, !filteredReading.isEmpty else { exit(1) }

func shouldOmit(line givenLine: inout String) -> Bool {
  guard givenLine.prefix(3) != "## " else { return true }
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
