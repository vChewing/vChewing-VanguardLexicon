// (c) 2025 and onwards The vChewing Project (MulanPSL-2.0 License).
// ====================
// This code is released under the SPDX-License-Identifier: `MulanPSL-2.0`.

import Foundation

// MARK: - UnigramSegmenter

/// 以單元圖詞頻做最短路分詞。
///
/// 分詞器本質上就是「詞典 ＋ 頻率」的 Viterbi；此處不引進任何外部詞典，
/// 而是直接以引擎自己的 `.txtMap` 單元圖為詞典與權重——統計單位因此與引擎一致，
/// 且整條路徑可由同一個 `.txtMap` 完全重建。
///
/// 邊權為 `p(word)`（`p` 為對數機率、越大越好）；未知單字以固定罰分自成一個節點。
struct UnigramSegmenter {
  // MARK: Lifecycle

  init(index: TxtMapUnigramIndex, maximumWordLength: Int? = nil) {
    self.index = index
    self.maximumWordLength = max(1, maximumWordLength ?? index.maximumValueLength)
  }

  // MARK: Internal

  struct Result {
    let words: [String]
    /// 連續兩個以上「詞表外單字」所組成的片段；此即「疑似缺詞」之訊號。
    let unknownRuns: [String]
  }

  let index: TxtMapUnigramIndex
  let maximumWordLength: Int

  /// 詞表外單字的罰分：等同「詞頻 0.5」之機率，與 `Collector` 對零頻詞的處置同數量級。
  var unknownCharacterProbability: Double { log10(0.5 / index.norm) }

  func segment(_ text: String) -> Result {
    let characters = Array(text)
    let count = characters.count
    guard count > 0 else { return Result(words: [], unknownRuns: []) }

    var scores = [Double](repeating: -.infinity, count: count + 1)
    var previousCut = [Int](repeating: 0, count: count + 1)
    scores[0] = 0

    for start in 0 ..< count where scores[start] > -.infinity {
      let limit = min(maximumWordLength, count - start)
      var length = limit
      while length >= 1 {
        let candidate = String(characters[start ..< (start + length)])
        let probability: Double? = if let known = index.probability(of: candidate) {
          known
        } else if length == 1 {
          unknownCharacterProbability
        } else {
          nil
        }
        if let probability {
          let total = scores[start] + probability
          if total > scores[start + length] {
            scores[start + length] = total
            previousCut[start + length] = start
          }
        }
        length -= 1
      }
    }

    var words = [String]()
    var cursor = count
    while cursor > 0 {
      let start = previousCut[cursor]
      words.append(String(characters[start ..< cursor]))
      cursor = start
    }
    words.reverse()

    return Result(words: Self.coalescingASCIIRuns(in: words), unknownRuns: Self.unknownRuns(in: words, index: index))
  }

  // MARK: Private

  private static let cjkRanges: [ClosedRange<UInt32>] = [
    0x4E00 ... 0x9FFF, // CJK Unified Ideographs
    0x3400 ... 0x4DBF, // Extension A
    0x20000 ... 0x2A6DF, // Extension B
    0x2A700 ... 0x2EBEF, // Extensions C–F
    0x30000 ... 0x323AF, // Extension G–H
    0xF900 ... 0xFAFF, // Compatibility Ideographs
  ]

  private static func isASCIIWordCharacter(_ character: Character) -> Bool {
    guard let scalar = character.unicodeScalars.first, character.unicodeScalars.count == 1 else { return false }
    return CharacterSet.alphanumerics.contains(scalar) && scalar.isASCII
  }

  /// 相鄰的 ASCII 英數片段併為一詞（`1`、`4`、`9` → `149`），既貼近實際書寫，也免於統計被數字切碎。
  static func coalescingASCIIRuns(in words: [String]) -> [String] {
    var result = [String]()
    var pending = ""
    func flush() {
      defer { pending = "" }
      if !pending.isEmpty { result.append(pending) }
    }
    for word in words {
      if word.count == 1, let character = word.first, isASCIIWordCharacter(character) {
        pending += word
      } else {
        flush()
        result.append(word)
      }
    }
    flush()
    return result
  }

  static func isCJK(_ character: Character) -> Bool {
    guard let scalar = character.unicodeScalars.first, character.unicodeScalars.count == 1 else { return false }
    return cjkRanges.contains { $0.contains(scalar.value) }
  }

  /// 疑似缺詞之偵測：連續兩字以上的「不在詞表裡的單字」。
  /// - Note: 不列純 ASCII／標點片段，否則數字與網址會塞滿報表。
  static func unknownRuns(in words: [String], index: TxtMapUnigramIndex) -> [String] {
    var runs = [String]()
    var current = [String]()
    func flush() {
      defer { current.removeAll() }
      guard current.count >= 2, current.allSatisfy({ $0.count == 1 }), current.allSatisfy({ isCJK($0.first!) }) else {
        return
      }
      runs.append(current.joined())
    }
    for word in words {
      let isKnown = index.unigram(word) != nil
      if !isKnown, word.count == 1 {
        current.append(word)
      } else {
        flush()
      }
    }
    flush()
    return runs
  }
}
