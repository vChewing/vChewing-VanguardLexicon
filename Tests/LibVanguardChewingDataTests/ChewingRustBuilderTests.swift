// (c) 2021 and onwards The vChewing Project (BSD-3-Clause).
// ====================
// This code is released under the SPDX-License-Identifier: `BSD-3-Clause`.

import Foundation
@testable import LibVanguardChewingData
import Testing

@Suite
struct ChewingRustBuilderTests {
  // MARK: Internal

  @Test
  func testSyllableEncodingMatchesLibChewingRustLayout() {
    #expect(ChewingRustSyllableEncoder.uintFromPhone("ㄅㄚ") == 520)
    #expect(ChewingRustSyllableEncoder.uintFromPhone("ㄉㄧㄢˋ") == 2_764)
    #expect(ChewingRustSyllableEncoder.uintFromPhone("ㄇㄚˉ") == 1_549)
    #expect(ChewingRustSyllableEncoder.uintFromPhone("ˋㄚ") == nil)
    #expect(ChewingRustSyllableEncoder.uintFromPhone("ㄧㄅ") == nil)
  }

  @Test
  func testDuplicatePhraseUsesLatestFrequency() throws {
    let source = """
    測 1 ㄘㄜˋ
    測 9 ㄘㄜˋ
    詞典 5 ㄘˊ ㄉㄧㄢˇ
    詞典 3 ㄘˊ ㄉㄧㄢˇ
    """

    let builder = try makeBuilder(source: source)

    let single = try #require(builder.phrasesForSyllables(try encodeTokens(["ㄘㄜˋ"])))
    #expect(single == [.init(text: "測", freq: 9)])

    let phrase = try #require(builder.phrasesForSyllables(try encodeTokens(["ㄘˊ", "ㄉㄧㄢˇ"])))
    #expect(phrase == [.init(text: "詞典", freq: 3)])
  }

  @Test
  func testIgnoringNegativeFrequencyForSingleCharEntries() throws {
    let source = """
    ば -1 ㄅㄚ
    バ -1 ㄅㄚ
    八 5 ㄅㄚ
    """

    let builder = try makeBuilder(source: source)
    let phrases = try #require(builder.phrasesForSyllables(try encodeTokens(["ㄅㄚ"])))
    #expect(phrases == [.init(text: "八", freq: 5)])
  }

  @Test
  func testRejectingNegativeFrequencyForMultiCharacterPhrases() {
    let source = "ばば -1 ㄅㄚ ㄅㄚ\n"

    #expect(throws: Error.self) {
      _ = try makeBuilder(source: source)
    }
  }

  @Test
  func testLeafOrderingMatchesRustTrieBuilderSemantics() throws {
    let singleCharSource = """
    冊 9 ㄘㄜˋ
    側 1 ㄘㄜˋ
    測 5 ㄘㄜˋ
    """

    let singleBuilder = try makeBuilder(source: singleCharSource)
    let singlePhrases = try #require(singleBuilder.phrasesForSyllables(try encodeTokens(["ㄘㄜˋ"])))
    #expect(singlePhrases.map(\.text) == ["冊", "側", "測"])

    let multiCharSource = """
    甲乙 5 ㄐㄧㄚˇ ㄧˇ
    乙甲 5 ㄐㄧㄚˇ ㄧˇ
    丙丁 9 ㄐㄧㄚˇ ㄧˇ
    """

    let multiBuilder = try makeBuilder(source: multiCharSource)
    let multiPhrases = try #require(multiBuilder.phrasesForSyllables(try encodeTokens(["ㄐㄧㄚˇ", "ㄧˇ"])))
    #expect(multiPhrases.map(\.text) == ["丙丁", "甲乙", "乙甲"])
  }

  @Test
  func testGenerateArtifactsProduceChewDocumentHeader() throws {
    let artifacts = try ChewingRustDatabaseGenerator.generateArtifacts(
      tsiSrc: "詞典 7 ㄘˊ ㄉㄧㄢˇ\n",
      wordSrc: "詞 2 ㄘˊ\n"
    )

    #expect(artifacts.tsi.first == 0x30)
    #expect(artifacts.word.first == 0x30)
    #expect(artifacts.tsi.range(of: Data("CHEW".utf8)) != nil)
    #expect(artifacts.word.range(of: Data("CHEW".utf8)) != nil)
  }

  // MARK: Private

  private func makeBuilder(source: String) throws -> ChewingRustDatabaseGenerator.TrieBuilder {
    let builder = ChewingRustDatabaseGenerator.TrieBuilder()
    for entry in try ChewingRustDatabaseGenerator.parseSource(source) {
      try builder.insert(entry)
    }
    return builder
  }

  private func encodeTokens(_ tokens: [String]) throws -> [UInt16] {
    try tokens.map { token in
      try #require(ChewingRustSyllableEncoder.uintFromPhone(token))
    }
  }
}
