// (c) 2021 and onwards The vChewing Project (BSD-3-Clause).
// ====================
// This code is released under the SPDX-License-Identifier: `BSD-3-Clause`.

import Foundation

// MARK: - VCDataBuilder.ChewingCBasedDataBuilder

extension VCDataBuilder {
  public actor ChewingCBasedDataBuilder: DataBuilderProtocol {
    // MARK: Lifecycle

    public init?(isCHS: Bool?) async throws {
      guard let isCHS else { return nil }
      self.isCHS = isCHS
      // 新酷音因為有 Windows 版的緣故，所以需要相容模式。
      // Windows 不是所有軟體都有支援高萬字。
      self.data = try Collector(isCHS: isCHS, compatibleMode: true)
    }

    // MARK: Public

    nonisolated public let isCHS: Bool?

    public let data: Collector
  }
}

extension VCDataBuilder.ChewingCBasedDataBuilder {
  nonisolated public var langSuffix: String {
    (isCHS ?? true) ? "chs" : "cht" // 這個 variable 在這個 Actor 內永遠都不可能是 nil。
  }

  nonisolated public var subFolderNameComponents: [String] {
    ["Intermediate", "chewing-cbased-\(langSuffix)"]
  }

  nonisolated public var subFolderNameComponentsAftermath: [String] {
    ["Release", "chewing-cbased-\(langSuffix)"]
  }

  public func getIteratorForLexiconAssemblyTask() async throws -> VCDataBuilder.ChunkIterator {
    /// 新酷音輸入法在建置 dat 時會自行健檢，所以這裡略過健檢步驟。
    var tsiSRC = [String]()
    var charDef = [String]()
    var grams = await data.getAllUnigrams(isCHS: isCHS, sorted: false)
    grams = grams.sorted { lhs, rhs -> Bool in
      (lhs.key, rhs.count, lhs.timestamp) < (rhs.key, lhs.count, rhs.timestamp)
    }
    grams.forEach { gram in
      let keyCells = gram.keyCells
      guard keyCells.count == gram.value.count else { return }
      tsiSRC.append("\(gram.value) \(gram.count) \(keyCells.joined(separator: " "))\n")
      if keyCells.count == 1 {
        charDef.append(
          "\(gram.key.asBopomofo2Dachien) \(gram.value)\n"
        )
      }
    }
    charDef.append("%chardef  end\n")
    charDef.insert(Self.getPhoneCINHeader(), at: 0)
    let dataTsiSRC = tsiSRC.joined().data(using: .utf8)
    let dataCharDef = charDef.joined().data(using: .utf8)
    guard let dataTsiSRC, let dataCharDef else {
      throw VCDataBuilder.Exception.errMsg("Data encoding failed on assembling for ChewingCBased.")
    }
    return AsyncThrowingStream { continuation in
      continuation.yield(.init(fileName: "tsi.src", data: dataTsiSRC, isLastChunk: true))
      continuation.yield(.init(fileName: "phone.cin", data: dataCharDef, isLastChunk: true))
      continuation.finish()
    }
  }

  public func performPostCompilation() async throws {
    guard let executablePathFetched = Self.getExecutablePath() else {
      throw VCDataBuilder.Exception.errMsg(
        "Unable to determine executable path for this operating system."
      )
    }

    let executablePath = ShellHelper.normalizePathForCurrentOS(executablePathFetched)
    let pathStemTemp = ShellHelper.normalizePathForCurrentOS(
      "./Build/" + subFolderNameComponents.joined(separator: "/")
    )
    let pathStemFinal = ShellHelper.normalizePathForCurrentOS(
      "./Build/" + subFolderNameComponentsAftermath.joined(separator: "/")
    )

    // 儘可能使用 `exec` 執行命令以避免 shell 解析。
    #if os(Windows)
      // 對於 Windows，避免使用 shell 字串建構，直接執行二進位檔案並傳遞引數。
      // 為 Windows 路徑分隔符號正規化路徑。
      let phoneCinPath = pathStemTemp + "\\phone.cin"
      let tsiSrcPath = pathStemTemp + "\\tsi.src"
      let args = [phoneCinPath, tsiSrcPath]
      print("Executing: \(executablePath) \(args.joined(separator: " "))")
      let result = ShellHelper.exec(executablePath, args: args)
    #else
      let args = ["\(pathStemTemp)/phone.cin", "\(pathStemTemp)/tsi.src"]
      print("Executing: \(executablePath) \(args.joined(separator: " "))")
      let result = ShellHelper.exec(executablePath, args: args)
    #endif
    if result.exitCode != 0 {
      throw VCDataBuilder.Exception.errMsg(
        "Failed to initialize database:\n\(result.output)"
      )
    }

    // 使用 FileManager 將產生的檔案移動至適當目錄
    do {
      try FileManager.default.createDirectory(atPath: pathStemFinal, withIntermediateDirectories: true)
      let filesToMove = ["index_tree.dat", "dictionary.dat"]
      for f in filesToMove {
        let src = FileManager.default.currentDirectoryPath + "/" + f
        let dst = pathStemFinal + "/" + f
        if FileManager.default.fileExists(atPath: src) {
          if FileManager.default.fileExists(atPath: dst) {
            try FileManager.default.removeItem(atPath: dst)
          }
          try FileManager.default.moveItem(atPath: src, toPath: dst)
        }
      }
    } catch {
      throw VCDataBuilder.Exception.errMsg("Failed to move generated files: \(error.localizedDescription)")
    }

    print("Database initialization successfully for C-Based Chewing.")
  }
}

// MARK: - BPMF to Dachen Converter

extension String {
  fileprivate static let bpmfReplacements: [Character: Character] = [
    "ㄝ": ",", "ㄦ": "-", "ㄡ": ".", "ㄥ": "/", "ㄢ": "0",
    "ㄅ": "1", "ㄉ": "2", "ˇ": "3", "ˋ": "4", "ㄓ": "5",
    "ˊ": "6", "˙": "7", "ㄚ": "8", "ㄞ": "9", "ㄤ": ";",
    "ㄇ": "a", "ㄖ": "b", "ㄏ": "c", "ㄎ": "d", "ㄍ": "e",
    "ㄑ": "f", "ㄕ": "g", "ㄘ": "h", "ㄛ": "i", "ㄨ": "j",
    "ㄜ": "k", "ㄠ": "l", "ㄩ": "m", "ㄙ": "n", "ㄟ": "o",
    "ㄣ": "p", "ㄆ": "q", "ㄐ": "r", "ㄋ": "s", "ㄔ": "t",
    "ㄧ": "u", "ㄒ": "v", "ㄊ": "w", "ㄌ": "x", "ㄗ": "y",
    "ㄈ": "z",
  ]

  fileprivate var asBopomofo2Dachien: String {
    String(map { Self.bpmfReplacements[$0] ?? $0 })
  }
}

// MARK: - Phone.cin Header

extension VCDataBuilder.ChewingCBasedDataBuilder {
  fileprivate static func getPhoneCINHeader() -> String {
    let fileNameStem = "phone-header"
    let fileURL = Bundle.module.url(forResource: fileNameStem, withExtension: "txt")
    guard let fileURL else { return "" }
    let dataStr = try? String(contentsOf: fileURL, encoding: .utf8)
    guard let dataStr else { return "" }
    return dataStr
  }
}

// MARK: - Aftermath

extension VCDataBuilder.ChewingCBasedDataBuilder {
  /// 根據作業系統返回適當的可執行檔案路徑
  fileprivate static func getExecutablePath() -> String? {
    #if canImport(Darwin)
      return "./bin/libchewing-database-initializer/init_database_macos_universal"
    #elseif canImport(Glibc)
      return "./bin/libchewing-database-initializer/init_database_linux_amd64"
    #elseif os(Windows)
      return "./bin/libchewing-database-initializer/init_database_winnt_amd64.exe"
    #else
      return .none
    #endif
  }
}
