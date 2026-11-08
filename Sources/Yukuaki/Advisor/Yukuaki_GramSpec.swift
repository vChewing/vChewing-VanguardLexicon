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
      existingCount: Double? = nil,
      norm: Double? = nil,
      denominator: Double? = nil,
      denominatorSource: DenominatorSource = .normalizedBaseline,
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
      self.existingCount = existingCount
      self.norm = norm
      self.denominator = denominator
      self.denominatorSource = denominatorSource
      self.tier = tier
    }

    /// 由一條 Gram 與一個門檻分數組出提案，並用辭典正規化基準逆推 count。
    public init(
      gram: Yukuaki.Gram,
      role: Role,
      requiredProbability: Double,
      norm: Double?,
      contextCount: Double? = nil,
      existingCount: Double? = nil,
      tier: Tier = .addUnigram
    ) {
      let kind: Kind = gram.isTrigram ? .trigram : (gram.isBigram ? .bigram : .unigram)
      let denominator = contextCount ?? norm
      // 前文詞頻取不到時，分母只是 `_NORM`（無條件機率），並非條件機率的分母。
      let denominatorSource: DenominatorSource = contextCount == nil ? .normalizedBaseline : .fullContext
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
        existingCount: existingCount,
        norm: norm,
        denominator: denominator,
        denominatorSource: denominatorSource,
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

    /// 逆推 count 時所用分母的來源。
    public enum DenominatorSource: String, Codable, Sendable {
      /// 前文之完整詞頻（bigram 為 `count(y)`、trigram 為 `count(x, y)`）。
      case fullContext
      /// 未取得前文詞頻，暫以 `_NORM` 折算之無條件機率。
      case normalizedBaseline
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

    /// 該詞條的現行頻次（可由既有 gram 的分數逆推）。僅 unigram 有值。
    public let existingCount: Double?

    /// 逆推時採用的正規化基準。
    public let norm: Double?

    /// 逆推時實際使用的分母：unigram 用 `_NORM`、bigram 用 `count(y)`、trigram 用 `count(x, y)`。
    public let denominator: Double?

    /// 上述分母的來源。
    public let denominatorSource: DenominatorSource

    /// 匯出原廠多字圖列時所用的名義分母（與 P336 之腳本一致）。
    public static let nominalDenominator: Double = 1_000

    /// 該提案的證據等級。
    public let tier: Tier

    /// 該詞條至少需要的整數頻次（`requiredCount` 的無條件進位）；不到 1 者為 `nil`。
    public var countThreshold: Int? {
      guard let requiredCount, requiredCount.isFinite, requiredCount >= 1 else { return nil }
      return Int(requiredCount.rounded(.up))
    }

    /// 所需頻次相對現行頻次的倍率。
    ///
    /// 只有 `adjustCount` 有意義：`fillMissingCount` 的既有頻次是零頻次基線（0.25），
    /// 倍率再大也只是「補上缺失頻次」，不是改寫既有詞頻。
    public var countMultiplier: Double? {
      guard tier == .adjustCount, let requiredCount, let existingCount, existingCount > 0 else { return nil }
      return requiredCount / existingCount
    }

    /// 可直接貼進 `userdata-{cht,chs}.txt` 的一列（僅 n-gram 提案）。
    ///
    /// 前文鏈由舊至新以 `|` 相接，分數取「剛好夠用」的邊界；實際寫入時可視情況加嚴。
    public var userDataRow: String? {
      guard kind != .unigram else { return nil }
      let chain = [anterior, previous].compactMap { $0 }.joined(separator: "|")
      guard !chain.isEmpty else { return nil }
      let reading = keyArray.joined(separator: "-")
      let score = String(format: "%.4f", requiredProbability)
      return "\(current) \(reading) \(score) #NGRAM:\(chain)"
    }

    /// 原廠多字圖列（`phrases-ngram-*.txt`）所需的整數次數。
    ///
    /// 與 `Dict_NewPhrasesPreparer`（P336）同式：`次數 = max(1, round(D × 10^分數 / e^(詞長/3 − 1)))`。
    /// 名義分母之下限為 `log10(e^(詞長/3 − 1) / D)`；比它更弱的分數一律被抬成 1 次（因而變強）。
    public func factoryCount(nominalDenominator: Double = GramSpec.nominalDenominator) -> Int? {
      guard kind != .unigram else { return nil }
      let scale = exp(Double(current.count) / 3 - 1)
      guard scale > 0 else { return nil }
      let raw = nominalDenominator * pow(10, requiredProbability) / scale
      guard raw.isFinite, raw > 0 else { return nil }
      return max(1, Int(raw.rounded()))
    }

    /// 名義分母之下限分數（比它更弱者無法以整數次數表達）。
    public func nominalFloor(nominalDenominator: Double = GramSpec.nominalDenominator) -> Double? {
      guard kind != .unigram else { return nil }
      let scale = exp(Double(current.count) / 3 - 1)
      guard scale > 0 else { return nil }
      return log10(scale / nominalDenominator)
    }

    /// 以「1 次」表達該分數所需的最小名義分母。
    ///
    /// 現行名義分母（1000）不足以表達弱分數時，維護者可據此判斷要不要調大分母。
    public func minimalNominalDenominator() -> Double? {
      guard kind != .unigram else { return nil }
      let scale = exp(Double(current.count) / 3 - 1)
      guard scale > 0 else { return nil }
      let value = scale / pow(10, requiredProbability)
      return value.isFinite ? value : nil
    }

    /// 該提案的分數是否弱於名義分母之下限。
    public func isBelowNominalFloor(nominalDenominator: Double = GramSpec.nominalDenominator) -> Bool {
      guard let floor = nominalFloor(nominalDenominator: nominalDenominator) else { return false }
      return requiredProbability < floor
    }

    /// 可直接貼進 `phrases-ngram-{cht,chs}.txt` 的一列（僅 n-gram 提案）。
    ///
    /// 欄序與 P336 之匯出腳本一致：`詞值 次數 讀音 前文鏈 count(前文)`。
    /// 欄界是空白（空格或 TAB 皆可），但欄內不得再有空白：讀音以 `-` 連接、
    /// 前文鏈以 `|` 連接（由舊至新）——故 TAB 被編輯器換成空格也不會歧義。
    public func factoryRow(nominalDenominator: Double = GramSpec.nominalDenominator) -> String? {
      guard let count = factoryCount(nominalDenominator: nominalDenominator) else { return nil }
      let chain = [anterior, previous].compactMap { $0 }.joined(separator: "|")
      guard !chain.isEmpty else { return nil }
      let reading = keyArray.joined(separator: "-")
      return [current, "\(count)", reading, chain, "\(Int(nominalDenominator))"].joined(separator: " ")
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

    /// 所需頻次是否已逾「補頻次」的合理範圍。
    ///
    /// 這與證據等級描述的是兩件事：等級說「這是哪一種新事實」，倍率說「這個改動有多大」。
    /// 把一個既有詞的頻次抬高一個數量級，已經不是「它原本被低估了一點」，而是重寫該詞
    /// 在語料裡的分量——全域生效、且與其他句子互相牽連。屆時一條條件機率的 n-gram
    /// 往往是更誠實的說法，故由 `Advisor` 降級為替代方案。
    public func isOverCountBudget(threshold: Double) -> Bool {
      guard let countMultiplier else { return false }
      return countMultiplier > threshold
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
      let basis = previous.map { basisText(previous: $0) } ?? ""
      if let countThreshold {
        pieces.append("count ≥ \(countThreshold)\(basis)")
      } else if let requiredCount {
        pieces.append(String(format: "所需 count %.2f\(basis)（不足 1，現行基準無法達成）", requiredCount))
      }
      if let countMultiplier, let existingCount {
        pieces.append(String(format: "現行約 %.0f，倍率 %.1f×", existingCount, countMultiplier))
      }
      pieces.append("證據等級：\(tier.label)")
      return pieces.joined(separator: "｜")
    }

    // MARK: Private

    /// 分母依據的人類可讀說明。
    private func basisText(previous: String) -> String {
      let context = [anterior, previous].compactMap { $0 }.joined(separator: " ")
      switch denominatorSource {
      case .fullContext:
        return "（以「\(context)」的 count 為基準）"
      case .normalizedBaseline:
        return kind == .unigram ? "" : "（未取得「\(context)」的 count，暫以 _NORM 折算）"
      }
    }
  }
}
