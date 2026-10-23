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
  static let norm: Double = 374_388_831.9686408

  @Test("繁體語系的 bigram 與 trigram 都會被讀入")
  func loadsChtRecords() throws {
    let records = try VCDataBuilder.Unigram.prepareRawNgramRecords(isCHS: false, norm: Self.norm)
    #expect(!records.isEmpty)

    let bigram = try #require(records.first { $0.value == "再" && $0.context.count == 1 })
    #expect(bigram.readings == ["ㄗㄞˋ"])
    #expect(bigram.context == ["要"])
    #expect(bigram.count == 5)
    #expect(bigram.isCHS == false)
    // 權重折算後應為負值（log10 權重）。
    #expect(bigram.score < 0)

    let trigram = try #require(records.first { $0.value == "再" && $0.context.count == 2 })
    #expect(trigram.context == ["不", "要"])
    #expect(trigram.count == 4)
  }

  @Test("帶前驗詞鏈的條目以「前驗詞的詞頻」為分母算條件機率")
  func conditionalScoreUsesContextCount() throws {
    let records = try VCDataBuilder.Unigram.prepareRawNgramRecords(
      isCHS: false,
      norm: Self.norm,
      contextCounts: [false: ["要": 6_528]]
    )
    let bigram = try #require(records.first { $0.value == "再" && $0.context == ["要"] })
    // log10(e^(1/3 - 1) × 5 / 6528)
    #expect(abs(bigram.score - -3.405) < 0.001)
    // 取不到前驗詞頻次時，退回以 `_NORM` 折算的無條件機率。
    let unconditional = try VCDataBuilder.Unigram.prepareRawNgramRecords(
      isCHS: false,
      norm: Self.norm
    )
    let fallback = try #require(unconditional.first { $0.value == "再" && $0.context == ["要"] })
    #expect(abs(fallback.score - -8.164) < 0.001)
  }

  @Test("兩語系一併讀取時，同值不同語系的條目並存")
  func loadsBothLocales() throws {
    let records = try VCDataBuilder.Unigram.prepareRawNgramRecords(isCHS: nil, norm: Self.norm)
    #expect(records.contains { $0.value == "再" && !$0.isCHS })
    #expect(records.contains { $0.value == "再" && $0.isCHS })
    #expect(records.count >= 4)
  }

  @Test("n-gram 條目會進到組句用的 Trie")
  func ngramsReachTypingTrie() async throws {
    let builder = try #require(await VCDataBuilder.VanguardTextMapDataBuilder(isCHS: nil))
    let nodes = builder.mutexTrie4Typing.value.nodes.values
    #expect(nodes.contains { $0.entries.contains { $0.context == ["要"] } })
    #expect(nodes.contains { $0.entries.contains { $0.context == ["不", "要"] } })
  }
}
