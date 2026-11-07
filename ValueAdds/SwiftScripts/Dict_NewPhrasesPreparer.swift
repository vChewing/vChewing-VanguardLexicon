#!/usr/bin/env swift

// (c) 2021 and onwards The vChewing Project (MulanPSL-2.0 License).
// ====================
// This code is released under the SPDX-License-Identifier: `MulanPSL-2.0`.

// 開發用私人腳本，將自己記錄的新詞的內容同步到先鋒語料庫內。
//
// 兩條輸出：
// ① `phrases-{cht,chs}.txt` 之單元圖列（`字詞 次數 讀音`）——既有行為。
// ② `phrases-ngram-{cht,chs}.txt` 之多字圖列（`詞值 次數 讀音 前文鏈 count(前文)`）——
//    來源是使用者片語辭典內以 `#NGRAM:前文鏈` 宣告之列。
//
// 分數 → 次數之換算（與產製端 `weighten` 互逆；名義分母 D ＝ 1000，與運送中之示範列對齊）：
//     p = log₁₀( e^(len/3 − 1) · c / D )   ⇔   c = round( D · 10^p / e^(len/3 − 1) )
// 其中 len 為詞值之字數。此處之數值係**策展權重**、非語料樣本頻次，手調本屬正當；
// 可追溯性由輸出行尾之 `#` 註解承擔。
//
// 另印一份 lint：凡 n-gram 列之閘門或前文鏈不合格者逐條列出（與 `LXCoreEX` 之載入期診斷同準則）。

import Foundation

// MARK: - Constants

/// 分數 → 次數換算所用之名義分母。
let nominalDenominator: Double = 1_000

func readUserDataFile(at path: String, label: String) -> String? {
  do {
    return try String(contentsOfFile: path, encoding: .utf8)
  } catch {
    print("// !! 無法讀取使用者資料檔案 (\(label)): \(path)")
    print("// !! 錯誤: \(error.localizedDescription)")
    return nil
  }
}

let chsFilterRaw = readUserDataFile(
  at: "/Users/shikisuen/Library/Mobile Documents/com~apple~CloudDocs/vChewing/userdata-chs.txt",
  label: "CHS"
)
let chtFilterRaw = readUserDataFile(
  at: "/Users/shikisuen/Library/Mobile Documents/com~apple~CloudDocs/vChewing/userdata-cht.txt",
  label: "CHT"
)

guard let chsFilterRaw = chsFilterRaw, let chtFilterRaw = chtFilterRaw else {
  print("// !! 使用者資料檔案讀取失敗，prepare 程序終止。")
  exit(1)
}

// MARK: - Phrase（單元圖列）

struct Phrase {
  static var cellTitlesForReport: [String] {
    ["字詞 次數 讀音", "電玩", "複寫", "錯字檢查"]
  }

  static var bareCellTitlesForReport: [String] {
    ["字詞 次數 讀音"]
  }

  let text: String
  let pronunciation: String
  var count = 4
  var isOverridden = false
  var requireKanjiCheck = false
  var isGame = false

  var reportAsCells: [String] {
    [
      "\(text) \(count) \(pronunciation)",
      isGame ? "#電玩" : "",
      isOverridden ? "#複寫" : "",
      requireKanjiCheck ? "#錯字檢查" : "",
    ]
  }

  var reportAsBareCells: [String] {
    ["\(text) \(count) \(pronunciation)"]
  }
}

// MARK: - NGramRow

struct NGramRow {
  let value: String
  let reading: String
  var context: [String]
  let score: Double?
  /// 診斷（nil＝合格）。
  var issue: String?

  /// 詞值字數。
  var valueLength: Int { value.count }

  /// `p = log₁₀(e^(len/3 − 1) · c / D)` 之逆。
  var requiredCount: Int? {
    guard let score else { return nil }
    let scale = exp(Double(valueLength) / 3 - 1)
    guard scale > 0 else { return nil }
    let raw = nominalDenominator * pow(10, score) / scale
    guard raw.isFinite, raw > 0 else { return nil }
    return max(1, Int(raw.rounded()))
  }

  /// `詞值<TAB>次數<TAB>讀音<TAB>前文鏈<TAB>count(前文)`
  var reportAsLine: String? {
    guard let count = requiredCount else { return nil }
    let readingCells = reading.replacingOccurrences(of: "-", with: " ")
    let contextCells = context.joined(separator: " ")
    return [
      value,
      "\(count)",
      readingCells,
      contextCells,
      "\(Int(nominalDenominator))",
    ].joined(separator: "\t")
  }
}

// MARK: - Parsing

/// 該格是否為 `#NGRAM` 閘門；是則回傳 `:` 之後的前文鏈字串（裸 `#NGRAM` 回傳空字串）。
func ngramGatePayload(_ cell: String) -> String? {
  guard cell.hasPrefix("#") else { return nil }
  let body = cell.dropFirst()
  guard body.count >= 5 else { return nil }
  guard body.prefix(5).lowercased() == "ngram" else { return nil }
  let remainder = body.dropFirst(5)
  guard remainder.hasPrefix(":") else { return "" } // 裸 `#NGRAM` 或未知變體
  return String(remainder.dropFirst())
}

/// 切分前文鏈並驗證位置；nil＝不合格。
func parseChain(_ payload: String) -> (previous: String, anterior: String?)? {
  let tokens = payload.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
  guard !tokens.isEmpty, tokens.allSatisfy({ !$0.isEmpty }) else { return nil }
  switch tokens.count {
  case 1:
    guard tokens[0] != "*" else { return nil }
    return (tokens[0], nil)
  case 2:
    if tokens[1] == "*" {
      guard tokens[0] != "*" else { return nil }
      return ("*", tokens[0])
    }
    guard !tokens.contains("*") else { return nil }
    return (tokens[1], tokens[0])
  default:
    return nil
  }
}

func makeUnigrams(from rawString: String) -> [Phrase] {
  var phrases: [Phrase] = []
  rawString.enumerateLines { line, _ in
    let cells = line.split(separator: " ")
    guard cells.count >= 2, cells.first != "#" else { return }
    guard cells.compactMap({ ngramGatePayload($0.description) }).isEmpty else { return }
    let reading = cells[1].replacingOccurrences(of: "-", with: " ")
    var phrase = Phrase(text: cells[0].description, pronunciation: reading.description)
    if line.contains(" #𝙃𝙪𝙢𝙖𝙣𝘊𝙝𝙚𝙘𝙠𝙍𝙚𝙦𝙪𝙞𝙧𝙚𝙙") { phrase.requireKanjiCheck = true }
    if line.contains(" #𝙾𝚟𝚎𝚛𝚛𝚒𝚍𝚎") { phrase.isOverridden = true } // 得手動檢查升頻值。
    if line.contains(" #GAME") { phrase.isGame = true } // 得手動檢查升頻值。
    if cells.count >= 3, let weightValue = Double(cells[2].description) {
      switch weightValue {
      case ..<(-114): phrase.count = 0
      case -114 ..< 0: phrase.count = 2
      default: phrase.count = phrase.isOverridden ? 4_444_444 : 4
      }
    }
    phrases.append(phrase)
  }
  return phrases
}

func makeNGrams(from rawString: String) -> [NGramRow] {
  var rows: [NGramRow] = []
  rawString.enumerateLines { line, _ in
    let cells = line.split(separator: " ").map(\.description)
    guard cells.count >= 2, cells.first != "#" else { return }
    let gateCells = cells.compactMap { cell -> String? in
      guard let payload = ngramGatePayload(cell) else { return nil }
      return payload
    }
    guard let firstPayload = gateCells.first else { return }
    var row = NGramRow(
      value: cells[0],
      reading: cells[1],
      context: [],
      score: cells.count >= 3 ? Double(cells[2]) : nil
    )
    if gateCells.count > 1 {
      row.issue = "一列出現 \(gateCells.count) 個 #NGRAM 閘門"
    } else if firstPayload.isEmpty {
      row.issue = "#NGRAM 之後缺 :前文鏈"
    } else if let chain = parseChain(firstPayload) {
      row.context = chain.anterior.map { [$0, chain.previous] } ?? [chain.previous]
      if row.score == nil { row.issue = "未寫分數（將無法換算次數）" }
    } else {
      row.issue = "前文鏈不合格（`*` 位置、空詞或層數 > 2）"
    }
    rows.append(row)
  }
  return rows
}

// MARK: - Reporting

extension Array where Element == Phrase {
  func makeReport(bare: Bool = false) -> String {
    let result = NSMutableString(string: "")
    result
      .append(
        bare ? Phrase.bareCellTitlesForReport.joined(separator: "\t") : Phrase
          .cellTitlesForReport.joined(separator: "\t")
      )
    result.append("\n")
    forEach { phrase in
      result
        .append(
          bare ? phrase.reportAsBareCells.joined(separator: "\t") : phrase.reportAsCells
            .joined(separator: "\t")
        )
      result.append("\n")
    }
    return result.description
  }
}

extension Bool {
  var nyet: Bool { !self }
}

func emit(label: String, unigrams: [Phrase], ngrams: [NGramRow], tags: [String]) {
  print("// ================================================================")
  print("// \(label)")
  print("// ================================================================")
  print("// ── phrases-\(label.lowercased()).txt（單元圖列）──")
  print(unigrams.makeReport(bare: true), terminator: "")
  print("// ── phrases-ngram-\(label.lowercased()).txt（多字圖列）──")
  print("// 欄序：詞值\t次數\t讀音\t前文鏈\tcount(前文)")
  ngrams.forEach { row in
    if let line = row.reportAsLine, row.issue == nil {
      print(line)
    } else {
      print("# 略過：\(row.value)（\(row.issue ?? "無法換算次數")）")
    }
  }
  let issues = ngrams.filter { $0.issue != nil }
  if !issues.isEmpty {
    print("// ── lint：以下 \(issues.count) 列有問題（未匯出）──")
    issues.forEach { print("//   \($0.value)：\($0.issue ?? "")") }
  }
  print("")
}

let chsUnigrams = makeUnigrams(from: chsFilterRaw)
let chtUnigrams = makeUnigrams(from: chtFilterRaw)
let chsNgrams = makeNGrams(from: chsFilterRaw)
let chtNgrams = makeNGrams(from: chtFilterRaw)

print("// 單元圖列：CHS \(chsUnigrams.count) 筆／CHT \(chtUnigrams.count) 筆。")
print("// 多字圖列：CHS \(chsNgrams.count) 筆／CHT \(chtNgrams.count) 筆。")
print("// 名義分母 D = \(Int(nominalDenominator))；數值係策展權重，非語料樣本頻次。")
print("")
emit(label: "CHS", unigrams: chsUnigrams.filter(\.isGame.nyet), ngrams: chsNgrams, tags: ["chs"])
emit(label: "CHT", unigrams: chtUnigrams.filter(\.isGame.nyet), ngrams: chtNgrams, tags: ["cht"])
