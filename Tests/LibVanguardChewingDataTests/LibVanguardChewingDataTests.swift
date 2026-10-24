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
    // 傳入與產製端同源的詞頻表（count(書) 取自 `char-kanji-core.txt` 的繁中欄）。
    let records = try VCDataBuilder.Unigram.prepareRawNgramRecords(
      isCHS: false,
      norm: Self.norm,
      contextCounts: [false: ["書": 5_602]]
    )
    #expect(!records.isEmpty)

    let library = try #require(records.first { $0.value == "館" && $0.context == ["圖", "書"] })
    #expect(library.readings == ["ㄍㄨㄢˇ"])
    #expect(library.count == 249)
    #expect(library.contextCount == 294)
    #expect(library.denominatorSource == .fullContext)
    #expect(library.isCHS == false)
    // 權重折算後應為負值（log10 權重）。
    #expect(library.score < 0)

    // 同一批證據的 bigram 列（前文只有「書」）仍走 legacy 分母：count(書)。
    let bigram = try #require(records.first { $0.value == "館" && $0.context == ["書"] })
    #expect(bigram.count == 249)
    // bigram 的「完整前文」就是那一個詞，故 contextCount 即 count(書)。
    #expect(bigram.contextCount == 5_602)
    #expect(bigram.denominatorSource == .legacyUnigramCount)
    // 兩列同源、只差鏈長；trigram 換上 count(圖,書)＝294 之後，
    // 分數由 bigram 的 −1.642 抬到 −0.362（δ＝log10(5602/294)＝1.280）。
    #expect(abs(library.score - Self.weight(count: 249, denominator: 294, value: "館")) < 0.001)
    #expect(abs(bigram.score - Self.weight(count: 249, denominator: 5_602, value: "館")) < 0.001)
    #expect(abs((library.score - bigram.score) - 1.280) < 0.001)
  }

  @Test("trigram 以完整前文詞頻為分母，bigram 仍以緊鄰前詞為分母")
  func conditionalScoreUsesContextCount() throws {
    let records = try VCDataBuilder.Unigram.prepareRawNgramRecords(
      isCHS: false,
      norm: Self.norm,
      contextCounts: [false: ["書": 651]]
    )
    let trigram = try #require(records.first { $0.value == "館" && $0.context == ["圖", "書"] })
    // 分母取自第 5 欄（294），不是 count(書)（651）。
    #expect(trigram.denominatorSource == .fullContext)
    #expect(abs(trigram.score - Self.weight(count: 249, denominator: 294, value: "館")) < 0.001)

    // bigram 無第 5 欄時沿用 count(前一個詞)（legacy），不得混入 trigram 的分母。
    let legacy = try VCDataBuilder.Unigram.parseNgramLines(
      "再\t5\tㄗㄞˋ\t要",
      isCHS: false,
      norm: Self.norm,
      counts: ["要": 6_528]
    )
    let bigram = try #require(legacy.first)
    #expect(bigram.denominatorSource == .legacyUnigramCount)
    #expect(abs(bigram.score - Self.weight(count: 5, denominator: 6_528, value: "再")) < 0.001)

    // 取不到前驗詞頻時，才退回以 `_NORM` 折算（僅 bigram 允許）。
    let fallbackRecords = try VCDataBuilder.Unigram.parseNgramLines(
      "再\t5\tㄗㄞˋ\t要",
      isCHS: false,
      norm: Self.norm,
      counts: [:]
    )
    let fallback = try #require(fallbackRecords.first)
    #expect(fallback.denominatorSource == .normalizedFallback)
    #expect(abs(fallback.score - Self.weight(count: 5, denominator: Self.norm, value: "再")) < 0.001)
  }

  @Test("兩語系一併讀取時，各自的 trigram 條目並存")
  func loadsBothLocales() throws {
    let records = try VCDataBuilder.Unigram.prepareRawNgramRecords(isCHS: nil, norm: Self.norm)
    #expect(records.contains { $0.value == "館" && $0.context == ["圖", "書"] && !$0.isCHS })
    #expect(records.contains { $0.value == "网" && $0.context == ["互", "联"] && $0.isCHS })
    // 兩語系各六列：館／馆 四列（案、檔 案、書、圖 書）、網／网 一列、碳 一列。
    #expect(records.count == 12)
  }

  @Test("n-gram 條目會進到組句用的 Trie")
  func ngramsReachTypingTrie() async throws {
    let builder = try #require(await VCDataBuilder.VanguardTextMapDataBuilder(isCHS: nil))
    let nodes = builder.mutexTrie4Typing.value.nodes.values
    #expect(nodes.contains { $0.entries.contains { $0.context == ["圖", "書"] } })
    #expect(nodes.contains { $0.entries.contains { $0.context == ["氧", "化"] } })
  }

  @Test("詞類模板：詞值欄與前驗詞鏈欄都會展開成逐條成員")
  func classTemplateExpands() throws {
    let raw = """
    <PLACE_NOUN>\t120\t-\t在
    在\t120\tㄗㄞˋ\t<PLACE_NOUN>
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
      "<PLACE_NOUN>\t9\t-\t在",
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
        "再\t5\tㄗㄞˋ\t甲 乙 丙",
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
      "\(emoji)\t5\tㄗㄞˋ\t要 \(emoji)\t7",
      isCHS: false,
      norm: 1_000,
      counts: [:]
    )
    #expect(records.count == 1)
    #expect(records.first?.value == emoji)
    #expect(records.first?.context == ["要", emoji])
  }

  @Test("詞值與前文中的控制字元會報錯")
  func rejectsControlCharacters() {
    for raw in ["再\u{1}\t5\tㄗㄞˋ\t要", "再\t5\tㄗㄞˋ\t要\u{7}"] {
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
        "館\t249\tㄍㄨㄢˇ\t圖 書",
        isCHS: false,
        norm: 1_000,
        counts: ["書": 651]
      )
    }
    // 第 5 欄寫成註解同樣不算數。
    #expect(throws: VCDataBuilder.Exception.self) {
      try VCDataBuilder.Unigram.parseNgramLines(
        "館\t249\tㄍㄨㄢˇ\t圖 書\t# lift=1.0",
        isCHS: false,
        norm: 1_000,
        counts: [:]
      )
    }
    // bigram 沒有第 5 欄仍可解析。
    let bigramRecords = try VCDataBuilder.Unigram.parseNgramLines(
      "館\t249\tㄍㄨㄢˇ\t書",
      isCHS: false,
      norm: 1_000,
      counts: ["書": 651]
    )
    #expect(bigramRecords.count == 1)
  }

  @Test("完整前文詞頻欄非整數或非正數時會報錯")
  func rejectsInvalidContextCountColumn() {
    for raw in ["館\t249\tㄍㄨㄢˇ\t圖 書\tabc", "館\t249\tㄍㄨㄢˇ\t圖 書\t0"] {
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
        "館\t249\tㄍㄨㄢˇ\t<PLACE_NOUN> 書\t294",
        isCHS: false,
        norm: 1_000,
        counts: [:],
        classTable: ["<PLACE_NOUN>": ["圖"]]
      )
    }
  }
}
