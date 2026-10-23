// (c) 2025 and onwards The vChewing Project (MulanPSL-2.0 License).
// ====================
// This code is released under the SPDX-License-Identifier: `MulanPSL-2.0`.

import Testing
@testable import Yukuaki

// MARK: - StubLexicon

/// 給測試用的最小辭典：只按讀音回傳詞條。
private struct StubLexicon {
  let grams: [Yukuaki.Gram]

  func querier(_ keys: [Yukuaki.PossibleKey]) -> [Yukuaki.Gram] {
    let wanted = keys.representativeKeys
    return grams.filter { $0.keyArray == wanted }
  }

  func checker(_ keys: [String]) -> Bool {
    grams.contains { $0.keyArray == keys }
  }

  func assembler(maxSegLength: Int = 10) -> Yukuaki.Assembler {
    Yukuaki.Assembler(
      gramQuerier: querier,
      gramAvailabilityChecker: checker,
      config: Yukuaki.Config(maxSegLength: maxSegLength)
    )
  }
}

private func unigram(_ key: String, _ value: String, _ probability: Double) -> Yukuaki.Gram {
  Yukuaki.Gram(keyArray: [key], current: value, probability: probability)
}

private func multiGram(
  _ keys: [String],
  _ value: String,
  _ probability: Double,
  previous: String? = nil,
  anterior: String? = nil
)
  -> Yukuaki.Gram {
  Yukuaki.Gram(
    keyArray: keys,
    current: value,
    previous: previous,
    anterior: anterior,
    probability: probability
  )
}

// MARK: - YukuakiAssemblyTests

@Suite("Yukuaki：組句")
struct YukuakiAssemblyTests {
  @Test("單字詞時取分數最高的 unigram")
  func picksHighestUnigram() throws {
    let lexicon = StubLexicon(grams: [
      unigram("ㄅㄚ", "八", -3),
      unigram("ㄅㄚ", "巴", -5),
    ])
    let assembler = lexicon.assembler()
    try assembler.insertKeys(["ㄅㄚ", "ㄅㄚ"])
    #expect(assembler.assembledText == "八八")
    #expect(abs(assembler.assembleWithScore().score - -6) < 1e-9)
  }

  @Test("多音節詞條會勝過逐字組句")
  func prefersMultiSyllableWord() throws {
    let lexicon = StubLexicon(grams: [
      unigram("ㄉㄧㄢˋ", "電", -3),
      unigram("ㄋㄠˇ", "腦", -3),
      multiGram(["ㄉㄧㄢˋ", "ㄋㄠˇ"], "電腦", -5),
    ])
    let assembler = lexicon.assembler()
    try assembler.insertKeys(["ㄉㄧㄢˋ", "ㄋㄠˇ"])
    #expect(assembler.assembledText == "電腦")
    #expect(assembler.assembledSentence.count == 1)
  }

  @Test("bigram 分數高於 unigram 基底時會改變組句")
  func bigramFlipsResult() throws {
    let lexicon = StubLexicon(grams: [
      unigram("ㄅㄚ", "八", -3),
      unigram("ㄅㄚ", "巴", -5),
      multiGram(["ㄅㄚ"], "巴", -2, previous: "八"),
    ])
    let assembler = lexicon.assembler()
    try assembler.insertKeys(["ㄅㄚ", "ㄅㄚ"])
    #expect(assembler.assembledText == "八巴")
    #expect(abs(assembler.assembleWithScore().score - -5) < 1e-9)
  }

  @Test("同分時 trigram 優先於 bigram")
  func trigramWinsOnTie() throws {
    let lexicon = StubLexicon(grams: [
      unigram("ㄅㄚ", "八", -3),
      multiGram(["ㄅㄚ"], "巴", -2, previous: "八"),
      multiGram(["ㄅㄚ"], "巴", -2, previous: "巴", anterior: "八"),
    ])
    let assembler = lexicon.assembler()
    try assembler.insertKeys(["ㄅㄚ", "ㄅㄚ", "ㄅㄚ"])
    let path = assembler.assembledSentence
    #expect(path.count == 3)
    #expect(path[2].gram.isTrigram)
  }

  @Test("覆寫成 withSpecified 時直接採用覆寫分數")
  func explicitOverrideWins() throws {
    let lexicon = StubLexicon(grams: [
      unigram("ㄅㄚ", "八", -3),
      unigram("ㄅㄚ", "巴", -5),
    ])
    let assembler = lexicon.assembler()
    try assembler.insertKeys(["ㄅㄚ"])
    let node = Yukuaki.Node(
      keyArray4Query: ["ㄅㄚ"],
      grams: [unigram("ㄅㄚ", "八", -3), unigram("ㄅㄚ", "巴", -5)]
    )
    var overridden = node
    try overridden.select(
      keyArray: ["ㄅㄚ"],
      value: "巴",
      previous: nil,
      anterior: nil,
      type: .withSpecified
    )
    #expect(overridden.evaluate(previous: nil).score == Yukuaki.Node.defaultOverridingScore)
    #expect(overridden.evaluate(previous: nil).gram?.current == "巴")
    #expect(assembler.assembledText == "八")
  }

  @Test("查無詞條的讀音會拋錯")
  func missingKeyThrows() {
    let lexicon = StubLexicon(grams: [unigram("ㄅㄚ", "八", -3)])
    let assembler = lexicon.assembler()
    #expect(throws: Yukuaki.Exception.self) {
      try assembler.insertKeys(["ㄅㄚ", "ㄅㄛ"])
    }
  }

  @Test("空讀音鏈會拋錯")
  func emptyChainThrows() {
    let lexicon = StubLexicon(grams: [unigram("ㄅㄚ", "八", -3)])
    let assembler = lexicon.assembler()
    #expect(throws: Yukuaki.Exception.self) {
      try assembler.insertKeys([String]())
    }
  }

  @Test("topPaths 會給出多條候選路徑")
  func topPathsReturnsAlternatives() throws {
    let lexicon = StubLexicon(grams: [
      unigram("ㄅㄚ", "八", -3),
      unigram("ㄅㄚ", "巴", -5),
    ])
    let assembler = lexicon.assembler()
    try assembler.insertKeys(["ㄅㄚ", "ㄅㄚ"])
    let paths = assembler.topPaths(limit: 5)
    #expect(!paths.isEmpty)
    #expect(paths.first?.text == "八八")
    #expect(paths.allSatisfy { $0.keyArray == ["ㄅㄚ", "ㄅㄚ"] })
  }

  @Test("節點格的幅節長度上限會被 Cartesian 預算壓低")
  func cartesianBudgetShrinksSegLength() throws {
    let keys = (0 ..< 12).map { "ㄅ\($0)" }
    var grams = [Yukuaki.Gram]()
    for key in keys {
      grams.append(Yukuaki.Gram(keyArray: [key], current: "字", probability: -3))
    }
    let lexicon = StubLexicon(grams: grams)
    let assembler = lexicon.assembler(maxSegLength: 10)
    try assembler.insertKeys(keys)
    #expect(assembler.assembledText == String(repeating: "字", count: 12))
  }
}
