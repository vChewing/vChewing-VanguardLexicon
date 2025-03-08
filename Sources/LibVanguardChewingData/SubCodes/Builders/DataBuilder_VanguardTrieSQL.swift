// (c) 2021 and onwards The vChewing Project (BSD-3-Clause).
// ====================
// This code is released under the SPDX-License-Identifier: `BSD-3-Clause`.

import Foundation
import VanguardTrieKit

// MARK: - VCDataBuilder.VanguardTrieSQLDataBuilder

extension VCDataBuilder {
  public actor VanguardTrieSQLDataBuilder: DataBuilderProtocol, TriePreparatorProtocol {
    // MARK: Lifecycle

    public init?(isCHS: Bool?) async throws {
      self.isCHS = nil
      // 這裡取 false，由應用程式針對不同的平台處理高萬字的相容性。
      self.data = try Collector(isCHS: isCHS, compatibleMode: false, cns: true)
      await data.propagateWeights()
      try await printHealthCheckReports()
      await prepareTrie()
    }

    // MARK: Public

    nonisolated public let isCHS: Bool?

    public let data: Collector
    nonisolated public let trie4TypingBasic: VanguardTrie.Trie = .init(separator: "-")
    nonisolated public let trie4TypingCNS: VanguardTrie.Trie = .init(separator: "-")
    nonisolated public let trie4TypingMisc: VanguardTrie.Trie = .init(separator: "-")
    nonisolated public let trie4Rev: VanguardTrie.Trie = .init(separator: "-")
  }
}

extension VCDataBuilder.VanguardTrieSQLDataBuilder {
  nonisolated public var langSuffix: String { "" }

  nonisolated public var subFolderNameComponents: [String] {
    ["Intermediate", "vanguard-trie-sql"]
  }

  nonisolated public var subFolderNameComponentsAftermath: [String] {
    ["Release", "vanguard-trie-sql"]
  }

  public func assemble() async throws -> [String: Data] {
    let table: [String: VanguardTrie.Trie] = [
      "VanguardFactoryDict4TypingBasic.sql": trie4TypingBasic,
      "VanguardFactoryDict4TypingCNS.sql": trie4TypingCNS,
      "VanguardFactoryDict4TypingMisc.sql": trie4TypingMisc,
      "VanguardFactoryDict4RevLookup.sql": trie4Rev,
    ]
    var output = [String: Data]()
    try table.forEach { filename, currentTrie in
      let sqlStr = VanguardTrie.TrieSQLScriptGenerator.generate(currentTrie)
      guard let sqlData = sqlStr.data(using: .utf8) else {
        throw VCDataBuilder.Exception
          .errMsg("Data encoding failed on assembling for VanguardTrieSQL.")
      }
      output[filename] = sqlData
    }
    return output
  }

  public func performPostCompilation() async throws {
    try await runInTextBlockThrowable {
      print("Vanguard Trie SQLite database compilation started.")
      try await compileSQLite(fileNameStem: "VanguardFactoryDict4TypingBasic")
      try await compileSQLite(fileNameStem: "VanguardFactoryDict4TypingCNS")
      try await compileSQLite(fileNameStem: "VanguardFactoryDict4TypingMisc")
      try await compileSQLite(fileNameStem: "VanguardFactoryDict4RevLookup")
      print("Vanguard Trie SQLite database compilation completed successfully.")
    }
  }
}
