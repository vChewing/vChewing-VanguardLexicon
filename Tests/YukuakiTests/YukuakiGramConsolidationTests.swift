// (c) 2026 and onwards The vChewing Project (MulanPSL-2.0 License).
// ====================
// This code is released under the SPDX-License-Identifier: `MulanPSL-2.0`.

import Foundation
import Testing
@testable import Yukuaki

// MARK: - YukuakiGramConsolidationTests

@Suite("Yukuaki：gram 去重")
struct YukuakiGramConsolidationTests {
  @Test("同身分留最高分、同分留先出現者、前文不同與讀音鍵不同皆不併")
  func consolidatedKeepsHighestProbability() {
    let low = Yukuaki.Gram(keyArray: ["ㄅㄚ"], current: "八", probability: -5)
    let high = Yukuaki.Gram(keyArray: ["ㄅㄚ"], current: "八", probability: -3)
    let middle = Yukuaki.Gram(keyArray: ["ㄅㄚ"], current: "八", probability: -4)
    let contextual = Yukuaki.Gram(
      keyArray: ["ㄅㄚ"],
      current: "八",
      previous: "十",
      probability: -9
    )
    let consolidated = [low, high, middle, contextual].consolidated()
    #expect(consolidated.count == 2)
    #expect(consolidated.first?.probability == -3)
    #expect(consolidated.first?.previous == nil)
    #expect(consolidated.last?.previous == "十")

    let tied1 = Yukuaki.Gram(keyArray: ["ㄅㄚ"], current: "吧", probability: -2)
    let tied2 = Yukuaki.Gram(keyArray: ["ㄅㄚ"], current: "吧", probability: -2)
    #expect([tied1, tied2].consolidated().count == 1)

    let otherKey = Yukuaki.Gram(keyArray: ["ㄆㄚ"], current: "吧", probability: -2)
    #expect([tied1, otherKey].consolidated().count == 2)
  }

  @Test("組句器：同一節點內同值多筆只留最高分者")
  func assemblerConsolidatesSameValue() throws {
    let grams: [Yukuaki.Gram] = [
      Yukuaki.Gram(keyArray: ["ㄅㄚ"], current: "八", probability: -5),
      Yukuaki.Gram(keyArray: ["ㄅㄚ"], current: "八", probability: -3),
      Yukuaki.Gram(keyArray: ["ㄅㄚ"], current: "吧", probability: -4),
    ]
    let querier: Yukuaki.GramQuerier = { keys in
      grams.filter { $0.keyArray == keys.representativeKeys }
    }
    let assembler = Yukuaki.Assembler(
      gramQuerier: querier,
      config: Yukuaki.Config(maxSegLength: 10)
    )
    try assembler.insertKeys(["ㄅㄚ"].map { Yukuaki.PossibleKey.singleKey($0) })
    let nodes = assembler.dumpNodes()
    let node = try #require(nodes.first)
    #expect(node.unigramCount == 2)
    #expect(node.candidates.map(\.value) == ["八", "吧"])
    #expect(node.candidates.first?.probability == -3)
  }

  @Test("逆推：同值多筆不改變提案（以最高分為準，不得把頻次不足誤判為零頻次）")
  func advisorIgnoresDuplicates() throws {
    let high: [Yukuaki.Gram] = [
      Yukuaki.Gram(keyArray: ["ㄉㄧㄢˋ"], current: "電", probability: -3),
      Yukuaki.Gram(keyArray: ["ㄋㄠˇ"], current: "腦", probability: -3),
      Yukuaki.Gram(keyArray: ["ㄋㄠˇ"], current: "惱", probability: -4),
      Yukuaki.Gram(keyArray: ["ㄉㄧㄢˋ-ㄋㄠˇ"], current: "電腦", probability: -3.3),
    ]
    // 低分那筆刻意排在最前：舊制之 `first(where:)` 會取到它，把「頻次不足」誤判成「零頻次」。
    let duplicated = [
      Yukuaki.Gram(keyArray: ["ㄋㄠˇ"], current: "惱", probability: -114.514),
    ] + high

    func proposals(_ grams: [Yukuaki.Gram]) throws -> [Yukuaki.GramSpec] {
      let querier: Yukuaki.GramQuerier = { keys in
        grams.filter { $0.keyArray == keys.representativeKeys }
      }
      let advisor = Yukuaki.Advisor(gramQuerier: querier, norm: 1_000_000_000)
      return try advisor.analyze(readingChain: ["ㄉㄧㄢˋ", "ㄋㄠˇ"], expected: "電惱").proposals
    }

    let base = try proposals(high)
    let withDuplicate = try proposals(duplicated)
    #expect(base == withDuplicate)
    // 「惱」在期望分詞之內：若取到較低分那筆，會被誤判成「零頻次」（`fillMissingCount`）。
    let nǎo = try #require(base.first { $0.current == "惱" && $0.previous == nil })
    #expect(nǎo.tier == .adjustCount)
  }
}
