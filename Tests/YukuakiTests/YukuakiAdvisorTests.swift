// (c) 2025 and onwards The vChewing Project (MulanPSL-2.0 License).
// ====================
// This code is released under the SPDX-License-Identifier: `MulanPSL-2.0`.

import Foundation
import Testing
@testable import Yukuaki

// MARK: - AdvisorFixture

/// 給逆推測試用的辭典。
private struct AdvisorFixture {
  // MARK: Lifecycle

  init(grams: [Yukuaki.Gram], norm: Double? = 1_000_000_000) {
    self.grams = grams
    self.norm = norm
  }

  // MARK: Internal

  let grams: [Yukuaki.Gram]
  let norm: Double?

  func query(_ keys: [Yukuaki.PossibleKey]) -> [Yukuaki.Gram] {
    let wanted = keys.representativeKeys
    return grams.filter { $0.keyArray == wanted }
  }

  func advisor(maxChunkLength: Int = 10) -> Yukuaki.Advisor {
    var options = Yukuaki.Advisor.Options()
    options.maxChunkLength = maxChunkLength
    return Yukuaki.Advisor(gramQuerier: query, norm: norm, options: options)
  }

  func assembledText(of chain: [String]) throws -> String {
    let assembler = Yukuaki.Assembler(
      gramQuerier: query,
      config: Yukuaki.Config(maxSegLength: 10)
    )
    try assembler.insertKeys(chain)
    return assembler.assembledText
  }
}

private func ug(_ key: String, _ value: String, _ probability: Double) -> Yukuaki.Gram {
  Yukuaki.Gram(keyArray: [key], current: value, probability: probability)
}

private func bg(_ key: String, _ value: String, _ probability: Double, previous: String) -> Yukuaki.Gram {
  Yukuaki.Gram(keyArray: [key], current: value, previous: previous, probability: probability)
}

// MARK: - YukuakiAdvisorTests

@Suite("Yukuaki：逆推")
struct YukuakiAdvisorTests {
  // MARK: Internal

  @Test("預設組句與期望結果一致時不給提案")
  func matchedNeedsNoProposal() throws {
    let fixture = dianNaoLexicon
    #expect(try fixture.assembledText(of: ["ㄉㄧㄢˋ", "ㄋㄠˇ"]) == "電腦")
    let report = try fixture.advisor().analyze(readingChain: ["ㄉㄧㄢˋ", "ㄋㄠˇ"], expected: "電腦")
    #expect(report.isMatched)
    #expect(report.proposals.isEmpty)
    #expect(report.validation == nil)
  }

  @Test("競品頻次不足時優先抬高該詞條的 count，而不是新增 bigram")
  func prefersAdjustingExistingCount() throws {
    let fixture = dianNaoLexicon
    let report = try fixture.advisor().analyze(readingChain: ["ㄉㄧㄢˋ", "ㄋㄠˇ"], expected: "電惱")
    #expect(!report.isMatched)
    #expect(report.proposals.count == 1)
    let proposal = try #require(report.proposals.first)
    /// 「惱」本來就在詞庫裡、只是輸給「腦」——最便宜的修法是抬高它的頻次，
    /// 而不是去編造一條 bigram。這正是證據成本分級的第一級。
    #expect(proposal.kind == .unigram)
    #expect(proposal.current == "惱")
    #expect(proposal.previous == nil)
    #expect(proposal.tier == .adjustCount)
    /// 競品（腦）的分數是 -3，故所需分數必定高於 -3、且高不出一個量級。
    #expect(proposal.requiredProbability > -3)
    #expect(proposal.requiredProbability < -2.9)
    #expect(proposal.isCountExpressive)
    let count = try #require(proposal.requiredCount)
    #expect(count > 0)
    #expect(report.validation?.isSatisfied == true)
    #expect(report.validation?.finalText == "電惱")
  }

  @Test("詞庫缺詞時提議新增該 unigram，並與既有詞的頻次調整分級")
  func proposesMissingUnigram() throws {
    let fixture = dianNaoLexicon
    /// 把詞段長度限死在 1，強制分詞成兩個單字詞，才能驗證「缺 unigram」的情形。
    let report = try fixture.advisor(maxChunkLength: 1)
      .analyze(readingChain: ["ㄉㄧㄢˋ", "ㄋㄠˇ"], expected: "惦惱")
    #expect(!report.isMatched)
    #expect(report.proposals.count == 2)
    #expect(report.proposals.allSatisfy { $0.kind == .unigram })
    #expect(report.proposals.allSatisfy { $0.isCountExpressive })
    /// 「惦」是詞庫沒有的字，證據等級最高（最貴）；「惱」只是頻次不足。
    #expect(report.proposals.first { $0.current == "惦" }?.tier == .addUnigram)
    #expect(report.proposals.first { $0.current == "惱" }?.tier == .adjustCount)
    #expect(report.validation?.isSatisfied == true)
    #expect(report.validation?.finalText == "惦惱")
  }

  @Test("再／在 這類詞界改選，也走「抬高既有詞條頻次」的便宜路徑")
  func prefersAdjustingExistingCountForZai() throws {
    let fixture = AdvisorFixture(grams: [
      ug("ㄗㄞˋ", "在", -3),
      ug("ㄗㄞˋ", "再", -4.5),
      ug("ㄓㄜˋ", "這", -3),
      ug("ㄧㄤˋ", "樣", -3),
    ])
    #expect(try fixture.assembledText(of: ["ㄗㄞˋ", "ㄓㄜˋ", "ㄧㄤˋ"]) == "在這樣")
    let report = try fixture.advisor()
      .analyze(readingChain: ["ㄗㄞˋ", "ㄓㄜˋ", "ㄧㄤˋ"], expected: "再這樣")
    #expect(!report.isMatched)
    #expect(report.proposals.count == 1)
    let proposal = try #require(report.proposals.first)
    #expect(proposal.kind == .unigram)
    #expect(proposal.current == "再")
    #expect(proposal.tier == .adjustCount)
    #expect(report.validation?.finalText == "再這樣")
  }

  @Test("已存在的長詞條被拆開時給出 selecting 型提案")
  func proposesSelectingBigram() throws {
    let fixture = AdvisorFixture(grams: [
      ug("ㄉㄧㄢˋ", "電", -3),
      ug("ㄋㄠˇ", "腦", -3),
      Yukuaki.Gram(keyArray: ["ㄉㄧㄢˋ", "ㄋㄠˇ"], current: "電腦", probability: -5),
      ug("ㄋㄠˇ", "惱", -6),
    ])
    #expect(try fixture.assembledText(of: ["ㄉㄧㄢˋ", "ㄋㄠˇ"]) == "電腦")
    let report = try fixture.advisor().analyze(readingChain: ["ㄉㄧㄢˋ", "ㄋㄠˇ"], expected: "電惱")
    #expect(!report.isMatched)
    #expect(!report.proposals.isEmpty)
    #expect(report.validation?.isSatisfied == true)
  }

  @Test("未提供正規化基準時無法逆推 count")
  func noNormMeansNoCount() throws {
    let fixture = AdvisorFixture(
      grams: [
        ug("ㄉㄧㄢˋ", "電", -3),
        ug("ㄋㄠˇ", "腦", -3),
        ug("ㄋㄠˇ", "惱", -4.5),
      ],
      norm: nil
    )
    let report = try fixture.advisor().analyze(readingChain: ["ㄉㄧㄢˋ", "ㄋㄠˇ"], expected: "電惱")
    #expect(report.proposals.allSatisfy { $0.requiredCount == nil })
    #expect(report.notes.contains { $0.contains("正規化基準") })
  }

  @Test("字數與讀音數不符時拋錯")
  func mismatchThrows() {
    let fixture = dianNaoLexicon
    #expect(throws: Yukuaki.Exception.self) {
      try fixture.advisor().analyze(readingChain: ["ㄉㄧㄢˋ", "ㄋㄠˇ"], expected: "電腦愛好者")
    }
  }

  @Test("逆推 count 的公式可以反解回分數")
  func invertedCountRoundTrips() throws {
    let norm = 1_000_000_000.0
    let value = "電腦"
    let probability = -3.0
    let count = try #require(Yukuaki.GramSpec.invertedCount(probability: probability, value: value, denominator: norm))
    /// score = log10(e^(len/3 - 1) × count / norm)
    let restored = log10(exp(Double(value.count) / 3 - 1) * count / norm)
    #expect(abs(restored - probability) < 1e-9)
  }

  @Test("GramSpec 的摘要包含所需分數與逆推頻次")
  func specSummaryIsInformative() {
    let spec = Yukuaki.GramSpec(
      kind: .bigram,
      keyArray: ["ㄉㄧㄢˋ", "ㄋㄠˇ"],
      current: "電腦",
      previous: "我",
      role: .boosting,
      requiredProbability: -3.5,
      requiredCount: 12_345,
      norm: 1e9
    )
    let summary = spec.summary()
    #expect(summary.contains("bigram"))
    #expect(summary.contains("boosting"))
    #expect(summary.contains("電腦"))
    #expect(summary.contains("前文「我」"))
    #expect(summary.contains("count"))
  }

  // MARK: Private

  private var dianNaoLexicon: AdvisorFixture {
    AdvisorFixture(grams: [
      ug("ㄉㄧㄢˋ", "電", -3),
      ug("ㄋㄠˇ", "腦", -3),
      ug("ㄋㄠˇ", "惱", -4.5),
    ])
  }
}
