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
    let buildRoot = FileManager.urlCurrentFolder.appendingPathComponent("Build")
    let intermediateFolderURL = subFolderNameComponents.reduce(buildRoot) { partial, component in
      partial.appendingPathComponent(component)
    }

    var outputFolderURL = FileManager.urlCurrentFolder
    if ProcessInfo.processInfo.environment["VANGUARD_OUTPUT_DIR"] == nil {
      outputFolderURL.appendPathComponent("Build")
    }
    outputFolderURL = subFolderNameComponentsAftermath.reduce(outputFolderURL) { partial, component in
      partial.appendingPathComponent(component)
    }

    let tsiSrcURL = intermediateFolderURL.appendingPathComponent("tsi.src")
    let wordSrcURL = intermediateFolderURL.appendingPathComponent("word.src")

    NSLog("針對 Rust 版新酷音引擎的資料建置正式開始，這需要一些時間。")
    do {
      try ChewingRustDatabaseGenerator.writeArtifacts(
        tsiSrcURL: tsiSrcURL,
        wordSrcURL: wordSrcURL,
        outputDirectory: outputFolderURL
      )
    } catch {
      throw VCDataBuilder.Exception.errMsg(
        "Failed to generate chewing-rust dictionaries:\n\(error.localizedDescription)"
      )
    }

    NSLog("針對 Rust 版新酷音引擎的資料建置已順利完成。")
  }
}
