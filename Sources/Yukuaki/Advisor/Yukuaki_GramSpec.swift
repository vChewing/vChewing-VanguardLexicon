// (c) 2025 and onwards The vChewing Project (MulanPSL-2.0 License).
// ====================
// This code is released under the SPDX-License-Identifier: `MulanPSL-2.0`.

import Foundation

extension Yukuaki {
  /// 一條「建議追補的詞條」。這是 Yukuaki 的面相之一：不是給輸入法用的，
  /// 而是告訴詞庫維護者「要得到這條組句結果，還缺什麼」。
  public struct GramSpec: Hashable, Codable, Sendable {
    // MARK: Lifecycle

    public init(
      kind: Kind,
      keyArray: [String],
      current: String,
      previous: String? = nil,
      anterior: String? = nil,
      role: Role,
      requiredProbability: Double,
      requiredCount: Double? = nil,
      norm: Double? = nil,
      denominator: Double? = nil,
      tier: Tier = .addUnigram
    ) {
      self.kind = kind
      self.keyArray = keyArray
      self.current = current
      self.previous = previous
      self.anterior = anterior
      self.role = role
      self.requiredProbability = requiredProbability
      self.requiredCount = requiredCount
      self.norm = norm
      self.denominator = denominator
      self.tier = tier
    }

    /// 由一條 Gram 與一個門檻分數組出提案，並用辭典正規化基準逆推 count。
    public init(
      gram: Yukuaki.Gram,
      role: Role,
      requiredProbability: Double,
      norm: Double?,
      contextCount: Double? = nil,
      tier: Tier = .addUnigram
    ) {
      let kind: Kind = gram.isTrigram ? .trigram : (gram.isBigram ? .bigram : .unigram)
      let denominator = contextCount ?? norm
      self.init(
        kind: kind,
        keyArray: gram.keyArray,
        current: gram.current,
        previous: gram.previous,
        anterior: gram.anterior,
        role: role,
        requiredProbability: requiredProbability,
        requiredCount: Self.invertedCount(
          probability: requiredProbability,
          value: gram.current,
          denominator: denominator
        ),
        norm: norm,
        denominator: denominator,
        tier: tier
      )
    }

    // MARK: Public

    /// 詞條種類。
    public enum Kind: String, Codable, Sendable, CaseIterable {
      case unigram
      case bigram
      case trigram
    }

    /// 該詞條在「誘導組句」裡扮演的角色。
    public enum Role: String, Codable, Sendable {
      /// 該詞條在辭典內完全不存在，需要新增。
      case fabricating
      /// 該詞條存在、但分數不夠，需要抬高。
      case boosting
      /// 該詞條用於把組句誘導到「不分詞／換一種分詞」的讀法。
      case selecting
    }

    /// 一條提案的「證據等級」：等級靠前者，所需的「新事實」較少。
    ///
    /// 這與「分數差最小」不是同一回事：分數差只描述距離，證據等級描述「你有多少理由
    /// 相信這是真的」。詞庫裡 count 為 0 的詞條，代表「這個詞存在、頻次未知」——它的
    /// 缺失頻次是本資料集的常態，補一個整數所需的信任遠低於新增一條 bigram。
    public enum Tier: String, Codable, Sendable, CaseIterable, Comparable {
      /// 既有詞條，但 count 為 0（落於零頻次基線）。補上頻次即可。
      case fillMissingCount
      /// 既有詞條，count > 0。需抬高其頻次。
      case adjustCount
      /// 新增一條 bigram。
      case addBigram
      /// 新增一條 trigram。
      case addTrigram
      /// 新增一條詞條。
      case addUnigram

      // MARK: Public

      /// 給人看的一句話。
      public var label: String {
        switch self {
        case .fillMissingCount: "補既有詞條的缺失頻次"
        case .adjustCount: "抬高既有詞條的頻次"
        case .addBigram: "新增 bigram"
        case .addTrigram: "新增 trigram"
        case .addUnigram: "新增詞條"
        }
      }

      public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.order < rhs.order
      }

      // MARK: Private

      private var order: Int {
        switch self {
        case .fillMissingCount: 0
        case .adjustCount: 1
        case .addBigram: 2
        case .addTrigram: 3
        case .addUnigram: 4
        }
      }
    }

    public let kind: Kind
    public let keyArray: [String]
    public let current: String
    public let previous: String?
    public let anterior: String?
    public let role: Role

    /// 該詞條至少需要的分數（log10 權重，愈大愈優先；0 最大）。
    public let requiredProbability: Double

    /// 由該分數逆推出來的出現頻次。辭典未提供正規化基準時為 `nil`。
    public let requiredCount: Double?

    /// 逆推時採用的正規化基準。
    public let norm: Double?

    /// 逆推時實際使用的分母：unigram 用 `_NORM`，帶前驗詞鏈的條目用前驗詞的 count。
    public let denominator: Double?

    /// 該提案的證據等級。
    public let tier: Tier

    /// 該詞條至少需要的整數頻次（`requiredCount` 的無條件進位）；不到 1 者為 `nil`。
    public var countThreshold: Int? {
      guard let requiredCount, requiredCount.isFinite, requiredCount >= 1 else { return nil }
      return Int(requiredCount.rounded(.up))
    }

    /// 該詞條對應的 Gram。
    public var gram: Yukuaki.Gram {
      .init(
        keyArray: keyArray,
        current: current,
        previous: previous,
        anterior: anterior,
        probability: requiredProbability
      )
    }

    /// 是否能以整數頻次表達（count ≥ 1）。
    public var isCountExpressive: Bool {
      guard let requiredCount else { return false }
      return requiredCount >= 1 && requiredCount.isFinite
    }

    /// 逆推公式的反函式。
    ///
    /// 詞頻轉分數的公式（見 `Collector.Unigram.weighten`）是
    /// `score = log10(e^(長度/3 - 1) × count / denominator)`。
    /// unigram 的分母是 `_NORM`（語料總量）；帶前驗詞鏈的條目分母是前驗詞本身的 count，
    /// 因為該分數是條件機率 `p(詞｜前文)`。反函式即 `count = denominator × 10^score / e^(長度/3 - 1)`。
    public static func invertedCount(probability: Double, value: String, denominator: Double?) -> Double? {
      guard let denominator, denominator > 0 else { return nil }
      let scale = exp(Double(value.count) / 3 - 1)
      guard scale > 0 else { return nil }
      let count = denominator * pow(10, probability) / scale
      return count.isFinite ? count : nil
    }

    /// 人類可讀的一行摘要。
    public func summary(separator: String = "-") -> String {
      let reading = keyArray.joined(separator: separator)
      var context: String?
      switch (previous, anterior) {
      case let (previous?, anterior?):
        context = "前文「\(anterior)」→「\(previous)」"
      case (let previous?, nil):
        context = "前文「\(previous)」"
      default:
        context = nil
      }
      var pieces = ["[\(kind.rawValue)|\(role.rawValue)|\(tier.rawValue)] \(reading) → \(current)"]
      if let context { pieces.append(context) }
      pieces.append(String(format: "所需分數 %.4f", requiredProbability))
      let basis = previous.map { denominator != nil ? "（以「\($0)」的 count 為基準）" : "" } ?? ""
      if let countThreshold {
        pieces.append("count ≥ \(countThreshold)\(basis)")
      } else if let requiredCount {
        pieces.append(String(format: "所需 count %.2f\(basis)（不足 1，現行基準無法達成）", requiredCount))
      }
      pieces.append("證據等級：\(tier.label)")
      return pieces.joined(separator: "｜")
    }
  }
}
