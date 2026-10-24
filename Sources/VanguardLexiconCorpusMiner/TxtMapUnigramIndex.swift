// (c) 2025 and onwards The vChewing Project (MulanPSL-2.0 License).
// ====================
// This code is released under the SPDX-License-Identifier: `MulanPSL-2.0`.

import Foundation

// MARK: - TxtMapUnigramIndexError

struct TxtMapUnigramIndexError: Error, CustomStringConvertible {
  let description: String
}

// MARK: - TxtMapUnigramIndex

/// 以 `.txtMap` 為資料源之單元圖索引。
///
/// 語料挖掘與分詞都必須使用「引擎自己認定的機率與詞頻」，否則候選門檻
/// （`n 元圖之機率須嚴格大於同詞之單元圖分數`）就會算在另一套統計上。
/// 故本索引直接讀取 `.txtMap`，並以 `_NORM` 反推詞頻：
///
/// ```
/// p = log10(e^(len/3-1) * count / norm)   ⇒   count = norm * 10^p / e^(len/3-1)
/// ```
///
/// 反推只承接 `.txtMap` 既有的捨入誤差；`norm` 本身照抄自同一個檔案。
struct TxtMapUnigramIndex {
  // MARK: Lifecycle

  init(url: URL, locale: TxtMapUnigramIndex.Locale = .chs) throws {
    let text = try String(contentsOf: url, encoding: .utf8)
    var lines = text.components(separatedBy: "\n")
    while let last = lines.last, last.isEmpty { lines.removeLast() }

    let valuesPragma = "#PRAGMA:VANGUARD_HOMA_LEXICON_VALUES"
    let keyMapPragma = "#PRAGMA:VANGUARD_HOMA_LEXICON_KEY_LINE_MAP"
    guard let valuesIndex = lines.firstIndex(of: valuesPragma),
          let keyMapIndex = lines.firstIndex(of: keyMapPragma),
          keyMapIndex > valuesIndex
    else {
      throw TxtMapUnigramIndexError(description: "找不到 `\(valuesPragma)`／`\(keyMapPragma)` 區段標記。")
    }

    var separator = "-"
    for line in lines[0 ..< valuesIndex] {
      let fields = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
      if fields.first == "READING_SEPARATOR", fields.count > 1 { separator = fields[1] }
    }

    // 讀音：KEY_LINE_MAP 之每一行對應 VALUES 區段中的同一行序。
    let valueLineCount = keyMapIndex - valuesIndex - 1
    var readings = [String](repeating: "", count: valueLineCount)
    for line in lines[(keyMapIndex + 1)...] {
      let fields = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
      guard fields.count >= 3,
            let start = Int(fields[1]), let count = Int(fields[2]),
            start >= 0, start + count <= valueLineCount
      else { continue }
      for index in start ..< (start + count) { readings[index] = fields[0] }
    }

    let defaultProbabilities = TxtMapUnigramIndex.parseDefaultProbabilities(in: lines[0 ..< valuesIndex])
    var norm: Double?
    var timestamp: Double = 0
    var table = [String: Unigram]()

    for (offset, line) in lines[(valuesIndex + 1) ..< keyMapIndex].enumerated() {
      let readingKey = readings[offset]
      let reading = readingKey.isEmpty ? nil : TxtMapUnigramIndex.splitReadingKey(readingKey, separator: separator)
      let tabCount = line.reduce(0) { $0 + ($1 == "\t" ? 1 : 0) }
      let fields = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
      guard let head = fields.first else { continue }

      if head.hasPrefix("@"), fields.count >= 2 {
        // 型別 B：`@probability\tchsCell\tchtCell`
        guard let probability = Double(head.dropFirst()) else { continue }
        var cells = [String]()
        if locale.includesCHS { cells.append(fields[1]) }
        if locale.includesCHT { cells.append(fields.count > 2 ? fields[2] : "") }
        for value in cells.flatMap(TxtMapUnigramIndex.decodeGroupedCell) where TxtMapUnigramIndex.isSegmentationEligible(value) {
          TxtMapUnigramIndex.insert(value: value, probability: probability, reading: reading, into: &table)
        }
      } else if head.hasPrefix(">") {
        // 型別 A：`>typeID\tencodedCell`（合併行，機率為該 typeID 之預設值；見 DEFAULT_PROB）
        guard fields.count >= 2, let typeID = Int32(head.dropFirst()) else { continue }
        let probability = defaultProbabilities[typeID] ?? -13
        for value in TxtMapUnigramIndex.decodeGroupedCell(fields[1]) where TxtMapUnigramIndex.isSegmentationEligible(value) {
          TxtMapUnigramIndex.insert(value: value, probability: probability, reading: reading, into: &table)
        }
      } else if tabCount >= 2, fields.count >= 3, let probability = Double(fields[1]) {
        // 型別 C：`value\tprobability\ttypeID[\tcontextCell]`
        guard tabCount == 2 else { continue } // 帶前驗詞鏈者不是單元圖。
        if head == "_NORM" { norm = probability; continue }
        if head == "_BUILD_TIMESTAMP" { timestamp = probability; continue }
        guard TxtMapUnigramIndex.isSegmentationEligible(head) else { continue }
        TxtMapUnigramIndex.insert(value: head, probability: probability, reading: reading, into: &table)
      }
    }

    guard let detectedNorm = norm, detectedNorm > 0 else {
      throw TxtMapUnigramIndexError(description: "`.txtMap` 內沒有可用的 `_NORM`。")
    }

    // 詞頻反推：同一詞可能有多讀音，取詞頻最大者（與 `Collector` 的 `makeCountTable` 同義）。
    var counted = table
    for (value, unigram) in counted {
      var updated = unigram
      updated.count = detectedNorm * pow(10, unigram.probability) / exp(Double(value.count) / 3 - 1)
      counted[value] = updated
    }

    self.sourceURL = url
    self.locale = locale
    self.norm = detectedNorm
    self.buildTimestamp = timestamp
    self.readingSeparator = separator
    self.unigrams = counted
    self.maximumValueLength = counted.keys.map(\.count).max() ?? 1
  }

  /// 供測試與離線情境使用之建構器。
  init(
    norm: Double,
    buildTimestamp: Double = 0,
    readingSeparator: String = "-",
    entries: [(value: String, probability: Double, reading: [String])]
  ) {
    var table = [String: Unigram]()
    for entry in entries {
      TxtMapUnigramIndex.insert(
        value: entry.value,
        probability: entry.probability,
        reading: entry.reading,
        into: &table
      )
    }
    var counted = table
    for (value, unigram) in counted {
      var updated = unigram
      updated.count = norm * pow(10, unigram.probability) / exp(Double(value.count) / 3 - 1)
      counted[value] = updated
    }
    self.sourceURL = URL(fileURLWithPath: "/dev/null")
    self.locale = .both
    self.norm = norm
    self.buildTimestamp = buildTimestamp
    self.readingSeparator = readingSeparator
    self.unigrams = counted
    self.maximumValueLength = counted.keys.map(\.count).max() ?? 1
  }

  // MARK: Internal

  enum Locale: String {
    case chs
    case cht
    case both

    var includesCHS: Bool { self != .cht }
    var includesCHT: Bool { self != .chs }
  }

  struct Unigram {
    var probability: Double
    /// 各讀音個別之機率；同一詞於不同讀音下是不同詞條。
    var readings: [(key: [String], probability: Double)]
    var count: Double
  }

  let sourceURL: URL
  let locale: Locale
  let norm: Double
  let buildTimestamp: Double
  let readingSeparator: String
  let maximumValueLength: Int

  private(set) var unigrams: [String: Unigram]

  var valueCount: Int { unigrams.count }

  func unigram(_ value: String) -> Unigram? { unigrams[value] }

  func probability(of value: String) -> Double? { unigrams[value]?.probability }

  func count(of value: String) -> Double { unigrams[value]?.count ?? 0 }

  // MARK: Private

  private static func splitReadingKey(_ key: String, separator: String) -> [String] {
    key.components(separatedBy: separator)
  }

  private static func insert(
    value: String,
    probability: Double,
    reading: [String]?,
    into table: inout [String: Unigram]
  ) {
    var unigram = table[value] ?? .init(probability: -Double.infinity, readings: [], count: 0)
    unigram.probability = max(unigram.probability, probability)
    if let reading, !reading.isEmpty, !unigram.readings.contains(where: { $0.key == reading }) {
      unigram.readings.append((key: reading, probability: probability))
    }
    table[value] = unigram
  }

  private static func decodeGroupedCell(_ cell: String) -> [String] {
    guard !cell.isEmpty else { return [] }
    var values = [String]()
    var current = ""
    var escaping = false
    for char in cell {
      if escaping {
        switch char {
        case "s": current.append(" ")
        case "a": current.append("\u{7}")
        case "\\": current.append("\\")
        case "|": current.append("|")
        default: current.append(char)
        }
        escaping = false
      } else if char == "\\" {
        escaping = true
      } else if char == "|" {
        values.append(current)
        current = ""
      } else {
        current.append(char)
      }
    }
    values.append(current)
    return values.filter { !$0.isEmpty && $0 != "\u{7}" }
  }

  /// 分詞索引只收「語料可能出現的詞」：略去注音／聲調本身、以及 `_` 開頭之虛擬詞條。
  private static func isSegmentationEligible(_ value: String) -> Bool {
    guard !value.isEmpty, !value.hasPrefix("_") else { return false }
    let bopomofoOrTone = "ㄅㄆㄇㄈㄉㄊㄋㄌㄍㄎㄏㄐㄑㄒㄓㄔㄕㄖㄗㄘㄙㄧㄨㄩㄚㄛㄜㄝㄞㄟㄠㄡㄢㄣㄤㄥㄦˊˇˋ˙ˉ"
    return !value.allSatisfy { bopomofoOrTone.contains($0) }
  }
}

// MARK: - Default probability table

extension TxtMapUnigramIndex {
  /// 解析 `DEFAULT_PROB_*` 表頭；型別 A 之合併行以此為機率。
  private static func parseDefaultProbabilities(in headerLines: ArraySlice<String>) -> [Int32: Double] {
    var result = [Int32: Double]()
    for line in headerLines {
      let fields = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
      guard fields.count >= 2, fields[0].hasPrefix("DEFAULT_PROB_"),
            let typeID = Int32(fields[0].dropFirst("DEFAULT_PROB_".count)),
            let probability = Double(fields[1])
      else { continue }
      result[typeID] = probability
    }
    return result
  }
}
