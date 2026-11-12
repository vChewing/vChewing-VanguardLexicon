// (c) 2021 and onwards The vChewing Project (MulanPSL-2.0 License).
// ====================
// This code is released under the SPDX-License-Identifier: `MulanPSL-2.0`.

import Foundation
@testable import LibVanguardChewingData
import Testing

@Test
func testCollectorInitialization() async throws {
  let actorTested = try VCDataBuilder.Collector(isCHS: nil, cns: true)
  NSLog("Collector booting complete with all files collected.")
  let norm = await actorTested.norm
  NSLog("Star propagating weights using norm: \(norm)")
  let startDate = Date.now
  await actorTested.propagateWeights()
  let secondsDelta = Date.now.timeIntervalSince1970 - startDate.timeIntervalSince1970
  NSLog("Weight propagation complete. Time costed as seconds: \(secondsDelta)")
  print(await actorTested.unigramsCHS.values.map(\.values.count).reduce(0, +))
  print(await actorTested.unigramsCHT.values.map(\.values.count).reduce(0, +))
  print(await actorTested.reverseLookupTable.count)
  print(await actorTested.reverseLookupTable4NonKanji.count)
  print(await actorTested.tableKanjiCNS.values.map(\.count).reduce(0, +))
  print(await actorTested.reverseLookupTable4CNS.count)
}

@Test
func testCollectorSanityCheckCHS() async throws {
  let actorTested = try VCDataBuilder.Collector(isCHS: true)
  NSLog("Collector booting complete with all files collected.")
  let norm = await actorTested.norm
  NSLog("Star propagating weights using norm: \(norm)")
  let startDate = Date.now
  await actorTested.propagateWeights()
  let secondsDelta = Date.now.timeIntervalSince1970 - startDate.timeIntervalSince1970
  NSLog("Weight propagation complete. Time costed as seconds: \(secondsDelta)")
  print(await actorTested.unigramsCHS.values.map(\.values.count).reduce(0, +))
  try await actorTested.healthCheckPerMode(isCHS: true).forEach { print($0) }
}

@Test
func testCollectorSanityCheckCHT() async throws {
  let actorTested = try VCDataBuilder.Collector(isCHS: false)
  NSLog("Collector booting complete with all files collected.")
  let norm = await actorTested.norm
  NSLog("Star propagating weights using norm: \(norm)")
  let startDate = Date.now
  await actorTested.propagateWeights()
  let secondsDelta = Date.now.timeIntervalSince1970 - startDate.timeIntervalSince1970
  NSLog("Weight propagation complete. Time costed as seconds: \(secondsDelta)")
  print(await actorTested.unigramsCHT.values.map(\.values.count).reduce(0, +))
  try await actorTested.healthCheckPerMode(isCHS: false).forEach { print($0) }
}

@Test
func testTrie() async throws {
  let builder = try await VCDataBuilder.VanguardTextMapDataBuilder(isCHS: nil)
  let matchedA4 = builder?.mutexTrie4Typing.value.nodes.values.first {
    $0.readingKey == "a4"
  }
  #expect(matchedA4 != nil)
  let matched = builder?.mutexTrie4Typing.value.nodes.values.first {
    $0.readingKey == "diE2"
  }
  #expect(matched != nil)
}

@Test
func testTextMapBuilderEmitsTypingFileOnly() async throws {
  let builder = try #require(await VCDataBuilder.VanguardTextMapDataBuilder(isCHS: nil))
  let iterator = try await builder.getIteratorForLexiconAssemblyTask()

  var fileNames = [String]()
  for try await chunk in iterator {
    fileNames.append(chunk.fileName)
  }

  #expect(fileNames == ["VanguardFactoryDict4Typing.txtMap"])
}

// MARK: - NgramRecordsTests

@Suite("n-gram：前驗詞庫解析")
struct NgramRecordsTests {
  // MARK: Internal

  static let norm: Double = 374_388_831.9686408

  @Test("繁體語系的 trigram 會連同完整前文詞頻一併讀入")
  func loadsChtRecords() throws {
    let records = try VCDataBuilder.Unigram.prepareRawNgramRecords(
      isCHS: false,
      norm: Self.norm
    )
    #expect(!records.isEmpty)

    let trigram = try #require(records.first { $0.value == "的話" && $0.context == ["再", "這樣"] })
    #expect(trigram.readings == ["ㄉㄜ˙", "ㄏㄨㄚˋ"])
    #expect(trigram.count == 1)
    #expect(trigram.contextCount == 1_000)
    #expect(trigram.denominatorSource == .fullContext)
    #expect(trigram.isCHS == false)
    #expect(trigram.score < 0)
    #expect(abs(trigram.score - Self.weight(count: 1, denominator: 1_000, value: "的話")) < 0.001)

    // bigram 無第 5 欄時沿用 count(前一個詞)（legacy）。
    let legacyRecords = try VCDataBuilder.Unigram.parseNgramLines(
      "館 249 ㄍㄨㄢˇ 書",
      isCHS: false,
      norm: Self.norm,
      counts: ["書": 5_602]
    )
    let bigram = try #require(legacyRecords.first)
    #expect(bigram.count == 249)
    #expect(bigram.contextCount == 5_602)
    #expect(bigram.denominatorSource == .legacyUnigramCount)
    #expect(abs(bigram.score - Self.weight(count: 249, denominator: 5_602, value: "館")) < 0.001)
  }

  @Test("trigram 以完整前文詞頻為分母，bigram 仍以緊鄰前詞為分母")
  func conditionalScoreUsesContextCount() throws {
    let records = try VCDataBuilder.Unigram.prepareRawNgramRecords(
      isCHS: false,
      norm: Self.norm
    )
    let trigram = try #require(records.first { $0.value == "的話" && $0.context == ["再", "這樣"] })
    // 分母取自第 5 欄（1000），不是 count(再)。
    #expect(trigram.denominatorSource == .fullContext)
    #expect(trigram.contextCount == 1_000)
    #expect(abs(trigram.score - Self.weight(count: 1, denominator: 1_000, value: "的話")) < 0.001)

    // bigram 無第 5 欄時沿用 count(前一個詞)（legacy），不得混入 trigram 的分母。
    let legacy = try VCDataBuilder.Unigram.parseNgramLines(
      "再 5 ㄗㄞˋ 要",
      isCHS: false,
      norm: Self.norm,
      counts: ["要": 6_528]
    )
    let bigram = try #require(legacy.first)
    #expect(bigram.denominatorSource == .legacyUnigramCount)
    #expect(abs(bigram.score - Self.weight(count: 5, denominator: 6_528, value: "再")) < 0.001)

    // 取不到前驗詞頻時，才退回以 `_NORM` 折算（僅 bigram 允許）。
    let fallbackRecords = try VCDataBuilder.Unigram.parseNgramLines(
      "再 5 ㄗㄞˋ 要",
      isCHS: false,
      norm: Self.norm,
      counts: [:]
    )
    let fallback = try #require(fallbackRecords.first)
    #expect(fallback.denominatorSource == .normalizedFallback)
    #expect(abs(fallback.score - Self.weight(count: 5, denominator: Self.norm, value: "再")) < 0.001)
  }

  @Test("欄內含空白（讀音未以 - 連接）的列會報錯，不得靜默略過")
  func rejectsInnerSpaces() {
    /// 舊制以空格分隔欄內的讀音；新制要求讀音以 `-` 連接，否則欄數會爆開。
    let pasted = "的話 1 ㄉㄜ˙ ㄏㄨㄚˋ 再 這樣 1000"
    #expect(throws: VCDataBuilder.Exception.self) {
      try VCDataBuilder.Unigram.parseNgramLines(
        pasted,
        isCHS: false,
        norm: Self.norm,
        counts: [:]
      )
    }
  }

  @Test("次數欄非整數時會報錯")
  func rejectsNonIntegerCount() {
    #expect(throws: VCDataBuilder.Exception.self) {
      try VCDataBuilder.Unigram.parseNgramLines(
        "再 五 ㄗㄞˋ 要",
        isCHS: false,
        norm: Self.norm,
        counts: [:]
      )
    }
  }

  @Test("非詞類之列缺讀音時會報錯")
  func rejectsMissingReadings() {
    #expect(throws: VCDataBuilder.Exception.self) {
      try VCDataBuilder.Unigram.parseNgramLines(
        "再 5 - 要",
        isCHS: false,
        norm: Self.norm,
        counts: [:]
      )
    }
  }

  @Test("兩語系一併讀取時，各自的 trigram 條目並存")
  func loadsBothLocales() throws {
    let records = try VCDataBuilder.Unigram.prepareRawNgramRecords(isCHS: nil, norm: Self.norm)
    #expect(records.contains { $0.value == "的話" && $0.context == ["再", "這樣"] && !$0.isCHS })
    #expect(records.contains { $0.value == "的话" && $0.context == ["再", "这样"] && $0.isCHS })
    // 列數自資料導出：合併讀取恰為兩軌之和，不硬寫運送中的列數。
    let cht = try VCDataBuilder.Unigram.prepareRawNgramRecords(isCHS: false, norm: Self.norm)
    let chs = try VCDataBuilder.Unigram.prepareRawNgramRecords(isCHS: true, norm: Self.norm)
    #expect(records.count == cht.count + chs.count)
    // 缺口列在兩軌皆在（`[在, *]`）。
    for isCHS in [false, true] {
      #expect(records.contains { $0.value == "的" && $0.context == ["在", "*"] && $0.isCHS == isCHS })
    }
  }

  @Test("n-gram 條目會進到組句用的 Trie")
  func ngramsReachTypingTrie() async throws {
    let builder = try #require(await VCDataBuilder.VanguardTextMapDataBuilder(isCHS: nil))
    let nodes = builder.mutexTrie4Typing.value.nodes.values
    #expect(nodes.contains { $0.entries.contains { $0.context == ["顆"] } })
    #expect(nodes.contains { $0.entries.contains { $0.context == ["再"] } })
  }

  @Test("詞類模板：詞值欄與前驗詞鏈欄都會展開成逐條成員")
  func classTemplateExpands() throws {
    let raw = """
    <PLACE_NOUN> 120 - 在
    在 120 ㄗㄞˋ <PLACE_NOUN>
    """
    let classes = ["<PLACE_NOUN>": ["這裡", "那裡"]]
    let readings = [
      "這裡": ["ㄓㄜˋ", "ㄌㄧˇ"],
      "那裡": ["ㄋㄚˋ", "ㄌㄧˇ"],
      "在": ["ㄗㄞˋ"],
    ]
    let records = try VCDataBuilder.Unigram.parseNgramLines(
      raw,
      isCHS: false,
      norm: Self.norm,
      counts: ["在": 6_528],
      classTable: classes,
      readings: readings
    )
    // 兩條模板 × 兩名成員 ⇒ 四條 n-gram。
    #expect(records.count == 4)
    let here = try #require(records.first { $0.value == "這裡" && $0.context == ["在"] })
    #expect(here.readings == ["ㄓㄜˋ", "ㄌㄧˇ"])
    // 詞值為類名時，讀音取自 `readings`；分母取自前驗詞（在）的詞頻。
    // 期望值一律由產製端 `weighten` 給出：語料側權重之規格（P324）係
    // `log10(e^(len/3−1) × count / 分母)`，但常數不該在測試裡另立一份——
    // POM 側才是野獸常數曲線（`kWeightMultiplier`），兩者不可混用。
    let probe = VCDataBuilder.Unigram(
      key: "ㄓㄜˋ-ㄌㄧˇ",
      value: "這裡",
      score: 0,
      count: 120,
      category: .custom
    )
    probe.weighten(norm: 6_528)
    #expect(abs(here.score - probe.score) < 0.001)
    let zai = try #require(records.first { $0.value == "在" && $0.context == ["這裡"] })
    #expect(zai.readings == ["ㄗㄞˋ"])
  }

  @Test("詞類成員查無讀音時，該成員略過而不臆造讀音")
  func classMemberWithoutReadingsIsSkipped() throws {
    let records = try VCDataBuilder.Unigram.parseNgramLines(
      "<PLACE_NOUN> 9 - 在",
      isCHS: false,
      norm: Self.norm,
      counts: [:],
      classTable: ["<PLACE_NOUN>": ["這裡", "查無此詞"]],
      readings: ["這裡": ["ㄓㄜˋ", "ㄌㄧˇ"]]
    )
    #expect(records.map(\.value) == ["這裡"])
  }

  @Test("詞類清單可自資源檔讀取")
  func loadsShippedClassTables() throws {
    // 類名（token）繁簡共用，故兩檔查的是同一組鍵。
    let cht = try VCDataBuilder.Unigram.loadClassTable(isCHS: false)
    #expect(cht["<PLACE_NOUN>"]?.contains("這裡") == true)
    #expect(cht["<OBJECTIVE_VERB>"]?.contains("說") == true)
    #expect(cht["<SELF_VERB>"]?.contains("來") == true)
    let chs = try VCDataBuilder.Unigram.loadClassTable(isCHS: true)
    #expect(chs["<PLACE_NOUN>"]?.contains("这里") == true)
    #expect(chs["<OBJECTIVE_VERB>"]?.contains("说") == true)
    #expect(chs["<SELF_VERB>"]?.contains("来") == true)
  }

  // MARK: Private

  /// 依產製端同一條公式折算權重，避免測試自己另立一份常數。
  private static func weight(count: Int, denominator: Double, value: String) -> Double {
    let probe = VCDataBuilder.Unigram(
      key: "probe",
      value: value,
      score: 0,
      count: count,
      category: .custom
    )
    probe.weighten(norm: denominator)
    return probe.score
  }
}

// MARK: - VanguardTextMapBuilderContextualTests

@Suite("TextMap 產製：C／D 與分段")
struct VanguardTextMapBuilderContextualTests {
  // MARK: Internal

  @Test("同值同語系才組 D，且 17 筆拆成 15＋2")
  func buildsGroupedContextualLines() async throws {
    let builder = try #require(await VCDataBuilder.VanguardTextMapDataBuilder(isCHS: nil))
    let trie = builder.mutexTrie4Typing.value

    func render() async throws -> String {
      let iterator = try await builder.getIteratorForLexiconAssemblyTask()
      var data = Data()
      for try await chunk in iterator { data.append(chunk.data) }
      return try #require(String(data: data, encoding: .utf8))
    }

    trie.clearAllContents()
    trie.insert(
      entry: .init(value: "再", typeID: .init(rawValue: 6), probability: -3.405, context: ["要"]),
      readingsEncrypted: ["ㄗㄞˋ"]
    )
    trie.insert(
      entry: .init(value: "再", typeID: .init(rawValue: 6), probability: -3.502, context: ["不", "要"]),
      readingsEncrypted: ["ㄗㄞˋ"]
    )
    trie.insert(
      entry: .init(value: "再", typeID: .init(rawValue: 5), probability: -2, context: ["要"]),
      readingsEncrypted: ["ㄗㄞˋ"]
    )
    trie.insert(
      entry: .init(value: "在", typeID: .init(rawValue: 6), probability: -4, context: ["要"]),
      readingsEncrypted: ["ㄗㄞˋ"]
    )
    trie.insert(
      entry: .init(value: "再", typeID: .init(rawValue: 6), probability: -1, context: ["呢"]),
      readingsEncrypted: ["ㄗㄞˋ"]
    )
    trie.insert(
      entry: .init(value: "再", typeID: .init(rawValue: 6), probability: -7, context: ["要"]),
      readingsEncrypted: ["ㄧㄤˋ"]
    )
    trie.insert(
      entry: .init(value: "( ͒˃⌂˂ ͒)", typeID: .init(rawValue: 9), probability: -9),
      readingsEncrypted: ["ㄗㄞˋ"]
    )

    let textMap = try await render()
    #expect(textMap.contains("ENTRY_COUNT\t5\n"))
    #expect(textMap.contains("KEY_COUNT\t2\n"))
    #expect(valueLines(from: textMap).count == 5)
    #expect(valueLines(from: textMap, forKey: "ㄗㄞˋ") == [
      ">9\t(\\s͒˃⌂˂\\s͒)",
      "!再\t6\t-3.405\t要\t-3.502\t不|要\t-1\t呢",
      "再\t-2\t5\t要",
      "在\t-4\t6\t要",
    ])
    #expect(valueLines(from: textMap, forKey: "ㄧㄤˋ") == ["再\t-7\t6\t要"])

    trie.clearAllContents()
    for index in 0 ..< 17 {
      trie.insert(
        entry: .init(
          value: "再",
          typeID: .init(rawValue: 6),
          probability: -1,
          context: ["P\(index)"]
        ),
        readingsEncrypted: ["ㄗㄞˋ"]
      )
    }
    let chunked = try await render()
    let lines = valueLines(from: chunked)
    #expect(lines.map { ($0.components(separatedBy: "\t").count - 2) / 2 } == [15, 2])
    #expect(chunked.contains("ENTRY_COUNT\t2\n"))
    #expect(keyMapLine(from: chunked, forKey: "ㄗㄞˋ") == "ㄗㄞˋ\t0\t2")
  }

  // MARK: Private

  private func valueLines(from textMap: String) -> [String] {
    guard let values = textMap.range(of: "#PRAGMA:VANGUARD_HOMA_LEXICON_VALUES\n"),
          let keyMap = textMap.range(of: "#PRAGMA:VANGUARD_HOMA_LEXICON_KEY_LINE_MAP")
    else { return [] }
    return textMap[values.upperBound ..< keyMap.lowerBound].split(whereSeparator: \.isNewline).map(String.init)
  }

  private func valueLines(from textMap: String, forKey key: String) -> [String] {
    let lines = valueLines(from: textMap)
    guard let mapLine = keyMapLine(from: textMap, forKey: key) else { return [] }
    let fields = mapLine.components(separatedBy: "\t")
    guard fields.count == 3, let start = Int(fields[1]), let count = Int(fields[2]),
          start >= 0, start + count <= lines.count
    else { return [] }
    return Array(lines[start ..< (start + count)])
  }

  private func keyMapLine(from textMap: String, forKey key: String) -> String? {
    guard let keyMap = textMap.range(of: "#PRAGMA:VANGUARD_HOMA_LEXICON_KEY_LINE_MAP\n") else { return nil }
    return textMap[keyMap.upperBound...].split(whereSeparator: \.isNewline).map(String.init).first {
      $0.components(separatedBy: "\t").first == key
    }
  }
}

// MARK: - NgramInputValidationTests

@Suite("n-gram：v2.0 輸入限制")
struct NgramInputValidationTests {
  @Test("三層以上前文會報錯")
  func rejectsLongContext() {
    #expect(throws: VCDataBuilder.Exception.self) {
      try VCDataBuilder.Unigram.parseNgramLines(
        "再 5 ㄗㄞˋ 甲|乙|丙",
        isCHS: false,
        norm: 1_000,
        counts: [:]
      )
    }
  }

  @Test("ZWJ emoji 是合法詞值與前文成分")
  func acceptsZWJEmoji() throws {
    let emoji = "🙅‍♀️"
    let records = try VCDataBuilder.Unigram.parseNgramLines(
      "\(emoji) 5 ㄗㄞˋ 要|\(emoji) 7",
      isCHS: false,
      norm: 1_000,
      counts: [:]
    )
    #expect(records.count == 1)
    #expect(records.first?.value == emoji)
    #expect(records.first?.context == ["要", emoji])
  }

  @Test("缺口列：`*` 可佔 previous 一格，且須帶聚合分母")
  func parsesGapRow() throws {
    let records = try VCDataBuilder.Unigram.parseNgramLines(
      "的 120 ㄉㄜ˙ 在|* 500",
      isCHS: false,
      norm: 1_000,
      counts: [:]
    )
    #expect(records.count == 1)
    #expect(records.first?.context == ["在", VCDataBuilder.NgramRecord.wildcardContextToken])
    #expect(records.first?.contextCount == 500)
    #expect(records.first?.denominatorSource == .fullContext)
  }

  @Test("缺口列：`*` 單獨成鏈會報錯")
  func rejectsBareWildcardContext() {
    #expect(throws: VCDataBuilder.Exception.self) {
      try VCDataBuilder.Unigram.parseNgramLines(
        "的 120 ㄉㄜ˙ * 500",
        isCHS: false,
        norm: 1_000,
        counts: [:]
      )
    }
  }

  @Test("缺口列：`*` 佔 anterior 一格會報錯")
  func rejectsWildcardInAnteriorSlot() {
    #expect(throws: VCDataBuilder.Exception.self) {
      try VCDataBuilder.Unigram.parseNgramLines(
        "的 120 ㄉㄜ˙ *|在 500",
        isCHS: false,
        norm: 1_000,
        counts: [:]
      )
    }
  }

  @Test("缺口列與同名 trigram 列不得並存")
  func rejectsGapRowCoexistingWithTrigram() {
    #expect(throws: VCDataBuilder.Exception.self) {
      try VCDataBuilder.Unigram.parseNgramLines(
        [
          "的 50 ㄉㄜ˙ 在|* 500",
          "的 80 ㄉㄜ˙ 在|這樣 500",
        ].joined(separator: "\n"),
        isCHS: false,
        norm: 1_000,
        counts: [:]
      )
    }
  }

  @Test("缺口列只與同一 anterior 的 trigram 衝突")
  func gapRowCoexistsWithUnrelatedTrigram() throws {
    let records = try VCDataBuilder.Unigram.parseNgramLines(
      [
        "的 50 ㄉㄜ˙ 在|* 500",
        "的 80 ㄉㄜ˙ 要|這樣 500",
      ].joined(separator: "\n"),
      isCHS: false,
      norm: 1_000,
      counts: [:]
    )
    #expect(records.count == 2)
  }

  @Test("詞值與前文中的控制字元會報錯")
  func rejectsControlCharacters() {
    for raw in ["再\u{1} 5 ㄗㄞˋ 要", "再 5 ㄗㄞˋ 要\u{7}"] {
      #expect(throws: VCDataBuilder.Exception.self) {
        try VCDataBuilder.Unigram.parseNgramLines(
          raw,
          isCHS: false,
          norm: 1_000,
          counts: [:]
        )
      }
    }
  }

  @Test("trigram 缺完整前文詞頻會報錯，bigram 則可沿用 legacy 分母")
  func rejectsTrigramWithoutContextCount() throws {
    // trigram 只寫得出 count(書) 時，不得以前一個詞的詞頻冒充分母。
    #expect(throws: VCDataBuilder.Exception.self) {
      try VCDataBuilder.Unigram.parseNgramLines(
        "館 249 ㄍㄨㄢˇ 圖|書",
        isCHS: false,
        norm: 1_000,
        counts: ["書": 651]
      )
    }
    // 第 5 欄寫成註解同樣不算數。
    #expect(throws: VCDataBuilder.Exception.self) {
      try VCDataBuilder.Unigram.parseNgramLines(
        "館 249 ㄍㄨㄢˇ 圖|書 #comment",
        isCHS: false,
        norm: 1_000,
        counts: [:]
      )
    }
    // bigram 沒有第 5 欄仍可解析。
    let bigramRecords = try VCDataBuilder.Unigram.parseNgramLines(
      "館 249 ㄍㄨㄢˇ 書",
      isCHS: false,
      norm: 1_000,
      counts: ["書": 651]
    )
    #expect(bigramRecords.count == 1)
  }

  @Test("完整前文詞頻欄非整數或非正數時會報錯")
  func rejectsInvalidContextCountColumn() {
    for raw in ["館 249 ㄍㄨㄢˇ 圖|書 abc", "館 249 ㄍㄨㄢˇ 圖|書 0"] {
      #expect(throws: VCDataBuilder.Exception.self) {
        try VCDataBuilder.Unigram.parseNgramLines(
          raw,
          isCHS: false,
          norm: 1_000,
          counts: ["書": 651]
        )
      }
    }
  }

  @Test("完整前文詞頻欄與詞類模板不可併用")
  func rejectsContextCountWithClassTemplate() {
    #expect(throws: VCDataBuilder.Exception.self) {
      try VCDataBuilder.Unigram.parseNgramLines(
        "館 249 ㄍㄨㄢˇ <PLACE_NOUN>|書 294",
        isCHS: false,
        norm: 1_000,
        counts: [:],
        classTable: ["<PLACE_NOUN>": ["圖"]]
      )
    }
  }
}
