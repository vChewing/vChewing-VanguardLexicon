// (c) 2021 and onwards The vChewing Project (BSD-3-Clause).
// ====================
// This code is released under the SPDX-License-Identifier: `BSD-3-Clause`.

import Foundation
import VanguardTrieKit

// MARK: - VCDataBuilder.VanguardTextMapDataBuilder

extension VCDataBuilder {
  public actor VanguardTextMapDataBuilder: DataBuilderProtocol, TriePreparatorProtocol {
    // MARK: Lifecycle

    public init?(isCHS: Bool?) async throws {
      self.isCHS = nil
      self.data = try Collector(isCHS: isCHS, compatibleMode: false, cns: true)
      await data.propagateWeights()
      try await printHealthCheckReports()
      await prepareTrie()
    }

    // MARK: Public

    nonisolated public let isCHS: Bool?
    nonisolated public let shouldPrepareRevLookupTrie = false

    public let data: Collector
    nonisolated public let mutexTrie4Typing: NSMutex<VanguardTrie.Trie> = .init(.init(separator: "-"))
    nonisolated public let mutexTrie4Rev: NSMutex<VanguardTrie.Trie> = .init(.init(separator: "-"))
  }
}

extension VCDataBuilder.VanguardTextMapDataBuilder {
  nonisolated public var langSuffix: String { "" }

  nonisolated public var subFolderNameComponents: [String] {
    ["Release", "vanguard-textmap"]
  }

  nonisolated public var subFolderNameComponentsAftermath: [String] { [] }

  public func getIteratorForLexiconAssemblyTask() async throws -> VCDataBuilder.ChunkIterator {
    AsyncThrowingStream { continuation in
      Task { [self] in
        do {
          // Phase 02: 生成 Typing TextMap。
          let typingData = assembleTextMapFromTrie(trie4Typing)
          guard let typingBytes = typingData.data(using: .utf8) else {
            throw VCDataBuilder.Exception
              .errMsg("Data encoding failed on assembling VanguardTextMap (Typing).")
          }
          continuation.yield(
            .init(fileName: "VanguardFactoryDict4Typing.txtMap", data: typingBytes, isLastChunk: true)
          )

          continuation.finish()
        } catch {
          continuation.finish(throwing: error)
        }
      }
    }
  }

  public func performPostCompilation() async throws {
    var buildFolderURL = FileManager.urlCurrentFolder.appendingPathComponent("Build")
    subFolderNameComponents.forEach { currentComponentName in
      buildFolderURL = buildFolderURL.appendingPathComponent(currentComponentName)
    }
    let legacyRevLookupURL = buildFolderURL.appendingPathComponent("VanguardFactoryDict4RevLookup.revlookup")
    if FileManager.default.fileExists(atPath: legacyRevLookupURL.path) {
      try FileManager.default.removeItem(at: legacyRevLookupURL)
    }
    print("Vanguard TextMap database initialization completed successfully.")
  }
}

// MARK: - TextMap Assembly

extension VCDataBuilder.VanguardTextMapDataBuilder {
  /// 將 Double 機率值格式化為字串，若小數部分為零則以整數呈現。
  private static func formatProbability(_ value: Double) -> String {
    let str = value.description
    return str.hasSuffix(".0") ? String(str.dropLast(2)) : str
  }

  private static let typingGroupedLinePrefix = "@"
  private static let groupedValueEscape: Character = #"\"#
  private static let groupedValueSeparator = "|"
  private static let emptyGroupedCellPlaceholder = "\u{7}"

  private static func encodeGroupedValues(_ values: [String]) -> String {
    guard !values.isEmpty else { return Self.emptyGroupedCellPlaceholder }
    return values.map(Self.escapeGroupedValue).joined(separator: Self.groupedValueSeparator)
  }

  private static func escapeGroupedValue(_ value: String) -> String {
    var result = ""
    result.reserveCapacity(value.count)
    for char in value {
      switch char {
      case Self.groupedValueEscape:
        result.append(Self.groupedValueEscape)
        result.append(Self.groupedValueEscape)
      case "|":
        result.append(Self.groupedValueEscape)
        result.append("|")
      case " ":
        result.append(Self.groupedValueEscape)
        result.append("s")
      case "\u{7}":
        result.append(Self.groupedValueEscape)
        result.append("a")
      default:
        result.append(char)
      }
    }
    return result
  }

  /// 從 Trie 結構組裝 TextMap 格式的字串。
  ///
  /// TextMap 格式包含三個區段：HEADER、VALUES、KEY_LINE_MAP。
  /// - VALUES 區段包含三種行型別：
  ///   - 型別 A：`>typeID\tencodedCell`。
  ///   - 型別 B：`@probability\tchsCell\tchtCell`。
  ///   - 型別 C：`value\tprobability\ttypeID[\tprevious]`。
  /// - KEY_LINE_MAP 區段：每行為一個讀音索引，格式為 `讀音\t起始行號\t筆數`。
  private func assembleTextMapFromTrie(
    _ trie: VanguardTrie.Trie
  )
    -> String {
    // 收集所有有 entries 的節點，按 readingKey 排序。
    let nodesWithEntries = trie.nodes.values
      .filter { !$0.entries.isEmpty && !$0.readingKey.isEmpty }
      .sorted { $0.readingKey < $1.readingKey }

    // 計算每個 typeID 的預設機率（排除 CHS/CHT，因其以 `@probability` 分組行另行處理）。
    var probsByType: [Int32: Set<Double>] = [:]
    for node in nodesWithEntries {
      for entry in node.entries where entry.typeID != .chs && entry.typeID != .cht {
        probsByType[entry.typeID.rawValue, default: []].insert(entry.probability)
      }
    }
    var defaultProbs: [Int32: Double] = [:]
    for (typeID, probs) in probsByType where probs.count == 1 {
      defaultProbs[typeID] = probs.first!
    }

    var valueLines = [String]()
    var keyMapLines = [String]()

    for node in nodesWithEntries {
      let startLine = valueLines.count
      assembleTypingEntries(from: node, into: &valueLines, defaultProbs: defaultProbs)
      let count = valueLines.count - startLine
      if count > 0 {
        keyMapLines.append("\(node.readingKey)\t\(startLine)\t\(count)")
      }
    }

    var result = ""
    // HEADER
    result += "#PRAGMA:VANGUARD_HOMA_LEXICON_HEADER\n"
    result += "VERSION\t1\n"
    result += "TYPE\tTYPING\n"
    result += "READING_SEPARATOR\t\(trie.readingSeparator)\n"
    result += "ENTRY_COUNT\t\(valueLines.count)\n"
    result += "KEY_COUNT\t\(keyMapLines.count)\n"
    for (typeID, prob) in defaultProbs.sorted(by: { $0.key < $1.key }) {
      result += "DEFAULT_PROB_\(typeID)\t\(Self.formatProbability(prob))\n"
    }
    // VALUES
    result += "#PRAGMA:VANGUARD_HOMA_LEXICON_VALUES\n"
    for line in valueLines {
      result += line
      result += "\n"
    }
    // KEY_LINE_MAP
    result += "#PRAGMA:VANGUARD_HOMA_LEXICON_KEY_LINE_MAP\n"
    for line in keyMapLines {
      result += line
      result += "\n"
    }
    return result
  }

  /// 為 Typing 類型節點組裝 VALUES 行。
  ///
  /// CHS/CHT 按機率分組合併：`@probability\tchsCell\tchtCell`，行按機率降冪排列。
  /// Grouped cell 內多個 values 以 `|` 分隔，空白與 `|` 以反斜線跳脫。
  /// 其他類型具有預設機率者以 `>typeID\tencodedCell` 合併行格式輸出。
  private func assembleTypingEntries(
    from node: VanguardTrie.Trie.TNode,
    into lines: inout [String],
    defaultProbs: [Int32: Double]
  ) {
    let chsEntries = node.entries.filter { $0.typeID == .chs }
    let chtEntries = node.entries.filter { $0.typeID == .cht }
    let otherEntries = node.entries.filter { $0.typeID != .chs && $0.typeID != .cht }

    // CHS/CHT 按機率分組，同機率的 values 以 escaped grouped cell 形式輸出。
    var chsByProb: [Double: [String]] = [:]
    var chtByProb: [Double: [String]] = [:]
    for e in chsEntries { chsByProb[e.probability, default: []].append(e.value) }
    for e in chtEntries { chtByProb[e.probability, default: []].append(e.value) }
    let allProbs = Set(chsByProb.keys).union(chtByProb.keys).sorted(by: >)
    for prob in allProbs {
      let probStr = Self.formatProbability(prob)
      let chsStr = Self.encodeGroupedValues(chsByProb[prob] ?? [])
      let chtStr = Self.encodeGroupedValues(chtByProb[prob] ?? [])
      lines.append("\(Self.typingGroupedLinePrefix)\(probStr)\t\(chsStr)\t\(chtStr)")
    }

    // 其他類型的詞條：具有預設機率者以 `>typeID\tencodedCell` 合併行格式輸出。
    var groupedByType: [Int32: [String]] = [:]
    var ungrouped: [VanguardTrie.Trie.Entry] = []
    for entry in otherEntries {
      if let defaultProb = defaultProbs[entry.typeID.rawValue], entry.probability == defaultProb {
        groupedByType[entry.typeID.rawValue, default: []].append(entry.value)
      } else {
        ungrouped.append(entry)
      }
    }
    for (typeID, values) in groupedByType.sorted(by: { $0.key < $1.key }) {
      lines.append(">\(typeID)\t\(Self.encodeGroupedValues(values))")
    }
    for entry in ungrouped {
      lines.append(
        "\(entry.value)\t\(Self.formatProbability(entry.probability))\t\(entry.typeID.rawValue)"
      )
    }
  }
}
