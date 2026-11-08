#!/usr/bin/env swift

// (c) 2021 and onwards The vChewing Project (MulanPSL-2.0 License).
// ====================
// This code is released under the SPDX-License-Identifier: `MulanPSL-2.0`.

// 開發用腳本：將 `Resources/components/` 之下、檔名以 `phrases-` 起首的資料檔
// （不含 `custom`）的資料列依筆畫排序，供人手編輯後整理。
//
// 註解（`#` 起首）與空行一律原位、逐位元組保留：本工具只重排資料列，不搬動、
// 不合併、不刪除任何非資料列。故 `phrases-ngram-*.txt` 之檔尾說明塊、以及註解塊內
// 單獨一個 `#` 之段落分隔行，皆不受影響。資料列若被註解或空行分段，則各段分別排序，
// 不跨段合併。
//
// 護欄：若輸出並非原檔之單純重排（非資料列之序列改變、或行集合不變），則跳過該檔、
// 不寫入。

import Foundation

let strDataPath = "./Sources/LibVanguardChewingData/Resources/components"

func handleFiles(_ handler: @escaping ((url: URL, fileName: String)) -> ()) {
  let rawURLs = FileManager.default.enumerator(
    at: URL(fileURLWithPath: strDataPath),
    includingPropertiesForKeys: nil
  )?.compactMap { $0 as? URL }
  rawURLs?.forEach { url in
    guard let fileName = url.pathComponents.last, fileName.suffix(4).lowercased() == ".txt",
          fileName.prefix(8) == "phrases-" else { return }
    guard !fileName.contains("custom") else { return }
    handler((url, fileName))
  }
}

/// 註解行與空行之判準與產製端之剖析器一致：以 `#` 起首即註解，其餘才是資料列。
/// 舊版只認 `# ` 與 `#=`，故單獨一個 `#` 的註解行會被當成資料列、排序時被搬離原位。
func isCommentOrBlank(_ line: String) -> Bool {
  line.isEmpty || line.hasPrefix("#")
}

let locale = Locale(identifier: "zh@collation=stroke")

func sortedContentLines(_ lines: [String]) -> [String] {
  lines.sorted { lhs, rhs in
    switch lhs.compare(rhs, locale: locale) {
    case .orderedAscending: return true
    case .orderedDescending: return false
    case .orderedSame: return lhs < rhs
    }
  }
}

handleFiles { url, fileName in
  guard let rawStr = try? String(contentsOf: url, encoding: .utf8) else {
    print("// !! 無法讀取目標檔案: \(fileName)")
    return
  }
  let lineSeparator = rawStr.contains("\r\n") ? "\r\n" : "\n"
  var rawLines = rawStr.components(separatedBy: lineSeparator)
  let hadTrailingNewline = !rawStr.isEmpty && rawLines.last == ""
  if hadTrailingNewline { rawLines.removeLast() }
  let lines = rawLines

  var resultLines = [String]()
  var pendingLines = [String]()
  func flushPendingLines() {
    resultLines.append(contentsOf: sortedContentLines(pendingLines))
    pendingLines.removeAll()
  }

  for line in lines {
    guard !isCommentOrBlank(line) else {
      flushPendingLines()
      resultLines.append(line)
      continue
    }
    pendingLines.append(line)
  }
  flushPendingLines()

  // 護欄：本工具只准重排資料列。註解與空行須逐位元組留在原位，且輸出的行集合
  // 必須與原檔完全相同（不增、不減、不改寫）。
  let expectedComments = lines.filter(isCommentOrBlank)
  let actualComments = resultLines.filter(isCommentOrBlank)
  guard actualComments == expectedComments, resultLines.sorted() == lines.sorted() else {
    print("// !! 排序結果並非原檔之單純重排，已跳過: \(fileName)")
    return
  }

  var output = resultLines.joined(separator: lineSeparator)
  if hadTrailingNewline { output += lineSeparator }
  do {
    try output.write(to: url, atomically: false, encoding: .utf8)
  } catch {
    print("!! Error writing to \(fileName)")
  }
}
