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

  public func assemble() async throws -> [String: Data] {
    let assembled = await assembleSQLFile { [self] in
      let unigramLines = await data.prepareUnigramMapsToSQLLegacy()
      let revLookupLines = await data.prepareRevLookupMapToSQLLegacy()
      return unigramLines + revLookupLines
    }
    guard let dataSQL = assembled.data(using: .utf8) else {
      throw VCDataBuilder.Exception
        .errMsg("Data encoding failed on assembling for VanguardSQLLegacy.")
    }
    return ["vanguardLegacy.sql": dataSQL]
  }

  // This method uses terminal commands to convert SQL file to SQLite file.
  public func performPostCompilation() async throws {
    try await runInTextBlockThrowable {
      print("Vanguard Legacy SQLite database compilation started.")
      try await compileSQLite(
        fileNameStem: "vanguardLegacy",
        outputFileNameStem: "vChewingFactoryDatabase"
      )
      print("Vanguard Legacy SQLite database compilation completed successfully.")
    }
  }
}

extension VCDataBuilder.VanguardSQLLegacyDataBuilder {
  func assembleSQLFile(_ insertData: @escaping () async -> String) async -> String {
    var strBuilder = [String]()
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
    strBuilder.append(sqlHeader)
    strBuilder.append("\n")
    strBuilder.append(await insertData())
    strBuilder.append("\nCOMMIT;\n")
    return strBuilder.joined()
  }
}

extension VCDataBuilder.Collector {
  fileprivate func prepareRevLookupMapToSQLLegacy() -> String {
    var script = [String]()
    var allKeys = Set<String>()
    reverseLookupTable.keys.forEach { allKeys.insert($0) }
    reverseLookupTable4NonKanji.keys.forEach { allKeys.insert($0) }
    reverseLookupTable4CNS.keys.forEach { allKeys.insert($0) }
    for key in allKeys.sorted() {
      var arrValues = [String]()
      arrValues.append(contentsOf: reverseLookupTable[key] ?? [])
      arrValues.append(contentsOf: reverseLookupTable4NonKanji[key] ?? [])
      arrValues.append(contentsOf: reverseLookupTable4CNS[key] ?? [])
      arrValues = NSOrderedSet(array: arrValues).array.compactMap { $0 as? String }
      arrValues = VCDataBuilder.TestSampleFilter.filterReadings(arrValues)
      guard !arrValues.isEmpty else { continue }
      // SQL 語言需要對西文 ASCII 半形單引號做回退處理、變成「''」。
      let safeKey = key.asEncryptedBopomofoKeyChain.replacingOccurrences(of: "'", with: "''")
      let valueText = arrValues.joined(separator: "\t").replacingOccurrences(of: "'", with: "''")
      let sqlStmt =
        "INSERT INTO DATA_REV (theChar, theReadings) VALUES ('\(safeKey)', '\(valueText)') ON CONFLICT(theChar) DO UPDATE SET theReadings='\(valueText)';"
      script.append("\(sqlStmt)\n")
    }
    return script.joined()
  }

  fileprivate func prepareUnigramMapsToSQLLegacy() -> String {
    var script = [String]()
    // Punctuations -> theDataCHS and theDataCHT.
    var allPunctuationsMap = [String: VCDataBuilder.Unigram.GramSet]()
    getPunctuations().forEach {
      allPunctuationsMap[$0.key, default: []].insert($0)
    }
    handleUnigramTableToSQLLegacy(
      &script,
      allPunctuationsMap,
      columnName: "theDataCHT"
    ) { unigram in
      unigram.value
    }
    handleUnigramTableToSQLLegacy(
      &script,
      allPunctuationsMap,
      columnName: "theDataCHS"
    ) { unigram in
      unigram.value
    }

    // Core Kanjis and Phrases -> theDataCHS and theDataCHT.
    var allGramsMapCHS = [String: VCDataBuilder.Unigram.GramSet]()
    var allGramsMapCHT = [String: VCDataBuilder.Unigram.GramSet]()
    getAllUnigrams(isCHS: false).forEach {
      allGramsMapCHT[$0.key, default: []].insert($0)
    }
    getAllUnigrams(isCHS: true).forEach {
      allGramsMapCHS[$0.key, default: []].insert($0)
    }
    handleUnigramTableToSQLLegacy(
      &script,
      allGramsMapCHS,
      columnName: "theDataCHS"
    ) { unigram in
      "\(unigram.score) \(unigram.value)"
    }
    handleUnigramTableToSQLLegacy(
      &script,
      allGramsMapCHT,
      columnName: "theDataCHT"
    ) { unigram in
      "\(unigram.score) \(unigram.value)"
    }

    // Zhuyinwen.
    var allGramsMapZhuyinwen = [String: VCDataBuilder.Unigram.GramSet]()
    getZhuyinwen().forEach {
      allGramsMapZhuyinwen[$0.key, default: []].insert($0)
    }
    handleUnigramTableToSQLLegacy(
      &script,
      allGramsMapZhuyinwen,
      columnName: "theDataCHEW"
    ) { unigram in
      unigram.value
    }

    // Symbols and Emojis.
    var allGramsMapSymbols = [String: VCDataBuilder.Unigram.GramSet]()
    getSymbols().forEach {
      allGramsMapSymbols[$0.key, default: []].insert($0)
    }
    handleUnigramTableToSQLLegacy(
      &script,
      allGramsMapSymbols,
      columnName: "theDataSYMB"
    ) { unigram in
      unigram.value
    }

    // CNS.
    handleUnigramTableToSQLLegacy(&script, tableKanjiCNS, columnName: "theDataCNS") { unigram in
      unigram.value
    }

    return script.joined()
  }

  private func handleUnigramTableToSQLLegacy(
    _ script: inout [String],
    _ table: [String: VCDataBuilder.Unigram.GramSet],
    columnName: String,
    unigramStringBuilder: (VCDataBuilder.Unigram) -> String
  ) {
    for (key, unigrams) in table {
      if VCDataBuilder.TestSampleFilter.shouldFilter(key) {
        continue
      }
      let filteredUnigrams = VCDataBuilder.TestSampleFilter.filterUnigrams(unigrams)
      guard !filteredUnigrams.isEmpty else { continue }
      // SQL 語言需要對西文 ASCII 半形單引號做回退處理、變成「''」。
      let safeKey = key.asEncryptedBopomofoKeyChain.replacingOccurrences(of: "'", with: "''")
      var sortedUnigrams = filteredUnigrams.sorted { lhs, rhs -> Bool in
        (lhs.key, rhs.score, lhs.timestamp) < (rhs.key, lhs.score, rhs.timestamp)
      }
      if columnName == "theDataCNS", VCDataBuilder.TestSampleFilter.isEnabled {
        sortedUnigrams = Array(sortedUnigrams.prefix(5))
      }
      let arrValues = sortedUnigrams.map(unigramStringBuilder)
      let valueText = arrValues.joined(separator: "\t").replacingOccurrences(of: "'", with: "''")
      let sqlStmt =
        "INSERT INTO DATA_MAIN (theKey, \(columnName)) VALUES ('\(safeKey)', '\(valueText)') ON CONFLICT(theKey) DO UPDATE SET \(columnName)='\(valueText)';"
      script.append("\(sqlStmt)\n")
    }
  }
}
