// (c) 2025 and onwards The vChewing Project (MulanPSL-2.0 License).
// ====================
// This code is released under the SPDX-License-Identifier: `MulanPSL-2.0`.

// MARK: - Yukuaki.GramInPath

extension Yukuaki {
  /// 組句結果內的一節。與 Homa 的 `Homa.GramInPath` 相比，這裡去掉了 POM
  /// （行為感知）相關的成員。
  public struct GramInPath: Codable, Hashable, Sendable {
    // MARK: Lifecycle

    public init(gram: Yukuaki.Gram, isExplicit: Bool = false) {
      self.gram = gram
      self.isExplicit = isExplicit
    }

    // MARK: Public

    public let gram: Yukuaki.Gram
    public let isExplicit: Bool

    /// 該節的詞。
    public var value: String { gram.current }
    /// 該節的讀音。
    public var keyArray: [String] { gram.keyArray }
    /// 該節貢獻給組句總分的分數。
    public var score: Double { gram.probability }
    /// 該節的幅節長度。
    public var segLength: Int { gram.segLength }
    /// 該節的讀音長度與詞長是否不符。
    public var isReadingMismatched: Bool { gram.isReadingMismatched }
    /// 該節的前文詞。
    public var previous: String? { gram.previous }
    /// 該節的前前文詞。
    public var anterior: String? { gram.anterior }
    /// 該節是否是 unigram。
    public var isUnigram: Bool { gram.isUnigram }

    /// 該節的候選對。
    public var asCandidatePair: Yukuaki.CandidatePairRAW { (gram.keyArray, gram.current) }

    public var description: String { gram.describe() }

    /// 將該節的讀音以指定分隔符串接。
    public func joinedCurrentKey(by separator: String = "-") -> String {
      keyArray.joined(separator: separator)
    }
  }
}

extension Array where Element == Yukuaki.GramInPath {
  /// 組句結果全部的詞。
  public var values: [String] { map(\.value) }

  /// 組句結果全部的讀音。
  public var keyArrays: [[String]] { map(\.keyArray) }

  /// 組句結果的讀音總數。
  public var totalKeyCount: Int { reduce(0) { $0 + $1.segLength } }

  /// 組句結果的總分。
  public var totalScore: Double { reduce(0) { $0 + $1.score } }

  /// 組句結果攤成的字串。
  public var joinedSentence: String { values.joined() }

  /// 組句結果每一節各自的讀音字串。
  public func joinedKeys(by separator: String = "-") -> [String] {
    map { $0.joinedCurrentKey(by: separator) }
  }

  /// 組句結果攤平之後的讀音序列。
  public var flattenedKeys: [String] { flatMap(\.keyArray) }

  /// 組句結果攤成的完整讀音字串。
  public func joinedKeyChain(by separator: String = "-") -> String {
    flattenedKeys.joined(separator: separator)
  }

  /// 組句結果的「讀音－詞」配對。
  public var smashedPairs: [(key: String, value: String)] {
    flatMap { section in
      section.keyArray.map { ($0, section.value) }
    }
  }
}
