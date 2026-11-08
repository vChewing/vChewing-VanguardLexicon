// (c) 2026 and onwards The vChewing Project (MulanPSL-2.0 License).
// ====================
// This code is released under the SPDX-License-Identifier: `MulanPSL-2.0`.

import Foundation

// MARK: - VCDataBuilder.NgramRecord

extension VCDataBuilder {
  /// n-gram 條件機率之分母的來源。
  ///
  /// 條件機率 `p(詞｜前文)` 的分母是「前文」本身的詞頻：bigram（前文一詞 `y`）
  /// 用 `count(y)`、trigram（前文兩詞 `x y`）用 `count(x, y)`。
  /// 舊式 backlog 只寫得出 `count(y)`，故另立一級以資區別。
  public enum NgramDenominatorSource: String, Sendable, Hashable, CaseIterable {
    /// 前文鏈之完整詞頻：bigram 為 `count(y)`、trigram 為 `count(x, y)`。
    case fullContext
    /// 舊式 backlog 未載完整前文詞頻，沿用緊鄰前一詞之詞頻 `count(y)`。
    case legacyUnigramCount
    /// 取不到任何詞頻，退回以 `Collector.norm` 折算的無條件機率。
    case normalizedFallback
  }

  /// 一筆「附帶前驗詞鏈」的 n-gram 條目。
  ///
  /// `context` 由舊至新，v2.0 最多兩層；同一讀音索引鍵下可並存多筆僅前文不同的條目。
  public struct NgramRecord: Sendable, Hashable {
    // MARK: Lifecycle

    public init(
      value: String,
      readings: [String],
      context: [String],
      count: Int,
      score: Double,
      isCHS: Bool,
      contextCount: Int? = nil,
      denominatorSource: NgramDenominatorSource = .normalizedFallback
    ) {
      self.value = value
      self.readings = readings
      self.context = context
      self.count = count
      self.score = score
      self.isCHS = isCHS
      self.contextCount = contextCount
      self.denominatorSource = denominatorSource
    }

    // MARK: Public

    /// 前文格之萬用符：該格不指定詞值，其貢獻已聚合進分母。
    ///
    /// 只用於「有 anterior、缺 previous」之缺口列（`[x, *]`）；只准出現在兩格前文鏈之
    /// 最後一格，且該列之第 5 欄須為聚合後之前文詞頻 `count(x, ·)`。
    public static let wildcardContextToken = "*"

    /// 詞值。
    public let value: String
    /// 該詞本身的讀音（注音音節，即 Trie 的索引鍵）。
    public let readings: [String]
    /// 前驗詞鏈（由舊至新；空陣列代表 unigram，最後一個元素是緊鄰的前一個詞）。
    public let context: [String]
    /// 出現次數（權重計算之依據）。
    public let count: Int
    /// log10 權重（負值）。
    ///
    /// 分母是「前文」本身的詞頻：bigram 取緊鄰前一詞（`context.last`）之 `count(y)`、
    /// trigram 取其完整前文之 `count(x, y)`（見 `denominatorSource`）。
    /// 只有在完全取不到詞頻時，才退回以 `Collector.norm` 折算的無條件機率。
    public let score: Double
    /// 所屬語系：`true` 為簡體、`false` 為繁體。
    public let isCHS: Bool
    /// 折算 `score` 時所用的分母詞頻；`nil` 代表退回 `Collector.norm`。
    public let contextCount: Int?
    /// 折算 `score` 時分母的來源。
    public let denominatorSource: NgramDenominatorSource
  }
}

// MARK: - VCDataBuilder.Unigram (Ngram Loading)

extension VCDataBuilder.Unigram {
  /// 讀取並折算所有 n-gram 前驗詞庫（`phrases-ngram-{chs,cht}.txt`）。
  ///
  /// 行格式：`詞值\t次數\t讀音（空格分隔）\t前驗詞鏈（空格分隔、由舊至新）\t完整前文詞頻\t註解`。
  /// 第 5 欄（完整前文的原始詞頻）為 v2.0 之新欄：給出即代表分母取自同一語料；
  /// 空白欄或以 `#` 起首者視為舊式註解，trigram 列因此缺分母時一律報錯。
  /// 以 `#` 起首的行與空行一律忽略；欄位不足或讀音為空的行亦忽略。
  /// 詞值欄與前驗詞鏈欄都可以寫成 `<類名>`，由詞類清單
  /// （`phrases-ngram-classes-{chs,cht}.txt`）展開成逐條成員。
  /// - Parameters:
  ///   - isCHS: `true` 只讀簡體檔、`false` 只讀繁體檔、`nil` 兩者皆讀。
  ///   - norm: 詞頻正規化基準（unigram 側的語料總量）。
  ///   - contextCounts: 各語系的「詞值 → 詞頻」對照表；用於把前驗詞的詞頻當作條件機率的分母。
  ///   - classTables: 各語系的詞類清單（`<TOKEN>` → 成員）；`nil` 代表自資源檔載入。
  ///     類名一律為英文 token、繁簡共用，僅成員隨語系而異。
  ///   - readingsTables: 各語系的「詞值 → 讀音」對照表；詞類列展開時用來補成員的讀音。
  /// - Returns: 已折算權重、且依索引鍵排序的 n-gram 條目。
  static func prepareRawNgramRecords(
    isCHS: Bool?,
    norm: Double,
    contextCounts: [Bool: [String: Int]] = [:],
    classTables: [Bool: [String: [String]]]? = nil,
    readingsTables: [Bool: [String: [String]]] = [:]
  )
    throws -> [VCDataBuilder.NgramRecord] {
    let locales: [Bool] = if let isCHS { [isCHS] } else { [true, false] }
    var records: [VCDataBuilder.NgramRecord] = []
    for isCHSLanguage in locales {
      let suffix = isCHSLanguage ? "chs" : "cht"
      let assetURL = try Bundle.module
        .findFiles(matching: "phrases-ngram-\(suffix)", extension: "txt")
        .sorted { $0.absoluteString < $1.absoluteString }
        .first
      guard let assetURL else { continue }
      let strRAW = try String(contentsOf: assetURL, encoding: .utf8)
      let classTable = try classTables.map { $0[isCHSLanguage] ?? [:] }
        ?? loadClassTable(isCHS: isCHSLanguage)
      records.append(
        contentsOf: try parseNgramLines(
          strRAW,
          isCHS: isCHSLanguage,
          norm: norm,
          counts: contextCounts[isCHSLanguage] ?? [:],
          classTable: classTable,
          readings: readingsTables[isCHSLanguage] ?? [:]
        )
      )
    }
    return records.sorted { lhs, rhs in
      if lhs.readings != rhs
        .readings { return lhs.readings.joined(separator: "-") < rhs.readings.joined(separator: "-") }
      if lhs.context.count != rhs.context.count { return lhs.context.count < rhs.context.count }
      if lhs.context != rhs.context { return lhs.context.joined(separator: "-") < rhs.context.joined(separator: "-") }
      return lhs.value < rhs.value
    }
  }

  /// 一列 n-gram 之分母的解析結果。
  struct NgramDenominator {
    /// 折算 `score` 時用的分母。
    let value: Double
    /// 分母的詞頻（`nil` 代表退回 `norm`）。
    let contextCount: Int?
    /// 分母的來源。
    let source: VCDataBuilder.NgramDenominatorSource
  }

  /// 讀入第 5 欄（完整前文的原始詞頻）。
  ///
  /// 空白欄或以 `#` 起首者視為舊式註解（回傳 `nil`）；其餘必須是整數。
  /// 詞類模板列（前文欄含 `<類名>`）不得攙此欄——展開後每個成員的前文詞頻各自不同，
  /// 一列只寫一個數只會張冠李戴。
  static func parseContextCountCell(
    _ cell: String,
    rawContext: [String],
    classTable: [String: [String]]
  )
    throws -> Int? {
    guard !cell.isEmpty, !cell.hasPrefix("#") else { return nil }
    guard let count = Int(cell) else {
      throw VCDataBuilder.Exception.errMsg(
        "n-gram contextCount must be an integer or a `#` comment, got「\(cell)」."
      )
    }
    guard !rawContext.contains(where: { classTable[$0] != nil }) else {
      throw VCDataBuilder.Exception.errMsg(
        "n-gram contextCount cannot be combined with class-templated context tokens."
      )
    }
    return count
  }

  /// 決定一列 n-gram 的條件機率分母。
  ///
  /// 條件機率 `p(詞｜前文)` 的分母是「前文」本身的詞頻：
  /// - bigram（前文一詞）：有明確 `contextCount` 就用它；否則沿用緊鄰前詞之詞頻 `count(y)`（legacy）。
  /// - trigram（前文兩詞）：**必須**有明確 `contextCount`（即 `count(x, y)`）。缺欄即報錯：
  ///   退回 `count(y)` 或 `_NORM` 只是把錯誤的分母當成正確答案。
  static func resolveNgramDenominator(
    context: [String],
    explicitContextCount: Int?,
    counts: [String: Int],
    norm: Double
  )
    throws -> NgramDenominator {
    if let explicitContextCount {
      guard explicitContextCount > 0 else {
        throw VCDataBuilder.Exception.errMsg(
          "n-gram contextCount must be positive, got \(explicitContextCount) for context「\(context.joined(separator: " "))」."
        )
      }
      return NgramDenominator(
        value: Double(explicitContextCount),
        contextCount: explicitContextCount,
        source: .fullContext
      )
    }
    if context.count >= 2 {
      throw VCDataBuilder.Exception.errMsg(
        "TextMap v2.0 trigram rows require the full-context count (count(\(context.joined(separator: ", ")))); add the fifth column to「\(context.joined(separator: " "))」."
      )
    }
    if let last = context.last, let count = counts[last], count > 0 {
      return NgramDenominator(value: Double(count), contextCount: count, source: .legacyUnigramCount)
    }
    guard norm > 0 else {
      throw VCDataBuilder.Exception.errMsg("n-gram normalization baseline must be positive.")
    }
    return NgramDenominator(value: norm, contextCount: nil, source: .normalizedFallback)
  }

  /// 解析 n-gram 前驗詞庫的內容。
  ///
  /// 詞值欄與前驗詞鏈欄都可以寫成 `<類名>`（見 `loadClassTable(isCHS:)`）：
  /// 詞類在解析時展開成逐條成員，故一條模板列即可生成整族 n-gram。
  /// 詞值欄為類名時，該列的讀音欄無意義（可填 `-`），改由 `readings` 逐成員補上；
  /// 查無讀音的成員一律略過——讀音不臆造。
  static func parseNgramLines(
    _ raw: String,
    isCHS: Bool,
    norm: Double,
    counts: [String: Int],
    classTable: [String: [String]] = [:],
    readings: [String: [String]] = [:]
  )
    throws -> [VCDataBuilder.NgramRecord] {
    var bucketed: [String: VCDataBuilder.NgramRecord] = [:]
    for (lineIndex, lineData) in raw.components(separatedBy: .newlines).enumerated() {
      let lineNumber = lineIndex + 1
      let line = lineData.hasSuffix("\r") ? String(lineData.dropLast()) : lineData
      let trimmedLine = line.trimmingCharacters(in: .whitespaces)
      guard !trimmedLine.isEmpty, !trimmedLine.hasPrefix("#") else { continue }
      /// 欄界是「一段空白」（空格或 TAB 均可摺疊）；欄內不得再有空白：
      /// 讀音以 `-` 連接、前驗詞鏈以 `|` 連接。故編輯器把 TAB 換成空格也不影響語意。
      let cells = line.split(whereSeparator: \.isWhitespace).map(String.init)
      guard (4 ... 6).contains(cells.count) else {
        throw VCDataBuilder.Exception.errMsg(
          "n-gram 第 \(lineNumber) 行：欄數為 \(cells.count)，應為 4 至 6 欄；欄界是空白，但欄內不得再有空白——讀音請以 `-` 連接、前驗詞鏈請以 `|` 連接。該行開頭：\(line.prefix(40))"
        )
      }
      let valueCell = cells[0]
      guard !valueCell.isEmpty else {
        throw VCDataBuilder.Exception.errMsg("n-gram 第 \(lineNumber) 行：詞值欄為空。")
      }
      let countCell = cells[1]
      guard let count = Int(countCell) else {
        throw VCDataBuilder.Exception.errMsg(
          "n-gram 第 \(lineNumber) 行：次數欄「\(countCell)」不是整數。"
        )
      }
      guard cells.count < 6 || cells[5].hasPrefix("#") else {
        throw VCDataBuilder.Exception.errMsg(
          "n-gram 第 \(lineNumber) 行：第 6 欄只能是 `#` 起首的單一註解 token（不得含空白）。"
        )
      }
      let literalReadings = cells[2] == "-"
        ? []
        : cells[2].split(separator: "-").map(String.init).filter { !$0.isEmpty }
      let rawContext = cells[3].split(separator: "|").map(String.init).filter { !$0.isEmpty }
      guard !rawContext.isEmpty else {
        throw VCDataBuilder.Exception.errMsg("n-gram 第 \(lineNumber) 行：前驗詞鏈欄為空。")
      }
      guard rawContext.count <= 2 else {
        throw VCDataBuilder.Exception.errMsg("TextMap v2.0 n-gram context is limited to two tokens.")
      }
      try validateWildcardPlacement(rawContext)
      let contextCountCell = cells.count >= 5 ? cells[4] : ""
      let explicitContextCount = try parseContextCountCell(
        contextCountCell,
        rawContext: rawContext,
        classTable: classTable
      )
      let valueIsClass = classTable[valueCell] != nil
      guard valueIsClass || !literalReadings.isEmpty else {
        throw VCDataBuilder.Exception.errMsg("n-gram 第 \(lineNumber) 行：非詞類之列缺讀音。")
      }
      let contextVariants = expandTokens(rawContext, classTable: classTable)
      let valueVariants = valueIsClass ? (classTable[valueCell] ?? []) : [valueCell]
      for value in valueVariants {
        try validateNgramToken(value)
        let readings4ThisValue = valueIsClass ? (readings[value] ?? []) : literalReadings
        guard !readings4ThisValue.isEmpty else { continue }
        for context in contextVariants {
          guard (1 ... 2).contains(context.count) else {
            throw VCDataBuilder.Exception.errMsg("TextMap v2.0 n-gram context is limited to two tokens.")
          }
          for token in context { try validateNgramToken(token) }
          // 分母是「前文」本身的詞頻：bigram 取 `count(y)`、trigram 取完整前文之 `count(x, y)`。
          let resolved = try resolveNgramDenominator(
            context: context,
            explicitContextCount: explicitContextCount,
            counts: counts,
            norm: norm
          )
          let probe = VCDataBuilder.Unigram(
            key: readings4ThisValue.joined(separator: "-"),
            value: value,
            score: 0,
            count: count,
            category: .custom
          )
          probe.weighten(norm: resolved.value)
          let record = VCDataBuilder.NgramRecord(
            value: value,
            readings: readings4ThisValue,
            context: context,
            count: count,
            score: probe.score,
            isCHS: isCHS,
            contextCount: resolved.contextCount,
            denominatorSource: resolved.source
          )
          let identityKey =
            "\(isCHS ? "chs" : "cht")|\(readings4ThisValue.joined(separator: "-"))|\(context.joined(separator: "-"))|\(value)"
          if let existing = bucketed[identityKey], existing.count >= record.count { continue }
          bucketed[identityKey] = record
        }
      }
    }
    let records = Array(bucketed.values)
    try validateGapExclusivity(records)
    return records
  }

  /// 缺口列（`[x, *]`）與 trigram 列（`[x, y]`）互斥。
  ///
  /// 同一 `(x, y, w)` 不得同時以兩條軸估值：缺口列涵蓋**所有** `y`，故只要該詞在該讀音
  /// 下已有任一 `[x, y]` 之 trigram 列，該缺口列即不得存在。互斥於產製端強制——txtMap
  /// 係由本層產出，人手只改來源表，故這裡是唯一能同時看到兩類列的位置。
  static func validateGapExclusivity(
    _ records: [VCDataBuilder.NgramRecord]
  )
    throws {
    guard records.contains(where: { $0.context.last == VCDataBuilder.NgramRecord.wildcardContextToken }) else {
      return
    }
    var exactKeys = Set<String>()
    for record in records where record.context.last != VCDataBuilder.NgramRecord.wildcardContextToken {
      guard record.context.count == 2 else { continue }
      exactKeys.insert(exclusivityKey(record))
    }
    for record in records where record.context.last == VCDataBuilder.NgramRecord.wildcardContextToken {
      guard exactKeys.contains(exclusivityKey(record)) else { continue }
      let chain = record.context.joined(separator: " ")
      throw VCDataBuilder.Exception.errMsg(
        "n-gram gap row [\(chain)] for「\(record.value)」conflicts with an existing trigram row on the same antecedent."
      )
    }
  }

  /// 互斥判定之身分鍵：語系＋讀音＋詞值＋**實際約束的那個前文**（`x`）。
  ///
  /// 缺口列 `[x, *]` 與 trigram 列 `[x, y]` 皆取 `context[0]`，故同一 `x` 之下只要存在
  /// 任何 trigram 列，缺口列即衝突。
  private static func exclusivityKey(_ record: VCDataBuilder.NgramRecord) -> String {
    let anterior = record.context.first ?? ""
    let readings = record.readings.joined(separator: "-")
    return "\(record.isCHS ? "chs" : "cht")|\(readings)|\(record.value)|\(anterior)"
  }

  /// 萬用符只准出現在兩格前文鏈之最後一格。
  private static func validateWildcardPlacement(_ rawContext: [String]) throws {
    guard rawContext.contains(VCDataBuilder.NgramRecord.wildcardContextToken) else { return }
    guard rawContext.count == 2,
          rawContext[1] == VCDataBuilder.NgramRecord.wildcardContextToken else {
      throw VCDataBuilder.Exception.errMsg(
        "n-gram wildcard context token is only allowed as the last of two tokens."
      )
    }
  }

  private static func validateNgramToken(_ token: String) throws {
    guard !token.isEmpty else {
      throw VCDataBuilder.Exception.errMsg("n-gram values and context tokens must not be empty.")
    }
    for scalar in token.unicodeScalars {
      let isStructuralControl = scalar.properties.generalCategory == .control
        || CharacterSet.newlines.contains(scalar)
      guard !isStructuralControl else {
        throw VCDataBuilder.Exception.errMsg("n-gram values and context tokens reject control characters.")
      }
    }
  }

  /// 把一組詞（詞值欄或前驗詞鏈）中的類名展開成逐一成員的所有組合。
  ///
  /// 不含類名的詞原樣保留；空類別展開後一無所有（該列因而消失）。
  static func expandTokens(
    _ tokens: [String],
    classTable: [String: [String]]
  )
    -> [[String]] {
    tokens.reduce([[]]) { partials, token in
      let variants = classTable[token] ?? [token]
      return partials.flatMap { partial in variants.map { partial + [$0] } }
    }
  }

  /// 讀取詞類清單（`phrases-ngram-classes-{chs,cht}.txt`）。
  ///
  /// 行格式：`類名\t詞值（空格分隔）`；類名以角括號包住，供 n-gram 表以 `<TOKEN>` 引用。
  /// 類名一律為英文 token（`<PLACE_NOUN>`、`<OBJECTIVE_VERB>`、`<SELF_VERB>`…），繁簡共用。
  /// 以 `#` 起首的行與空行一律忽略；檔案不存在時回傳空表。
  static func loadClassTable(isCHS: Bool) throws -> [String: [String]] {
    let suffix = isCHS ? "chs" : "cht"
    let assetURL = try Bundle.module
      .findFiles(matching: "phrases-ngram-classes-\(suffix)", extension: "txt")
      .sorted { $0.absoluteString < $1.absoluteString }
      .first
    guard let assetURL else { return [:] }
    let strRAW = try String(contentsOf: assetURL, encoding: .utf8)
    var result: [String: [String]] = [:]
    strRAW.components(separatedBy: .newlines).forEach { lineData in
      let line = lineData.hasSuffix("\r") ? String(lineData.dropLast()) : lineData
      guard !line.isEmpty, !line.hasPrefix("#") else { return }
      let cells = line.split(whereSeparator: \.isWhitespace).map(String.init)
      guard cells.count >= 2 else { return }
      let name = cells[0]
      let members = cells.dropFirst().filter { !$0.isEmpty }
      guard !name.isEmpty, !members.isEmpty else { return }
      result[name] = members
    }
    return result
  }
}

// MARK: - VCDataBuilder.Unigram (Count Table)

extension VCDataBuilder.Unigram {
  /// 由若干張 unigram 表建出「詞值 → 詞頻」對照表。
  ///
  /// 同一個詞值可能對應多個讀音、各讀音的詞頻不同，此處取最大值。
  static func makeCountTable(
    _ tables: [[Category: [String: GramSet]]]
  )
    -> [String: Int] {
    var result: [String: Int] = [:]
    for table in tables {
      for gramSet in table.values.flatMap(\.values) {
        for unigram in gramSet {
          result[unigram.value] = max(result[unigram.value] ?? unigram.count, unigram.count)
        }
      }
    }
    return result
  }

  /// 由若干張 unigram 表建出「詞值 → 讀音」對照表。
  ///
  /// 詞類列展開時，成員的讀音由此補上（`NgramRecord.readings` 即 Trie 的索引鍵）。
  /// 同一個詞值可能對應多組讀音，此處取詞頻最高者的讀音。
  static func makeReadingTable(
    _ tables: [[Category: [String: GramSet]]]
  )
    -> [String: [String]] {
    var result: [String: (count: Int, readings: [String])] = [:]
    for table in tables {
      for gramSet in table.values.flatMap(\.values) {
        for unigram in gramSet {
          if let existing = result[unigram.value], existing.count >= unigram.count { continue }
          result[unigram.value] = (
            unigram.count,
            unigram.key.split(separator: "-").map(\.description)
          )
        }
      }
    }
    return result.mapValues(\.readings).filter { !$0.value.isEmpty }
  }
}
