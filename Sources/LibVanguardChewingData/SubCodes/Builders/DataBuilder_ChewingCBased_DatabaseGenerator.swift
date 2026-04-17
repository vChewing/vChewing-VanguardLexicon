// (c) 2021 and onwards The vChewing Project (BSD-3-Clause).
// ====================
// This code is released under the SPDX-License-Identifier: `BSD-3-Clause`.

import Foundation

// MARK: - ChewingPhoneEncoder

enum ChewingPhoneEncoder {
  // MARK: Internal

  static let shift = [9, 7, 3, 0]

  static func uintFromPhone(_ token: some StringProtocol) -> UInt16? {
    var result: UInt16 = 0
    var nextGroup = 0

    for character in token {
      guard let entry = bopomofoIndexMap[character], entry.group >= nextGroup else {
        return nil
      }
      result |= entry.index << shift[entry.group]
      nextGroup = entry.group + 1
    }

    return result == 0 ? nil : result
  }

  static func uintFromDachenKey(_ key: some StringProtocol) -> UInt16? {
    var result: UInt16 = 0
    var nextGroup = 0

    for character in key {
      guard let mapped = dachenToBopomofo[character],
            let entry = bopomofoIndexMap[mapped],
            entry.group >= nextGroup
      else {
        return nil
      }
      result |= entry.index << shift[entry.group]
      nextGroup = entry.group + 1
    }

    return result == 0 ? nil : result
  }

  // MARK: Private

  private static let groups: [[Character]] = [
    Array("ㄅㄆㄇㄈㄉㄊㄋㄌㄍㄎㄏㄐㄑㄒㄓㄔㄕㄖㄗㄘㄙ"),
    Array("ㄧㄨㄩ"),
    Array("ㄚㄛㄜㄝㄞㄟㄠㄡㄢㄣㄤㄥㄦ"),
    Array("˙ˊˇˋ"),
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

  private static let dachenToBopomofo: [Character: Character] = {
    Dictionary(uniqueKeysWithValues: String.bpmfReplacements.map { ($1, $0) })
  }()
}

// MARK: - ChewingCBasedDatabaseGenerator

enum ChewingCBasedDatabaseGenerator {
  // MARK: Internal

  struct GeneratedArtifacts {
    let dictionary: Data
    let indexTree: Data
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

  static func writeArtifacts(
    phoneCinURL: URL,
    tsiSrcURL: URL,
    outputDirectory: URL
  ) throws {
    let phoneCin = try String(contentsOf: phoneCinURL, encoding: .utf8)
    let tsiSrc = try String(contentsOf: tsiSrcURL, encoding: .utf8)
    let artifacts = try generateArtifacts(phoneCin: phoneCin, tsiSrc: tsiSrc)

    try FileManager.default.createDirectory(
      at: outputDirectory,
      withIntermediateDirectories: true
    )

    try artifacts.dictionary.write(to: outputDirectory.appendingPathComponent(dictionaryFileName))
    try artifacts.indexTree.write(to: outputDirectory.appendingPathComponent(indexTreeFileName))
  }

  static func generateArtifacts(
    phoneCin: String,
    tsiSrc: String
  ) throws
    -> GeneratedArtifacts {
    var words = try parsePhoneCin(phoneCin)
    let wordLookup = Dictionary(
      uniqueKeysWithValues: words.enumerated().map { index, word in
        (WordKey(scalar: word.scalar, phone: word.phone), index)
      }
    )
    var wordMatched = Array(repeating: false, count: words.count)
    var phrases = try parseTsiSrc(
      tsiSrc,
      wordLookup: wordLookup,
      wordMatched: &wordMatched
    )

    let dictionary = try makeDictionaryData(words: &words, phrases: &phrases)
    let indexTree = try makeIndexTreeData(words: words, phrases: phrases)
    return GeneratedArtifacts(dictionary: dictionary, indexTree: indexTree)
  }

  // MARK: Private

  private struct WordKey: Hashable {
    let scalar: UInt32
    let phone: UInt16
  }

  private struct PhraseKey: Hashable {
    let phrase: String
    let phones: [UInt16]
  }

  private struct ExceptionPhraseEntry {
    let phrase: String
    let phones: [UInt16]
  }

  private struct ExceptionWordEntry {
    let scalar: UInt32
    let phone: UInt16
  }

  private struct WordRecord {
    let phrase: String
    let scalar: UInt32
    let phone: UInt16
    let index: Int
    var pos: UInt32 = 0
  }

  private struct PhraseRecord {
    let phrase: String
    let freq: UInt32
    let phones: [UInt16]
    var pos: UInt32 = 0
  }

  private struct LeafRecord {
    let phrasePos: UInt32
    let phraseFreq: UInt32
    let insertionOrder: Int
  }

  private final class TreeNode {
    // MARK: Lifecycle

    init(key: UInt16) {
      self.originalKey = key
      self.outputKey = key
    }

    // MARK: Internal

    let originalKey: UInt16
    var outputKey: UInt16
    var childBegin: UInt32 = 0
    var childEnd: UInt32 = 0
    var phrasePos: UInt32 = 0
    var phraseFreq: UInt32 = 0
    var internalChildren = [TreeNode]()
    var leaves = [LeafRecord]()

    var isLeaf: Bool { originalKey == 0 }
  }

  private static let dictionaryFileName = "dictionary.dat"
  private static let indexTreeFileName = "index_tree.dat"
  private static let maxPhraseLength = 11
  private static let uint24Max = 0xFF_FFFF

  private static let exceptionPhrases: [ExceptionPhraseEntry] = [
    ("好萊塢", ["ㄏㄠˇ", "ㄌㄞˊ", "ㄨ"]),
    ("成日家", ["ㄔㄥˊ", "ㄖˋ", "ㄐㄧㄚ˙"]),
    ("俾倪", ["ㄅㄧˋ", "ㄋㄧˋ"]),
    ("揩油", ["ㄎㄚ", "ㄧㄡˊ"]),
    ("敁敪", ["ㄉㄧㄢ", "ㄉㄨㄛ˙"]),
    ("一骨碌", ["ㄧ", "ㄍㄨˊ", "ㄌㄨ˙"]),
    ("邋遢", ["ㄌㄚˊ", "ㄊㄚ˙"]),
    ("溜達", ["ㄌㄧㄡˋ", "ㄉㄚ˙"]),
    ("遛達", ["ㄌㄧㄡˋ", "ㄉㄚ˙"]),
    ("大夫", ["ㄉㄞˋ", "ㄈㄨ˙"]),
    ("咖喱", ["ㄍㄚ", "ㄌㄧˊ"]),
    ("咖喱汁", ["ㄍㄚ", "ㄌㄧˊ", "ㄓ"]),
    ("咖喱粉", ["ㄍㄚ", "ㄌㄧˊ", "ㄈㄣˇ"]),
    ("咖喱雞", ["ㄍㄚ", "ㄌㄧˊ", "ㄐㄧ"]),
    ("咖喱飯", ["ㄍㄚ", "ㄌㄧˊ", "ㄈㄢˋ"]),
  ].map { phrase, phones in
    ExceptionPhraseEntry(
      phrase: phrase,
      phones: phones.map { token in
        guard let encoded = ChewingPhoneEncoder.uintFromPhone(token) else {
          preconditionFailure("Invalid exception phrase phone token: \(token)")
        }
        return encoded
      }
    )
  }

  private static let exceptionWords: [ExceptionWordEntry] = [
    ("嗦", "ㄙㄨㄛ˙"),
    ("巴", "ㄅㄚ˙"),
    ("伙", "ㄏㄨㄛ˙"),
  ].map { phrase, phone in
    guard let scalar = phrase.unicodeScalars.first,
          phrase.unicodeScalars.count == 1,
          let encoded = ChewingPhoneEncoder.uintFromPhone(phone)
    else {
      preconditionFailure("Invalid exception word entry: \(phrase) / \(phone)")
    }
    return ExceptionWordEntry(scalar: scalar.value, phone: encoded)
  }
}

extension ChewingCBasedDatabaseGenerator {
  private static let fieldSeparators: Set<Character> = [" ", "\t"]

  private static func renderedLine(_ line: Substring) -> String {
    String(line)
  }

  private static func phraseScalars(of phrase: String) -> [UInt32] {
    phrase.unicodeScalars.map(\.value)
  }
}

extension ChewingCBasedDatabaseGenerator {
  private static func parsePhoneCin(_ contents: String) throws -> [WordRecord] {
    enum ParseState {
      case searchingBegin
      case readingDefinitions
      case finished
    }

    var state = ParseState.searchingBegin
    var words = [WordRecord]()

    for (offset, rawLine) in contents.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
      .enumerated() {
      let lineNumber = offset + 1
      let line = stripLine(rawLine)
      let tokens = splitFields(line)

      switch state {
      case .searchingBegin:
        guard let first = tokens.first else { continue }
        if first == "%chardef" {
          guard tokens.count >= 2 else {
            throw GeneratorError.message("Unexpected %chardef declaration in line \(lineNumber).")
          }
          guard tokens[1] == "begin" else {
            throw GeneratorError.message("Unexpected %chardef \(tokens[1]) in line \(lineNumber).")
          }
          state = .readingDefinitions
        }

      case .readingDefinitions:
        if tokens.first == "%chardef" {
          guard tokens.count >= 2 else {
            throw GeneratorError.message("Unexpected %chardef declaration in line \(lineNumber).")
          }
          guard tokens[1] == "end" else {
            throw GeneratorError.message("Unexpected %chardef \(tokens[1]) in line \(lineNumber).")
          }
          state = .finished
          continue
        }

        guard !tokens.isEmpty else { continue }
        guard tokens.count >= 2 else {
          throw GeneratorError.message("Error reading line \(lineNumber), `\(renderedLine(line))`.")
        }
        guard tokens[0].count <= 4 else {
          throw GeneratorError.message("Error reading line \(lineNumber), `\(renderedLine(line))`.")
        }
        guard let phone = ChewingPhoneEncoder.uintFromDachenKey(tokens[0]) else {
          throw GeneratorError.message("Error reading line \(lineNumber), `\(renderedLine(line))`.")
        }

        let phrase = String(tokens[1])
        guard let scalar = phrase.unicodeScalars.first, phrase.unicodeScalars.count == 1 else {
          throw GeneratorError.message("Error reading line \(lineNumber), `\(renderedLine(line))`.")
        }
        words.append(WordRecord(phrase: phrase, scalar: scalar.value, phone: phone, index: words.count))

      case .finished:
        break
      }
    }

    guard state != .searchingBegin else {
      throw GeneratorError.message("No expected %chardef begin in phone.cin.")
    }
    guard state == .finished else {
      throw GeneratorError.message("No expected %chardef end in phone.cin.")
    }

    words.sort { lhs, rhs in
      let phraseComparison = compareBytes(lhs.phrase, rhs.phrase)
      if phraseComparison != .orderedSame {
        return phraseComparison == .orderedAscending
      }
      return lhs.phone < rhs.phone
    }

    for index in 1 ..< words.count {
      let previous = words[index - 1]
      let current = words[index]
      if previous.phrase == current.phrase, previous.phone == current.phone {
        throw GeneratorError.message("Duplicated word found (`\(current.phrase)', \(current.phone)).")
      }
    }

    return words
  }

  private static func parseTsiSrc(
    _ contents: String,
    wordLookup: [WordKey: Int],
    wordMatched: inout [Bool]
  ) throws
    -> [PhraseRecord] {
    var phrases = [PhraseRecord]()
    var seenKeys = Set<PhraseKey>()

    for (offset, rawLine) in contents.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
      .enumerated() {
      let lineNumber = offset + 1
      let line = stripLine(rawLine)
      if line.isEmpty { continue }

      let tokens = splitFields(line)
      guard tokens.count >= 3 else {
        throw GeneratorError.message("Error reading line \(lineNumber), `\(renderedLine(line))`.")
      }

      let phrase = String(tokens[0])
      guard let rawFreq = Int64(tokens[1]) else {
        throw GeneratorError.message(
          "Error reading frequency `\(tokens[1])' in line \(lineNumber), `\(renderedLine(line))`."
        )
      }

      let phraseScalars = phraseScalars(of: phrase)
      let phoneTokenCount = tokens.count - 2
      guard phoneTokenCount <= maxPhraseLength else {
        throw GeneratorError.message("Phrase `\(phrase)' too long in line \(lineNumber).")
      }
      guard phraseScalars.count == phoneTokenCount else {
        throw GeneratorError.message(
          "Phrase length and bopomofo length mismatch in line \(lineNumber), `\(renderedLine(line))`."
        )
      }

      var phones = [UInt16]()
      phones.reserveCapacity(phoneTokenCount)
      for token in tokens.dropFirst(2) {
        guard let encoded = ChewingPhoneEncoder.uintFromPhone(token) else {
          throw GeneratorError.message(
            "Error reading bopomofo `\(token)' in line \(lineNumber), `\(renderedLine(line))`."
          )
        }
        phones.append(encoded)
      }

      if phraseScalars.count == 1, shouldIgnoreSingleCharacterEntry(rawFrequency: rawFreq) {
        continue
      }

      var foundWordIndex: Int?
      for (position, scalarValue) in phraseScalars.enumerated() {
        let key = WordKey(scalar: scalarValue, phone: phones[position])
        foundWordIndex = wordLookup[key]
        if foundWordIndex == nil || (phraseScalars.count == 1 && wordMatched[foundWordIndex!]) {
          guard isExceptionPhrase(phrase: phrase, phones: phones, scalarWords: phraseScalars, position: position) else {
            let word = Unicode.Scalar(scalarValue).map(String.init) ?? ""
            throw GeneratorError.message(
              "Error in phrase `\(phrase)'. Word `\(word)' has no phone \(phones[position]) in line \(lineNumber)."
            )
          }
        }
      }

      if phraseScalars.count >= 2 {
        guard let freq = normalizePhraseFrequency(rawFreq) else {
          throw GeneratorError.message(
            "Error reading frequency `\(tokens[1])' in line \(lineNumber), `\(renderedLine(line))`."
          )
        }
        let key = PhraseKey(phrase: phrase, phones: phones)
        guard seenKeys.insert(key).inserted else {
          throw GeneratorError.message("Duplicated phrase `\(phrase)' found.")
        }
        phrases.append(PhraseRecord(phrase: phrase, freq: freq, phones: phones))
      } else if let foundWordIndex {
        wordMatched[foundWordIndex] = true
      }
    }

    phrases.sort { lhs, rhs in
      let phraseComparison = compareBytes(lhs.phrase, rhs.phrase)
      if phraseComparison != .orderedSame {
        return phraseComparison == .orderedAscending
      }
      return lhs.freq > rhs.freq
    }

    return phrases
  }

  private static func isExceptionPhrase(
    phrase: String,
    phones: [UInt16],
    scalarWords: [UInt32],
    position: Int
  )
    -> Bool {
    if exceptionPhrases.contains(where: { $0.phrase == phrase && $0.phones == phones }) {
      return true
    }

    if exceptionWords.contains(where: { $0.scalar == scalarWords[position] && $0.phone == phones[position] }) {
      return true
    }

    guard position > 0, scalarWords[position - 1] == scalarWords[position] else {
      return false
    }
    return ((phones[position - 1] & ~0x7) | 0x1) == phones[position]
  }
}

extension ChewingCBasedDatabaseGenerator {
  private static func makeDictionaryData(
    words: inout [WordRecord],
    phrases: inout [PhraseRecord]
  ) throws
    -> Data {
    // 下述運算必須拆開，不能將兩個算式直接相加，否則 Windows 版 Swift 無法正常解讀。
    let estimatedSizeOfWords = words.reduce(into: 0) { partialResult, word in
      partialResult += word.phrase.utf8.count + 1
    }
    let estimatedSizeOfPhrases = phrases.reduce(into: 0) { partialResult, phrase in
      partialResult += phrase.phrase.utf8.count + 1
    }
    let estimatedSize = estimatedSizeOfWords + estimatedSizeOfPhrases

    var dictionary = Data()
    dictionary.reserveCapacity(estimatedSize)
    var lastPhrase: String?
    var lastOffset: UInt32 = 0
    var wordIndex = 0
    var phraseIndex = 0

    while wordIndex < words.count || phraseIndex < phrases.count {
      let useWord: Bool = if wordIndex == words.count {
        false
      } else if phraseIndex == phrases.count {
        true
      } else {
        compareBytes(words[wordIndex].phrase, phrases[phraseIndex].phrase) == .orderedAscending
      }

      if useWord {
        if words[wordIndex].phrase == lastPhrase {
          words[wordIndex].pos = lastOffset
        } else {
          let offset = try appendDictionaryEntry(words[wordIndex].phrase, to: &dictionary)
          words[wordIndex].pos = offset
          lastPhrase = words[wordIndex].phrase
          lastOffset = offset
        }
        wordIndex += 1
      } else {
        if phrases[phraseIndex].phrase == lastPhrase {
          phrases[phraseIndex].pos = lastOffset
        } else {
          let offset = try appendDictionaryEntry(phrases[phraseIndex].phrase, to: &dictionary)
          phrases[phraseIndex].pos = offset
          lastPhrase = phrases[phraseIndex].phrase
          lastOffset = offset
        }
        phraseIndex += 1
      }
    }

    return dictionary
  }

  private static func appendDictionaryEntry(_ phrase: String, to dictionary: inout Data) throws -> UInt32 {
    guard dictionary.count <= uint24Max else {
      throw GeneratorError.message("Dictionary data exceeded 24-bit offset limit.")
    }
    let offset = UInt32(dictionary.count)
    dictionary.append(contentsOf: phrase.utf8)
    dictionary.append(0)
    return offset
  }

  private static func makeIndexTreeData(words: [WordRecord], phrases: [PhraseRecord]) throws -> Data {
    let root = TreeNode(key: 1)
    var nextLeafInsertionOrder = 0

    let wordsByPhone = words.sorted { lhs, rhs in
      if lhs.phone != rhs.phone { return lhs.phone > rhs.phone }
      return lhs.index > rhs.index
    }

    for word in wordsByPhone {
      let level = findOrInsert(parent: root, key: word.phone)
      appendLeaf(parent: level, phrasePos: word.pos, freq: 0, insertionOrder: nextLeafInsertionOrder)
      nextLeafInsertionOrder += 1
    }

    for phrase in phrases {
      var level = root
      for phone in phrase.phones {
        level = findOrInsert(parent: level, key: phone)
      }
      appendLeaf(parent: level, phrasePos: phrase.pos, freq: phrase.freq, insertionOrder: nextLeafInsertionOrder)
      nextLeafInsertionOrder += 1
    }

    var flatNodes = [root]
    var cursor = 0
    while cursor < flatNodes.count {
      let current = flatNodes[cursor]
      if !current.isLeaf {
        let children = orderedChildren(of: current)
        if !children.isEmpty {
          current.childBegin = UInt32(flatNodes.count)
          flatNodes.append(contentsOf: children)
          current.childEnd = UInt32(flatNodes.count)
        }
      }
      cursor += 1
    }

    root.outputKey = UInt16(truncatingIfNeeded: flatNodes.count)

    var data = Data(capacity: flatNodes.count * 8)
    for node in flatNodes {
      appendUInt16(node.outputKey, to: &data)
      if node.isLeaf {
        try appendUInt24(node.phrasePos, to: &data)
        try appendUInt24(node.phraseFreq, to: &data)
      } else {
        try appendUInt24(node.childBegin, to: &data)
        try appendUInt24(node.childEnd, to: &data)
      }
    }
    return data
  }

  private static func findOrInsert(parent: TreeNode, key: UInt16) -> TreeNode {
    let lookup = internalChildLookup(in: parent.internalChildren, key: key)
    if lookup.found {
      return parent.internalChildren[lookup.index]
    }

    let newNode = TreeNode(key: key)
    parent.internalChildren.insert(newNode, at: lookup.index)
    return newNode
  }

  private static func internalChildLookup(in children: [TreeNode], key: UInt16) -> (found: Bool, index: Int) {
    var lowerBound = 0
    var upperBound = children.count

    while lowerBound < upperBound {
      let middle = (lowerBound + upperBound) / 2
      let currentKey = children[middle].originalKey
      if currentKey == key {
        return (true, middle)
      }
      if currentKey < key {
        lowerBound = middle + 1
      } else {
        upperBound = middle
      }
    }

    return (false, lowerBound)
  }

  private static func appendLeaf(parent: TreeNode, phrasePos: UInt32, freq: UInt32, insertionOrder: Int) {
    parent.leaves.append(.init(phrasePos: phrasePos, phraseFreq: freq, insertionOrder: insertionOrder))
  }

  private static func orderedChildren(of node: TreeNode) -> [TreeNode] {
    var result = [TreeNode]()
    result.reserveCapacity(node.leaves.count + node.internalChildren.count)

    let leaves = node.leaves.count > 1
      ? node.leaves.sorted { lhs, rhs in
        if lhs.phraseFreq != rhs.phraseFreq {
          return lhs.phraseFreq > rhs.phraseFreq
        }
        return lhs.insertionOrder > rhs.insertionOrder
      }
      : node.leaves

    for leafRecord in leaves {
      let leaf = TreeNode(key: 0)
      leaf.phrasePos = leafRecord.phrasePos
      leaf.phraseFreq = leafRecord.phraseFreq
      result.append(leaf)
    }

    result.append(contentsOf: node.internalChildren)
    return result
  }

  private static func stripLine(_ line: Substring) -> Substring {
    var result = line
    if let commentStart = result.firstIndex(of: "#") {
      result = result[..<commentStart]
    }
    while let last = result.last, last.isWhitespace {
      result = result.dropLast()
    }
    return result
  }

  private static func splitFields(_ line: Substring) -> [Substring] {
    line.split(whereSeparator: { fieldSeparators.contains($0) })
  }
}

extension ChewingCBasedDatabaseGenerator {
  private static func compareBytes(_ lhs: String, _ rhs: String) -> ComparisonResult {
    let left = lhs.utf8
    let right = rhs.utf8

    var leftIterator = left.makeIterator()
    var rightIterator = right.makeIterator()

    while let leftByte = leftIterator.next(), let rightByte = rightIterator.next() {
      if leftByte < rightByte { return .orderedAscending }
      if leftByte > rightByte { return .orderedDescending }
    }

    if left.count == right.count { return .orderedSame }
    return left.count < right.count ? .orderedAscending : .orderedDescending
  }

  private static func appendUInt16(_ value: UInt16, to data: inout Data) {
    data.append(UInt8(truncatingIfNeeded: value))
    data.append(UInt8(truncatingIfNeeded: value >> 8))
  }

  private static func appendUInt24(_ value: UInt32, to data: inout Data) throws {
    guard value <= UInt32(uint24Max) else {
      throw GeneratorError.message("24-bit value overflow while serializing index tree.")
    }
    data.append(UInt8(truncatingIfNeeded: value))
    data.append(UInt8(truncatingIfNeeded: value >> 8))
    data.append(UInt8(truncatingIfNeeded: value >> 16))
  }

  private static func normalizePhraseFrequency(
    _ rawFrequency: Int64
  )
    -> UInt32? {
    guard rawFrequency >= 0 else { return nil }
    guard rawFrequency <= Int64(UInt32.max) else {
      return nil
    }
    return UInt32(rawFrequency)
  }

  private static func shouldIgnoreSingleCharacterEntry(rawFrequency: Int64) -> Bool {
    rawFrequency < 0
  }
}
