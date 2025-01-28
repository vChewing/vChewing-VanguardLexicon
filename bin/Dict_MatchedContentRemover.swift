#!/usr/bin/env swift

// (c) 2021 and onwards The vChewing Project (MIT-NTL License).
// ====================
// This code is released under the MIT license (SPDX-License-Identifier: MIT)
// ... with NTL restriction stating that:
// No trademark license is granted to use the trade names, trademarks, service
// marks, or product names of Contributor, except as required to fulfill notice
// requirements defined in MIT License.

// 開發用私人腳本，將自己記錄的語彙過濾表的內容同步到威注音語彙庫內。

import Foundation

// MARK: - Constants

let chsFilterRaw =
  try? String(
    contentsOfFile: "/Users/shikisuen/Library/Mobile Documents/com~apple~CloudDocs/vChewing/exclude-phrases-chs.txt",
    encoding: .utf8
  )
let chtFilterRaw =
  try? String(
    contentsOfFile: "/Users/shikisuen/Library/Mobile Documents/com~apple~CloudDocs/vChewing/exclude-phrases-cht.txt",
    encoding: .utf8
  )
let urlCHS = URL(fileURLWithPath: "../components/chs/")
let urlCHT = URL(fileURLWithPath: "../components/cht/")

guard let chsFilterRaw = chsFilterRaw, let chtFilterRaw = chtFilterRaw else { exit(0) }

func makeFilter(from rawString: String) -> [(String, String)] {
  var pairsToFilter: [(String, String)] = []
  rawString.enumerateLines { line, _ in
    let cells = line.split(separator: " ")
    guard cells.count >= 2, cells.first != "#" else { return }
    let reading = cells[1].replacing("-", with: " ")
    pairsToFilter.append(("\(cells[0]) ", " \(reading)"))
    pairsToFilter.append(("\(cells[0])\t", "\t\(reading)"))
  }
  return pairsToFilter
}

let chsFilter: [(String, String)] = makeFilter(from: chsFilterRaw)
let chtFilter: [(String, String)] = makeFilter(from: chtFilterRaw)

// MARK: - LangTag

enum LangTag: String, CaseIterable {
  case chs
  case cht

  // MARK: Internal

  var folderURL: URL { URL(fileURLWithPath: "../components/\(rawValue)/") }

  var filter: [(String, String)] {
    switch self {
    case .chs: chsFilter
    case .cht: chtFilter
    }
  }
}

func trimSingleFile(lang: LangTag, target: inout String) {
  let tempTarget = NSMutableString()
  target.enumerateLines { currentLine, _ in
    var matched = false
    for (prefix, suffix) in lang.filter {
      guard currentLine.hasPrefix(prefix), currentLine.hasSuffix(suffix) else { continue }
      matched = true
      break
    }
    guard !matched else { return }
    tempTarget.append(currentLine + "\n")
  }
  target = tempTarget.description
}

func handleURLs(lang: LangTag, handler: @escaping (LangTag, URL) -> ()) {
  let url = lang.folderURL
  FileManager.default.enumerator(
    at: url,
    includingPropertiesForKeys: [.isRegularFileKey],
    options: [.skipsHiddenFiles, .skipsPackageDescendants]
  )?.forEach { rawURL in
    guard let fileURL = rawURL as? URL else { return }
    let filePath = fileURL.path
    guard filePath.contains("/phrases-"), filePath.lowercased().hasSuffix(".txt") else { return }
    guard (try? fileURL.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile ?? false
    else { return }
    handler(lang, fileURL)
  }
}

LangTag.allCases.forEach { langTag in
  handleURLs(lang: langTag) { i18nTag, fileURL in
    guard var target = try? String(contentsOf: fileURL, encoding: .utf8) else { return }
    trimSingleFile(lang: i18nTag, target: &target)
    print("\(target.count) \(fileURL.path)")
    try? target.write(to: fileURL, atomically: true, encoding: .utf8)
  }
}
