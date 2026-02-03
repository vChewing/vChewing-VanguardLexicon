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
  public protocol TriePreparatorProtocol: Actor, DataBuilderProtocol {
    nonisolated var mutexTrie4Typing: NSMutex<VanguardTrie.Trie> { get }
    nonisolated var mutexTrie4Rev: NSMutex<VanguardTrie.Trie> { get }
  }
}

extension VCDataBuilder.TriePreparatorProtocol {
  public var trie4Typing: VanguardTrie.Trie { mutexTrie4Typing.value }
  public var trie4Rev: VanguardTrie.Trie { mutexTrie4Rev.value }

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
        // 反查表
        var allKeys = Set<String>()
        let table = await data.reverseLookupTable
        let tableNonKanji = await data.reverseLookupTable4NonKanji
        let tableCNS = await data.reverseLookupTable4CNS

        table.keys.forEach { allKeys.insert($0) }
        tableNonKanji.keys.forEach { allKeys.insert($0) }
        tableCNS.keys.forEach { allKeys.insert($0) }

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
        for key in allKeysToHandle {
          var arrValues = [String]()
          arrValues.append(contentsOf: table[key] ?? [])
          arrValues.append(contentsOf: tableNonKanji[key] ?? [])
          arrValues.append(contentsOf: tableCNS[key] ?? [])
          arrValues = NSOrderedSet(array: arrValues).array.compactMap { $0 as? String }
          let newEntry = VanguardTrie.Trie.Entry(
            value: arrValues.joined(separator: "\t").asEncryptedBopomofoKeyChain,
            typeID: .revLookup,
            probability: 0,
            previous: nil
          )
          mutexTrie4Rev.withLock {
            $0.insert(entry: newEntry, readings: [key])
          }
        }
        NSLog(" - 通用: 成功構築辭典樹（反查表）。")
      }
      group.addTask { [self] in
        await withTaskGroup(of: [(VanguardTrie.Trie.Entry, [String])].self) { subGroup in
          subGroup.addTask {
            // 簡體中文
            await self.data.unigramsKanjiCHS.values.flatMap {
              $0.values.flatMap { $0.map { $0 } }
            }.compactMap { $0.asEntry(type: .chs) }
          }
          subGroup.addTask {
            await self.data.unigramsCHS.values.flatMap {
              $0.values.flatMap { $0.map { $0 } }
            }.compactMap { $0.asEntry(type: .chs) }
          }
          subGroup.addTask {
            // 繁體中文
            await self.data.unigramsKanjiCHT.values.flatMap {
              $0.values.flatMap { $0.map { $0 } }
            }.compactMap { $0.asEntry(type: .cht) }
          }
          subGroup.addTask {
            await self.data.unigramsCHT.values.flatMap {
              $0.values.flatMap { $0.map { $0 } }
            }.compactMap { $0.asEntry(type: .cht) }
          }
          subGroup.addTask {
            // 非漢字
            await self.data.unigrams4NonKanji.values.flatMap {
              $0.values.flatMap { $0.map { $0 } }
            }.compactMap { $0.asEntry(type: .nonKanji) }
          }
          subGroup.addTask {
            // 符號詞組
            await self.data.getSymbols().compactMap { $0.asEntry(type: .symbolPhrases) }
          }
          subGroup.addTask {
            // 注音文
            await self.data.getZhuyinwen().compactMap { $0.asEntry(type: .zhuyinwen) }
          }
          subGroup.addTask {
            // 字母與標點符號
            await self.data.getPunctuations().compactMap { $0.asEntry(type: .letterPunctuations) }
          }
          subGroup.addTask {
            // CNS 全字庫
            await self.data.tableKanjiCNS.values.flatMap { $0 }.compactMap { $0.asEntry(type: .cns) }
          }
          for await result in subGroup {
            for x in result {
              mutexTrie4Typing.withLock {
                $0.insert(entry: x.0, readingsEncrypted: x.1)
              }
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
  public typealias ChunkIterator = AsyncThrowingStream<BuildArtifactChunk, Error>

  public struct BuildArtifactChunk: Sendable {
    public let fileName: String
    public let data: Data
    public let isLastChunk: Bool
  }

  public protocol DataBuilderProtocol: Actor {
    init?(isCHS: Bool?) async throws
    var subFolderNameComponents: [String] { get }
    var subFolderNameComponentsAftermath: [String] { get }
    var isCHS: Bool? { get }
    var data: Collector { get }
    func getIteratorForLexiconAssemblyTask() async throws -> ChunkIterator
    func performPostCompilation() async throws
  }
}

extension VCDataBuilder.DataBuilderProtocol {
  public init?(isCHS: Bool? = nil) async throws {
    try await self.init(isCHS: isCHS)
  }

  @Sendable
  public func runInTextBlock(_ task: @Sendable () async -> ()) async {
    NSLog("===============================")
    NSLog("-------------------------------")
    defer {
      NSLog("-------------------------------")
      NSLog("===============================")
    }
    await task()
  }

  @Sendable
  public func runInTextBlockThrowable(_ task: @Sendable () async throws -> ()) async throws {
    NSLog("===============================")
    NSLog("-------------------------------")
    defer {
      NSLog("-------------------------------")
      NSLog("===============================")
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
        try await data.healthCheckPerMode(isCHS: lang).forEach { NSLog($0) }
      }
    }
  }

  public func writeAssembledAssets() async throws {
    let subFolderNameComponentsAftermath = subFolderNameComponentsAftermath
    // 必要時建立追加資料夾。
    aftermath: do {
      guard !subFolderNameComponentsAftermath.isEmpty else { break aftermath }
      var folderURLAftermath = FileManager.urlCurrentFolder
      if ProcessInfo.processInfo.environment["VANGUARD_OUTPUT_DIR"] == nil {
        folderURLAftermath.appendPathComponent("Build")
      }
      subFolderNameComponentsAftermath.forEach { currentComponentName in
        folderURLAftermath = folderURLAftermath.appendingPathComponent(currentComponentName)
      }
      try FileManager.default.createDirectory(
        at: folderURLAftermath,
        withIntermediateDirectories: true
      )
    }
    // 建立主資料夾。
    var folderURL = FileManager.urlCurrentFolder.appendingPathComponent("Build")
    subFolderNameComponents.forEach { currentComponentName in
      folderURL = folderURL.appendingPathComponent(currentComponentName)
    }
    // 開始組裝與輸出資料。
    NSLog(" - 通用: 開始生成最終輸出的 SQL / 二進位產物。")
    let assemblyStart = Date()
    let stream = try await getIteratorForLexiconAssemblyTask()

    try FileManager.default.createDirectory(
      at: folderURL,
      withIntermediateDirectories: true
    )

    var fileHandles = [String: FileHandle]()
    var bytesWritten = 0

    func makeFileHandle(for chunk: VCDataBuilder.BuildArtifactChunk) throws -> FileHandle {
      if let existed = fileHandles[chunk.fileName] {
        return existed
      }
      let fileURL = folderURL.appendingPathComponent(chunk.fileName)
      if FileManager.default.fileExists(atPath: fileURL.path) {
        try FileManager.default.removeItem(at: fileURL)
      }
      let fileCreated = FileManager.default.createFile(atPath: fileURL.path, contents: nil)
      guard fileCreated else {
        throw VCDataBuilder.Exception.errMsg(
          "Unable to create file at path: \(fileURL.path)"
        )
      }
      let fileHandle = try FileHandle(forWritingTo: fileURL)
      fileHandles[chunk.fileName] = fileHandle
      return fileHandle
    }

    do {
      for try await chunk in stream {
        let fileHandle = try makeFileHandle(for: chunk)
        if !chunk.data.isEmpty {
          fileHandle.write(chunk.data)
          bytesWritten += chunk.data.count
        }
        if chunk.isLastChunk {
          try fileHandle.close()
          fileHandles.removeValue(forKey: chunk.fileName)
        }
      }
      for handle in fileHandles.values {
        try handle.close()
      }
      fileHandles.removeAll()
    } catch {
      for handle in fileHandles.values {
        try? handle.close()
      }
      fileHandles.removeAll()
      throw error
    }

    NSLog(
      " - 通用: 完成生成輸出內容，耗時 %.2f 秒，累計寫入 %.2f MB。",
      Date().timeIntervalSince(assemblyStart),
      Double(bytesWritten) / 1_048_576.0
    )
    // 追加處理。
    NSLog(" - 準備執行追加建置過程。")
    NSLog(" - 通用: 所有前置作業已完成，開始進入後續辭典檔案建置階段。")
    try await runInTextBlockThrowable {
      try await performPostCompilation()
    }
    NSLog(" - 成功執行追加建置過程。")
  }

  func compileSQLite(fileNameStem: String, outputFileNameStem: String? = nil) async throws {
    let outputFileNameStem = outputFileNameStem ?? fileNameStem
    NSLog("   > 正在透過 SQLite C API 準備組裝 SQLite 資料庫……")

    let buildRoot = FileManager.urlCurrentFolder.appendingPathComponent("Build")
    let sqlFolderURL = subFolderNameComponents.reduce(buildRoot) { partial, component in
      partial.appendingPathComponent(component)
    }
    let sqlFileURL = sqlFolderURL.appendingPathComponent("\(fileNameStem).sql")

    var dbFolderURL = FileManager.urlCurrentFolder
    if ProcessInfo.processInfo.environment["VANGUARD_OUTPUT_DIR"] == nil {
      dbFolderURL.appendPathComponent("Build")
    }
    dbFolderURL = subFolderNameComponentsAftermath.reduce(dbFolderURL) { partial, component in
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
        NSLog("   > 已移除既有的資料庫檔案。")
      } catch {
        NSLog("   > 警告：無法移除既有的資料庫檔案：\(error)")
      }
    }

    var sqlData = try Data(contentsOf: sqlFileURL)
    if sqlData.starts(with: [0xEF, 0xBB, 0xBF]) {
      sqlData.removeFirst(3)
    }
    // sqlite3_exec 期望接收以 null 結尾的緩衝區。
    if sqlData.last != 0 {
      sqlData.append(0)
    }

    NSLog("   > 正在開啟位於 \(dbFileURL.path) 的 SQLite 資料庫。")

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
        NSLog("   > 警告：sqlite3_close 傳回錯誤：\(closeMessage)")
      }
    }

    NSLog("   > 正在透過 SQLite C API 執行 SQL 指令稿……")

    var errorMessagePointer: UnsafeMutablePointer<CChar>?
    let execResult = sqlData.withUnsafeBytes { rawBuffer -> Int32 in
      let buffer = rawBuffer.bindMemory(to: CChar.self)
      guard let baseAddress = buffer.baseAddress else { return SQLITE_OK }
      return sqlite3_exec(db, baseAddress, nil, nil, &errorMessagePointer)
    }

    if execResult != SQLITE_OK {
      let message = errorMessagePointer.map { String(cString: $0) }
        ?? String(cString: sqlite3_errmsg(db))
      if let errorMessagePointer {
        sqlite3_free(errorMessagePointer)
      }
      throw VCDataBuilder.Exception
        .errMsg("SQLite execution failed (code \(execResult)): \(message)")
    }

    if let errorMessagePointer {
      sqlite3_free(errorMessagePointer)
    }

    NSLog("   > 已完成 SQL 指令稿的執行。")

    if !FileManager.default.fileExists(atPath: dbFileURL.path) {
      throw VCDataBuilder.Exception
        .errMsg("Database file was not created at path: \(dbFileURL.path)")
    }

    NSLog("   > 已成功在 \(dbFileURL.path) 建立 SQLite 資料庫。")
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
      cachedEnvironment["VANGUARD_CORPUS_BUILD_MODE"] == "SMALL_TESTABLE_SAMPLE"
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

    private static let cachedEnvironment: [String: String] = ProcessInfo.processInfo.environment

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
