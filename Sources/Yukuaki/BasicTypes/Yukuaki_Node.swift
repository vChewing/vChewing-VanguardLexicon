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
      self.grams = Self.sortGrams(grams)
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
    public func contextGram(previous: String?, anterior: String? = nil) -> Yukuaki.Gram? {
      guard let previous, !previous.isEmpty else { return nil }
      var bestBigram: Yukuaki.Gram?
      var bestTrigram: Yukuaki.Gram?
      for gram in grams {
        guard gram.previous == previous else { continue }
        if gram.anterior == nil {
          bestBigram = gram
        } else if gram.anterior == anterior {
          bestTrigram = gram
        }
      }
      var best = bestTrigram
      if let bestBigram, bestBigram.probability > (best?.probability ?? -.infinity) { best = bestBigram }
      return best
    }

    /// 以純函式方式估算該節點在給定前文下的分數。不會改動節點狀態。
    public func evaluate(previous: String?, anterior: String? = nil) -> Evaluation {
      guard !grams.isEmpty else {
        return .init(score: 0, gram: nil, isExplicit: isExplicitlyOverridden, usedBackoff: false)
      }
      let unigramBaseline = unigramScore
      guard let previous, !previous.isEmpty else {
        return evaluateWithoutContext(baseline: unigramBaseline)
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
        return .init(
          score: unigramBaseline,
          gram: topUnigramGram,
          isExplicit: isExplicitlyOverridden,
          usedBackoff: false
        )
      case nil:
        if let bestBonus, bestBonus.probability > unigramBaseline {
          return .init(
            score: bestBonus.probability,
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
    @discardableResult
    public mutating func adopt(previous: String?, anterior: String? = nil) -> Double {
      let evaluation = evaluate(previous: previous, anterior: anterior)
      if let gram = evaluation.gram, let index = grams.firstIndex(of: gram) {
        currentGramIndex = index
      }
      return evaluation.score
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

    /// 用另一個節點的 grams 同步該節點，並在必要時重置覆寫狀態。
    public mutating func syncingGrams(from node: Yukuaki.Node) {
      let oldValue = currentGram
      grams = node.grams
      if let oldValue, let newValue = currentGram, oldValue.current == newValue.current { return }
      reset()
    }

    // MARK: Private

    /// 沒有前文時的估值。
    private func evaluateWithoutContext(baseline: Double) -> Evaluation {
      let gram = topUnigramGram ?? grams[0]
      switch currentOverrideType {
      case .withSpecified:
        return .init(
          score: overridingScore,
          gram: currentGram ?? gram,
          isExplicit: isExplicitlyOverridden,
          usedBackoff: false
        )
      case .withTopGramScore:
        return .init(
          score: gram.probability,
          gram: gram,
          isExplicit: isExplicitlyOverridden,
          usedBackoff: false
        )
      case nil:
        if let currentGram, currentGram.isUnigram {
          return .init(
            score: currentGram.probability,
            gram: currentGram,
            isExplicit: isExplicitlyOverridden,
            usedBackoff: false
          )
        }
        return .init(
          score: baseline == 0 ? gram.probability : baseline,
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
