// (c) 2021 and onwards The vChewing Project (MulanPSL-2.0 License).
// ====================
// This code is released under the SPDX-License-Identifier: `MulanPSL-2.0`.

import Foundation

// MARK: - VCDataBuilder.TextKVSTableDataBuilder

extension VCDataBuilder {
  public actor TextKVSTableDataBuilder: DataBuilderProtocol {
    // MARK: Lifecycle

    public init?(isCHS: Bool?) async throws {
      guard let isCHS else { return nil }
      self.isCHS = isCHS
      // 純文字表不綁定消費端；此處沿用非相容模式以保留完整字集。
      self.data = try Collector(isCHS: isCHS, compatibleMode: false)
      await data.propagateWeights()
      try await printHealthCheckReports()
    }

    // MARK: Public

    nonisolated public let isCHS: Bool?

    public let data: Collector
  }
}

extension VCDataBuilder.TextKVSTableDataBuilder {
  nonisolated public var langSuffix: String {
    (isCHS ?? true) ? "chs" : "cht" // 這個 variable 在這個 Actor 內永遠都不可能是 nil。
  }

  nonisolated public var subFolderNameComponents: [String] {
    ["Release", "textKVSTable-\(langSuffix)"]
  }

  nonisolated public var subFolderNameComponentsAftermath: [String] { [] }

  public func getIteratorForLexiconAssemblyTask() async throws -> VCDataBuilder.ChunkIterator {
    var resultString = [String]()
    var grams = await data.getAllUnigrams(isCHS: isCHS, sorted: false)
    grams.append(contentsOf: await data.getPunctuations())
    grams.append(contentsOf: await data.getSymbols())
    grams.append(contentsOf: await data.getZhuyinwen())
    grams = grams.sorted { lhs, rhs -> Bool in
      (lhs.key, rhs.score, lhs.timestamp) < (rhs.key, lhs.score, rhs.timestamp)
    }
    grams.forEach { gram in
      resultString.append("\(gram.key) \(gram.value) \(gram.score)")
      resultString.append("\n")
    }
    guard let data = resultString.joined().data(using: .utf8) else {
      throw VCDataBuilder.Exception.errMsg("Data encoding failed on assembling the text KVS table.")
    }
    return AsyncThrowingStream { continuation in
      continuation.yield(.init(fileName: "data.txt", data: data, isLastChunk: true))
      continuation.finish()
    }
  }

  /// 純文字表不需要額外的後編譯步驟。
  public func performPostCompilation() async throws {
    print("Data compilation succeeded for the text KVS table.")
  }
}
