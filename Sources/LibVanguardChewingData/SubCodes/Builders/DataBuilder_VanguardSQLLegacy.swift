// (c) 2021 and onwards The vChewing Project (BSD-3-Clause).
// ====================
// This code is released under the SPDX-License-Identifier: `BSD-3-Clause`.

import Foundation

// MARK: - VCDataBuilder.VanguardSQLLegacyDataBuilder

extension VCDataBuilder {
  public actor VanguardSQLLegacyDataBuilder: DataBuilderProtocol {
    // MARK: Lifecycle

    public init?(isCHS: Bool?) async throws {
      self.isCHS = nil
      // 這裡取 false，由應用程式針對不同的平台處理高萬字的相容性。
      self.data = try Collector(isCHS: isCHS, compatibleMode: false, cns: true)
      await data.propagateWeights()
      try await printHealthCheckReports()
    }

    // MARK: Public

    nonisolated public let isCHS: Bool?

    public let data: Collector
  }
}

extension VCDataBuilder.VanguardSQLLegacyDataBuilder {
  nonisolated public var langSuffix: String { "" }

  nonisolated public var subFolderNameComponents: [String] {
    ["Intermediate", "vanguardSQL-Legacy"]
  }

  nonisolated public var subFolderNameComponentsAftermath: [String] {
    ["Release", "vanguardSQL-Legacy"]
  }

  public func getIteratorForLexiconAssemblyTask() async throws -> VCDataBuilder.ChunkIterator {
    let chunkSize = 512 * 1_024
    let fileName = "vanguardLegacy.sql"
    return AsyncThrowingStream { continuation in
      Task { [self] in
        do {
          try await assembleSQLFile(chunkSize: chunkSize) { data, isFinal in
            continuation.yield(.init(fileName: fileName, data: data, isLastChunk: isFinal))
          }
          continuation.finish()
        } catch {
          continuation.finish(throwing: error)
        }
      }
    }
  }

  // This method uses terminal commands to convert SQL file to SQLite file.
  public func performPostCompilation() async throws {
    try await runInTextBlockThrowable {
      NSLog(" - 通用: 已完成健康檢查與資料通盤準備，準備開始辭典檔案建置組裝。")
      NSLog(" - 通用: Vanguard Legacy SQLite 資料庫建置開始。")
      try await compileSQLite(
        fileNameStem: "vanguardLegacy",
        outputFileNameStem: "vChewingFactoryDatabase"
      )
      NSLog(" - 通用: Vanguard Legacy SQLite 資料庫建置完成。")
    }
  }
}

extension VCDataBuilder.VanguardSQLLegacyDataBuilder {
  func assembleSQLFile(
    chunkSize: Int = 512 * 1_024,
    emit: @escaping (_ chunk: Data, _ isFinal: Bool) async throws -> ()
  ) async throws {
    let effectiveChunkSize = max(64 * 1_024, chunkSize)
    var buffer = Data()
    buffer.reserveCapacity(effectiveChunkSize)

    func flush(isFinal: Bool) async throws {
      guard !buffer.isEmpty else {
        if isFinal {
          try await emit(Data(), true)
        }
        return
      }
      let payload = buffer
      buffer.removeAll(keepingCapacity: true)
      try await emit(payload, isFinal)
    }

    func appendData(_ dataFragment: Data) async throws {
      guard !dataFragment.isEmpty else { return }
      buffer.append(dataFragment)
      if buffer.count >= effectiveChunkSize {
        try await flush(isFinal: false)
      }
    }

    func append(_ text: String) async throws {
      try await appendData(Data(text.utf8))
    }

    // theDataMISC 這個欄目其實並沒有被使用到。但為了相容性所以繼續保留。
    let sqlHeader = #"""
    PRAGMA synchronous=OFF;
    PRAGMA journal_mode=OFF;
    PRAGMA foreign_keys=OFF;
    BEGIN TRANSACTION;
    DROP TABLE IF EXISTS DATA_MAIN;
    DROP TABLE IF EXISTS DATA_REV;
    CREATE TABLE DATA_MAIN (
      theKey TEXT NOT NULL,
      theDataCHS TEXT,
      theDataCHT TEXT,
      theDataCNS TEXT,
      theDataMISC TEXT,
      theDataSYMB TEXT,
      theDataCHEW TEXT,
      PRIMARY KEY (theKey)
    ) WITHOUT ROWID;
    CREATE TABLE DATA_REV (
      theChar TEXT NOT NULL,
      theReadings TEXT NOT NULL,
      PRIMARY KEY (theChar)
    ) WITHOUT ROWID;
    """#

    try await append(sqlHeader)
    try await append("\n")

    let unigramStart = Date()
    NSLog("   > Vanguard SQL Legacy: 正在整理主要語料為 SQL。")
    try await data.prepareLegacyGramFragments(chunkSize: effectiveChunkSize) { fragment in
      try await appendData(fragment)
    }
    NSLog(
      "   > Vanguard SQL Legacy: 語料 SQL 段落整理完畢，耗時 %.2f 秒。",
      Date().timeIntervalSince(unigramStart)
    )

    let revStart = Date()
    NSLog("   > Vanguard SQL Legacy: 正在整理反查資料為 SQL。")
    try await data.prepareRevLookupMapToSQLLegacy(chunkSize: effectiveChunkSize) { fragment in
      try await append(fragment)
    }
    NSLog(
      "   > Vanguard SQL Legacy: 反查 SQL 段落整理完畢，耗時 %.2f 秒。",
      Date().timeIntervalSince(revStart)
    )

    try await append("\nCOMMIT;\n")
    try await flush(isFinal: true)
  }
}

extension VCDataBuilder.Collector {
  fileprivate func prepareRevLookupMapToSQLLegacy(
    chunkSize: Int,
    _ writer: (_ fragment: String) async throws -> ()
  ) async throws {
    let chunkLimit = max(64 * 1_024, chunkSize)
    var buffer = String()
    buffer.reserveCapacity(chunkLimit)
    var bufferBytes = 0

    func flushBuffer(force: Bool) async throws {
      guard force || bufferBytes >= chunkLimit else { return }
      guard !buffer.isEmpty else { return }
      let payload = buffer
      buffer.removeAll(keepingCapacity: true)
      bufferBytes = 0
      try await writer(payload)
    }

    func appendFragment(_ fragment: String) async throws {
      guard !fragment.isEmpty else { return }
      buffer.append(fragment)
      bufferBytes += fragment.utf8.count
      try await flushBuffer(force: false)
    }

    var allKeys = Set<String>()
    reverseLookupTable.keys.forEach { allKeys.insert($0) }
    reverseLookupTable4NonKanji.keys.forEach { allKeys.insert($0) }
    reverseLookupTable4CNS.keys.forEach { allKeys.insert($0) }
    var keysToHandle = allKeys.sorted()
    if VCDataBuilder.TestSampleFilter.isEnabled {
      let limit = VCDataBuilder.TestSampleFilter.revLookupSampleLimit
      var limitedKeys = Array(keysToHandle.prefix(limit))
      if allKeys.contains("和"), !limitedKeys.contains("和") {
        limitedKeys.append("和")
      }
      keysToHandle = limitedKeys.sorted()
    }
    for key in keysToHandle {
      var arrValues = [String]()
      arrValues.append(contentsOf: reverseLookupTable[key] ?? [])
      arrValues.append(contentsOf: reverseLookupTable4NonKanji[key] ?? [])
      arrValues.append(contentsOf: reverseLookupTable4CNS[key] ?? [])
      arrValues = NSOrderedSet(array: arrValues).array.compactMap { $0 as? String }
      let filteredArrValues = VCDataBuilder.TestSampleFilter.filterReadings(arrValues)
      let readingsToUse: [String]
      if VCDataBuilder.TestSampleFilter.isEnabled {
        readingsToUse = filteredArrValues.isEmpty ? Array(arrValues.prefix(1)) : filteredArrValues
      } else {
        readingsToUse = arrValues
      }
      guard !readingsToUse.isEmpty else { continue }
      let encryptedValues = readingsToUse.map { $0.asEncryptedBopomofoKeyChain }
      // SQL 語言需要對西文 ASCII 半形單引號做回退處理、變成「''」。
      let safeKey = key.asEncryptedBopomofoKeyChain.replacingOccurrences(of: "'", with: "''")
      let valueText = encryptedValues.joined(separator: "\t")
        .replacingOccurrences(of: "'", with: "''")
      let sqlStmt =
        "INSERT INTO DATA_REV (theChar, theReadings) VALUES ('\(safeKey)', '\(valueText)') ON CONFLICT(theChar) DO UPDATE SET theReadings='\(valueText)';\n"
      try await appendFragment(sqlStmt)
    }
    try await flushBuffer(force: true)
  }

  fileprivate func prepareLegacyGramFragments(
    chunkSize: Int,
    _ writer: (_ fragment: Data) async throws -> ()
  ) async throws {
    let chunkLimit = max(64 * 1_024, chunkSize)
    var buffer = ContiguousArray<UInt8>()
    buffer.reserveCapacity(chunkLimit)
    let functionStart = Date()
    NSLog("|||_prepareLegacyGramFragments: 開始，chunkLimit=\(chunkLimit)")

    func flushBuffer(force: Bool) async throws {
      guard force || buffer.count >= chunkLimit else { return }
      guard !buffer.isEmpty else { return }
      let payload = Data(buffer)
      buffer.removeAll(keepingCapacity: true)
      try await writer(payload)
    }

    func appendFragment(_ fragment: Data) async throws {
      guard !fragment.isEmpty else { return }
      buffer.append(contentsOf: fragment)
      try await flushBuffer(force: false)
    }

    let chunkedWriter: (Data) async throws -> () = { fragment in
      try await appendFragment(fragment)
    }

    // Punctuations -> theDataCHS and theDataCHT.
    var allPunctuationsMap = [String: VCDataBuilder.Unigram.GramSet]()
    let punctuationCollectStart = Date()
    getPunctuations().forEach {
      allPunctuationsMap[$0.key, default: []].insert($0)
    }
    NSLog(
      "|||_prepareLegacyGramFragments: 蒐集標點資料完成，鍵數=\(allPunctuationsMap.count)，耗時 %.2f 秒",
      Date().timeIntervalSince(punctuationCollectStart)
    )
    let punctuationCHTStart = Date()
    try await handleUnigramTableToSQLLegacy(
      allPunctuationsMap,
      columnName: "theDataCHT",
      unigramStringBuilder: { unigram in unigram.value },
      writer: chunkedWriter
    )
    NSLog(
      "|||_prepareLegacyGramFragments: 標點 CHT 寫入完成，耗時 %.2f 秒",
      Date().timeIntervalSince(punctuationCHTStart)
    )
    let punctuationCHSStart = Date()
    try await handleUnigramTableToSQLLegacy(
      allPunctuationsMap,
      columnName: "theDataCHS",
      unigramStringBuilder: { unigram in unigram.value },
      writer: chunkedWriter
    )
    NSLog(
      "|||_prepareLegacyGramFragments: 標點 CHS 寫入完成，耗時 %.2f 秒",
      Date().timeIntervalSince(punctuationCHSStart)
    )

    // Core Kanjis and Phrases -> theDataCHS and theDataCHT.
    var allGramsMapCHS = [String: VCDataBuilder.Unigram.GramSet]()
    var allGramsMapCHT = [String: VCDataBuilder.Unigram.GramSet]()
    let gramCollectStartCHT = Date()
    getAllUnigrams(isCHS: false).forEach {
      allGramsMapCHT[$0.key, default: []].insert($0)
    }
    NSLog(
      "|||_prepareLegacyGramFragments: 蒐集繁體主語料完成，鍵數=\(allGramsMapCHT.count)，耗時 %.2f 秒",
      Date().timeIntervalSince(gramCollectStartCHT)
    )
    let gramCollectStartCHS = Date()
    getAllUnigrams(isCHS: true).forEach {
      allGramsMapCHS[$0.key, default: []].insert($0)
    }
    NSLog(
      "|||_prepareLegacyGramFragments: 蒐集簡體主語料完成，鍵數=\(allGramsMapCHS.count)，耗時 %.2f 秒",
      Date().timeIntervalSince(gramCollectStartCHS)
    )
    let gramCHSWriteStart = Date()
    try await handleUnigramTableToSQLLegacy(
      allGramsMapCHS,
      columnName: "theDataCHS",
      unigramStringBuilder: { unigram in "\(unigram.score) \(unigram.value)" },
      writer: chunkedWriter
    )
    NSLog(
      "|||_prepareLegacyGramFragments: 簡體主語料寫入完成，耗時 %.2f 秒",
      Date().timeIntervalSince(gramCHSWriteStart)
    )
    let gramCHTWriteStart = Date()
    try await handleUnigramTableToSQLLegacy(
      allGramsMapCHT,
      columnName: "theDataCHT",
      unigramStringBuilder: { unigram in "\(unigram.score) \(unigram.value)" },
      writer: chunkedWriter
    )
    NSLog(
      "|||_prepareLegacyGramFragments: 繁體主語料寫入完成，耗時 %.2f 秒",
      Date().timeIntervalSince(gramCHTWriteStart)
    )

    // Zhuyinwen.
    var allGramsMapZhuyinwen = [String: VCDataBuilder.Unigram.GramSet]()
    let zhuyinCollectStart = Date()
    getZhuyinwen().forEach {
      allGramsMapZhuyinwen[$0.key, default: []].insert($0)
    }
    NSLog(
      "|||_prepareLegacyGramFragments: 蒐集注音文資料完成，鍵數=\(allGramsMapZhuyinwen.count)，耗時 %.2f 秒",
      Date().timeIntervalSince(zhuyinCollectStart)
    )
    let zhuyinWriteStart = Date()
    try await handleUnigramTableToSQLLegacy(
      allGramsMapZhuyinwen,
      columnName: "theDataCHEW",
      unigramStringBuilder: { unigram in unigram.value },
      writer: chunkedWriter
    )
    NSLog(
      "|||_prepareLegacyGramFragments: 注音文寫入完成，耗時 %.2f 秒",
      Date().timeIntervalSince(zhuyinWriteStart)
    )

    // Symbols and Emojis.
    var allGramsMapSymbols = [String: VCDataBuilder.Unigram.GramSet]()
    let symbolCollectStart = Date()
    getSymbols().forEach {
      allGramsMapSymbols[$0.key, default: []].insert($0)
    }
    NSLog(
      "|||_prepareLegacyGramFragments: 蒐集符號資料完成，鍵數=\(allGramsMapSymbols.count)，耗時 %.2f 秒",
      Date().timeIntervalSince(symbolCollectStart)
    )
    let symbolWriteStart = Date()
    try await handleUnigramTableToSQLLegacy(
      allGramsMapSymbols,
      columnName: "theDataSYMB",
      unigramStringBuilder: { unigram in unigram.value },
      writer: chunkedWriter
    )
    NSLog(
      "|||_prepareLegacyGramFragments: 符號寫入完成，耗時 %.2f 秒",
      Date().timeIntervalSince(symbolWriteStart)
    )

    // CNS.
    let cnsWriteStart = Date()
    try await handleUnigramTableToSQLLegacy(
      tableKanjiCNS,
      columnName: "theDataCNS",
      unigramStringBuilder: { unigram in unigram.value },
      writer: chunkedWriter
    )
    NSLog(
      "|||_prepareLegacyGramFragments: CNS 寫入完成，來源鍵數=\(tableKanjiCNS.count)，耗時 %.2f 秒",
      Date().timeIntervalSince(cnsWriteStart)
    )
    try await flushBuffer(force: true)
    NSLog(
      "|||_prepareLegacyGramFragments: 整體完成，耗時 %.2f 秒",
      Date().timeIntervalSince(functionStart)
    )
  }

  private func handleUnigramTableToSQLLegacy(
    _ table: [String: VCDataBuilder.Unigram.GramSet],
    columnName: String,
    unigramStringBuilder: (VCDataBuilder.Unigram) -> String,
    writer: (_ fragment: Data) async throws -> ()
  ) async throws {
    let handlerStart = Date()
    var processedEntries = 0
    var skippedByFilter = 0
    var skippedEmpty = 0
    var totalFilterTime: TimeInterval = 0
    var totalSortTime: TimeInterval = 0
    var totalBuildTime: TimeInterval = 0
    var totalWriteTime: TimeInterval = 0
    var maxUnigramCount = 0
    var totalUnigramCount = 0
    var sampleCounter = 0
    var timeSnapshots = [Int: TimeInterval]()
    NSLog(
      "|||_handleUnigramTableToSQLLegacy: column=\(columnName) 開始，輸入鍵數=\(table.count)"
    )
    for (key, unigrams) in table {
      if VCDataBuilder.TestSampleFilter.shouldFilter(key) {
        skippedByFilter += 1
        continue
      }
      let filterStart = Date()
      let filteredUnigrams = VCDataBuilder.TestSampleFilter.filterUnigrams(unigrams)
      totalFilterTime += Date().timeIntervalSince(filterStart)
      guard !filteredUnigrams.isEmpty else {
        skippedEmpty += 1
        continue
      }
      maxUnigramCount = max(maxUnigramCount, filteredUnigrams.count)
      totalUnigramCount += filteredUnigrams.count
      let sortStart = Date()
      // SQL 語言需要對西文 ASCII 半形單引號做回退處理、變成「''」。
      let safeKey = key.asEncryptedBopomofoKeyChain.replacingOccurrences(of: "'", with: "''")
      var sortedUnigrams = filteredUnigrams.sorted { lhs, rhs -> Bool in
        (lhs.key, rhs.score, lhs.timestamp) < (rhs.key, lhs.score, rhs.timestamp)
      }
      totalSortTime += Date().timeIntervalSince(sortStart)
      if columnName == "theDataCNS", VCDataBuilder.TestSampleFilter.isEnabled {
        sortedUnigrams = Array(sortedUnigrams.prefix(5))
      }
      let buildStart = Date()
      let arrValues = sortedUnigrams.map(unigramStringBuilder)
      let valueText = arrValues.joined(separator: "\t").replacingOccurrences(of: "'", with: "''")
      let sqlStmt =
        "INSERT INTO DATA_MAIN (theKey, \(columnName)) VALUES ('\(safeKey)', '\(valueText)') ON CONFLICT(theKey) DO UPDATE SET \(columnName)='\(valueText)';\n"
      totalBuildTime += Date().timeIntervalSince(buildStart)
      let writeStart = Date()
      try await writer(Data(sqlStmt.utf8))
      totalWriteTime += Date().timeIntervalSince(writeStart)
      processedEntries += 1
      sampleCounter += 1
      if sampleCounter % 25000 == 0 {
        let elapsed = Date().timeIntervalSince(handlerStart)
        timeSnapshots[sampleCounter] = elapsed
        NSLog(
          "|||_handleUnigramTableToSQLLegacy: column=\(columnName) 已寫入=\(sampleCounter)，耗時=%.2f 秒",
          elapsed
        )
      }
    }
    let duration = Date().timeIntervalSince(handlerStart)
    NSLog(
      "|||_handleUnigramTableToSQLLegacy: column=\(columnName) 完成，寫入=\(processedEntries)，被過濾=\(skippedByFilter)，無資料=\(skippedEmpty)，最大單元圖數=\(maxUnigramCount)，平均單元圖數=\(processedEntries > 0 ? Double(totalUnigramCount) / Double(processedEntries) : 0)，耗時 %.2f 秒",
      duration
    )
    NSLog(
      "|||_handleUnigramTableToSQLLegacy: column=\(columnName) 細項耗時：filter=%.2f 秒、sort=%.2f 秒、build=%.2f 秒、write=%.2f 秒",
      totalFilterTime,
      totalSortTime,
      totalBuildTime,
      totalWriteTime
    )
  }
}
