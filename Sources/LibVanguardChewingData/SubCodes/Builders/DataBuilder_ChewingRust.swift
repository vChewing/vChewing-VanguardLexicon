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

    // MARK: Internal

    let data: Collector
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

  public func assemble() async throws -> [String: String] {
    let tsiSRC = NSMutableString(string: "")
    let wordSRC = NSMutableString(string: "")
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
    return [
      "tsi.src": String(tsiSRC),
      "word.src": String(wordSRC),
    ]
  }

  public func performPostCompilation() async throws {
    print("Locating Rust and Cargo executables...")

    // Find the location of cargo using 'which'
    let cargoLocationResult = ShellHelper.shell("which cargo")
    if cargoLocationResult.exitCode != 0 || cargoLocationResult.output
      .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      throw VCDataBuilder.Exception
        .errMsg("Cargo not found in PATH. Please make sure Rust and Cargo are properly installed.")
    }

    // Extract cargo path and its directory
    let cargoPath = cargoLocationResult.output.trimmingCharacters(in: .whitespacesAndNewlines)
    let cargoDir = URL(fileURLWithPath: cargoPath).deletingLastPathComponent().path

    // Add cargo directory to current PATH
    let originalPath = ProcessInfo.processInfo.environment["PATH"] ?? ""
    let updatedPath = "\(cargoDir):\(originalPath)"

    print("Found Cargo at: \(cargoPath)")
    print("Added \(cargoDir) to PATH")

    // Check if rustc is installed and version is at least 1.83.0
    let rustVersionCheck = ShellHelper.shellWithPath("rustc --version", path: updatedPath)
    if rustVersionCheck.exitCode != 0 {
      throw VCDataBuilder.Exception.errMsg("Rust is not installed or not found in PATH.")
    }

    // Extract version number from rustc output
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

    // Initialize path variable that will be used for subsequent commands
    var pathToUse = updatedPath

    // Check if chewing-cli is installed
    print("Checking if chewing-cli is installed...")
    let chewingCliCheck = ShellHelper.shellWithPath("which chewing-cli", path: pathToUse)

    if chewingCliCheck.exitCode != 0 || chewingCliCheck.output
      .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      print("chewing-cli is not installed. Attempting to install...")

      // Get the cargo bin directory (where binaries are installed)
      let cargoBinDir = "\(ProcessInfo.processInfo.environment["HOME"] ?? ".")/cargo/bin"

      // Get the cargo installation directory
      let cargoInstallResult = ShellHelper.shellWithPath(
        "cargo install --list",
        path: pathToUse
      )
      print("Cargo install location check: \(cargoInstallResult.output)")

      // Install chewing-cli
      let installResult = ShellHelper.shellWithPath(
        "cargo install chewing-cli",
        path: pathToUse
      )
      if installResult.exitCode != 0 {
        throw VCDataBuilder.Exception
          .errMsg("Failed to install chewing-cli:\n\(installResult.output)")
      }

      // Update PATH to include the cargo bin directory
      pathToUse = "\(pathToUse):\(cargoBinDir)"
      print("Added cargo bin directory to PATH: \(cargoBinDir)")

      print("chewing-cli has been successfully installed.")
    } else {
      print(
        "chewing-cli is already installed at: \(chewingCliCheck.output.trimmingCharacters(in: .whitespacesAndNewlines))"
      )
    }

    // Run the chewing-cli commands
    print("Running chewing-cli commands...")

    let pathStemTemp = "./Build/" + subFolderNameComponents.joined(separator: "/")
    let pathStemFinal = "./Build/" + subFolderNameComponentsAftermath.joined(separator: "/")

    // First command
    let firstCommand =
      "chewing-cli init-database -t trie \(pathStemTemp)/tsi.src \(pathStemFinal)/tsi.dat"
    print("Executing: \(firstCommand)")
    let firstResult = ShellHelper.shellWithPath(firstCommand, path: pathToUse)
    if firstResult.exitCode != 0 {
      print("Command failed with error:")
      print(firstResult.output)
      // We don't exit here, we continue to the next command
    } else {
      print("First command executed successfully.")
    }

    // Second command
    let secondCommand =
      "chewing-cli init-database -t trie \(pathStemTemp)/word.src \(pathStemFinal)/word.dat"
    print("Executing: \(secondCommand)")
    let secondResult = ShellHelper.shellWithPath(secondCommand, path: pathToUse)
    if secondResult.exitCode != 0 {
      print("Command failed with error:")
      print(secondResult.output)
      // We continue to report any error but don't exit
    } else {
      print("Second command executed successfully.")
    }

    // Check if any command failed
    if firstResult.exitCode != 0 || secondResult.exitCode != 0 {
      throw VCDataBuilder.Exception.errMsg("One or more chewing-cli commands failed.")
    } else {
      print("All operations completed successfully.")
    }
  }
}
