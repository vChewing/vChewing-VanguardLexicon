// (c) 2025 and onwards The vChewing Project (MulanPSL-2.0 License).
// ====================
// This code is released under the SPDX-License-Identifier: `MulanPSL-2.0`.

import Foundation
import Yukuaki

// MARK: - VanguardTextMapReader

/// `.txtMap` 詞庫的唯讀存取器。
///
/// 檔案格式見 `VCDataBuilder.VanguardTextMapDataBuilder`：
/// 三個區段（HEADER／VALUES／KEY_LINE_MAP），其中 VALUES 有三種行型別：
/// - 型別 A：`>typeID\tencodedCell`
/// - 型別 B：`@probability\tchsCell\tchtCell`
/// - 型別 C：`value\tprobability\ttypeID[\tprevious]`
final class VanguardTextMapReader {
  // MARK: Lifecycle

  init(url: URL, locale: Locale = .cht) throws {
    self.url = url
    self.locale = locale
    let text = try String(contentsOf: url, encoding: .utf8)
    var lines = text.components(separatedBy: "\n")
    while let last = lines.last, last.isEmpty { lines.removeLast() }

    let valuesPragma = "#PRAGMA:VANGUARD_HOMA_LEXICON_VALUES"
    let keyMapPragma = "#PRAGMA:VANGUARD_HOMA_LEXICON_KEY_LINE_MAP"
    guard let valuesIndex = lines.firstIndex(of: valuesPragma),
          let keyMapIndex = lines.firstIndex(of: keyMapPragma),
          keyMapIndex > valuesIndex
    else {
      throw DebuggerError.malformedTextMap("找不到 `\(valuesPragma)` 或 `\(keyMapPragma)` 區段標記。")
    }

    // HEADER
    var separator = "-"
    var defaultProbs = [Int: Double]()
    for line in lines[0 ..< valuesIndex] {
      /// 區段標頭的欄位以 TAB 分隔；此處對空白也寬容，方便手寫測資。
      let fields = line.split(whereSeparator: \.isWhitespace).map(String.init)
      guard fields.count >= 2 else { continue }
      switch fields[0] {
      case "READING_SEPARATOR":
        separator = fields[1]
      default:
        guard fields[0].hasPrefix("DEFAULT_PROB_") else { continue }
        guard let typeID = Int(fields[0].dropFirst("DEFAULT_PROB_".count)) else { continue }
        guard let probability = Double(fields[1]) else { continue }
        defaultProbs[typeID] = probability
      }
    }
    self.readingSeparator = separator.isEmpty ? "-" : separator
    self.defaultProbs = defaultProbs

    // VALUES
    self.valueLines = Array(lines[(valuesIndex + 1) ..< keyMapIndex])

    // KEY_LINE_MAP
    var table = [String: (start: Int, count: Int)]()
    for line in lines[(keyMapIndex + 1)...] {
      let fields = line.split(whereSeparator: \.isWhitespace).map(String.init)
      guard fields.count >= 3 else { continue }
      guard let start = Int(fields[1]), let count = Int(fields[2]) else { continue }
      table[fields[0]] = (start, count)
    }
    self.keyTable = table

    // 附帶統計：正規化基準與是否含有前文詞條。
    var detectedNorm: Double?
    var contextual = false
    for line in valueLines {
      if line.hasPrefix("_NORM\t") {
        let fields = line.components(separatedBy: "\t")
        if fields.count >= 2 { detectedNorm = Double(fields[1]) }
      } else if !line.hasPrefix("@"), !line.hasPrefix(">") {
        let tabCount = line.reduce(0) { $0 + ($1 == "\t" ? 1 : 0) }
        if tabCount >= 3 { contextual = true }
      }
    }
    self.norm = detectedNorm
    self.hasContextualEntries = contextual
  }

  // MARK: Internal

  /// 詞條語系取捨。
  enum Locale: String {
    /// 只取繁體（缺時退回簡體）。
    case cht
    /// 只取簡體（缺時退回繁體）。
    case chs
    /// 兩者都收。
    case both
  }

  let url: URL
  let locale: Locale
  /// 因只存在於另一語系軌而改以零頻次權重計分的詞條數。
  private(set) var crossLaneValueCount = 0
  let readingSeparator: String
  let norm: Double?
  let hasContextualEntries: Bool

  var keyCount: Int { keyTable.count }
  var entryLineCount: Int { valueLines.count }

  /// 查詢某組讀音對應的全部詞條。
  ///
  /// 兩個語系軌的詞條一律收下，語系只決定「計分時用哪一軌的權重」：本軌詞條照該行
  /// 的機率計分，另一軌獨有的詞條改以零頻次權重計分（見 `crossLaneWeight`）。因此
  /// 繁體模式仍打得出簡體字、簡體模式仍打得出繁體字，只是排序靠後。
  func grams(forKeys keys: [String]) -> [Yukuaki.Gram] {
    let cacheKey = keys.joined(separator: readingSeparator)
    if let cached = gramCache[cacheKey] { return cached }
    guard let range = keyTable[cacheKey] else {
      gramCache[cacheKey] = []
      return []
    }
    let grams = decode(range, keys: keys, locale: locale)
    gramCache[cacheKey] = grams
    return grams
  }

  /// 某組讀音是否至少有一條詞條。
  func hasGrams(forKeys keys: [String]) -> Bool {
    keyTable[keys.joined(separator: readingSeparator)] != nil
  }

  // MARK: Private

  /// 詞條型別。與 `VanguardTrie.Trie.EntryType` 的原始值對應。
  private enum EntryType {
    static let langNeutral = 1
    static let meta = 2
    static let revLookup = 3
    static let chs = 5
    static let cht = 6
  }

  private let valueLines: [String]
  private let keyTable: [String: (start: Int, count: Int)]
  private let defaultProbs: [Int: Double]
  private var gramCache = [String: [Yukuaki.Gram]]()

  private func decode(
    _ range: (start: Int, count: Int),
    keys: [String],
    locale: Locale
  )
    -> [Yukuaki.Gram] {
    var grams = [Yukuaki.Gram]()
    for offset in 0 ..< range.count {
      let index = range.start + offset
      guard valueLines.indices.contains(index) else { continue }
      grams.append(contentsOf: parseValueLine(valueLines[index], keys: keys, locale: locale))
    }
    return grams
  }

  /// 詞條型別是否為可查詢的詞條：`meta`（`_NORM`／`_DATE`）與 `revLookup` 不是詞條。
  ///
  /// 其餘型別一律收下、不分語系軌——含 `chs`（5）與 `cht`（6），因為兩軌的漢字在
  /// 對方面前都仍可選，差別只在權重（見 `crossLaneWeight`）。
  private func accepts(typeID: Int) -> Bool {
    typeID != EntryType.meta && typeID != EntryType.revLookup
  }

  /// 組織一行 `@` 的詞條：本軌照行機率計分，另一軌獨有的詞條改以零頻次權重計分。
  private func grams(
    own: [String],
    other: [String],
    probability: Double,
    keys: [String]
  )
    -> [Yukuaki.Gram] {
    var grams = own.map { Yukuaki.Gram(keyArray: keys, current: $0, probability: probability) }
    var seen = Set(own)
    for value in other where seen.insert(value).inserted {
      crossLaneValueCount += 1
      grams.append(
        .init(
          keyArray: keys,
          current: value,
          probability: crossLaneWeight(for: value, fallback: probability)
        )
      )
    }
    return grams
  }

  /// 「僅存在於另一語系軌」之詞條的權重。
  ///
  /// 沿用 `Collector` 對頻次 0 的計分式 `log10(e^(字數/3 − 1) × 0.25 / norm)`，與
  /// txtMap 自身的 count-0 桶同式（故單字得 -9.465 之流），字數愈長罰得愈輕。
  /// 詞庫缺少 `_NORM` 時無從計分，直接沿用該行機率。
  private func crossLaneWeight(for value: String, fallback: Double) -> Double {
    guard let norm, norm > 0 else { return fallback }
    return log10(exp(Double(value.count) / 3 - 1) * 0.25 / norm)
  }

  private func parseValueLine(
    _ line: String,
    keys: [String],
    locale: Locale
  )
    -> [Yukuaki.Gram] {
    let fields = line.components(separatedBy: "\t")
    guard let first = fields.first, let head = first.first else { return [] }
    switch head {
    case "@":
      guard fields.count >= 3 else { return [] }
      guard let probability = Double(first.dropFirst()) else { return [] }
      let chsValues = decodeCell(fields[1])
      let chtValues = decodeCell(fields[2])
      switch locale {
      case .cht:
        return grams(own: chtValues, other: chsValues, probability: probability, keys: keys)
      case .chs:
        return grams(own: chsValues, other: chtValues, probability: probability, keys: keys)
      case .both:
        let values = chtValues + chsValues.filter { !chtValues.contains($0) }
        return values.map { Yukuaki.Gram(keyArray: keys, current: $0, probability: probability) }
      }

    case ">":
      guard fields.count >= 2 else { return [] }
      guard let typeID = Int(first.dropFirst()) else { return [] }
      guard accepts(typeID: typeID) else { return [] }
      guard let probability = defaultProbs[typeID] else { return [] }
      return decodeCell(fields[1]).map {
        Yukuaki.Gram(keyArray: keys, current: $0, probability: probability)
      }

    default:
      guard fields.count >= 3 else { return [] }
      guard let typeID = Int(fields[2]), accepts(typeID: typeID) else { return [] }
      guard let probability = Double(fields[1]) else { return [] }
      let value = decodeToken(fields[0])
      guard !value.isEmpty else { return [] }
      let previous = fields.count >= 4 ? decodeToken(fields[3]) : ""
      return [
        .init(
          keyArray: keys,
          current: value,
          previous: previous.isEmpty ? nil : previous,
          probability: probability
        ),
      ]
    }
  }

  /// 解開 `|` 分隔的欄位（含跳脫）。
  private func decodeCell(_ cell: String) -> [String] {
    var tokens = [String]()
    var current = ""
    var escaping = false
    for character in cell {
      if escaping {
        current.append(unescape(character))
        escaping = false
        continue
      }
      switch character {
      case "\\":
        escaping = true
      case "|":
        tokens.append(current)
        current = ""
      default:
        current.append(character)
      }
    }
    tokens.append(current)
    return tokens.filter { !$0.isEmpty && $0 != "\u{7}" }
  }

  private func decodeToken(_ token: String) -> String {
    var result = ""
    var escaping = false
    for character in token {
      if escaping {
        result.append(unescape(character))
        escaping = false
        continue
      }
      if character == "\\" {
        escaping = true
        continue
      }
      result.append(character)
    }
    return result == "\u{7}" ? "" : result
  }

  private func unescape(_ character: Character) -> Character {
    switch character {
    case "s": return " "
    case "a": return "\u{7}"
    default: return character
    }
  }
}
