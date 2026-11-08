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
    let norm = 1_000.0
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
  // MARK: Internal

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

  // MARK: Private

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

    // 以「很 北京」之四階共現餵入 4 次；分母取自同批語料的 count(很)＝4。
    for _ in 0 ..< 4 { miner.ingest(words: ["很", "北京"]) }
    let result = miner.mine(index: index, options: options)
    // 「北京」以單讀音出現，應有一列候選；其 required 不超過語料次數。
    #expect(result.candidates.count == 1)
    #expect(result.candidates.first?.value == "北京")
    #expect(result.candidates.first?.corpusCount == 4)
    #expect(result.candidates.first?.contextCount == 4)
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
    // 分母取自同批語料：「很」有 100 次後繼，其中僅 1 次接「北京」。
    for _ in 0 ..< 99 { miner.ingest(words: ["很", "甲"]) }
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

// MARK: - TxtMapVersionAndTypeDTests

struct TxtMapVersionAndTypeDTests {
  // MARK: Internal

  @Test
  func typeDDoesNotEnterUnigramIndex() throws {
    let contents = """
    VERSION\t2.0
    READING_SEPARATOR\t-
    #PRAGMA:VANGUARD_HOMA_LEXICON_VALUES
    _NORM\t1000\t2
    北京\t-2\t1
    !北京\t1\t-1\t北\t-0.5\t京
    #PRAGMA:VANGUARD_HOMA_LEXICON_KEY_LINE_MAP
    _norm\t0\t1
    ㄅㄟˇ-ㄐㄧㄥ\t1\t2
    """
    let url = try write(contents)
    defer { try? FileManager.default.removeItem(at: url) }
    let index = try TxtMapUnigramIndex(url: url)
    #expect(index.valueCount == 1)
    #expect(index.probability(of: "北京") == -2)
  }

  @Test
  func versionMustBeExplicit20() throws {
    for version in [nil, "VERSION\t2.1"] {
      var lines = [String]()
      if let version { lines.append(version) }
      lines.append("READING_SEPARATOR\t-")
      lines.append("#PRAGMA:VANGUARD_HOMA_LEXICON_VALUES")
      lines.append("_NORM\t1000\t2")
      lines.append("#PRAGMA:VANGUARD_HOMA_LEXICON_KEY_LINE_MAP")
      let url = try write(lines.joined(separator: "\n"))
      defer { try? FileManager.default.removeItem(at: url) }
      #expect(throws: TxtMapUnigramIndexError.self) {
        try TxtMapUnigramIndex(url: url)
      }
    }
  }

  // MARK: Private

  private func write(_ contents: String) throws -> URL {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("txtmap-index-\(UUID().uuidString).txtMap")
    try contents.write(to: url, atomically: true, encoding: .utf8)
    return url
  }
}

// MARK: - CorpusMinerBacklogSafetyTests

struct CorpusMinerBacklogSafetyTests {
  // MARK: Internal

  @Test
  func renderedLineRejectsStructuralCharacters() {
    for candidate in [
      makeCandidate(value: "北\n京"),
      makeCandidate(value: "北\t京"),
      makeCandidate(context: ["很\n"]),
      makeCandidate(reading: ["ㄅㄟˇ\t"]),
    ] {
      #expect(candidate.renderedLine() == nil)
    }
    #expect(makeCandidate().renderedLine() != nil)
    #expect(makeCandidate(value: "北🙅‍♀️京").renderedLine() != nil)
  }

  @Test
  func miningRejectsControlCharactersBeforeBacklog() {
    for badValue in ["北\n京", "北\t京"] {
      let index = TxtMapUnigramIndex(
        norm: 10_000,
        entries: [(badValue, -2, ["ㄅㄟˇ"]), ("很", -2, ["ㄏㄣˇ"])]
      )
      var miner = CorpusMiner()
      var options = CorpusMiner.Options()
      options.minCount = 1
      options.minContextCount = 1
      options.margin = -100
      miner.ingest(words: ["很", badValue])
      #expect(miner.mine(index: index, options: options).candidates.isEmpty)
    }
  }

  // MARK: Private

  private func makeCandidate(
    value: String = "北京",
    context: [String] = ["很"],
    reading: [String] = ["ㄅㄟˇ", "ㄐㄧㄥ"]
  )
    -> CorpusMiner.Candidate {
    .init(
      context: context,
      value: value,
      reading: reading,
      corpusCount: 5,
      contextCount: 5,
      requiredCount: 5,
      lift: 1,
      lowerBound: 0.4,
      assumedReading: false
    )
  }
}

// MARK: - P332ReadingsAndEvidenceTests

struct P332ReadingsAndEvidenceTests {
  @Test
  func pseudoReadingsAreNotPronunciations() {
    // 詞庫的 key-line-map 段另有 `_alt_punctuation_*` 一類鍵位名（為符號鍵而設），
    // 若把它們算成讀音，`一`、`的` 這類常用字會被假的讀音撐破音字數。
    let index = TxtMapUnigramIndex(
      norm: 1_000,
      entries: [
        ("一", -2.0, ["ㄧ"]),
        ("一", -2.0, ["_alt_punctuation_1"]),
      ]
    )
    #expect(index.unigram("一")?.readings.count == 1)
    #expect(index.unigram("一")?.readings.first?.key == ["ㄧ"])
  }

  @Test
  func tiedTopProbabilityIsNotGuessed() {
    // 真詞庫對同一詞的各讀音寫入同一個機率（`和` 的 ㄏㄜˊ 與 ㄏㄢˋ 皆 -5.042），
    // 故 primary 若照樣取一條，等於憑檔案順序定讀音。
    let index = TxtMapUnigramIndex(
      norm: 10_000,
      entries: [
        ("和", -5.042, ["ㄏㄜˊ"]),
        ("和", -5.042, ["ㄏㄢˋ"]),
        ("很", -2.0, ["ㄏㄣˇ"]),
      ]
    )
    var miner = CorpusMiner()
    var options = CorpusMiner.Options()
    options.minCount = 1
    options.minContextCount = 1
    options.margin = -100
    options.ambiguousReadings = .primary
    miner.ingest(words: ["很", "和"])
    let result = miner.mine(index: index, options: options)
    #expect(result.candidates.isEmpty)
    #expect(result.ambiguous.first?.value == "和")
    #expect(result.ambiguous.first?.reason == "最高頻並列")
    #expect(result.ambiguous.first?.readings.count == 2)
  }

  @Test
  func distinctTopProbabilityStillResolves() {
    let index = TxtMapUnigramIndex(
      norm: 10_000,
      entries: [
        ("和", -5.042, ["ㄏㄜˊ"]),
        ("和", -4.0, ["ㄏㄢˋ"]),
        ("很", -2.0, ["ㄏㄣˇ"]),
      ]
    )
    var miner = CorpusMiner()
    var options = CorpusMiner.Options()
    options.minCount = 1
    options.minContextCount = 1
    options.margin = -100
    options.ambiguousReadings = .primary
    miner.ingest(words: ["很", "和"])
    let result = miner.mine(index: index, options: options)
    #expect(result.ambiguous.isEmpty)
    #expect(result.candidates.first?.reading == ["ㄏㄢˋ"])
    #expect(result.candidates.first?.assumedReading == true)
  }

  @Test
  func wilsonLowerBoundPenalisesSmallDenominators() {
    // 2/2 的原始比值是 1.0，但下界只有 0.342：兩次觀察撐不起「必接」的斷言。
    #expect(abs(CorpusMiner.wilsonLowerBound(successes: 2, trials: 2) - 0.342) < 0.005)
    #expect(abs(CorpusMiner.wilsonLowerBound(successes: 500, trials: 1_000) - 0.469) < 0.005)
    #expect(CorpusMiner.wilsonLowerBound(successes: 0, trials: 0) == 0)
  }

  @Test
  func minLowerBoundGatesCandidates() {
    let index = TxtMapUnigramIndex(
      norm: 10_000,
      entries: [("北京", -2.0, ["ㄅㄟˇ", "ㄐㄧㄥ"]), ("很", -2.0, ["ㄏㄣˇ"])]
    )
    var miner = CorpusMiner()
    var options = CorpusMiner.Options()
    options.minCount = 1
    options.minContextCount = 1
    options.margin = -100
    miner.ingest(words: ["很", "北京"])
    #expect(miner.mine(index: index, options: options).candidates.count == 1)
    options.minLowerBound = 0.5
    #expect(miner.mine(index: index, options: options).candidates.isEmpty)
  }

  @Test
  func renderedLineWritesTrueCorpusCount() {
    let candidate = CorpusMiner.Candidate(
      context: ["很"],
      value: "北京",
      reading: ["ㄅㄟˇ", "ㄐㄧㄥ"],
      corpusCount: 7,
      contextCount: 9,
      requiredCount: 5,
      lift: 1.2,
      lowerBound: 0.321,
      assumedReading: false
    )
    let fields = (candidate.renderedLine() ?? "").components(separatedBy: " ")
    #expect(fields[1] == "7")
    #expect(fields[5].contains("lb=0.321"))
  }

  @Test
  func maximumTokenLengthDefaultIsSix() {
    // 頂層 `let` 在本檔分派子命令之後才賦值，曾令預設值實際為 0、整份語料被切成單字。
    #expect(MiningDefaults.maximumTokenLength == 6)
  }
}
