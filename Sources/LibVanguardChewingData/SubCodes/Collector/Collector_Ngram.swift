// (c) 2026 and onwards The vChewing Project (MulanPSL-2.0 License).
// ====================
// This code is released under the SPDX-License-Identifier: `MulanPSL-2.0`.

import Foundation

// MARK: - VCDataBuilder.NgramRecord

extension VCDataBuilder {
  /// 一筆「附帶前驗詞鏈」的 n-gram 條目。
  ///
  /// 與 `Unigram` 不同之處在於：`context` 可承載任意層數的前驗詞鏈（由舊至新），
  /// 故同一個讀音索引鍵下可以並存多筆僅前文不同的條目。
  public struct NgramRecord: Sendable, Hashable {
    // MARK: Lifecycle

    public init(
      value: String,
      readings: [String],
      context: [String],
      count: Int,
      score: Double,
      isCHS: Bool
    ) {
      self.value = value
      self.readings = readings
      self.context = context
      self.count = count
      self.score = score
      self.isCHS = isCHS
    }

    // MARK: Public

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
    /// 帶前驗詞鏈的條目存的是條件機率 `p(詞｜前文)`：分母是前驗詞本身的詞頻，
    /// 而不是語料總量。取不到前驗詞的詞頻時，退回以 `Collector.norm` 折算的無條件機率。
    public let score: Double
    /// 所屬語系：`true` 為簡體、`false` 為繁體。
    public let isCHS: Bool
  }
}

// MARK: - VCDataBuilder.Unigram (Ngram Loading)

extension VCDataBuilder.Unigram {
  /// 讀取並折算所有 n-gram 前驗詞庫（`phrases-ngram-{chs,cht}.txt`）。
  ///
  /// 行格式：`詞值\t次數\t讀音（空格分隔）\t前驗詞鏈（空格分隔、由舊至新）`。
  /// 以 `#` 起首的行與空行一律忽略；欄位不足或讀音為空的行亦忽略。
  /// - Parameters:
  ///   - isCHS: `true` 只讀簡體檔、`false` 只讀繁體檔、`nil` 兩者皆讀。
  ///   - norm: 詞頻正規化基準（unigram 側的語料總量）。
  ///   - contextCounts: 各語系的「詞值 → 詞頻」對照表；用於把前驗詞的詞頻當作條件機率的分母。
  /// - Returns: 已折算權重、且依索引鍵排序的 n-gram 條目。
  static func prepareRawNgramRecords(
    isCHS: Bool?,
    norm: Double,
    contextCounts: [Bool: [String: Int]] = [:]
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
      records.append(
        contentsOf: parseNgramLines(
          strRAW,
          isCHS: isCHSLanguage,
          norm: norm,
          counts: contextCounts[isCHSLanguage] ?? [:]
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

  /// 解析 n-gram 前驗詞庫的內容。
  private static func parseNgramLines(
    _ raw: String,
    isCHS: Bool,
    norm: Double,
    counts: [String: Int]
  )
    -> [VCDataBuilder.NgramRecord] {
    var bucketed: [String: VCDataBuilder.NgramRecord] = [:]
    raw.components(separatedBy: .newlines).forEach { lineData in
      let line = lineData.hasSuffix("\r") ? String(lineData.dropLast()) : lineData
      guard !line.isEmpty, !line.hasPrefix("#") else { return }
      let cells = line.components(separatedBy: "\t")
      guard cells.count >= 4 else { return }
      let value = cells[0].trimmingCharacters(in: .whitespaces)
      let count = Int(cells[1].trimmingCharacters(in: .whitespaces)) ?? 0
      let readings = cells[2].split(separator: " ").map(\.description).filter { !$0.isEmpty }
      let context = cells[3].split(separator: " ").map(\.description).filter { !$0.isEmpty }
      guard !value.isEmpty, !readings.isEmpty else { return }
      // 條件機率的分母是緊鄰前一個詞的詞頻；取不到（或為 0）才退回語料總量。
      let denominator: Double = context.last.flatMap { counts[$0] }.flatMap { $0 > 0 ? Double($0) : nil }
        ?? norm
      let probe = VCDataBuilder.Unigram(
        key: readings.joined(separator: "-"),
        value: value,
        score: 0,
        count: count,
        category: .custom
      )
      probe.weighten(norm: denominator)
      let record = VCDataBuilder.NgramRecord(
        value: value,
        readings: readings,
        context: context,
        count: count,
        score: probe.score,
        isCHS: isCHS
      )
      let identityKey =
        "\(isCHS ? "chs" : "cht")|\(readings.joined(separator: "-"))|\(context.joined(separator: "-"))|\(value)"
      if let existing = bucketed[identityKey], existing.count >= record.count { return }
      bucketed[identityKey] = record
    }
    return Array(bucketed.values)
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
}
