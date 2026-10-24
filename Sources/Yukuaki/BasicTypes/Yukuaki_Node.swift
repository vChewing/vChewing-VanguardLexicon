// (c) 2025 and onwards The vChewing Project (MulanPSL-2.0 License).
// ====================
// This code is released under the SPDX-License-Identifier: `MulanPSL-2.0`.

// MARK: - Yukuaki.Node

extension Yukuaki {
  /// 組句用的節點。一個節點對應「某個起點、某個幅節長度」下的全部候選 gram。
  ///
  /// 節點自身會依前文（前一個詞、前兩個詞）挑出最合適的 gram；挑法與 Homa 相同：
  /// 取「unigram 基底分數」與「命中的 bigram／trigram 分數」當中的較大者
  /// （同分時 trigram 優先）。
  public struct Node: Hashable, Codable, Sendable {
    // MARK: Lifecycle

    public init(keyArray4Query: [String], grams: [Yukuaki.Gram]) {
      self.keyArray4Query = keyArray4Query
      self.grams = Self.sortGrams(Self.seedingFallbackUnigram(in: grams))
      self.currentGramIndex = 0
    }

    // MARK: Public

    /// 節點覆寫型別。與 Homa 的同名型別相容。
    public enum OverrideType: Int, Codable, Sendable {
      case withTopGramScore = 1
      case withSpecified = 2
    }

    /// 一次節點估值的結果。
    public struct Evaluation: Hashable, Sendable {
      /// 該節點貢獻給組句總分的分數。
      public let score: Double
      /// 該節點在此估值下會選用的 gram。
      public let gram: Yukuaki.Gram?
      /// 該分數是否來自覆寫。
      public let isExplicit: Bool
      /// 該分數是否退回了 unigram 基底（即沒有命中任何前文 gram）。
      public let usedBackoff: Bool
    }

    /// 節點覆寫的預設分數。
    public static let defaultOverridingScore: Double = 114_514

    public let keyArray4Query: [String]
    public var overridingScore: Double = defaultOverridingScore
    public var currentOverrideType: OverrideType?
    public var isExplicitlyOverridden: Bool = false

    public private(set) var grams: [Yukuaki.Gram] {
      didSet { currentGramIndex = grams.isEmpty ? 0 : min(grams.count - 1, max(0, currentGramIndex)) }
    }

    public private(set) var currentGramIndex: Int = 0 {
      didSet { currentGramIndex = grams.isEmpty ? 0 : min(grams.count - 1, max(0, currentGramIndex)) }
    }

    /// 該節點當前讀音（優先取自當前 gram）。
    public var keyArray: [String] { currentGram?.keyArray ?? keyArray4Query }

    /// 該節點的幅節長度（讀音長度）。
    public var segLength: Int { keyArray.count }

    /// 該節點當前的候選對。
    public var currentPair: Yukuaki.CandidatePairRAW? {
      guard let gram = currentGram else { return nil }
      return (gram.keyArray, gram.current)
    }

    /// 該節點當前的 gram。
    public var currentGram: Yukuaki.Gram? {
      grams.indices.contains(currentGramIndex) ? grams[currentGramIndex] : nil
    }

    /// 該節點當前的詞。
    public var value: String? { currentGram?.current }

    /// 該節點是否處於覆寫狀態。
    public var isOverridden: Bool { currentOverrideType != nil }

    /// 該節點當前的讀音長度與詞長是否不符。
    public var isReadingMismatched: Bool { (value ?? "").count != keyArray.count }

    /// 該節點內機率最高的 unigram。
    public var topUnigramGram: Yukuaki.Gram? { grams.first(where: \.isUnigram) }

    /// 該節點的 unigram 基底分數（即機率最高的 unigram 的分數）。
    public var unigramScore: Double { topUnigramGram?.probability ?? 0 }

    /// gram 的優先度排序：讀音長度遞減、分數遞減、其餘按字典序。
    public static func sortGrams(_ grams: [Yukuaki.Gram]) -> [Yukuaki.Gram] {
      grams.sorted(by: sortGram)
    }

    /// gram 的優先度比較函式。
    public static func sortGram(_ lhs: Yukuaki.Gram, _ rhs: Yukuaki.Gram) -> Bool {
      if lhs.keyArray.count != rhs.keyArray.count { return lhs.keyArray.count > rhs.keyArray.count }
      if lhs.probability != rhs.probability { return lhs.probability > rhs.probability }
      if lhs.keyArray != rhs.keyArray { return lhs.keyArray.lexicographicallyPrecedes(rhs.keyArray) }
      if lhs.previous != rhs.previous {
        return (lhs.previous ?? "") < (rhs.previous ?? "")
      }
      if lhs.anterior != rhs.anterior {
        return (lhs.anterior ?? "") < (rhs.anterior ?? "")
      }
      return lhs.current < rhs.current
    }

    /// 該節點內最合適的前文 gram（trigram 優先；bigram 需嚴格更高分才勝出）。
    /// - Note: 同一組前文可能對應多條 gram（例如同一詞值掛了不同的讀音或不同的覆寫來源），
    ///   此時取機率最高者；同分時取排序在前者，與 Homa 的 `contextGram` 行為一致。
    public func contextGram(previous: String?, anterior: String? = nil) -> Yukuaki.Gram? {
      guard let previous, !previous.isEmpty else { return nil }
      var bestBigram: Yukuaki.Gram?
      var bestTrigram: Yukuaki.Gram?
      for gram in grams {
        guard gram.previous == previous else { continue }
        if gram.anterior == nil {
          if bestBigram == nil || gram.probability > (bestBigram?.probability ?? -.infinity) {
            bestBigram = gram
          }
        } else if gram.anterior == anterior {
          if bestTrigram == nil || gram.probability > (bestTrigram?.probability ?? -.infinity) {
            bestTrigram = gram
          }
        }
      }
      // 候選之間的取捨以「按鏈長計次之後的分數」為準：trigram 的增益算兩次（P326 計分模型），
      // 故原始機率較低的 trigram 可能反而勝過 bigram。
      let baseline = unigramScore
      var best = bestTrigram
      if let bestBigram,
         bestBigram.weightedScore(against: baseline) > (best?.weightedScore(against: baseline) ?? -.infinity) {
        best = bestBigram
      }
      return best
    }

    /// 以純函式方式估算該節點在給定前文下的分數。不會改動節點狀態。
    public func evaluate(previous: String?, anterior: String? = nil) -> Evaluation {
      guard !grams.isEmpty else {
        return .init(score: 0, gram: nil, isExplicit: isExplicitlyOverridden, usedBackoff: false)
      }
      let unigramBaseline = unigramScore
      guard let previous, !previous.isEmpty else {
        return evaluateWithoutContext()
      }
      let bestBonus = contextGram(previous: previous, anterior: anterior)
      switch currentOverrideType {
      case .withSpecified:
        return .init(
          score: overridingScore,
          gram: currentGram ?? topUnigramGram,
          isExplicit: isExplicitlyOverridden,
          usedBackoff: false
        )
      case .withTopGramScore:
        // 弱釘選：只把分數壓回 unigram 基線，**不動**當前選取。此型別由 POM 之自動套用端
        // （`forceHighScoreOverride == false`）以 `selectOverrideGram` 設定，那時
        // `currentGramIndex` 已指向 POM 建議的那條 gram；若在此把它撥回 `topUnigramGram`，
        // 使用者在選字窗挑的詞就會被丟掉。（與 Homa 之 `targetIndex: nil` 同義。）
        return .init(
          score: unigramBaseline,
          gram: currentGram ?? topUnigramGram,
          isExplicit: isExplicitlyOverridden,
          usedBackoff: false
        )
      case nil:
        if let bestBonus, bestBonus.probability > unigramBaseline {
          return .init(
            score: bestBonus.weightedScore(against: unigramBaseline),
            gram: bestBonus,
            isExplicit: isExplicitlyOverridden,
            usedBackoff: false
          )
        }
        return .init(
          score: unigramBaseline,
          gram: topUnigramGram,
          isExplicit: isExplicitlyOverridden,
          usedBackoff: true
        )
      }
    }

    /// 瞄準給定前文的 gram 分數，但同時把節點的當前 gram 撥過去。
    /// - Note: 這是「估值＋寫回」的合體版，只適合單一路徑的場合。
    ///   需要同時評估多條假設時（例如 P325 之後的多狀態 DP），請改用 `evaluate` 取得
    ///   純量結果，再於確定勝出路徑之後用 `adopt(gram:)` 寫回，否則節點狀態會被
    ///   「最後一次估值」污染。
    @discardableResult
    public mutating func adopt(previous: String?, anterior: String? = nil) -> Double {
      let evaluation = evaluate(previous: previous, anterior: anterior)
      if let gram = evaluation.gram { adopt(gram: gram) }
      return evaluation.score
    }

    /// 把節點的當前 gram 撥到指定的 gram。只改索引，不改覆寫狀態。
    /// - Note: 以 `grams.firstIndex(of:)` 比對整條 gram（含前驗詞鏈），
    ///   故同詞值、不同前文的兩條 gram 不會互相誤認。
    public mutating func adopt(gram: Yukuaki.Gram) {
      guard let index = grams.firstIndex(of: gram) else { return }
      currentGramIndex = index
    }

    /// 強制該節點在此前文下選用指定的 gram。
    public mutating func select(
      keyArray: [String],
      value: String,
      previous: String?,
      anterior: String?,
      type: OverrideType = .withSpecified
    ) throws {
      guard let index = grams.firstIndex(where: {
        $0.keyArray == keyArray && $0.current == value && $0.previous == previous && $0.anterior == anterior
      }) else {
        throw Yukuaki.Exception.nodeHasNoCurrentGram
      }
      currentGramIndex = index
      currentOverrideType = type
      isExplicitlyOverridden = true
      overridingScore = max(overridingScore, Self.defaultOverridingScore)
    }

    /// 清空節點的覆寫狀態。
    public mutating func reset() {
      currentGramIndex = 0
      currentOverrideType = nil
      isExplicitlyOverridden = false
      overridingScore = Self.defaultOverridingScore
    }

    /// 節點必有單元圖：若給定的元圖陣列連一條單元圖都沒有，就在最前面補一條
    /// 「無語境證成」的單元圖（分值 `-114.514`），與 Homa 側的行為一致。
    ///
    /// 之所以要補：`unigramScore` 是節點估值的錨。節點若沒有單元圖，基線只能退化成
    /// `0`，而 `0` 又高於任何真實單元圖之分數，等於給異常節點加成。
    private static func seedingFallbackUnigram(in grams: [Yukuaki.Gram]) -> [Yukuaki.Gram] {
      guard !grams.isEmpty, !grams.contains(where: \.isUnigram) else { return grams }
      let fallback = Yukuaki.Gram(
        keyArray: grams[0].keyArray,
        current: grams[0].current,
        probability: fallbackUnigramProbability
      )
      return [fallback] + grams
    }

    /// 上述保險補入之單元圖所用的分值。
    static let fallbackUnigramProbability: Double = -114.514

    /// 用另一個節點的 grams 同步該節點，並在必要時重置覆寫狀態。
    public mutating func syncingGrams(from node: Yukuaki.Node) {
      let oldValue = currentGram
      grams = Self.seedingFallbackUnigram(in: node.grams)
      if let oldValue, let newValue = currentGram, oldValue.current == newValue.current { return }
      reset()
    }

    // MARK: Private

    /// 沒有前文時的估值。
    /// - Note: 這裡刻意不去讀 `currentGram`。組句的 DP 會在多條假設之間反覆估值，
    ///   同一節點在不同假設下必須得到同一個「無前文分數」；若讓結果取決於
    ///   `currentGramIndex`（也就是上一次組句寫回的殘留狀態），估值就不再是純函式，
    ///   重複組句的結果也會開始漂移。
    private func evaluateWithoutContext() -> Evaluation {
      let gram = topUnigramGram ?? grams[0]
      let effectiveBaseline = topUnigramGram?.probability ?? gram.probability
      switch currentOverrideType {
      case .withSpecified:
        return .init(
          score: overridingScore,
          gram: currentGram ?? gram,
          isExplicit: isExplicitlyOverridden,
          usedBackoff: false
        )
      case .withTopGramScore:
        // 同上：弱釘選只改分數、不改選取。
        return .init(
          score: effectiveBaseline,
          gram: currentGram ?? gram,
          isExplicit: isExplicitlyOverridden,
          usedBackoff: false
        )
      case nil:
        return .init(
          score: effectiveBaseline,
          gram: gram,
          isExplicit: isExplicitlyOverridden,
          usedBackoff: false
        )
      }
    }
  }
}

extension Array where Element == Yukuaki.Node {
  /// 將一串節點攤成當前組句結果。
  public var asGramChain: [Yukuaki.GramInPath] {
    compactMap { node in
      guard let gram = node.currentGram else { return nil }
      return Yukuaki.GramInPath(gram: gram, isExplicit: node.isExplicitlyOverridden)
    }
  }
}
