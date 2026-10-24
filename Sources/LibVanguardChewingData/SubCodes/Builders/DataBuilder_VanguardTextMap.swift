// (c) 2021 and onwards The vChewing Project (MulanPSL-2.0 License).
// ====================
// This code is released under the SPDX-License-Identifier: `MulanPSL-2.0`.

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
          // 生成 Typing TextMap。
          let typingData = try assembleTextMapFromTrie(trie4Typing)
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
    NSLog("Vanguard TextMap 資料庫初期化已成功完成。")
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
    // 必須逐 Unicode scalar 掃描：空白若與組合符相連，Character 迭代會將兩者併成單一字群。
    for scalar in value.unicodeScalars {
      switch scalar {
      case #"\"#:
        result.unicodeScalars.append(#"\"#)
        result.unicodeScalars.append(#"\"#)
      case "|":
        result.unicodeScalars.append(#"\"#)
        result.unicodeScalars.append("|")
      case " ":
        result.unicodeScalars.append(#"\"#)
        result.unicodeScalars.append("s")
      case "\u{7}":
        result.unicodeScalars.append(#"\"#)
        result.unicodeScalars.append("a")
      default:
        result.unicodeScalars.append(scalar)
      }
    }
    return result
  }

  /// 從 Trie 結構組裝 TextMap 格式的字串。
  ///
  /// TextMap 格式包含三個區段：HEADER、VALUES、KEY_LINE_MAP。
  /// - VALUES 區段包含四種行型別：
  ///   - 型別 A：`>typeID\tencodedCell`。
  ///   - 型別 B：`@probability\tchsCell\tchtCell`。
  ///   - 型別 C：`value\tprobability\ttypeID[\tcontextCell]`。
  ///   - 型別 D：`!value\ttypeID\tprobability\tcontextCell[…]`，聚合同值同語系的 2～16 筆前文條目。
  ///   `contextCell` 為 escaped-pipe 編碼的前驗詞鏈（由舊至新），v2.0 最多兩層。
  /// - KEY_LINE_MAP 區段：每行為一個讀音索引，格式為 `讀音\t起始行號\t筆數`。
  private func assembleTextMapFromTrie(
    _ trie: VanguardTrie.Trie
  )
    throws -> String {
    // 收集所有有 entries 的節點，按 readingKey 排序。
    let nodesWithEntries = trie.nodes.values
      .filter { !$0.entries.isEmpty && !$0.readingKey.isEmpty }
      .sorted { $0.readingKey < $1.readingKey }

    // 預設機率只採計無前文、非 CHS／CHT 的條目。
    var probsByType: [Int32: Set<Double>] = [:]
    for node in nodesWithEntries {
      for entry in node.entries {
        try Self.validateEntryForSerialization(entry)
        if entry.typeID != .chs, entry.typeID != .cht, entry.context.isEmpty {
          probsByType[entry.typeID.rawValue, default: []].insert(entry.probability)
        }
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
      try assembleTypingEntries(from: node, into: &valueLines, defaultProbs: defaultProbs)
      let count = valueLines.count - startLine
      if count > 0 {
        keyMapLines.append("\(node.readingKey.asDecryptedBopomofoKeyChain)\t\(startLine)\t\(count)")
      }
    }

    var result = ""
    // HEADER
    result += "#PRAGMA:VANGUARD_HOMA_LEXICON_HEADER\n"
    result += "VERSION\t2.0\n"
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
  /// CHS/CHT 無前文條目按機率組成 B；其他型別的預設機率條目組成 A。
  /// 其餘條目依原順序輸出 C，同值同型別的多筆前文條目則組成 D。
  private func assembleTypingEntries(
    from node: VanguardTrie.Trie.TNode,
    into lines: inout [String],
    defaultProbs: [Int32: Double]
  )
    throws {
    let chsEntries = node.entries.filter { $0.typeID == .chs && $0.context.isEmpty }
    let chtEntries = node.entries.filter { $0.typeID == .cht && $0.context.isEmpty }
    let otherEntries = node.entries.filter {
      ($0.typeID != .chs && $0.typeID != .cht) || !$0.context.isEmpty
    }

    var chsByProb: [Double: [String]] = [:]
    var chtByProb: [Double: [String]] = [:]
    for entry in chsEntries {
      try Self.validateGroupedToken(entry.value)
      chsByProb[entry.probability, default: []].append(entry.value)
    }
    for entry in chtEntries {
      try Self.validateGroupedToken(entry.value)
      chtByProb[entry.probability, default: []].append(entry.value)
    }
    let allProbs = Set(chsByProb.keys).union(chtByProb.keys).sorted(by: >)
    for prob in allProbs {
      let probStr = Self.formatProbability(prob)
      let chsStr = Self.encodeGroupedValues(chsByProb[prob] ?? [])
      let chtStr = Self.encodeGroupedValues(chtByProb[prob] ?? [])
      lines.append("\(Self.typingGroupedLinePrefix)\(probStr)\t\(chsStr)\t\(chtStr)")
    }

    var groupedByType: [Int32: [String]] = [:]
    var ungrouped: [VanguardTrie.Trie.Entry] = []
    for entry in otherEntries {
      if entry.context.isEmpty,
         let defaultProb = defaultProbs[entry.typeID.rawValue], entry.probability == defaultProb {
        try Self.validateGroupedToken(entry.value)
        groupedByType[entry.typeID.rawValue, default: []].append(entry.value)
      } else {
        ungrouped.append(entry)
      }
    }
    for (typeID, values) in groupedByType.sorted(by: { $0.key < $1.key }) {
      lines.append(">\(typeID)\t\(Self.encodeGroupedValues(values))")
    }
    try Self.appendSerializedEntries(ungrouped, to: &lines)
  }

  private struct ContextualGroupKey: Hashable {
    let value: String
    let typeID: Int32
  }

  private static func appendSerializedEntries(
    _ entries: [VanguardTrie.Trie.Entry],
    to lines: inout [String]
  )
    throws {
    var contextualGroups: [ContextualGroupKey: [VanguardTrie.Trie.Entry]] = [:]
    for entry in entries where !entry.context.isEmpty {
      let key = ContextualGroupKey(value: entry.value, typeID: entry.typeID.rawValue)
      contextualGroups[key, default: []].append(entry)
    }

    var emittedGroups: Set<ContextualGroupKey> = []
    for entry in entries {
      guard !entry.context.isEmpty else {
        lines.append(try makeTypeCLine(for: entry))
        continue
      }
      let key = ContextualGroupKey(value: entry.value, typeID: entry.typeID.rawValue)
      guard emittedGroups.insert(key).inserted, let group = contextualGroups[key] else { continue }
      try appendContextualGroup(group, to: &lines)
    }
  }

  private static func appendContextualGroup(
    _ entries: [VanguardTrie.Trie.Entry],
    to lines: inout [String]
  )
    throws {
    guard let first = entries.first else { return }
    if entries.count == 1 {
      lines.append(try makeTypeCLine(for: first))
      return
    }

    var start = 0
    while start < entries.count {
      let remaining = entries.count - start
      let chunkCount = remaining == 17 ? 15 : min(remaining, 16)
      let chunk = Array(entries[start ..< (start + chunkCount)])
      var cells = ["!\(first.value)", first.typeID.rawValue.description]
      for entry in chunk {
        cells.append(Self.formatProbability(entry.probability))
        cells.append(Self.encodeGroupedValues(entry.context))
      }
      lines.append(cells.joined(separator: "\t"))
      start += chunkCount
    }
  }

  private static func makeTypeCLine(for entry: VanguardTrie.Trie.Entry) throws -> String {
    try validateBareValue(entry.value)
    guard entry.context.count <= 2 else {
      throw VCDataBuilder.Exception.errMsg("TextMap v2.0 supports at most two context tokens.")
    }
    var cells = [
      entry.value,
      Self.formatProbability(entry.probability),
      entry.typeID.rawValue.description,
    ]
    if !entry.context.isEmpty {
      cells.append(Self.encodeGroupedValues(entry.context))
    }
    return cells.joined(separator: "\t")
  }

  private static func validateEntryForSerialization(_ entry: VanguardTrie.Trie.Entry) throws {
    guard entry.probability.isFinite else {
      throw VCDataBuilder.Exception.errMsg("Entry probability must be finite.")
    }
    guard !entry.value.isEmpty else {
      throw VCDataBuilder.Exception.errMsg("Entry value must not be empty.")
    }
    for scalar in entry.value.unicodeScalars where scalar.value != 0x07 {
      guard !isStructuralControl(scalar) else {
        let scalarID = "U+" + String(scalar.value, radix: 16, uppercase: true)
        throw VCDataBuilder.Exception.errMsg(
          "Entry value \(entry.value.debugDescription) contains raw control character \(scalarID)."
        )
      }
    }
    guard entry.context.count <= 2 else {
      throw VCDataBuilder.Exception.errMsg("TextMap v2.0 supports at most two context tokens.")
    }
    for token in entry.context {
      try validateGroupedToken(token)
    }
  }

  private static func validateBareValue(_ value: String) throws {
    guard !value.isEmpty else {
      throw VCDataBuilder.Exception.errMsg("Entry value must not be empty.")
    }
    for scalar in value.unicodeScalars {
      guard !isStructuralControl(scalar) else {
        throw VCDataBuilder.Exception.errMsg("Entry value contains a raw control character.")
      }
    }
  }

  private static func validateGroupedToken(_ token: String) throws {
    guard !token.isEmpty else {
      throw VCDataBuilder.Exception.errMsg("Grouped cells must not contain empty tokens.")
    }
    for scalar in token.unicodeScalars where scalar.value != 0x07 {
      if isStructuralControl(scalar) {
        throw VCDataBuilder.Exception.errMsg("Grouped cells must not contain raw control characters.")
      }
    }
  }

  /// 只拒絕會破壞文字格式的 Cc／換行；ZWJ 等 Cf 是合法詞值成分。
  private static func isStructuralControl(_ scalar: UnicodeScalar) -> Bool {
    scalar.properties.generalCategory == .control || CharacterSet.newlines.contains(scalar)
  }
}
