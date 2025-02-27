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
    }

    // MARK: Public

    nonisolated public let isCHS: Bool?

    // MARK: Internal

    let data: Collector
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

  public func assemble() async throws -> [String: String] {
    let assembled = await assembleSQLFile { [self] in
      let unigramLines = await data.prepareUnigramMapsToSQLLegacy()
      let revLookupLines = await data.prepareRevLookupMapToSQLLegacy()
      return unigramLines + revLookupLines
    }
    return ["vanguardLegacy.sql": assembled]
  }

  // This method uses terminal commands to convert SQL file to SQLite file.
  public func performPostCompilation() async throws {
    // Check if sqlite3 is installed
    print("Checking for SQLite3 installation...")
    let sqliteCheck = ShellHelper.shell("which sqlite3")
    if sqliteCheck.exitCode != 0 || sqliteCheck.output
      .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      throw VCDataBuilder.Exception
        .errMsg("SQLite3 is not installed or not found in PATH. Please install SQLite3.")
    }

    // Get the path to sqlite3 executable
    let sqlite3Path = sqliteCheck.output.trimmingCharacters(in: .whitespacesAndNewlines)
    print("Found SQLite3 at: \(sqlite3Path)")

    // Check if source files exist
    let fileManager = FileManager.default
    let sqlFilePath = "./Build/Intermediate/vanguardSQL-Legacy/vanguardLegacy.sql"
    let dbFilePath = "./Build/Release/vanguardSQL-Legacy/vChewingFactoryDatabase.sqlite"

    if !fileManager.fileExists(atPath: sqlFilePath) {
      throw VCDataBuilder.Exception.errMsg("SQL source file not found at path: \(sqlFilePath)")
    }

    // Make sure the directory for the database file exists
    let dbDirectory = URL(fileURLWithPath: dbFilePath).deletingLastPathComponent().path
    if !fileManager.fileExists(atPath: dbDirectory) {
      do {
        try fileManager.createDirectory(
          atPath: dbDirectory,
          withIntermediateDirectories: true,
          attributes: nil
        )
        print("Created directory for the database file: \(dbDirectory)")
      } catch {
        throw VCDataBuilder.Exception
          .errMsg("Failed to create directory for the database file: \(error.localizedDescription)")
      }
    }

    // Execute the SQLite command
    let command = "\(sqlite3Path) \"\(dbFilePath)\" < \"\(sqlFilePath)\""
    print("Executing: \(command)")

    let result = ShellHelper.shell(command)
    if result.exitCode != 0 {
      throw VCDataBuilder.Exception
        .errMsg("Failed to initialize Vanguard database:\n\(result.output)")
    }

    // Verify the database was created
    if !fileManager.fileExists(atPath: dbFilePath) {
      throw VCDataBuilder.Exception.errMsg("Database file was not created at path: \(dbFilePath)")
    }

    print("Vanguard Legacy SQLite database initialization completed successfully.")
  }
}

extension String {
  fileprivate static let bpmfReplacements: [Character: Character] = [
    "ㄅ": "b", "ㄆ": "p", "ㄇ": "m", "ㄈ": "f", "ㄉ": "d",
    "ㄊ": "t", "ㄋ": "n", "ㄌ": "l", "ㄍ": "g", "ㄎ": "k",
    "ㄏ": "h", "ㄐ": "j", "ㄑ": "q", "ㄒ": "x", "ㄓ": "Z",
    "ㄔ": "C", "ㄕ": "S", "ㄖ": "r", "ㄗ": "z", "ㄘ": "c",
    "ㄙ": "s", "ㄧ": "i", "ㄨ": "u", "ㄩ": "v", "ㄚ": "a",
    "ㄛ": "o", "ㄜ": "e", "ㄝ": "E", "ㄞ": "B", "ㄟ": "P",
    "ㄠ": "M", "ㄡ": "F", "ㄢ": "D", "ㄣ": "T", "ㄤ": "N",
    "ㄥ": "L", "ㄦ": "R", "ˊ": "2", "ˇ": "3", "ˋ": "4",
    "˙": "5",
  ]

  fileprivate var asEncryptedBopomofoKeyChain: String {
    guard first != "_" else { return self }
    return String(map { Self.bpmfReplacements[$0] ?? $0 })
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

    print("diagnose: \(tableKanjiCNS.count)")
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
      // SQL 語言需要對西文 ASCII 半形單引號做回退處理、變成「''」。
      let safeKey = key.asEncryptedBopomofoKeyChain.replacingOccurrences(of: "'", with: "''")
      let sortedUnigrams = unigrams.sorted { lhs, rhs -> Bool in
        (lhs.key, rhs.score, lhs.timestamp) < (rhs.key, lhs.score, rhs.timestamp)
      }
      let arrValues = sortedUnigrams.map(unigramStringBuilder)
      let valueText = arrValues.joined(separator: "\t").replacingOccurrences(of: "'", with: "''")
      let sqlStmt =
        "INSERT INTO DATA_MAIN (theKey, \(columnName)) VALUES ('\(safeKey)', '\(valueText)') ON CONFLICT(theKey) DO UPDATE SET \(columnName)='\(valueText)';"
      script.append("\(sqlStmt)\n")
    }
  }
}
