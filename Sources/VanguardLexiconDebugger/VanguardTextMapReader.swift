// (c) 2025 and onwards The vChewing Project (MulanPSL-2.0 License).
// ====================
// This code is released under the SPDX-License-Identifier: `MulanPSL-2.0`.

import Foundation
import Yukuaki

// MARK: - VanguardTextMapReader

/// `.txtMap` 詞庫的唯讀存取器。
///
/// VALUES 支援 A／B／C／D 四種行型別；C 為單筆詞條，D 為同值同型別的
/// 2～16 筆前文詞條。兩者的 `contextCell` 都最多承載兩層前文。
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

    var separator = "-"
    var defaultProbs = [Int: Double]()
    var versionCell: String?
    for line in lines[0 ..< valuesIndex] {
      // 手寫 Debugger 測資的 HEADER 可用空白分隔；VALUES 仍嚴格使用 TAB。
      let fields = line.split(whereSeparator: \.isWhitespace).map(String.init)
      guard fields.count >= 2 else { continue }
      switch fields[0] {
      case "VERSION":
        versionCell = fields[1]
      case "READING_SEPARATOR":
        separator = fields[1]
      default:
        guard fields[0].hasPrefix("DEFAULT_PROB_") else { continue }
        guard let typeID = Int(fields[0].dropFirst("DEFAULT_PROB_".count)) else { continue }
        guard let probability = Double(fields[1]) else { continue }
        defaultProbs[typeID] = probability
      }
    }
    guard versionCell == "2.0" else {
      throw DebuggerError.malformedTextMap("詞庫必須明確標記 VERSION 2.0。")
    }
    self.readingSeparator = separator.isEmpty ? "-" : separator
    self.defaultProbs = defaultProbs

    self.valueLines = Array(lines[(valuesIndex + 1) ..< keyMapIndex])

    var table = [String: (start: Int, count: Int)]()
    for line in lines[(keyMapIndex + 1)...] {
      let fields = line.split(whereSeparator: \.isWhitespace).map(String.init)
      guard fields.count >= 3 else { continue }
      guard let start = Int(fields[1]), let count = Int(fields[2]) else { continue }
      table[fields[0]] = (start, count)
    }
    self.keyTable = table

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
    try validateAllValueLines()
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

  /// 反查：值 → 該值可用的讀音鏈（只收 `values` 內的值）。
  ///
  /// - Note: 需掃過整份 `_KEY_LINE_MAP`，故只建議在「批次驗證」時呼叫一次。
  func readingsIndex(forValues values: Set<String>) -> [String: [[String]]] {
    var result = [String: [[String]]]()
    for (key, range) in keyTable {
      let keys = key.components(separatedBy: readingSeparator)
      for gram in decode(range, keys: keys, locale: locale) where values.contains(gram.current) {
        result[gram.current, default: []].append(keys)
      }
    }
    return result
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

  /// 前文條目（C／D）只取本軌。
  ///
  /// 單元圖跨軌並列的理由是「兩軌的漢字在對方面前都仍可選，差別只在權重」；但前文條目
  /// 綁的是一組具體字串（詞值＋前文鏈），跨軌並列只會讓「不要再這樣」在繁體軌以簡體
  /// 字形勝出——兩列的機率完全相同，取捨僅剩檔案順序。
  private func isOwnLane(typeID: Int, locale: Locale) -> Bool {
    switch (typeID, locale) {
    case (EntryType.chs, .cht), (EntryType.cht, .chs): false
    default: true
    }
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

  private func validateAllValueLines() throws {
    for (index, line) in valueLines.enumerated() {
      do {
        _ = try parseValidatedValueLine(line, keys: [], locale: .both)
      } catch {
        throw DebuggerError.malformedTextMap("VALUES 第 \(index + 1) 行無效：\(error.localizedDescription)")
      }
    }
  }

  private func parseValueLine(
    _ line: String,
    keys: [String],
    locale: Locale
  )
    -> [Yukuaki.Gram] {
    (try? parseValidatedValueLine(line, keys: keys, locale: locale)) ?? []
  }

  private func parseValidatedValueLine(
    _ line: String,
    keys: [String],
    locale: Locale
  )
    throws -> [Yukuaki.Gram] {
    let fields = line.components(separatedBy: "\t")
    guard let first = fields.first, !first.isEmpty else {
      throw DebuggerError.malformedTextMap("空 VALUES 行。")
    }

    // `@` 後不是有限機率時，仍可能是以 `@` 起首的 C 裸詞值。
    if fields.count == 3, first.hasPrefix("@"),
       let probability = Double(first.dropFirst()), probability.isFinite {
      let chsValues = try decodeCell(fields[1], allowsEmptyCell: true)
      let chtValues = try decodeCell(fields[2], allowsEmptyCell: true)
      switch locale {
      case .cht:
        return grams(own: chtValues, other: chsValues, probability: probability, keys: keys)
      case .chs:
        return grams(own: chsValues, other: chtValues, probability: probability, keys: keys)
      case .both:
        let values = chtValues + chsValues.filter { !chtValues.contains($0) }
        return values.map { Yukuaki.Gram(keyArray: keys, current: $0, probability: probability) }
      }
    }

    // 三／四欄仍可能是以 `>` 起首的 C 裸詞值。
    if first.hasPrefix(">"), fields.count == 2 {
      guard let typeID = Int(first.dropFirst()),
            let probability = defaultProbs[typeID], probability.isFinite
      else {
        throw DebuggerError.malformedTextMap("型別 A 必須引用有效 DEFAULT_PROB。")
      }
      let values = try decodeCell(fields[1])
      guard accepts(typeID: typeID) else { return [] }
      return values.map { Yukuaki.Gram(keyArray: keys, current: $0, probability: probability) }
    }

    if first.hasPrefix("!"), fields.count > 4 {
      guard fields.count % 2 == 0 else {
        throw DebuggerError.malformedTextMap("型別 D 必須是 2 + 2n 欄。")
      }
      let pairCount = (fields.count - 2) / 2
      guard (2 ... 16).contains(pairCount) else {
        throw DebuggerError.malformedTextMap("型別 D 每行須含 2～16 筆詞條。")
      }
      let value = String(first.dropFirst())
      try validateBareValue(value)
      guard let typeID = Int(fields[1]) else {
        throw DebuggerError.malformedTextMap("型別 D 的 typeID 無效。")
      }
      var pairs: [(probability: Double, context: [String])] = []
      for pairIndex in 0 ..< pairCount {
        let probabilityIndex = 2 + pairIndex * 2
        let probability = try finiteProbability(fields[probabilityIndex])
        let context = try decodeCell(fields[probabilityIndex + 1])
        guard (1 ... 2).contains(context.count) else {
          throw DebuggerError.malformedTextMap("v2.0 前文須為一或兩層。")
        }
        pairs.append((probability, context))
      }
      guard accepts(typeID: typeID), isOwnLane(typeID: typeID, locale: locale) else { return [] }
      return pairs.map { pair in
        makeGram(value: value, probability: pair.probability, context: pair.context, keys: keys)
      }
    }

    guard fields.count == 3 || fields.count == 4,
          let typeID = Int(fields[2])
    else {
      throw DebuggerError.malformedTextMap("型別 C 必須恰好三或四欄。")
    }
    let probability = try finiteProbability(fields[1])
    let value = fields[0]
    try validateBareValue(value)
    let context = try fields.count == 4 ? decodeCell(fields[3]) : []
    guard context.count <= 2, fields.count == 3 || !context.isEmpty else {
      throw DebuggerError.malformedTextMap("型別 C 有前文欄時，須含一或兩個 token。")
    }
    guard accepts(typeID: typeID), isOwnLane(typeID: typeID, locale: locale) else { return [] }
    return [makeGram(value: value, probability: probability, context: context, keys: keys)]
  }

  private func makeGram(
    value: String,
    probability: Double,
    context: [String],
    keys: [String]
  )
    -> Yukuaki.Gram {
    Yukuaki.Gram(
      keyArray: keys,
      current: value,
      previous: context.last,
      anterior: context.count == 2 ? context[0] : nil,
      probability: probability
    )
  }

  private func finiteProbability(_ rawValue: String) throws -> Double {
    guard let probability = Double(rawValue), probability.isFinite else {
      throw DebuggerError.malformedTextMap("機率必須是有限 Double。")
    }
    return probability
  }

  private func validateBareValue(_ value: String) throws {
    guard !value.isEmpty else { throw DebuggerError.malformedTextMap("詞值不得為空。") }
    for scalar in value.unicodeScalars {
      guard !isStructuralControl(scalar) else {
        throw DebuggerError.malformedTextMap("裸詞值不得含控制字元。")
      }
    }
  }

  /// 只拒絕會破壞文字格式的 Cc／換行；ZWJ 等 Cf 是合法詞值成分。
  private func isStructuralControl(_ scalar: UnicodeScalar) -> Bool {
    scalar.properties.generalCategory == .control || CharacterSet.newlines.contains(scalar)
  }

  /// 嚴格解開 escaped-pipe cell；只有 B 的任一侧允許以空字串表示空集合。
  private func decodeCell(
    _ cell: String,
    allowsEmptyCell: Bool = false
  )
    throws -> [String] {
    if cell.isEmpty {
      if allowsEmptyCell { return [] }
      throw DebuggerError.malformedTextMap("空 grouped cell。")
    }
    if cell == "\u{7}" { return [] }

    var tokens = [String]()
    var current = ""
    var escaping = false

    func finishToken() throws {
      guard !current.isEmpty else { throw DebuggerError.malformedTextMap("grouped cell 不得含空 token。") }
      tokens.append(current)
      current = ""
    }

    // 必須逐 Unicode scalar 掃描，不可逐 Character：轉義空格 `\s` 若緊接組合符（真詞庫
    // 第 115,279 行顏文字 `(\s͒˃⌂˂\s͒)` 的 U+0352 COMBINING FERMATA 即是），Character
    // 迭代會把「s」與組合符併成單一字群，令合法跳脫被誤判為未知跳脫而整份詞庫載不進來。
    // 產製端 `DataBuilder_VanguardTextMap.escapeGroupedValue` 本來就逐 scalar 掃描。
    for scalar in cell.unicodeScalars {
      if escaping {
        switch scalar {
        case "\\": current.unicodeScalars.append("\\")
        case "|": current.unicodeScalars.append("|")
        case "s": current.unicodeScalars.append(" ")
        case "a": current.unicodeScalars.append("\u{7}")
        default: throw DebuggerError.malformedTextMap("未知跳脫：\\\(scalar)。")
        }
        escaping = false
        continue
      }
      switch scalar {
      case "\\":
        escaping = true
      case "|":
        try finishToken()
      default:
        if (scalar.isASCII && CharacterSet.whitespacesAndNewlines.contains(scalar))
          || isStructuralControl(scalar) {
          throw DebuggerError.malformedTextMap("grouped cell 含未跳脫 ASCII 空白或裸控制字元。")
        }
        current.unicodeScalars.append(scalar)
      }
    }
    guard !escaping else { throw DebuggerError.malformedTextMap("跳脫字元後缺字。") }
    try finishToken()
    return tokens
  }
}
