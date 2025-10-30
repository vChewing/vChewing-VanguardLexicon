// (c) 2021 and onwards The vChewing Project (BSD-3-Clause).
// ====================
// This code is released under the SPDX-License-Identifier: `BSD-3-Clause`.

import CSQLite3
import Foundation
import VanguardTrieKit

extension VanguardTrie.Trie.EntryType {
  public static let meta = Self(rawValue: 2 << 0)
  public static let revLookup = Self(rawValue: 3 << 0)
  public static let letterPunctuations = Self(rawValue: 4 << 0)
  public static let chs = Self(rawValue: 5 << 0) // 0x0804
  public static let cht = Self(rawValue: 6 << 0) // 0x0404
  public static let cns = Self(rawValue: 7 << 0)
  public static let nonKanji = Self(rawValue: 8 << 0)
  public static let symbolPhrases = Self(rawValue: 9 << 0)
  public static let zhuyinwen = Self(rawValue: 10 << 0)
}

extension VanguardTrie.Trie {
  public func insert(entry: Entry, readingsEncrypted: [String]) {
    insert(entry: entry, readings: readingsEncrypted.map(\.asEncryptedBopomofoKeyChain))
  }
}

extension VCDataBuilder.Unigram {
  func asEntry(
    type: VanguardTrie.Trie.EntryType,
    previous: String? = nil
  )
    -> (VanguardTrie.Trie.Entry, readingArray: [String])? {
    guard !VCDataBuilder.TestSampleFilter.shouldFilter(key) else { return nil }
    let entry = VanguardTrie.Trie.Entry(
      value: value,
      typeID: type,
      probability: score,
      previous: nil
    )
    return (entry, keyCells)
  }
}

// MARK: - VCDataBuilder.TriePreparatorProtocol

extension VCDataBuilder {
  public protocol TriePreparatorProtocol: AnyObject, DataBuilderProtocol {
    var trie4Typing: VanguardTrie.Trie { get }
    var trie4Rev: VanguardTrie.Trie { get }
  }
}

extension VCDataBuilder.TriePreparatorProtocol {
  public func prepareTrie() async {
    NSLog(" - 通用: 正在構築辭典樹。")
    trie4Typing.clearAllContents()
    trie4Rev.clearAllContents()

    let normEntryKey = "_NORM"
    let normEntry = VanguardTrie.Trie.Entry(
      value: normEntryKey,
      typeID: .meta,
      probability: data.norm,
      previous: nil
    )
    trie4Typing.insert(entry: normEntry, readings: [normEntryKey])

    let dateEntryKey = "_BUILD_TIMESTAMP"
    let dateEntry = VanguardTrie.Trie.Entry(
      value: dateEntryKey,
      typeID: .meta,
      probability: Date().timeIntervalSince1970,
      previous: nil
    )
    trie4Typing.insert(entry: dateEntry, readings: [dateEntryKey])
    trie4Rev.insert(entry: dateEntry, readings: [dateEntryKey])

    await withTaskGroup(of: Void.self) { group in
      group.addTask { [self] in
        // revLookup
        var allKeys = Set<String>()
        data.reverseLookupTable.keys.forEach { allKeys.insert($0) }
        data.reverseLookupTable4NonKanji.keys.forEach { allKeys.insert($0) }
        data.reverseLookupTable4CNS.keys.forEach { allKeys.insert($0) }
        var allKeysToHandle = allKeys.sorted()
        if VCDataBuilder.TestSampleFilter.isEnabled {
          let limit = VCDataBuilder.TestSampleFilter.revLookupSampleLimit
          var limitedKeys = Array(allKeysToHandle.prefix(limit))
          if allKeys.contains("和"), !limitedKeys.contains("和") {
            limitedKeys.append("和")
            limitedKeys.sort()
          }
          allKeysToHandle = limitedKeys
        }
        allKeysToHandle.forEach { key in
          var arrValues = [String]()
          arrValues.append(contentsOf: data.reverseLookupTable[key] ?? [])
          arrValues.append(contentsOf: data.reverseLookupTable4NonKanji[key] ?? [])
          arrValues.append(contentsOf: data.reverseLookupTable4CNS[key] ?? [])
          arrValues = NSOrderedSet(array: arrValues).array.compactMap { $0 as? String }
          let newEntry = VanguardTrie.Trie.Entry(
            value: arrValues.joined(separator: "\t").asEncryptedBopomofoKeyChain,
            typeID: .revLookup,
            probability: 0,
            previous: nil
          )
          trie4Rev.insert(entry: newEntry, readings: [key])
        }
        NSLog(" - 通用: 成功構築辭典樹（反查表）。")
      }
      group.addTask { [self] in
        await withTaskGroup(of: [(VanguardTrie.Trie.Entry, [String])].self) { subGroup in
          subGroup.addTask {
            // chs
            self.data.unigramsKanjiCHS.values.flatMap {
              $0.values.flatMap { $0.map { $0 } }
            }.compactMap { $0.asEntry(type: .chs) }
          }
          subGroup.addTask {
            self.data.unigramsCHS.values.flatMap {
              $0.values.flatMap { $0.map { $0 } }
            }.compactMap { $0.asEntry(type: .chs) }
          }
          subGroup.addTask {
            // cht
            self.data.unigramsKanjiCHT.values.flatMap {
              $0.values.flatMap { $0.map { $0 } }
            }.compactMap { $0.asEntry(type: .cht) }
          }
          subGroup.addTask {
            self.data.unigramsCHT.values.flatMap {
              $0.values.flatMap { $0.map { $0 } }
            }.compactMap { $0.asEntry(type: .cht) }
          }
          subGroup.addTask {
            // nonKanji
            self.data.unigrams4NonKanji.values.flatMap {
              $0.values.flatMap { $0.map { $0 } }
            }.compactMap { $0.asEntry(type: .nonKanji) }
          }
          subGroup.addTask {
            // symbolPhrases
            await self.data.getSymbols().compactMap { $0.asEntry(type: .symbolPhrases) }
          }
          subGroup.addTask {
            // zhuyinwen
            await self.data.getZhuyinwen().compactMap { $0.asEntry(type: .zhuyinwen) }
          }
          subGroup.addTask {
            // letters and punctuations
            await self.data.getPunctuations().compactMap { $0.asEntry(type: .letterPunctuations) }
          }
          subGroup.addTask {
            // cns
            self.data.tableKanjiCNS.values.flatMap { $0 }.compactMap { $0.asEntry(type: .cns) }
          }
          for await result in subGroup {
            result.forEach {
              trie4Typing.insert(entry: $0.0, readingsEncrypted: $0.1)
            }
          }
        }
      }
      await group.waitForAll()
      NSLog(" - 通用: 成功構築所有的辭典樹。")
    }
  }
}

// MARK: - VCDataBuilder.DataBuilderProtocol

extension VCDataBuilder {
  public protocol DataBuilderProtocol: AnyObject {
    init?(isCHS: Bool?) async throws
    var subFolderNameComponents: [String] { get }
    var subFolderNameComponentsAftermath: [String] { get }
    var isCHS: Bool? { get }
    var data: Collector { get }
    func assemble() async throws -> [String: Data]
    func performPostCompilation() async throws
  }
}

extension VCDataBuilder.DataBuilderProtocol {
  public init?(isCHS: Bool? = nil) async throws {
    try await self.init(isCHS: isCHS)
  }

  public func runInTextBlock(_ task: () async -> ()) async {
    print("===============================")
    print("-------------------------------")
    defer {
      print("-------------------------------")
      print("===============================")
    }
    await task()
  }

  public func runInTextBlockThrowable(_ task: () async throws -> ()) async throws {
    print("===============================")
    print("-------------------------------")
    defer {
      print("-------------------------------")
      print("===============================")
    }
    try await task()
  }

  public func printHealthCheckReports() async throws {
    let langs: [Bool] = if let isCHS {
      [isCHS]
    } else {
      [true, false]
    }
    try await runInTextBlockThrowable {
      for lang in langs {
        try await data.healthCheckPerMode(isCHS: lang).forEach { print($0) }
      }
    }
  }

  public func writeAssembledAssets() async throws {
    let subFolderNameComponentsAftermath = subFolderNameComponentsAftermath
    // Create aftermath folder if necessary.
    aftermath: do {
      guard !subFolderNameComponentsAftermath.isEmpty else { break aftermath }
      var folderURLAftermath = FileManager.urlCurrentFolder.appendingPathComponent("Build")
      subFolderNameComponentsAftermath.forEach { currentComponentName in
        folderURLAftermath = folderURLAftermath.appendingPathComponent(currentComponentName)
      }
      try FileManager.default.createDirectory(
        at: folderURLAftermath,
        withIntermediateDirectories: true
      )
    }
    // Create primary folder.
    var folderURL = FileManager.urlCurrentFolder.appendingPathComponent("Build")
    subFolderNameComponents.forEach { currentComponentName in
      folderURL = folderURL.appendingPathComponent(currentComponentName)
    }
    // Starts assemblying and data output.
    let assembled = try await assemble()
    try assembled.forEach { filename, data in
      let fileURL = folderURL.appendingPathComponent(filename)
      try FileManager.default.createDirectory(
        at: folderURL,
        withIntermediateDirectories: true
      )
      if FileManager.default.fileExists(atPath: fileURL.path) {
        try FileManager.default.removeItem(at: fileURL)
      }
      try data.write(to: fileURL, options: [.atomic])
    }
    // Aftermath.
    NSLog(" - 準備執行追加建置過程。")
    try await runInTextBlockThrowable {
      try await performPostCompilation()
    }
    NSLog(" - 成功執行追加建置過程。")
  }

  func compileSQLite(fileNameStem: String, outputFileNameStem: String? = nil) async throws {
    let outputFileNameStem = outputFileNameStem ?? fileNameStem
    print("Preparing SQLite database assembly via SQLite C API...")

    let buildRoot = FileManager.urlCurrentFolder.appendingPathComponent("Build")
    let sqlFolderURL = subFolderNameComponents.reduce(buildRoot) { partial, component in
      partial.appendingPathComponent(component)
    }
    let sqlFileURL = sqlFolderURL.appendingPathComponent("\(fileNameStem).sql")

    let dbFolderURL = subFolderNameComponentsAftermath.reduce(buildRoot) { partial, component in
      partial.appendingPathComponent(component)
    }
    let dbFileURL = dbFolderURL.appendingPathComponent("\(outputFileNameStem).sqlite")

    guard FileManager.default.fileExists(atPath: sqlFileURL.path) else {
      throw VCDataBuilder.Exception
        .errMsg("SQL file not found at expected path: \(sqlFileURL.path)")
    }

    try FileManager.default.createDirectory(
      at: dbFolderURL,
      withIntermediateDirectories: true,
      attributes: nil
    )

    if FileManager.default.fileExists(atPath: dbFileURL.path) {
      do {
        try FileManager.default.removeItem(at: dbFileURL)
        print("Removed existing database file.")
      } catch {
        print("Warning: Failed to remove existing database file: \(error)")
      }
    }

    var sqlData = try Data(contentsOf: sqlFileURL)
    if sqlData.starts(with: [0xEF, 0xBB, 0xBF]) {
      sqlData.removeFirst(3)
    }

    print("Opening SQLite database at: \(dbFileURL.path)")

    var database: OpaquePointer?
    let openFlags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
    let openResult = sqlite3_open_v2(dbFileURL.path, &database, openFlags, nil)
    guard openResult == SQLITE_OK, let db = database else {
      let message = database.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "Unknown error"
      if let database {
        sqlite3_close(database)
      }
      throw VCDataBuilder.Exception.errMsg("Unable to open SQLite database: \(message)")
    }

    defer {
      if sqlite3_close(db) != SQLITE_OK {
        let closeMessage = String(cString: sqlite3_errmsg(db))
        print("Warning: sqlite3_close returned an error: \(closeMessage)")
      }
    }

    var executedStatements = 0

    print("Executing SQL script using SQLite C API...")
    try sqlData.withUnsafeBytes { rawBuffer in
      let buffer = rawBuffer.bindMemory(to: CChar.self)
      guard let baseAddress = buffer.baseAddress else { return }
      var current = baseAddress
      let endPointer = baseAddress + buffer.count

      func skipSeparators(_ pointer: inout UnsafePointer<CChar>) {
        while pointer < endPointer {
          let char = pointer.pointee
          switch char {
          case 0:
            pointer = endPointer
            return
          case 9, 10, 13, 32, 59: // tab, lf, cr, space, semicolon
            pointer = pointer.advanced(by: 1)
          case 45: // '-'
            let next = pointer.advanced(by: 1)
            if next < endPointer, next.pointee == 45 {
              pointer = next.advanced(by: 1)
              while pointer < endPointer {
                let c = pointer.pointee
                if c == 10 || c == 13 {
                  pointer = pointer.advanced(by: 1)
                  break
                }
                pointer = pointer.advanced(by: 1)
              }
            } else {
              return
            }
          case 47: // '/'
            let next = pointer.advanced(by: 1)
            if next < endPointer, next.pointee == 42 { // '/*'
              pointer = next.advanced(by: 1)
              while pointer < endPointer {
                if pointer.pointee == 42 {
                  let lookAhead = pointer.advanced(by: 1)
                  if lookAhead < endPointer, lookAhead.pointee == 47 {
                    pointer = lookAhead.advanced(by: 1)
                    break
                  }
                }
                pointer = pointer.advanced(by: 1)
              }
            } else {
              return
            }
          default:
            return
          }
        }
      }

      skipSeparators(&current)

      while current < endPointer {
        let remaining = current.distance(to: endPointer)
        if remaining <= 0 {
          break
        }
        guard remaining <= Int(Int32.max) else {
          throw VCDataBuilder.Exception
            .errMsg("SQL script is too large to process with the current allocator.")
        }

        var statement: OpaquePointer?
        var tail: UnsafePointer<CChar>?
        let prepareResult = sqlite3_prepare_v2(
          db,
          current,
          Int32(remaining),
          &statement,
          &tail
        )

        if prepareResult != SQLITE_OK {
          let message = String(cString: sqlite3_errmsg(db))
          throw VCDataBuilder.Exception
            .errMsg("SQLite prepare failed (code \(prepareResult)): \(message)")
        }

        guard let tail else { break }

        guard let statement else {
          current = tail
          skipSeparators(&current)
          continue
        }

        var stepResult = sqlite3_step(statement)
        while stepResult == SQLITE_ROW {
          stepResult = sqlite3_step(statement)
        }

        if stepResult != SQLITE_DONE {
          let message = String(cString: sqlite3_errmsg(db))
          sqlite3_finalize(statement)
          throw VCDataBuilder.Exception
            .errMsg("SQLite step failed (code \(stepResult)): \(message)")
        }

        sqlite3_finalize(statement)
        executedStatements += 1
        current = tail
        skipSeparators(&current)
      }
    }

    if executedStatements == 0 {
      print("Warning: SQL script executed zero statements.")
    } else {
      print("Executed \(executedStatements) SQL statement(s).")
    }

    if !FileManager.default.fileExists(atPath: dbFileURL.path) {
      throw VCDataBuilder.Exception.errMsg("Database file was not created at path: \(dbFileURL.path)")
    }

    print("Successfully created SQLite database at: \(dbFileURL.path)")
  }
}

// MARK: - VCDataBuilder.BuilderType

extension VCDataBuilder {
  public enum BuilderType: String, CaseIterable, Sendable, Hashable, Codable {
    case vanguardTrieSQL
    case vanguardTriePlist
    case chewingRustCHS
    case chewingRustCHT
    case chewingCBasedCHS
    case chewingCBasedCHT
    case mcbopomofoCHS
    case mcbopomofoCHT
    case vanguardSQLLegacy
  }
}

extension VCDataBuilder.BuilderType {
  public func getAssembler() async throws -> (VCDataBuilder.DataBuilderProtocol & Actor)? {
    switch self {
    case .vanguardTrieSQL: try await VCDataBuilder.VanguardTrieSQLDataBuilder()
    case .vanguardTriePlist: try await VCDataBuilder.VanguardTriePlistDataBuilder()
    case .chewingRustCHS: try await VCDataBuilder.ChewingRustDataBuilder(isCHS: true)
    case .chewingRustCHT: try await VCDataBuilder.ChewingRustDataBuilder(isCHS: false)
    case .chewingCBasedCHS: try await VCDataBuilder.ChewingCBasedDataBuilder(isCHS: true)
    case .chewingCBasedCHT: try await VCDataBuilder.ChewingCBasedDataBuilder(isCHS: false)
    case .mcbopomofoCHS: try await VCDataBuilder.McBopomofoDataBuilder(isCHS: true)
    case .mcbopomofoCHT: try await VCDataBuilder.McBopomofoDataBuilder(isCHS: false)
    case .vanguardSQLLegacy: try await VCDataBuilder.VanguardSQLLegacyDataBuilder()
    }
  }

  public func compile() async throws {
    NSLog("// ================ ")
    do {
      NSLog("// 開始建置： \(rawValue) ...")
      let assembler = try await getAssembler()
      guard assembler != nil else {
        NSLog(" ~ 略過處理： \(rawValue) ...")
        return
      }
      try await assembler?.writeAssembledAssets()
      NSLog(" ~ 成功建置： \(rawValue) ...")
    } catch {
      NSLog("!! 建置失敗： \(rawValue) ...")
      throw error
    }
  }
}

// MARK: - VCDataBuilder.TestSampleFilter

extension VCDataBuilder {
  enum TestSampleFilter {
    // MARK: Internal

    static var revLookupSampleLimit: Int { 10 }

    static var isEnabled: Bool {
      ProcessInfo.processInfo.environment["VANGUARD_CORPUS_BUILD_MODE"] == "SMALL_TESTABLE_SAMPLE"
    }

    static func shouldFilter(_ target: String) -> Bool {
      guard isEnabled else { return false }
      if target.hasPrefix("_") {
        return false
      }
      return !whitelist.contains(target)
    }

    static func filterReadings<S: Sequence>(_ readings: S) -> [String] where S.Element == String {
      guard isEnabled else { return Array(readings) }
      return Array(readings).filter { !shouldFilter($0) }
    }

    static func filterUnigrams<S: Sequence>(_ grams: S) -> [VCDataBuilder.Unigram]
      where S.Element == VCDataBuilder.Unigram {
      guard isEnabled else { return Array(grams) }
      return Array(grams).filter { !shouldFilter($0.key) }
    }

    // MARK: Private

    private static let whitelist: Set<String> = [
      "ㄇㄧˋ",
      "ㄇㄧˋ-ㄈㄥ",
      "ㄈㄤ",
      "ㄈㄥ",
      "ㄉㄚˋ-ㄕㄨˋ",
      "ㄉㄜ˙",
      "ㄉㄧㄝˊ",
      "ㄋㄥˊ",
      "ㄋㄥˊ-ㄌㄧㄡˊ",
      "ㄌㄧㄡˊ",
      "ㄌㄧㄡˊ-ㄧˋ",
      "ㄌㄩˇ",
      "ㄌㄩˇ-ㄈㄤ",
      "ㄍㄨㄛˇ",
      "ㄍㄨㄛˇ-ㄓ",
      "ㄍㄨㄥ",
      "ㄍㄨㄥ-ㄩㄢˊ",
      "ㄎㄜ",
      "ㄎㄜ-ㄐㄧˋ",
      "ㄐㄧˋ",
      "ㄐㄧˋ-ㄍㄨㄥ",
      "ㄒㄧㄣ",
      "ㄒㄧㄣ-ㄉㄜ˙",
      "ㄓ",
      "ㄕㄨㄟˇ",
      "ㄕㄨㄟˇ-ㄍㄨㄛˇ",
      "ㄕㄨㄟˇ-ㄍㄨㄛˇ-ㄓ",
      "ㄕㄨˋ",
      "ㄕㄨˋ-ㄒㄧㄣ",
      "ㄧㄡ",
      "ㄧㄡ-ㄉㄧㄝˊ",
      "ㄧˋ",
      "ㄧˋ-ㄌㄩˇ",
      "ㄩㄢˊ",
      "ㄋㄟ-ㄋㄟ",
      "ㄊㄝ",
      "ㄋㄧㄢˊ",
      "ㄋㄧㄢˊ-ㄓㄨㄥ",
      "ㄓㄨㄥ",
      "ㄎㄜ-ㄎㄜ",
      "ㄉㄢˋ",
      "ㄍㄠ",
      "ㄉㄢˋ-ㄍㄠ",
      "ㄨㄟ",
      "ㄨㄟˊ",
      "ㄏㄨㄛˊ",
      "ㄏㄜ˙",
      "ㄏㄨㄛ",
      "ㄉㄨㄥ",
      "ㄏㄜˊ",
      "ㄏㄜˋ",
      "ㄏㄢˋ",
      "ㄏㄨˊ",
      "ㄏㄨㄛ˙",
      "ㄏㄨㄛˋ",
    ]
  }
}
