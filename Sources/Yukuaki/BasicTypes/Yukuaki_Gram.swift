// (c) 2025 and onwards The vChewing Project (MulanPSL-2.0 License).
// ====================
// This code is released under the SPDX-License-Identifier: `MulanPSL-2.0`.

// MARK: - Yukuaki.Gram

extension Yukuaki {
  /// 一條 gram。unigram 是「讀音 → 詞」；bigram／trigram 額外攜帶前文。
  ///
  /// 與 Homa 的 `Homa.Gram` 相比，這裡去掉了識別碼（`id`）：Yukuaki 不需要
  /// 節點覆寫鏡像，故值語意即足以支撐節點比對與去重。
  public struct Gram: Codable, Hashable, Sendable {
    // MARK: Lifecycle

    public init(
      keyArray: [String],
      current: String,
      previous: String? = nil,
      anterior: String? = nil,
      probability: Double = 0,
      backoff: Double = 0
    ) {
      self.keyArray = keyArray
      self.current = current
      self.previous = previous
      self.anterior = anterior
      self.probability = probability
      self.backoff = backoff
    }

    public init(raw: Yukuaki.GramRAW) {
      self.keyArray = raw.keyArray
      self.current = raw.value
      self.previous = raw.previous
      self.anterior = raw.anterior
      self.probability = raw.probability
      self.backoff = 0
    }

    // MARK: Public

    public let keyArray: [String]
    public let current: String
    public let previous: String?
    public let anterior: String?
    public let probability: Double
    public let backoff: Double

    /// 該 gram 是否為 unigram（不攜帶任何前文）。
    public var isUnigram: Bool { previous == nil && anterior == nil }

    /// 該 gram 是否為 bigram（只攜帶前一個詞）。
    public var isBigram: Bool { previous != nil && anterior == nil }

    /// 該 gram 是否為 trigram（同時攜帶前兩個詞）。
    public var isTrigram: Bool { previous != nil && anterior != nil }

    /// 該 gram 的讀音長度。
    public var segLength: Int { keyArray.count }

    /// 該 gram 的前文鏈長（1 = unigram、2 = bigram、3 = trigram）。
    /// - Note: 這是「詞鏈」的長度，不是讀音長度：多音節詞的 unigram 仍然是 1。
    public var chainLength: Int { 1 + (previous == nil ? 0 : 1) + (anterior == nil ? 0 : 1) }

    /// 該 gram 的讀音長度與詞長是否不符。
    public var isReadingMismatched: Bool { keyArray.count != current.count }

    /// 該 gram 的無識別碼表示法。
    public var asTuple: Yukuaki.GramRAW { (keyArray, current, probability, previous, anterior) }

    public var description: String { describe() }

    /// 把 n-gram 的原始分數換算成「相對同名節點 unigram 基線的增益」，並按鏈長計次。
    ///
    /// 計分模型（P326）：`baseline + (chainLength − 1) × (probability − baseline)`。
    /// - bigram（chainLength = 2）的結果與舊行為完全相同：`probability`。
    /// - trigram（chainLength = 3）把增益算兩次：`2 × probability − baseline`。
    ///
    /// 之所以要按鏈長計次：在「總分 = 各節點分數之和」的模型裡，若高階 n-gram 的增益
    /// 只算一次，兩條假設的勝負就只取決於各自增益之比（PMI 之比），與詞鏈長度無關。
    /// 如此一來，長鏈證據與短鏈證據等權，右文脈即使成立也扳不動左文脈——這正是
    /// P325 案例之三之所以翻不了盤的根因。
    /// - Parameter baseline: 同名節點之 unigram 基線分數（通常是該節點最高分的 unigram）。
    public func weightedScore(against baseline: Double) -> Double {
      baseline + Double(chainLength - 1) * (probability - baseline)
    }

    /// 附帶讀音的敍述。
    public func describe(keySeparator: String = "-") -> String {
      let reading = keyArray.joined(separator: keySeparator)
      let context = [previous, anterior].compactMap { $0 }.joined(separator: " ")
      let body = "\(reading) -> \(current) (\(probability))"
      guard !context.isEmpty else { return body }
      return "\(body) [\(context)]"
    }
  }
}

extension Array where Element == Yukuaki.Gram {
  /// 將一組 gram 拆成 unigram 與 bigram 兩堆（trigram 不列入 bigram）。
  public var asGramTypes: (unigrams: [Yukuaki.Gram], bigrams: [Yukuaki.Gram]) {
    (filter(\.isUnigram), filter(\.isBigram))
  }
}
