// (c) 2021 and onwards The vChewing Project (BSD-3-Clause).
// ====================
// This code is released under the SPDX-License-Identifier: `BSD-3-Clause`.

import Foundation
import VanguardTrieKit

// MARK: - VCDataBuilder.VanguardTriePlistDataBuilder

extension VCDataBuilder {
  public actor VanguardTriePlistDataBuilder: DataBuilderProtocol, TriePreparatorProtocol {
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
    nonisolated public let mutexTrie4Typing: NSMutex<VanguardTrie.Trie> = .init(.init(separator: "-"))
    nonisolated public let mutexTrie4Rev: NSMutex<VanguardTrie.Trie> = .init(.init(separator: "-"))
  }
}

extension VCDataBuilder.VanguardTriePlistDataBuilder {
  nonisolated public var langSuffix: String { "" }

  nonisolated public var subFolderNameComponents: [String] {
    ["Release", "vanguard-trie-plist"]
  }

  nonisolated public var subFolderNameComponentsAftermath: [String] { [] }

  public func getIteratorForLexiconAssemblyTask() async throws -> VCDataBuilder.ChunkIterator {
    AsyncThrowingStream { continuation in
      Task {
        let table: [String: VanguardTrie.Trie] = [
          "VanguardFactoryDict4Typing.plist": trie4Typing,
          "VanguardFactoryDict4RevLookup.plist": trie4Rev,
        ]
        do {
          for (filename, currentTrie) in table {
            let data = try VanguardTrie.TrieIO.serialize(currentTrie)
            continuation.yield(.init(fileName: filename, data: data, isLastChunk: true))
          }
          continuation.finish()
        } catch {
          continuation.finish(throwing: error)
        }
      }
    }
  }

  public func performPostCompilation() async throws {
    print("Vanguard Trie Plist database initialization completed successfully.")
  }
}

extension VCDataBuilder.Collector {}
