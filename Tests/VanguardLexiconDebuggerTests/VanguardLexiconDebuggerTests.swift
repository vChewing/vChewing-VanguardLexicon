// (c) 2025 and onwards The vChewing Project (MulanPSL-2.0 License).
// ====================
// This code is released under the SPDX-License-Identifier: `MulanPSL-2.0`.

import Foundation
import Testing
@testable import VanguardLexiconDebugger
import Yukuaki

// MARK: - Fixture

private enum Fixture {
  static let simple = """
  VERSION 2.0
  TYPE TYPING
  READING_SEPARATOR -
  ENTRY_COUNT 3
  KEY_COUNT 2
  DEFAULT_PROB_9 -13
  #PRAGMA:VANGUARD_HOMA_LEXICON_VALUES
  @-3\t八|巴\t八|巴
  @-4.5\t八\t八
  _NORM\t1000\t2
  #PRAGMA:VANGUARD_HOMA_LEXICON_KEY_LINE_MAP
  ㄅㄚ\t0\t3
  ㄉㄧㄢˋ\t3\t0
  """

  static let escaped = """
  VERSION 2.0
  TYPE TYPING
  READING_SEPARATOR -
  KEY_COUNT 2
  DEFAULT_PROB_9 -13
  #PRAGMA:VANGUARD_HOMA_LEXICON_VALUES
  >9\t中\\s文|空
  >9\t甲\\|乙
  #PRAGMA:VANGUARD_HOMA_LEXICON_KEY_LINE_MAP
  ㄓㄨㄥ\t0\t1
  ㄐㄧㄚ\t1\t1
  """

  static let contextual = """
  VERSION 2.0
  TYPE TYPING
  READING_SEPARATOR -
  KEY_COUNT 1
  DEFAULT_PROB_9 -13
  #PRAGMA:VANGUARD_HOMA_LEXICON_VALUES
  @-3\t到\t到
  到\t-2.5\t6\t我
  #PRAGMA:VANGUARD_HOMA_LEXICON_KEY_LINE_MAP
  ㄉㄠˋ\t0\t2
  """

  /// trigram 測試用：型別 C 的第 4 欄是 escaped-pipe 編碼的前驗詞鏈（由舊至新）。
  static let trigram = """
  VERSION 2.0
  TYPE TYPING
  READING_SEPARATOR -
  KEY_COUNT 1
  DEFAULT_PROB_9 -13
  #PRAGMA:VANGUARD_HOMA_LEXICON_VALUES
  @-3	到	到
  到	-2.5	6	我
  到	-2.2	6	我|你
  #PRAGMA:VANGUARD_HOMA_LEXICON_KEY_LINE_MAP
  ㄉㄠˋ	0	3
  """

  /// 語系軌測試用：`@` 行分屬兩格、`>5`／`>6` 分屬兩語系。
  static let localized = """
  VERSION 2.0
  TYPE TYPING
  READING_SEPARATOR -
  KEY_COUNT 2
  DEFAULT_PROB_9 -13
  #PRAGMA:VANGUARD_HOMA_LEXICON_VALUES
  _NORM\t374388831.9686408\t2
  @-5.175\t干\t
  @-5.206\t\t幹
  >9\t干|幹
  @-4\t干戈\t
  #PRAGMA:VANGUARD_HOMA_LEXICON_KEY_LINE_MAP
  ㄍㄢˋ\t0\t4
  ㄍㄢˋ-ㄍㄜ\t4\t1
  """

  static func write(_ contents: String, name: String) throws -> URL {
    let url = URL(fileURLWithPath: NSTemporaryDirectory())
      .appendingPathComponent("YukuakiTests-\(name)-\(UUID().uuidString).txtMap")
    try contents.write(to: url, atomically: true, encoding: .utf8)
    return url
  }
}

// MARK: - DebuggerOptionsTests

@Suite("Debugger：參數解析")
struct DebuggerOptionsTests {
  @Test("基本參數")
  func parsesBasicArguments() throws {
    let options = try DebuggerOptions(arguments: [
      "--readingChain", "dian4-nao3", "--expected", "電腦", "--json", "--verbose", "--top", "5",
    ])
    #expect(options.readingChains == ["dian4-nao3"])
    #expect(options.expecteds == ["電腦"])
    #expect(options.wantsJSON)
    #expect(options.isVerbose)
    #expect(options.topPathCount == 5)
    #expect(options.usesPinyin)
  }

  @Test("等號形式與短旗標")
  func parsesInlineValues() throws {
    let options = try DebuggerOptions(arguments: [
      "--readingChain=ㄅㄚ-ㄅㄚ", "-e=八八", "-j", "-n", "2",
    ])
    #expect(options.readingChains == ["ㄅㄚ-ㄅㄚ"])
    #expect(options.expecteds == ["八八"])
    #expect(options.wantsJSON)
    #expect(options.topPathCount == 2)
    #expect(!options.usesPinyin)
  }

  @Test("可重複給定多個案例")
  func parsesRepeatedCases() throws {
    let options = try DebuggerOptions(arguments: [
      "-k", "bu2-yao4-zai4-zhe4-yang4", "-k", "bu2-yao4-zai4-zhe4-li3", "-e", "不要再這樣", "-e", "不要在這裡",
    ])
    #expect(options.readingChains == ["bu2-yao4-zai4-zhe4-yang4", "bu2-yao4-zai4-zhe4-li3"])
    #expect(options.expecteds == ["不要再這樣", "不要在這裡"])
  }

  @Test("未知參數會拋錯")
  func unknownArgumentThrows() {
    #expect(throws: DebuggerError.self) {
      try DebuggerOptions(arguments: ["--nonsense"])
    }
  }

  @Test("缺少參數值會拋錯")
  func missingValueThrows() {
    #expect(throws: DebuggerError.self) {
      try DebuggerOptions(arguments: ["--readingChain"])
    }
  }

  @Test("--separator 只接受單一字元")
  func separatorMustBeSingleCharacter() {
    #expect(throws: DebuggerError.self) {
      try DebuggerOptions(arguments: ["--separator", "ab"])
    }
  }

  @Test("--lang 認 BCP 47 標籤")
  func langAcceptsLanguageTags() throws {
    #expect(try DebuggerOptions(arguments: ["-k", "ㄅㄚ", "--lang", "zh-Hans"]).locale == .chs)
    #expect(try DebuggerOptions(arguments: ["-k", "ㄅㄚ", "--lang", "zh-Hant"]).locale == .cht)
    #expect(try DebuggerOptions(arguments: ["-k", "ㄅㄚ", "--lang", "ZH-hanT"]).locale == .cht)
  }

  @Test("--lang 拒收舊寫法")
  func langRejectsLegacyCodes() {
    #expect(throws: DebuggerError.self) {
      try DebuggerOptions(arguments: ["-k", "ㄅㄚ", "--lang", "cht"])
    }
  }

  @Test("--help 會要求顯示說明")
  func helpFlag() throws {
    let options = try DebuggerOptions(arguments: ["--help"])
    #expect(options.showsHelp)
    #expect(DebuggerOptions.usage.contains("--readingChain"))
    #expect(DebuggerOptions.usage.contains("--expected"))
  }
}

// MARK: - ReadingChainResolverTests

@Suite("Debugger：讀音鏈解析")
struct ReadingChainResolverTests {
  @Test("注音鏈直接切分")
  func bopomofoChain() throws {
    let resolved = try ReadingChainResolver.resolve("ㄉㄧㄢˋ-ㄋㄠˇ", separator: nil)
    #expect(resolved.chain == ["ㄉㄧㄢˋ", "ㄋㄠˇ"])
    #expect(resolved.notation == "bopomofo")
  }

  @Test("漢語拼音鏈會轉成注音")
  func pinyinChain() throws {
    let resolved = try ReadingChainResolver.resolve("dian4-nao3-ai4-hao4-zhe3", separator: nil)
    #expect(resolved.chain == ["ㄉㄧㄢˋ", "ㄋㄠˇ", "ㄞˋ", "ㄏㄠˋ", "ㄓㄜˇ"])
    #expect(resolved.notation == "hanyu-pinyin")
  }

  @Test("空字串會拋錯")
  func emptyChainThrows() {
    #expect(throws: DebuggerError.self) {
      try ReadingChainResolver.resolve("   ", separator: nil)
    }
  }

  @Test("拼音缺聲調數字會拋錯")
  func pinyinWithoutToneThrows() {
    #expect(throws: DebuggerError.self) {
      try ReadingChainResolver.resolve("dian-nao3", separator: nil)
    }
  }
}

// MARK: - VanguardTextMapReaderTests

@Suite("Debugger：txtMap 讀取")
struct VanguardTextMapReaderTests {
  @Test("讀取基本區段與詞條")
  func readsBasicSections() throws {
    let url = try Fixture.write(Fixture.simple, name: "simple")
    defer { try? FileManager.default.removeItem(at: url) }
    let reader = try VanguardTextMapReader(url: url)
    #expect(reader.readingSeparator == "-")
    #expect(reader.norm == 1_000)
    #expect(reader.keyCount == 2)
    #expect(!reader.hasContextualEntries)
    let grams = reader.grams(forKeys: ["ㄅㄚ"])
    #expect(grams.count == 3)
    #expect(grams.map(\.current) == ["八", "巴", "八"])
    #expect(grams.map(\.probability) == [-3, -3, -4.5])
    #expect(reader.hasGrams(forKeys: ["ㄅㄚ"]))
    #expect(!reader.hasGrams(forKeys: ["ㄅㄛ"]))
    #expect(reader.grams(forKeys: ["ㄅㄛ"]).isEmpty)
  }

  @Test("語系取捨：兩軌詞條都收，本軌排前")
  func localePreference() throws {
    let fixture = """
    VERSION\t2.0
    READING_SEPARATOR\t-
    #PRAGMA:VANGUARD_HOMA_LEXICON_VALUES
    @-3\t电|脑\t電|腦
    #PRAGMA:VANGUARD_HOMA_LEXICON_KEY_LINE_MAP
    ㄉㄧㄢˋ\t0\t1
    """
    let url = try Fixture.write(fixture, name: "locale")
    defer { try? FileManager.default.removeItem(at: url) }
    // 缺 `_NORM` 時無從計零頻次權重，外軌詞條沿用行機率，故只能驗「都在、本軌在前」。
    let cht = try VanguardTextMapReader(url: url)
    #expect(cht.grams(forKeys: ["ㄉㄧㄢˋ"]).map(\.current) == ["電", "腦", "电", "脑"])
    let chs = try VanguardTextMapReader(url: url, locale: .chs)
    #expect(chs.grams(forKeys: ["ㄉㄧㄢˋ"]).map(\.current) == ["电", "脑", "電", "腦"])
    let both = try VanguardTextMapReader(url: url, locale: .both)
    #expect(both.grams(forKeys: ["ㄉㄧㄢˋ"]).count == 4)
  }

  @Test("跳脫字元會被還原")
  func decodesEscapes() throws {
    let url = try Fixture.write(Fixture.escaped, name: "escaped")
    defer { try? FileManager.default.removeItem(at: url) }
    let reader = try VanguardTextMapReader(url: url)
    let spaced = reader.grams(forKeys: ["ㄓㄨㄥ"])
    #expect(spaced.count == 2)
    #expect(Set(spaced.map(\.current)) == ["中 文", "空"])
    #expect(spaced.allSatisfy { $0.probability == -13 })
    let piped = reader.grams(forKeys: ["ㄐㄧㄚ"])
    #expect(piped.map(\.current) == ["甲|乙"])
  }

  @Test("含前文的詞條會被標記，且 previous 會被解出")
  func detectsContextualEntries() throws {
    let url = try Fixture.write(Fixture.contextual, name: "contextual")
    defer { try? FileManager.default.removeItem(at: url) }
    let reader = try VanguardTextMapReader(url: url)
    #expect(reader.hasContextualEntries)
    let grams = reader.grams(forKeys: ["ㄉㄠˋ"])
    #expect(grams.count == 2)
    let bigram = try #require(grams.first { !$0.isUnigram })
    #expect(bigram.previous == "我")
    #expect(bigram.probability == -2.5)
  }

  @Test("型別 C 的前驗詞鏈可承載 trigram")
  func readsTrigramContext() throws {
    let url = try Fixture.write(Fixture.trigram, name: "trigram")
    defer { try? FileManager.default.removeItem(at: url) }
    let reader = try VanguardTextMapReader(url: url)
    let grams = reader.grams(forKeys: ["ㄉㄠˋ"])
    #expect(grams.count == 3)
    let bigram = try #require(grams.first { $0.isBigram })
    #expect(bigram.previous == "我")
    #expect(bigram.anterior == nil)
    let trigram = try #require(grams.first { $0.isTrigram })
    #expect(trigram.previous == "你")
    #expect(trigram.anterior == "我")
    #expect(trigram.probability == -2.2)
  }

  @Test("前文詞條會改變組句：在／再 由前文「要」決定")
  func bigramFlipsAssembly() throws {
    let fixture = """
    VERSION 2.0
    TYPE TYPING
    READING_SEPARATOR -
    KEY_COUNT 3
    #PRAGMA:VANGUARD_HOMA_LEXICON_VALUES
    @-5.128\t不\t不
    @-5.048\t要\t要
    @-5.009\t在\t在
    再\t-3.405\t6\t要
    #PRAGMA:VANGUARD_HOMA_LEXICON_KEY_LINE_MAP
    ㄅㄨˋ\t0\t1
    ㄧㄠˋ\t1\t1
    ㄗㄞˋ\t2\t2
    """
    let url = try Fixture.write(fixture, name: "zai")
    defer { try? FileManager.default.removeItem(at: url) }
    let reader = try VanguardTextMapReader(url: url)
    let assembler = Yukuaki.Assembler(
      gramQuerier: { reader.grams(forKeys: $0.representativeKeys) },
      gramAvailabilityChecker: { reader.hasGrams(forKeys: $0) },
      config: Yukuaki.Config(maxSegLength: 6)
    )
    try assembler.insertKeys(["ㄅㄨˋ", "ㄧㄠˋ", "ㄗㄞˋ"].map { Yukuaki.PossibleKey.singleKey($0) })
    let outcome = try #require(assembler.assembleWithScore())
    #expect(outcome.path.joinedSentence == "不要再")
    let contextual = try #require(outcome.path.first { $0.value == "再" })
    #expect(contextual.gram.previous == "要")
  }

  @Test("移除前文詞條後，同一條讀音鏈改選「在」")
  func withoutContextTheUnigramWins() throws {
    let fixture = """
    VERSION 2.0
    TYPE TYPING
    READING_SEPARATOR -
    KEY_COUNT 3
    #PRAGMA:VANGUARD_HOMA_LEXICON_VALUES
    @-5.128\t不\t不
    @-5.048\t要\t要
    @-5.009\t在\t在
    #PRAGMA:VANGUARD_HOMA_LEXICON_KEY_LINE_MAP
    ㄅㄨˋ\t0\t1
    ㄧㄠˋ\t1\t1
    ㄗㄞˋ\t2\t1
    """
    let url = try Fixture.write(fixture, name: "zai-plain")
    defer { try? FileManager.default.removeItem(at: url) }
    let reader = try VanguardTextMapReader(url: url)
    let assembler = Yukuaki.Assembler(
      gramQuerier: { reader.grams(forKeys: $0.representativeKeys) },
      gramAvailabilityChecker: { reader.hasGrams(forKeys: $0) },
      config: Yukuaki.Config(maxSegLength: 6)
    )
    try assembler.insertKeys(["ㄅㄨˋ", "ㄧㄠˋ", "ㄗㄞˋ"].map { Yukuaki.PossibleKey.singleKey($0) })
    let outcome = try #require(assembler.assembleWithScore())
    #expect(outcome.path.joinedSentence == "不要在")
  }

  @Test("缺少區段標記時拋錯")
  func malformedFileThrows() throws {
    let url = try Fixture.write("VERSION 1.1\nKEY_COUNT 0\n", name: "malformed")
    defer { try? FileManager.default.removeItem(at: url) }
    #expect(throws: DebuggerError.self) {
      try VanguardTextMapReader(url: url)
    }
  }
}

// MARK: - TextMapLocatorTests

@Suite("Debugger：詞庫定位")
struct TextMapLocatorTests {
  @Test("明確指定的路徑不存在時拋錯")
  func explicitMissingPathThrows() {
    #expect(throws: DebuggerError.self) {
      try TextMapLocator.locate(override: "/nonexistent/path/VanguardFactoryDict4Typing.txtMap")
    }
  }

  @Test("明確指定的路徑存在時直接採用")
  func explicitExistingPathIsUsed() throws {
    let url = try Fixture.write(Fixture.simple, name: "locator")
    defer { try? FileManager.default.removeItem(at: url) }
    let located = try TextMapLocator.locate(override: url.path)
    #expect(located.path == url.standardizedFileURL.path)
  }
}

// MARK: - DebuggerRunnerTests

@Suite("Debugger：離開碼語意")
struct DebuggerRunnerTests {
  // MARK: Internal

  @Test("未給 --expected 時恆為成功")
  func withoutExpectedIsSuccess() throws {
    #expect(try Self.run(["-k", "ㄉㄧㄢˋ-ㄋㄠˇ"]) == true)
  }

  @Test("期望結果命中也算成功")
  func matchedExpectationIsSuccess() throws {
    #expect(try Self.run(["-k", "ㄉㄧㄢˋ-ㄋㄠˇ", "-e", "電腦"]) == true)
  }

  @Test("期望結果未命中為失敗")
  func mismatchedExpectationFails() throws {
    #expect(try Self.run(["-k", "ㄉㄧㄢˋ-ㄋㄠˇ", "-e", "惦腦"]) == false)
  }

  // MARK: Private

  private static let competing = """
  VERSION 2.0
  TYPE TYPING
  READING_SEPARATOR -
  ENTRY_COUNT 3
  KEY_COUNT 2
  DEFAULT_PROB_9 -13
  #PRAGMA:VANGUARD_HOMA_LEXICON_VALUES
  @-3.3\t電\t電
  @-3.4\t惦\t惦
  @-1\t腦\t腦
  _NORM\t1000\t2
  #PRAGMA:VANGUARD_HOMA_LEXICON_KEY_LINE_MAP
  ㄉㄧㄢˋ\t0\t2
  ㄋㄠˇ\t2\t1
  """

  private static func run(_ arguments: [String]) throws -> Bool {
    let url = try Fixture.write(competing, name: "exit-code")
    let options = try DebuggerOptions(arguments: arguments + ["-d", url.path])
    let reader = try VanguardTextMapReader(url: url, locale: .cht)
    return try DebuggerRunner(options: options, reader: reader).run()
  }
}

// MARK: - VanguardTextMapReaderLocaleTests

@Suite("詞庫：語系軌")
struct VanguardTextMapReaderLocaleTests {
  // MARK: Internal

  @Test("繁體軌：另一軌的漢字仍可選，只是以零頻次權重落後")
  func chtLaneKeepsSimplifiedWithPenalty() throws {
    let reader = try makeReader(.cht)
    let grams = reader.grams(forKeys: ["ㄍㄢˋ"])
    #expect(Set(grams.map(\.current)) == ["幹", "干"])
    let best = grams.max { $0.probability < $1.probability }
    #expect(best?.current == "幹")
    #expect(reader.crossLaneValueCount == 1)
    // 單字零頻次權重＝log10(e^(-2/3) × 0.25 / norm)，與真詞庫的 -9.465 同式。
    #expect(abs((grams.first { $0.current == "干" }?.probability ?? 0) + 9.465) < 0.01)
  }

  @Test("簡體軌：另一軌的漢字仍可選，只是以零頻次權重落後")
  func chsLaneKeepsTraditionalWithPenalty() throws {
    let reader = try makeReader(.chs)
    let grams = reader.grams(forKeys: ["ㄍㄢˋ"])
    #expect(Set(grams.map(\.current)) == ["幹", "干"])
    let best = grams.max { $0.probability < $1.probability }
    #expect(best?.current == "干")
    #expect(reader.crossLaneValueCount == 1)
  }

  @Test("只在對面語系軌出現的詞條，按字數計零頻次權重")
  func crossLaneWordWeightUsesCharacterCount() throws {
    let reader = try makeReader(.cht)
    let grams = reader.grams(forKeys: ["ㄍㄢˋ-ㄍㄜ"])
    #expect(grams.map(\.current) == ["干戈"])
    // 兩字：log10(e^(-1/3) × 0.25 / norm) ≈ -9.321，比單字罰得輕。
    let probability = try #require(grams.first?.probability)
    #expect(abs(probability + 9.321) < 0.01)
    #expect(reader.crossLaneValueCount == 1)
  }

  // MARK: Private

  private func makeReader(_ locale: VanguardTextMapReader.Locale) throws -> VanguardTextMapReader {
    let url = try Fixture.write(Fixture.localized, name: "locale-\(locale.rawValue)")
    return try VanguardTextMapReader(url: url, locale: locale)
  }
}

// MARK: - VerifyRunnerTests

struct VerifyRunnerTests {
  private func temporaryFile(_ content: String) throws -> URL {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("verify-\(UUID().uuidString).tsv")
    try content.write(to: url, atomically: true, encoding: .utf8)
    return url
  }

  @Test
  func parsesBacklogRows() throws {
    let url = try temporaryFile("""
    再\t5\tㄗㄞˋ\t不 要
    # 註解不算
    大行星\t5557\tㄉㄚˋ ㄒㄧㄥˊ ㄒㄧㄥ\t八

    """)
    let rows = try VerifyRunner.loadBacklog(url)
    #expect(rows.count == 2)
    #expect(rows[0].value == "再")
    #expect(rows[0].context == ["不", "要"])
    #expect(rows[0].count == 5)
    #expect(rows[1].reading == ["ㄉㄚˋ", "ㄒㄧㄥˊ", "ㄒㄧㄥ"])
    try? FileManager.default.removeItem(at: url)
  }

  @Test
  func analyticProbabilityMatchesCollector() {
    // 與 P325 之測試值對齊：`再|要` 於 6528 個「要」的語料中出現 5 次 → −3.405。
    let value = VerifyRunner.analyticProbability(
      reading: ["ㄗㄞˋ"],
      countText: "5",
      denominator: 6528
    )
    #expect(abs(value - log10(5.0 / 6528.0)) < 1e-9)
  }
}
