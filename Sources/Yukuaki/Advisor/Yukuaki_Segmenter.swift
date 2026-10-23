// (c) 2025 and onwards The vChewing Project (MulanPSL-2.0 License).
// ====================
// This code is released under the SPDX-License-Identifier: `MulanPSL-2.0`.

extension Yukuaki {
  /// 期望結果的分詞器。把「給定的期望字串」拆成各種可能的詞段組合，
  /// 每段都必須與對應的讀音對齊、且讀音數與字數相等。
  public enum Segmenter {
    /// 一個詞段：讀音、詞、起點。
    public struct Chunk: Hashable, Codable, Sendable {
      public let keyArray: [String]
      public let value: String
      public let start: Int
      public let segLength: Int

      public var end: Int { start + segLength }
      public var asGram: Yukuaki.Gram { .init(keyArray: keyArray, current: value) }
    }

    /// 枚舉所有可行分段。
    /// - Parameters:
    ///   - values: 期望結果的字元陣列。
    ///   - keys: 讀音鏈。
    ///   - maxChunkLength: 單一詞段的讀音上限。
    ///   - limit: 最多回傳幾種分段。
    /// - Returns: 依「詞段長度遞減」的深度優先順序排出的分段清單。
    public static func alignments(
      values: [Character],
      keys: [String],
      maxChunkLength: Int = 10,
      limit: Int = 4_096
    )
      -> [[Chunk]] {
      guard values.count == keys.count, !values.isEmpty else { return [] }
      var results = [[Chunk]]()
      var buffer = [Chunk]()
      let upperbound = max(1, min(maxChunkLength, values.count))

      func walk(from position: Int) {
        guard results.count < limit else { return }
        if position == values.count {
          results.append(buffer)
          return
        }
        for length in stride(from: min(upperbound, values.count - position), through: 1, by: -1) {
          let value = String(values[position ..< (position + length)])
          let chunk = Chunk(
            keyArray: Array(keys[position ..< (position + length)]),
            value: value,
            start: position,
            segLength: length
          )
          buffer.append(chunk)
          walk(from: position + length)
          buffer.removeLast()
          guard results.count < limit else { return }
        }
      }

      walk(from: 0)
      return results
    }
  }
}
