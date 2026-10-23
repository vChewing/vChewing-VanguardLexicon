// (c) 2025 and onwards The vChewing Project (MulanPSL-2.0 License).
// ====================
// This code is released under the SPDX-License-Identifier: `MulanPSL-2.0`.

import Testing
@testable import Yukuaki

// MARK: - YukuakiNodeOverrideTests

/// 節點覆寫型別在組句期間的語義。
///
/// P325 的右文脈 DP 會對**同一個節點**以多組前文反覆估值，所以估值的兩個產物
/// （「得多少分」與「該選哪一條 gram」）必須分開說清楚；否則兩引擎會在同一份資料上
/// 給出不同的字，或同一引擎連兩次組句都給出不同的字。
@Suite("Yukuaki：節點覆寫與估值")
struct YukuakiNodeOverrideTests {
  // MARK: Internal

  /// 弱釘選（`withTopGramScore`）只把分數壓回 unigram 基線，**不得**改動當前選取。
  ///
  /// 該型別由 POM 之自動套用端（`forceHighScoreOverride == false`）以 `select` 設定，
  /// 那時 `currentGramIndex` 已經指向使用者在選字窗挑的那條候選；若在估值時把選取撥回
  /// `topUnigramGram`，使用者挑的詞就會被丟掉。（Homa 側以 `targetIndex: nil` 表達同一件事。）
  @Test("Yukuaki：弱釘選只壓分數、不動選取")
  func weakOverrideKeepsSelection() throws {
    var node = Self.makeNode()
    try node.select(
      keyArray: ["ㄓㄜˋ"],
      value: "著",
      previous: "再",
      anterior: nil,
      type: .withTopGramScore
    )
    let pinned = try #require(node.currentGram)
    let evaluation = node.evaluate(previous: "要")
    #expect(pinned.current == "著")
    #expect(evaluation.gram?.current == "著")
    #expect(evaluation.gram == pinned)
    // 分數仍是 unigram 基線（「這」的 −2.5），不是該 bigram 自己的 −1.0。
    #expect(abs(evaluation.score - -2.5) < 1e-6)
  }

  /// 強釘選（`withSpecified`）在**沒有前文**時仍取覆寫分數。
  ///
  /// 組句的第一個節點永遠沒有前文；若該臂繞過覆寫狀態，被 POM 釘住的節點就會輸給
  /// 其它路徑，使用者的選擇照樣會掉。（Homa 側於 P325 一併對齊。）
  @Test("Yukuaki：強釘選在無前文時仍取覆寫分數")
  func strongOverrideScoresWithoutPrevious() throws {
    var node = Self.makeNode()
    try node.select(
      keyArray: ["ㄓㄜˋ"],
      value: "著",
      previous: "再",
      anterior: nil,
      type: .withSpecified
    )
    let pinned = try #require(node.currentGram)
    let evaluation = node.evaluate(previous: nil)
    #expect(evaluation.gram == pinned)
    #expect(abs(evaluation.score - Yukuaki.Node.defaultOverridingScore) < 1e-6)
  }

  // MARK: Private

  /// 一個「單讀音、兩條 gram」的節點：「這」（單元圖 −2.5）與「著」（`再` 之後的 bigram、−1.0）。
  /// 排序後 bigram 因分數較高而排在前面，故 `currentGramIndex == 0` 時選取的是「著」。
  private static func makeNode() -> Yukuaki.Node {
    Yukuaki.Node(
      keyArray4Query: ["ㄓㄜˋ"],
      grams: [
        .init(keyArray: ["ㄓㄜˋ"], current: "這", probability: -2.5),
        .init(keyArray: ["ㄓㄜˋ"], current: "著", previous: "再", probability: -1.0),
      ]
    )
  }
}
