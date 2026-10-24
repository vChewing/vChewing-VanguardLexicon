// (c) 2025 and onwards The vChewing Project (MulanPSL-2.0 License).
// ====================
// This code is released under the SPDX-License-Identifier: `MulanPSL-2.0`.

import Foundation
import Testing
@testable import VanguardLexiconCorpusMiner

// MARK: - TxtMapUnigramIndexTests

struct TxtMapUnigramIndexTests {
  @Test
  func countInversionFollowsWeighten() {
    let norm = 1000.0
    let probability = -2.301
    let index = TxtMapUnigramIndex(
      norm: norm,
      entries: [("测试", probability, ["ㄘㄜˋ", "ㄕˋ"])]
    )
    let expected = norm * pow(10, probability) / exp(2.0 / 3 - 1)
    #expect(abs(index.count(of: "测试") - expected) < 1e-9)
    #expect(index.maximumValueLength == 2)
    #expect(index.unigram("测试")?.readings.count == 1)
  }

  @Test
  func multipleReadingsKeepTheirOwnProbability() {
    let index = TxtMapUnigramIndex(
      norm: 100,
      entries: [
        ("谁", -2.0, ["ㄕㄟˊ"]),
        ("谁", -6.0, ["ㄕㄨㄟˊ"]),
      ]
    )
    let readings = index.unigram("谁")?.readings ?? []
    #expect(readings.count == 2)
    #expect(readings.max { $0.probability < $1.probability }?.key == ["ㄕㄟˊ"])
    #expect(index.probability(of: "谁") == -2.0)
  }
}

// MARK: - UnigramSegmenterTests

struct UnigramSegmenterTests {
  private func makeIndex() -> TxtMapUnigramIndex {
    TxtMapUnigramIndex(
      norm: 10_000,
      entries: [
        ("北京", -1.5, ["ㄅㄟˇ", "ㄐㄧㄥ"]),
        ("北", -3.0, ["ㄅㄟˇ"]),
        ("京", -3.5, ["ㄐㄧㄥ"]),
        ("大学", -2.0, ["ㄉㄚˋ", "ㄒㄩㄝˊ"]),
        ("大", -1.0, ["ㄉㄚˋ"]),
        ("学", -2.5, ["ㄒㄩㄝˊ"]),
      ]
    )
  }

  @Test
  func prefersWholeWordWhenCheaper() {
    let segmenter = UnigramSegmenter(index: makeIndex())
    let result = segmenter.segment("北京大学")
    #expect(result.words == ["北京", "大学"])
  }

  @Test
  func maximumWordLengthCapsLookup() {
    let capped = UnigramSegmenter(index: makeIndex(), maximumWordLength: 1).segment("北京大学")
    #expect(capped.words == ["北", "京", "大", "学"])
    let restored = UnigramSegmenter(index: makeIndex(), maximumWordLength: 2).segment("北京大学")
    #expect(restored.words == ["北京", "大学"])
  }

  @Test
  func unknownSinglesFormRuns() {
    let segmenter = UnigramSegmenter(index: makeIndex())
    // 鑫垚 皆不在詞表，且皆為單字 → 一個「疑似缺詞」片段。
    let result = segmenter.segment("鑫垚")
    #expect(result.words == ["鑫", "垚"])
    #expect(result.unknownRuns == ["鑫垚"])
  }

  @Test
  func asciiRunsAreCoalesced() {
    let words = ["1", "4", "9", "年", ".", "5"]
    #expect(UnigramSegmenter.coalescingASCIIRuns(in: words) == ["149", "年", ".", "5"])
  }
}

// MARK: - CorpusMinerTests

struct CorpusMinerTests {
  @Test
  func candidateRequiresStrictLift() {
    // 「北京」之單元圖分數為 -2；候選列之機率須嚴格大於它（再加 margin）。
    let index = TxtMapUnigramIndex(
      norm: 10_000,
      entries: [
        ("北京", -2.0, ["ㄅㄟˇ", "ㄐㄧㄥ"]),
        ("很", -2.0, ["ㄏㄣˇ"]),
      ]
    )
    var miner = CorpusMiner()
    var options = CorpusMiner.Options()
    options.minCount = 3
    options.minContextCount = 1
    options.margin = 0.02

    // 以「很 北京」之四階共現餵入 4 次；上下文「很」之詞頻約 10_000 × 10^-2 / e^(-1/3)。
    for _ in 0 ..< 4 { miner.ingest(words: ["很", "北京"]) }
    let result = miner.mine(index: index, options: options)
    // 「北京」以單讀音出現，應有一列候選；其 required 不超過語料次數。
    #expect(result.candidates.count == 1)
    #expect(result.candidates.first?.value == "北京")
    #expect(result.candidates.first?.corpusCount == 4)
  }

  @Test
  func weakCooccurrenceIsRejected() {
    let index = TxtMapUnigramIndex(
      norm: 10_000,
      entries: [
        ("北京", -2.0, ["ㄅㄟˇ", "ㄐㄧㄥ"]),
        ("很", -2.0, ["ㄏㄣˇ"]),
      ]
    )
    var miner = CorpusMiner()
    var options = CorpusMiner.Options()
    options.minCount = 1
    options.minContextCount = 1
    for _ in 0 ..< 1 { miner.ingest(words: ["很", "北京"]) }
    let result = miner.mine(index: index, options: options)
    #expect(result.candidates.isEmpty)
  }

  @Test
  func ambiguousReadingsAreRecorded() {
    let index = TxtMapUnigramIndex(
      norm: 10_000,
      entries: [
        ("谁", -2.0, ["ㄕㄟˊ"]),
        ("谁", -6.0, ["ㄕㄨㄟˊ"]),
        ("是", -2.0, ["ㄕˋ"]),
      ]
    )
    var miner = CorpusMiner()
    var options = CorpusMiner.Options()
    options.minCount = 2
    options.minContextCount = 1
    options.ambiguousReadings = .skip
    for _ in 0 ..< 20 { miner.ingest(words: ["是", "谁"]) }
    let result = miner.mine(index: index, options: options)
    #expect(result.candidates.isEmpty)
    #expect(result.ambiguous.first?.value == "谁")
  }
}

// MARK: - SHA256Tests

struct SHA256Tests {
  @Test
  func knownVectors() {
    #expect(SHA256.hexDigest(Data()) == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
    #expect(SHA256.hexDigest(Data("abc".utf8)) == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    #expect(
      SHA256.hexDigest(Data("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq".utf8))
        == "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1"
    )
  }

  @Test
  func longMessage() {
    let data = Data(repeating: 97, count: 1_000_000)
    #expect(SHA256.hexDigest(data) == "cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0")
  }
}
