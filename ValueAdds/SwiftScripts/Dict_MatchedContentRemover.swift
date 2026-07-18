#!/usr/bin/env swift

// (c) 2021 and onwards The vChewing Project (BSD-3-Clause).
// ====================
// This code is released under the SPDX-License-Identifier: `BSD-3-Clause`.

// 開發用私人腳本，將自己記錄的語彙過濾表的內容同步到先鋒語料庫內。

import Foundation

// MARK: - Constants

func readFilterFile(at path: String, label: String) -> String? {
  do {
    return try String(contentsOfFile: path, encoding: .utf8)
  } catch {
    print("// !! 無法讀取過濾表檔案 (\(label)): \(path)")
    print("// !! 錯誤: \(error.localizedDescription)")
    return nil
  }
}

let chsFilterRaw = readFilterFile(
  at: "/Users/shikisuen/Library/Mobile Documents/com~apple~CloudDocs/vChewing/exclude-phrases-chs.txt",
  label: "CHS"
)
let chtFilterRaw = readFilterFile(
  at: "/Users/shikisuen/Library/Mobile Documents/com~apple~CloudDocs/vChewing/exclude-phrases-cht.txt",
  label: "CHT"
)
let urlCHS = URL(fileURLWithPath: "./Sources/LibVanguardChewingData/Resources/components/chs/")
let urlCHT = URL(fileURLWithPath: "./Sources/LibVanguardChewingData/Resources/components/cht/")

guard let chsFilterRaw = chsFilterRaw, let chtFilterRaw = chtFilterRaw else {
  print("// !! 過濾表檔案讀取失敗，bleach 程序終止。")
  exit(1)
}

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

  var folderURL: URL {
    URL(fileURLWithPath: "./Sources/LibVanguardChewingData/Resources/components/\(rawValue)/")
  }

  var filter: [(String, String)] {
    switch self {
    case .chs: chsFilter
    case .cht: chtFilter
    }
  }
}

func trimSingleFile(lang: LangTag, target: inout String) {
  let tempTarget = NSMutableString(string: "")
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
    guard var target = try? String(contentsOf: fileURL, encoding: .utf8) else {
      print("// !! 無法讀取目標檔案: \(fileURL.path)")
      return
    }
    let originalCount = target.count
    trimSingleFile(lang: i18nTag, target: &target)
    print("// \(originalCount) -> \(target.count) \(fileURL.path)")
    do {
      try target.write(to: fileURL, atomically: true, encoding: .utf8)
    } catch {
      print("// !! 無法寫入目標檔案: \(fileURL.path)")
      print("// !! 錯誤: \(error.localizedDescription)")
    }
  }
}
