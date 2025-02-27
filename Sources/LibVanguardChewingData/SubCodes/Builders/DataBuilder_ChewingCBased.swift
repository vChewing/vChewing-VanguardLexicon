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

    // MARK: Internal

    let data: Collector
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

  public func assemble() async throws -> [String: String] {
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
    return [
      "tsi.src": tsiSRC.joined(),
      "phone.cin": charDef.joined(),
    ]
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

    // Execute the command
    #if os(Windows)
      // 修正 PowerShell 命令格式
      let phoneCinPath = pathStemTemp + "\\phone.cin"
      let tsiSrcPath = pathStemTemp + "\\tsi.src"
      let command = "Start-Process -FilePath '" + executablePath + "' -ArgumentList '" +
        phoneCinPath + "','" + tsiSrcPath + "' -NoNewWindow -Wait"
    #else
      let command =
        "\"\(executablePath)\" \"\(pathStemTemp)/phone.cin\" \"\(pathStemTemp)/tsi.src\""
    #endif

    print("Executing: \(command)")

    let result = ShellHelper.shell(command)
    if result.exitCode != 0 {
      throw VCDataBuilder.Exception.errMsg(
        "Failed to initialize database:\n\(result.output)"
      )
    }

    // Move the generated files to the appropriate directory
    #if os(Windows)
      // 修正 PowerShell 移動文件命令
      let moveCommand = "if (Test-Path '.\\index_tree.dat','.\\dictionary.dat') { " +
        "New-Item -ItemType Directory -Force -Path '" + pathStemFinal + "'; " +
        "Move-Item -Force -Path '.\\index_tree.dat','.\\dictionary.dat' -Destination '" +
        pathStemFinal + "' }"
    #else
      let moveCommand = "mv -f \"./index_tree.dat\" \"./dictionary.dat\" \"\(pathStemFinal)/\""
    #endif

    print("Executing: \(moveCommand)")

    let moveResult = ShellHelper.shell(moveCommand)
    if moveResult.exitCode != 0 {
      throw VCDataBuilder.Exception.errMsg(
        "Failed to move generated files:\n\(moveResult.output)"
      )
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
  /// Returns the path to the appropriate executable based on the operating system
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
