// (c) 2021 and onwards The vChewing Project (BSD-3-Clause).
// ====================
// This code is released under the SPDX-License-Identifier: `BSD-3-Clause`.

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
    guard !keyShouldGetFiltered(key) else { return nil }
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
    var trie4TypingBasic: VanguardTrie.Trie { get }
    var trie4TypingCNS: VanguardTrie.Trie { get }
    var trie4TypingMisc: VanguardTrie.Trie { get }
    var trie4Rev: VanguardTrie.Trie { get }
  }
}

extension VCDataBuilder.TriePreparatorProtocol {
  public func prepareTrie() async {
    NSLog(" - 通用: 正在構築字典樹。")
    trie4TypingBasic.clearAllContents()
    trie4TypingCNS.clearAllContents()
    trie4TypingMisc.clearAllContents()
    trie4Rev.clearAllContents()

    let normEntryKey = "_NORM"
    let normEntry = VanguardTrie.Trie.Entry(
      value: normEntryKey,
      typeID: .meta,
      probability: data.norm,
      previous: nil
    )
    trie4TypingBasic.insert(entry: normEntry, readings: [normEntryKey])
    trie4TypingCNS.insert(entry: normEntry, readings: [normEntryKey])
    trie4TypingMisc.insert(entry: normEntry, readings: [normEntryKey])

    let dateEntryKey = "_BUILD_TIMESTAMP"
    let dateEntry = VanguardTrie.Trie.Entry(
      value: dateEntryKey,
      typeID: .meta,
      probability: Date().timeIntervalSince1970,
      previous: nil
    )
    trie4TypingBasic.insert(entry: dateEntry, readings: [dateEntryKey])
    trie4TypingCNS.insert(entry: normEntry, readings: [dateEntryKey])
    trie4TypingMisc.insert(entry: dateEntry, readings: [dateEntryKey])
    trie4Rev.insert(entry: dateEntry, readings: [dateEntryKey])

    await withTaskGroup(of: Void.self) { group in
      group.addTask { [self] in
        // revLookup
        var allKeys = Set<String>()
        data.reverseLookupTable.keys.forEach { allKeys.insert($0) }
        data.reverseLookupTable4NonKanji.keys.forEach { allKeys.insert($0) }
        data.reverseLookupTable4CNS.keys.forEach { allKeys.insert($0) }
        var allKeysToHandle = allKeys.sorted()
        if isTestSampleMode {
          allKeysToHandle = Array(allKeysToHandle.prefix(10))
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
        NSLog(" - 通用: 成功構築字典樹（反查表）。")
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
          for await result in subGroup {
            result.forEach {
              trie4TypingBasic.insert(entry: $0.0, readingsEncrypted: $0.1)
            }
          }
        }
        NSLog(" - 通用: 成功構築字典樹（通用表）。")
      }
      group.addTask { [self] in
        await withTaskGroup(of: [(VanguardTrie.Trie.Entry, [String])].self) { subGroup in
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
          for await result in subGroup {
            result.forEach {
              trie4TypingMisc.insert(entry: $0.0, readingsEncrypted: $0.1)
            }
          }
        }
      }
      group.addTask { [self] in
        await withTaskGroup(of: [(VanguardTrie.Trie.Entry, [String])].self) { subGroup in
          subGroup.addTask {
            // cns
            self.data.tableKanjiCNS.values.flatMap { $0 }.compactMap { $0.asEntry(type: .cns) }
          }
          for await result in subGroup {
            result.forEach {
              trie4TypingCNS.insert(entry: $0.0, readingsEncrypted: $0.1)
            }
          }
        }
      }
      await group.waitForAll()
      NSLog(" - 通用: 成功構築所有的字典樹。")
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
    // Check if sqlite3 is installed
    print("Checking for SQLite3 installation...")
    #if os(Windows)
      // Windows 的 SQLite3 檢查命令改用更可靠的方式
      let sqliteCheck = ShellHelper.shell("""
      $sqlitePath = $null
      if (Test-Path 'C:\\Program Files\\SQLite') {
        $sqlitePath = Get-ChildItem 'C:\\Program Files\\SQLite' -Recurse -Filter 'sqlite3.exe' | Select-Object -First 1 -ExpandProperty FullName
      }
      if (-not $sqlitePath) {
        if (Test-Path 'C:\\sqlite') {
          $sqlitePath = Get-ChildItem 'C:\\sqlite' -Recurse -Filter 'sqlite3.exe' | Select-Object -First 1 -ExpandProperty FullName
        }
      }
      if (-not $sqlitePath) {
        $sqlitePath = (Get-Command sqlite3 -ErrorAction SilentlyContinue).Path
      }
      if ($sqlitePath) {
        Write-Output $sqlitePath
        exit 0
      } else {
        exit 1
      }
      """)
    #else
      let sqliteCheck = ShellHelper.shell("which sqlite3")
    #endif

    if sqliteCheck.exitCode != 0 || sqliteCheck.output
      .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      throw VCDataBuilder.Exception
        .errMsg("""
        SQLite3 is not installed or not found in PATH.
        Please install SQLite3 and ensure it's in one of these locations:
        - C:\\Program Files\\SQLite
        - C:\\sqlite
        - Or add it to your system PATH
        """)
    }

    // Get the path to sqlite3 executable
    let sqlite3Path = sqliteCheck.output.trimmingCharacters(in: .whitespacesAndNewlines)

    print("Found SQLite3 at: \(sqlite3Path)")

    // 處理檔案路徑
    let sqlFilePath = ShellHelper.normalizePathForCurrentOS(
      "./Build/\(subFolderNameComponents.joined(separator: "/"))/\(fileNameStem).sql"
    )
    let dbFilePath = ShellHelper.normalizePathForCurrentOS(
      "./Build/\(subFolderNameComponentsAftermath.joined(separator: "/"))/\(outputFileNameStem).sqlite"
    )
    let dbDirectory = URL(fileURLWithPath: dbFilePath).deletingLastPathComponent().path

    // 先刪除現有的資料庫檔案以確保適當重建
    print("Removing any existing database file...")
    #if os(Windows)
      let removeCommand = "if (Test-Path '\(dbFilePath)') { Remove-Item -Force '\(dbFilePath)' }"
      let removeResult = ShellHelper.shell(removeCommand)
      if removeResult.exitCode != 0 {
        print("Warning: Failed to remove existing database file: \(removeResult.output)")
      }
    #else
      if FileManager.default.fileExists(atPath: dbFilePath) {
        do {
          try FileManager.default.removeItem(atPath: dbFilePath)
          print("Existing database file removed.")
        } catch {
          print("Warning: Failed to remove existing database file: \(error)")
        }
      }
    #endif

    // 建立目錄（Windows 專用命令）
    #if os(Windows)
      let createDirCommand = "New-Item -ItemType Directory -Force -Path '" + dbDirectory + "'"
      let createDirResult = ShellHelper.shell(createDirCommand)
      if createDirResult.exitCode != 0 {
        throw VCDataBuilder.Exception
          .errMsg("Failed to create directory: \(createDirResult.output)")
      }

      // Windows 的 SQLite 命令，改用 UTF-8 編碼處理
      let command = """
      $OutputEncoding = [Console]::OutputEncoding = [Text.Encoding]::UTF8;
      $sqlContent = Get-Content -Raw -Encoding UTF8 '\(sqlFilePath)';
      [System.IO.File]::WriteAllText('temp.sql', $sqlContent, [System.Text.Encoding]::UTF8);
      New-Item -ItemType Directory -Force -Path '\(dbDirectory)' | Out-Null;
      & '\(sqlite3Path)' '\(dbFilePath)' '.read temp.sql';
      if (Test-Path '\(dbFilePath)') {
          Remove-Item 'temp.sql' -Force;
          exit 0;
      } else {
          Remove-Item 'temp.sql' -Force;
          exit 1;
      }
      """
    #else
      try FileManager.default.createDirectory(
        atPath: dbDirectory,
        withIntermediateDirectories: true,
        attributes: nil
      )

      // Unix 的 SQLite 命令
      let command = "\(sqlite3Path) \"\(dbFilePath)\" < \"\(sqlFilePath)\""
    #endif

    print("Executing: \(command)")

    let result = ShellHelper.shell(command)
    if result.exitCode != 0 {
      throw VCDataBuilder.Exception
        .errMsg("Failed to initialize Vanguard database:\n\(result.output)")
    }

    // Verify the database was created
    if !FileManager.default.fileExists(atPath: dbFilePath) {
      throw VCDataBuilder.Exception.errMsg("Database file was not created at path: \(dbFilePath)")
    }

    print("Successfully created SQLite database at: \(dbFilePath)")
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

// MARK: - Key filters for making small testable samples.

private func keyShouldGetFiltered(_ target: String) -> Bool {
  guard isTestSampleMode else { return false }
  return if target.hasPrefix("_") {
    target.hasPrefix("_punctuation_list")
  } else {
    !whitelistedReadingsForUnitTests.contains(target)
  }
}

private var isTestSampleMode: Bool {
  ProcessInfo.processInfo.environment["VANGUARD_CORPUS_BUILD_MODE"] == "SMALL_TESTABLE_SAMPLE"
}

private let whitelistedReadingsForUnitTests: Set<String> = [
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
]
