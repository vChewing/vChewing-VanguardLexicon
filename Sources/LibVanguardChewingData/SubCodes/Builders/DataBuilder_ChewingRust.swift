// (c) 2021 and onwards The vChewing Project (BSD-3-Clause).
// ====================
// This code is released under the SPDX-License-Identifier: `BSD-3-Clause`.

import Foundation

// MARK: - VCDataBuilder.ChewingRustDataBuilder

extension VCDataBuilder {
  public actor ChewingRustDataBuilder: DataBuilderProtocol {
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

extension VCDataBuilder.ChewingRustDataBuilder {
  nonisolated public var langSuffix: String {
    (isCHS ?? true) ? "chs" : "cht" // 這個 variable 在這個 Actor 內永遠都不可能是 nil。
  }

  nonisolated public var subFolderNameComponents: [String] {
    ["Intermediate", "chewing-rust-\(langSuffix)"]
  }

  nonisolated public var subFolderNameComponentsAftermath: [String] {
    ["Release", "chewing-rust-\(langSuffix)"]
  }

  public func getIteratorForLexiconAssemblyTask() async throws -> VCDataBuilder.ChunkIterator {
    /// 新酷音輸入法在建置 dat 時會自行健檢，所以這裡略過健檢步驟。
    var tsiSRC = [String]()
    var wordSRC = [String]()
    var grams = await data.getAllUnigrams(isCHS: isCHS, sorted: false)
    grams = grams.sorted { lhs, rhs -> Bool in
      (lhs.key, rhs.count, lhs.timestamp) < (rhs.key, lhs.count, rhs.timestamp)
    }
    grams.forEach { gram in
      let keyCells = gram.keyCells
      guard keyCells.count == gram.value.count else { return }
      tsiSRC.append("\(gram.value) \(gram.count) \(keyCells.joined(separator: " "))\n")
      if keyCells.count == 1 {
        wordSRC.append("\(gram.value) \(gram.count) \(gram.key)\n")
      }
    }
    let dataTsiSRC = tsiSRC.joined().data(using: .utf8)
    let dataWordSRC = wordSRC.joined().data(using: .utf8)
    guard let dataTsiSRC, let dataWordSRC else {
      throw VCDataBuilder.Exception.errMsg("Data encoding failed on assembling for ChewingRust.")
    }
    return AsyncThrowingStream { continuation in
      continuation.yield(.init(fileName: "tsi.src", data: dataTsiSRC, isLastChunk: true))
      continuation.yield(.init(fileName: "word.src", data: dataWordSRC, isLastChunk: true))
      continuation.finish()
    }
  }

  public func performPostCompilation() async throws {
    print("Locating Rust and Cargo executables...")

    // 尋找 cargo 位置
    #if os(Windows)
      // 優先使用 findExecutable 而非執行 shell 腳本來尋找 cargo。
      var cargoLocationResult: (output: String, exitCode: Int32) = ("", 1)
      if let cargoFound = ShellHelper.findExecutable("cargo", path: ProcessInfo.processInfo.environment["PATH"]) {
        cargoLocationResult = (cargoFound + "\n", 0)
      }
      // 如果在 PATH 中找不到，則後備檢查常見安裝位置
      if cargoLocationResult.exitCode != 0 {
        let possiblePaths = [
          "\(ProcessInfo.processInfo.environment["USERPROFILE"] ?? "")\\.cargo\\bin\\cargo.exe",
          "C:\\Program Files\\.cargo\\bin\\cargo.exe",
        ]
        for p in possiblePaths {
          if FileManager.default.fileExists(atPath: p) {
            cargoLocationResult = (p + "\n", 0)
            break
          }
        }
      }
    #else
      let cargoFound = ShellHelper.findExecutable("cargo", path: ProcessInfo.processInfo.environment["PATH"])
      var cargoLocationResult: (output: String, exitCode: Int32)
      if let cargoFound {
        cargoLocationResult = (cargoFound + "\n", 0)
      } else {
        cargoLocationResult = ShellHelper.exec("/usr/bin/which", args: ["cargo"]) // 後備方案
      }
    #endif

    if cargoLocationResult.exitCode != 0 || cargoLocationResult.output
      .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      throw VCDataBuilder.Exception
        .errMsg("Cargo not found in PATH. Please make sure Rust and Cargo are properly installed.")
    }

    // 提取 cargo 路徑及其目錄
    #if os(Windows)
      let cargoPath = cargoLocationResult.output.trimmingCharacters(in: .whitespacesAndNewlines)
      let cargoDir = URL(fileURLWithPath: cargoPath).deletingLastPathComponent().path
    #else
      let cargoPath = cargoLocationResult.output.trimmingCharacters(in: .whitespacesAndNewlines)
      let cargoDir = URL(fileURLWithPath: cargoPath).deletingLastPathComponent().path
    #endif

    // 將 cargo 目錄加入目前的 PATH
    #if os(Windows)
      let originalPath = ProcessInfo.processInfo.environment["PATH"] ?? ""
      let updatedPath = "\(cargoDir);\(originalPath)"
    #else
      let originalPath = ProcessInfo.processInfo.environment["PATH"] ?? ""
      let updatedPath = "\(cargoDir):\(originalPath)"
    #endif

    print("Found Cargo at: \(cargoPath)")
    print("Added \(cargoDir) to PATH")

    // 檢查 rustc 版本
    #if os(Windows)
      let rustcPath = ShellHelper.findExecutable("rustc", path: updatedPath) ?? "rustc"
      let rustVersionCheck = ShellHelper.exec(rustcPath, args: ["--version"], path: updatedPath)
    #else
      let rustcPath = ShellHelper.findExecutable("rustc", path: updatedPath) ?? "rustc"
      let rustVersionCheck = ShellHelper.exec(rustcPath, args: ["--version"], path: updatedPath)
    #endif

    if rustVersionCheck.exitCode != 0 {
      throw VCDataBuilder.Exception.errMsg("Rust is not installed or not found in PATH.")
    }

    // 從 rustc 輸出中提取版本號碼
    let rustVersionOutput = rustVersionCheck.output.trimmingCharacters(in: .whitespacesAndNewlines)
    let versionRegex = try NSRegularExpression(pattern: "rustc (\\d+\\.\\d+\\.\\d+)")
    let outputRange = NSRange(
      rustVersionOutput.startIndex ..< rustVersionOutput.endIndex,
      in: rustVersionOutput
    )
    guard let match = versionRegex.firstMatch(in: rustVersionOutput, range: outputRange),
          let versionRange = Range(match.range(at: 1), in: rustVersionOutput) else {
      throw VCDataBuilder.Exception
        .errMsg("Could not parse Rust version from output: \(rustVersionOutput)")
    }

    let rustVersion = String(rustVersionOutput[versionRange])
    let minimumVersion = "1.83.0"

    if ShellHelper.compareVersions(rustVersion, minimumVersion) == .orderedAscending {
      throw VCDataBuilder.Exception
        .errMsg("Rust version must be at least \(minimumVersion). Found: \(rustVersion)")
    }

    print("Rust v\(rustVersion) (>= \(minimumVersion)) and Cargo are installed.")

    // 初始化後續命令將使用的 path 變數
    var pathToUse = updatedPath

    // 檢查 chewing-cli 是否已安裝
    print("Checking if chewing-cli is installed...")
    #if os(Windows)
      let chewingCliPath = "C:\\Program Files (x86)\\ChewingTextService\\chewing-cli.exe"
      if !FileManager.default.fileExists(atPath: chewingCliPath) {
        throw VCDataBuilder.Exception.errMsg("""
        chewing-cli not found at \(chewingCliPath).
        Please install TSF version of Chewing Input Method first.
        Download from: https://github.com/chewing/windows-chewing-tsf/releases
        """)
      }
      print("Found chewing-cli at: \(chewingCliPath)")
    #else
      let chewingCliFound = ShellHelper.findExecutable("chewing-cli", path: pathToUse)
      var chewingCliCheck: (output: String, exitCode: Int32)
      if let chewingCliFound {
        chewingCliCheck = (chewingCliFound + "\n", 0)
      } else {
        chewingCliCheck = ShellHelper.exec("/usr/bin/which", args: ["chewing-cli"], path: pathToUse)
      }
      if chewingCliCheck.exitCode != 0 || chewingCliCheck.output
        .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        print("chewing-cli is not installed. Attempting to install...")
        let cargoBinDir = "\(ProcessInfo.processInfo.environment["HOME"] ?? ".")/cargo/bin"

        // 取得 cargo 安裝目錄
        let cargoInstallResult = ShellHelper.exec("cargo", args: ["install", "--list"], path: pathToUse)
        print("Cargo install location check: \(cargoInstallResult.output)")

        // 安裝 chewing-cli
        let installResult = ShellHelper.exec("cargo", args: ["install", "chewing-cli"], path: pathToUse)
        if installResult.exitCode != 0 {
          throw VCDataBuilder.Exception
            .errMsg("Failed to install chewing-cli:\n\(installResult.output)")
        }

        pathToUse = "\(pathToUse):\(cargoBinDir)"

        print("Added cargo bin directory to PATH: \(cargoBinDir)")

        print("chewing-cli has been successfully installed.")
      } else {
        print(
          "chewing-cli is already installed at: \(chewingCliCheck.output.trimmingCharacters(in: .whitespacesAndNewlines))"
        )
      }
    #endif

    // 執行 chewing-cli 命令
    print("Running chewing-cli commands...")

    let pathStemTemp = ShellHelper.normalizePathForCurrentOS(
      "./Build/" + subFolderNameComponents.joined(separator: "/")
    )
    let pathStemFinal = ShellHelper.normalizePathForCurrentOS(
      "./Build/" + subFolderNameComponentsAftermath.joined(separator: "/")
    )

    // 修正跨平台命令
    #if os(Windows)
      // 直接使用 exec 呼叫 chewing-cli，並使用 FileManager 建立輸出目錄
      do {
        try FileManager.default.createDirectory(atPath: pathStemFinal, withIntermediateDirectories: true)
      } catch {
        throw VCDataBuilder.Exception
          .errMsg("Failed to create directory for chewing-cli output: \(error.localizedDescription)")
      }
    #else
      let firstCommand =
        "chewing-cli init-database -t trie \"\(pathStemTemp)/tsi.src\" \"\(pathStemFinal)/tsi.dat\""
      let secondCommand =
        "chewing-cli init-database -t trie \"\(pathStemTemp)/word.src\" \"\(pathStemFinal)/word.dat\""
    #endif

    print("Executing chewing-cli init-database for tsi.src -> tsi.dat")
    #if os(Windows)
      let firstArgs = ["init-database", "-t", "trie", "\(pathStemTemp)\\tsi.src", "\(pathStemFinal)\\tsi.dat"]
      let firstResult = ShellHelper.exec(chewingCliPath, args: firstArgs, path: updatedPath)
    #else
      let firstExecPath = ShellHelper.findExecutable("chewing-cli", path: pathToUse) ?? "chewing-cli"
      let firstArgs = ["init-database", "-t", "trie", "\(pathStemTemp)/tsi.src", "\(pathStemFinal)/tsi.dat"]
      let firstResult = ShellHelper.exec(firstExecPath, args: firstArgs, path: pathToUse)
    #endif
    if firstResult.exitCode != 0 {
      print("Command failed with error:")
      print(firstResult.output)
      // 我們不在此退出，繼續執行下一個命令
    } else {
      print("First command executed successfully.")
    }

    print("Executing chewing-cli init-database for word.src -> word.dat")
    #if os(Windows)
      let secondArgs = ["init-database", "-t", "trie", "\(pathStemTemp)\\word.src", "\(pathStemFinal)\\word.dat"]
      let secondResult = ShellHelper.exec(chewingCliPath, args: secondArgs, path: updatedPath)
    #else
      let secondExecPath = ShellHelper.findExecutable("chewing-cli", path: pathToUse) ?? "chewing-cli"
      let secondArgs = ["init-database", "-t", "trie", "\(pathStemTemp)/word.src", "\(pathStemFinal)/word.dat"]
      let secondResult = ShellHelper.exec(secondExecPath, args: secondArgs, path: pathToUse)
    #endif
    if secondResult.exitCode != 0 {
      print("Command failed with error:")
      print(secondResult.output)
      // 我們繼續回報任何錯誤，但不退出
    } else {
      print("Second command executed successfully.")
    }

    // 檢查是否有任何命令失敗
    if firstResult.exitCode != 0 || secondResult.exitCode != 0 {
      throw VCDataBuilder.Exception.errMsg("One or more chewing-cli commands failed.")
    } else {
      print("All operations completed successfully.")
    }
  }
}
