// (c) 2021 and onwards The vChewing Project (BSD-3-Clause).
// ====================
// This code is released under the SPDX-License-Identifier: `BSD-3-Clause`.

import Foundation

// MARK: - VCDataBuilder.McBopomofoDataBuilder

extension VCDataBuilder {
  public actor McBopomofoDataBuilder: DataBuilderProtocol {
    // MARK: Lifecycle

    public init?(isCHS: Bool?) async throws {
      guard let isCHS else { return nil }
      self.isCHS = isCHS
      // 小麥注音的 macOS 版和 Linux 版可以放心使用高萬字。
      // Windows 版是 TypeScript 實作、原理上無法更換原廠詞庫，所以不考慮。
      // 綜上所述，不需要相容模式。
      self.data = try Collector(isCHS: isCHS, compatibleMode: false)
      await data.propagateWeights()
    }

    // MARK: Public

    nonisolated public let isCHS: Bool?

    // MARK: Internal

    let data: Collector
  }
}

extension VCDataBuilder.McBopomofoDataBuilder {
  nonisolated public var langSuffix: String {
    (isCHS ?? true) ? "chs" : "cht" // 這個 variable 在這個 Actor 內永遠都不可能是 nil。
  }

  nonisolated public var subFolderNameComponents: [String] {
    ["Release", "mcbopomofo-\(langSuffix)"]
  }

  nonisolated public var subFolderNameComponentsAftermath: [String] { [] }

  public func assemble() async throws -> [String: String] {
    var resultString = ["# format org.openvanilla.mcbopomofo.sorted\n"]
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
    return ["data.txt": resultString.joined()]
  }

  /// This is a no-op for McBopomofo dict compilation process.
  public func performPostCompilation() async throws {}
}
