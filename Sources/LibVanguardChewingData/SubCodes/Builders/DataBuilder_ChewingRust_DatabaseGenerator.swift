// (c) 2021 and onwards The vChewing Project (BSD-3-Clause).
// ====================
// This code is released under the SPDX-License-Identifier: `BSD-3-Clause`.

import Foundation

// MARK: - ChewingRustSyllableEncoder

enum ChewingRustSyllableEncoder {
  // MARK: Internal

  static func uintFromPhone(_ token: String) -> UInt16? {
    var result: UInt16 = 0
    var nextGroup = 0

    for character in token {
      guard let entry = bopomofoIndexMap[character], entry.group >= nextGroup else {
        return nil
      }
      result |= entry.index << shifts[entry.group]
      nextGroup = entry.group + 1
    }

    return result == 0 ? nil : result
  }

  // MARK: Private

  private static let shifts = [9, 7, 3, 0]

  private static let groups: [[Character]] = [
    Array("ㄅㄆㄇㄈㄉㄊㄋㄌㄍㄎㄏㄐㄑㄒㄓㄔㄕㄖㄗㄘㄙ"),
    Array("ㄧㄨㄩ"),
    Array("ㄚㄛㄜㄝㄞㄟㄠㄡㄢㄣㄤㄥㄦ"),
    ["˙", "ˊ", "ˇ", "ˋ", "ˉ"],
  ]

  private static let bopomofoIndexMap: [Character: (group: Int, index: UInt16)] = {
    var result = [Character: (group: Int, index: UInt16)]()
    for (groupIndex, group) in groups.enumerated() {
      for (offset, character) in group.enumerated() {
        result[character] = (group: groupIndex, index: UInt16(offset + 1))
      }
    }
    return result
  }()
}

// MARK: - ChewingRustDatabaseGenerator

enum ChewingRustDatabaseGenerator {
  // MARK: Internal

  struct GeneratedArtifacts {
    let tsi: Data
    let word: Data
  }

  struct Metadata: Equatable {
    static let defaults = Self(
      name: "我的詞庫",
      copyright: "Unknown",
      license: "Unknown",
      version: "1.0.0",
      software: "VCDataBuilder"
    )

    let name: String
    let copyright: String
    let license: String
    let version: String
    let software: String
  }

  struct SourceEntry: Equatable {
    let phrase: String
    let freq: UInt32
    let syllables: [UInt16]
  }

  struct PhrasePayload: Equatable {
    // MARK: Lifecycle

    init(text: String, freq: UInt32, lastUsed: UInt64? = nil) {
      self.text = text
      self.freq = freq
      self.lastUsed = lastUsed
    }

    // MARK: Internal

    let text: String
    let freq: UInt32
    let lastUsed: UInt64?
  }

  enum GeneratorError: LocalizedError {
    case message(String)

    // MARK: Internal

    var errorDescription: String? {
      switch self {
      case let .message(message): return message
      }
    }
  }

  final class TrieBuilder {
    // MARK: Lifecycle

    init() {
      self.arena = [Node(id: 0)]
    }

    // MARK: Internal

    struct Node: Equatable {
      let id: Int
      var syllable: UInt16?
      var childIDs: [Int] = []
      var leafID: Int?
      var phrases: [PhrasePayload] = []

      var isInternal: Bool { syllable != nil || id == 0 }
    }

    private(set) var arena: [Node]
    var metadata = Metadata.defaults

    static func orderedPhrases(_ phrases: [PhrasePayload]) -> [PhrasePayload] {
      phrases.enumerated().sorted { lhs, rhs in
        let left = lhs.element
        let right = rhs.element
        let leftCharCount = left.text.count
        let rightCharCount = right.text.count

        if leftCharCount == 1, rightCharCount == 1 {
          return lhs.offset < rhs.offset
        }

        if leftCharCount == 1 || rightCharCount == 1 {
          let leftLength = left.text.utf8.count
          let rightLength = right.text.utf8.count
          if leftLength != rightLength {
            return leftLength < rightLength
          }
          return lhs.offset < rhs.offset
        }

        if left.freq != right.freq {
          return left.freq > right.freq
        }

        let leftBeforeRight = left.text.utf8.lexicographicallyPrecedes(right.text.utf8)
        let rightBeforeLeft = right.text.utf8.lexicographicallyPrecedes(left.text.utf8)
        if leftBeforeRight != rightBeforeLeft {
          return rightBeforeLeft
        }

        return lhs.offset < rhs.offset
      }.map(\.element)
    }

    func setInfo(_ metadata: Metadata) {
      self.metadata = metadata
    }

    func insert(_ entry: SourceEntry) throws {
      try insert(syllables: entry.syllables, phrase: .init(text: entry.phrase, freq: entry.freq))
    }

    func insert(syllables: [UInt16], phrase: PhrasePayload) throws {
      guard !syllables.isEmpty else {
        throw GeneratorError.message("Empty syllable array is not allowed for phrase: \(phrase.text)")
      }

      let leafID = findOrInsertInternal(syllables)
      if let existingIndex = phraseIndicesByLeafID[leafID]?[phrase.text] {
        arena[leafID].phrases[existingIndex] = phrase
      } else {
        let nextIndex = arena[leafID].phrases.count
        arena[leafID].phrases.append(phrase)
        phraseIndicesByLeafID[leafID, default: [:]][phrase.text] = nextIndex
      }
    }

    func phrasesForSyllables(_ syllables: [UInt16]) -> [PhrasePayload]? {
      let leafID = resolveLeafID(for: syllables)
      guard let leafID else { return nil }
      return Self.orderedPhrases(arena[leafID].phrases)
    }

    func encode() throws -> Data {
      let encoded = try encodeIndexAndPhraseSequence()
      let infoData = try Self.encodeSequence([
        try Self.encodeUTF8String(metadata.name),
        try Self.encodeUTF8String(metadata.copyright),
        try Self.encodeUTF8String(metadata.license),
        try Self.encodeUTF8String(metadata.version),
        try Self.encodeUTF8String(metadata.software),
      ])
      let phraseSeqData = try Self.encodeSequence([encoded.phraseSequence])
      return try Self.encodeSequence([
        try Self.encodeUTF8String("CHEW"),
        try Self.encodeInteger(UInt8(0)),
        infoData,
        try Self.encodeOctetString(encoded.index),
        phraseSeqData,
      ])
    }

    // MARK: Private

    private var phraseIndicesByLeafID = [Int: [String: Int]]()

    private static func encodePhrase(_ phrase: PhrasePayload) throws -> Data {
      var children = [try encodeUTF8String(phrase.text), try encodeInteger(phrase.freq)]
      if let lastUsed = phrase.lastUsed {
        children.append(try encodeContextSpecificInteger(tagNumber: 0, value: lastUsed))
      }
      return try encodeSequence(children)
    }

    private static func encodeContextSpecificInteger(tagNumber: UInt8, value: UInt64) throws -> Data {
      let tag = UInt8(0x80 | tagNumber)
      return try encodeTLV(tag: tag, value: encodeIntegerBytes(value))
    }

    private static func encodeUTF8String(_ string: String) throws -> Data {
      let value = Data(string.utf8)
      return try encodeTLV(tag: 0x0C, value: value)
    }

    private static func encodeOctetString(_ data: Data) throws -> Data {
      try encodeTLV(tag: 0x04, value: data)
    }

    private static func encodeInteger<T: FixedWidthInteger & UnsignedInteger>(_ value: T) throws -> Data {
      let bytes = encodeIntegerBytes(UInt64(value))
      return try encodeTLV(tag: 0x02, value: bytes)
    }

    private static func encodeIntegerBytes(_ value: UInt64) -> Data {
      var bigEndian = value.bigEndian
      let rawBytes = withUnsafeBytes(of: &bigEndian) { Array($0) }
      let trimmed = Array(rawBytes.drop { $0 == 0 })
      var bytes = trimmed.isEmpty ? [UInt8(0)] : trimmed
      if let first = bytes.first, first >= 0x80 {
        bytes.insert(0, at: 0)
      }
      return Data(bytes)
    }

    private static func encodeSequence(_ children: [Data]) throws -> Data {
      try encodeTLV(tag: 0x30, value: children.reduce(into: Data()) { $0.append($1) })
    }

    private static func encodeTLV(tag: UInt8, value: Data) throws -> Data {
      var data = Data([tag])
      data.append(try encodeLength(value.count))
      data.append(value)
      return data
    }

    private static func encodeLength(_ length: Int) throws -> Data {
      guard length >= 0 else {
        throw GeneratorError.message("Negative DER length is invalid.")
      }
      if length < 0x80 {
        return Data([UInt8(length)])
      }

      var bigEndian = UInt64(length).bigEndian
      let rawBytes = withUnsafeBytes(of: &bigEndian) { Array($0) }
      let trimmed = Array(rawBytes.drop { $0 == 0 })
      guard let count = UInt8(exactly: trimmed.count) else {
        throw GeneratorError.message("DER length overflow.")
      }
      return Data([0x80 | count] + trimmed)
    }

    private func allocLeaf() -> Int {
      let id = arena.count
      arena.append(Node(id: id))
      phraseIndicesByLeafID[id] = [:]
      return id
    }

    private func allocInternal(_ syllable: UInt16) -> Int {
      let id = arena.count
      arena.append(Node(id: id, syllable: syllable))
      return id
    }

    private func childLookup(in nodeID: Int, syllable: UInt16) -> (index: Int, childID: Int?) {
      let childIDs = arena[nodeID].childIDs
      var lowerBound = 0
      var upperBound = childIDs.count

      while lowerBound < upperBound {
        let midIndex = (lowerBound + upperBound) / 2
        let midSyllable = arena[childIDs[midIndex]].syllable ?? 0

        if midSyllable < syllable {
          lowerBound = midIndex + 1
        } else {
          upperBound = midIndex
        }
      }

      if lowerBound < childIDs.count, arena[childIDs[lowerBound]].syllable == syllable {
        return (lowerBound, childIDs[lowerBound])
      }

      return (lowerBound, nil)
    }

    private func findOrInsertInternal(_ syllables: [UInt16]) -> Int {
      var nodeID = 0

      for syllable in syllables {
        let childLookup = childLookup(in: nodeID, syllable: syllable)
        if let existingChildID = childLookup.childID {
          nodeID = existingChildID
          continue
        }

        let nextID = allocInternal(syllable)
        arena[nodeID].childIDs.insert(nextID, at: childLookup.index)
        nodeID = nextID
      }

      if let leafID = arena[nodeID].leafID {
        return leafID
      }

      let leafID = allocLeaf()
      arena[nodeID].leafID = leafID
      return leafID
    }

    private func resolveLeafID(for syllables: [UInt16]) -> Int? {
      var nodeID = 0
      for syllable in syllables {
        guard let nextID = childLookup(in: nodeID, syllable: syllable).childID else {
          return nil
        }
        nodeID = nextID
      }
      return arena[nodeID].leafID
    }

    private func encodeIndexAndPhraseSequence() throws -> (index: Data, phraseSequence: Data) {
      var currentLayer = [0] // root node id
      var childBegin = 1
      var index = Data()
      index.reserveCapacity(arena.count * 8)
      var phraseSequence = Data()

      while !currentLayer.isEmpty {
        var nextLayer = [Int]()
        nextLayer.reserveCapacity(currentLayer.count)
        for id in currentLayer {
          let node = arena[id]

          if node.isInternal {
            let childLength = node.childIDs.count + (node.leafID == nil ? 0 : 1)
            index.appendUInt32BE(UInt32(childBegin))
            index.appendUInt16BE(try UInt16(exactly: childLength).orThrow(
              "Child length overflow while serializing chewing-rust trie."
            ))
            index.appendUInt16BE(node.syllable ?? 0)
          } else {
            let orderedPhrases = Self.orderedPhrases(node.phrases)
            let dataBegin = phraseSequence.count
            for phrase in orderedPhrases {
              phraseSequence.append(try Self.encodePhrase(phrase))
            }
            let dataLength = phraseSequence.count - dataBegin
            index.appendUInt32BE(UInt32(dataBegin))
            index.appendUInt16BE(try UInt16(exactly: dataLength).orThrow(
              "Phrase payload too large for a single chewing-rust trie leaf."
            ))
            index.appendUInt16BE(0)
          }

          if let leafID = node.leafID {
            childBegin += 1
            nextLayer.append(leafID)
          }

          for childID in node.childIDs {
            childBegin += 1
            nextLayer.append(childID)
          }
        }
        currentLayer = nextLayer
      }

      return (index: index, phraseSequence: phraseSequence)
    }
  }

  static func writeArtifacts(
    tsiSrcURL: URL,
    wordSrcURL: URL,
    outputDirectory: URL,
    metadata: Metadata = .defaults
  ) throws {
    let tsiSrc = try String(contentsOf: tsiSrcURL, encoding: .utf8)
    let wordSrc = try String(contentsOf: wordSrcURL, encoding: .utf8)
    let artifacts = try generateArtifacts(tsiSrc: tsiSrc, wordSrc: wordSrc, metadata: metadata)

    try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
    try artifacts.tsi.write(to: outputDirectory.appendingPathComponent("tsi.dat"))
    try artifacts.word.write(to: outputDirectory.appendingPathComponent("word.dat"))
  }

  static func generateArtifacts(
    tsiSrc: String,
    wordSrc: String,
    metadata: Metadata = .defaults
  ) throws
    -> GeneratedArtifacts {
    GeneratedArtifacts(
      tsi: try generateDictionaryData(source: tsiSrc, metadata: metadata),
      word: try generateDictionaryData(source: wordSrc, metadata: metadata)
    )
  }

  static func generateDictionaryData(
    source: String,
    metadata: Metadata = .defaults
  ) throws
    -> Data {
    let builder = TrieBuilder()
    builder.setInfo(metadata)
    try forEachParsedEntry(in: source) { entry in
      try builder.insert(entry)
    }
    return try builder.encode()
  }

  static func parseSource(_ source: String) throws -> [SourceEntry] {
    var results = [SourceEntry]()

    try forEachParsedEntry(in: source) { entry in
      results.append(entry)
    }

    return results
  }

  // MARK: Private

  private static func forEachParsedEntry(
    in source: String,
    _ body: (SourceEntry) throws -> ()
  ) throws {
    for (offset, rawLine) in source.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
      .enumerated() {
      let lineNumber = offset + 1
      let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)

      if line.isEmpty || line.hasPrefix("#") {
        continue
      }

      let cells = line.split(whereSeparator: \.isWhitespace)
      guard cells.count >= 3 else {
        throw GeneratorError.message("Invalid chewing-rust source at line \(lineNumber): \(line)")
      }

      let phrase = String(cells[0])
      guard let signedFreq = Int(cells[1]) else {
        throw GeneratorError.message("Invalid frequency at line \(lineNumber): \(line)")
      }

      if signedFreq < 0 {
        if phrase.count == 1 {
          continue
        }
        throw GeneratorError.message(
          "Negative frequency is not allowed for multi-character phrase at line \(lineNumber): \(line)"
        )
      }

      guard let freq = UInt32(exactly: signedFreq) else {
        throw GeneratorError.message("Frequency overflow at line \(lineNumber): \(line)")
      }

      var syllables = [UInt16]()
      for cell in cells.dropFirst(2) {
        if cell.first == "#" { break }
        let token = String(cell)
        guard let syllable = ChewingRustSyllableEncoder.uintFromPhone(token) else {
          throw GeneratorError.message("Invalid syllable token \(token) at line \(lineNumber)")
        }
        syllables.append(syllable)
      }

      guard phrase.count == syllables.count else {
        throw GeneratorError.message(
          "Phrase/syllable count mismatch at line \(lineNumber): \(phrase) vs \(syllables.count)"
        )
      }

      try body(SourceEntry(phrase: phrase, freq: freq, syllables: syllables))
    }
  }
}

// MARK: - Private Helpers

extension Optional {
  fileprivate func orThrow(_ message: @autoclosure () -> String) throws -> Wrapped {
    guard let wrapped = self else {
      throw ChewingRustDatabaseGenerator.GeneratorError.message(message())
    }
    return wrapped
  }
}

extension Data {
  fileprivate mutating func appendUInt16BE(_ value: UInt16) {
    var bigEndian = value.bigEndian
    Swift.withUnsafeBytes(of: &bigEndian) {
      append(contentsOf: $0)
    }
  }

  fileprivate mutating func appendUInt32BE(_ value: UInt32) {
    var bigEndian = value.bigEndian
    Swift.withUnsafeBytes(of: &bigEndian) {
      append(contentsOf: $0)
    }
  }
}
