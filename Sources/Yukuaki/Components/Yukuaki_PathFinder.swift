// (c) 2025 and onwards The vChewing Project (MulanPSL-2.0 License).
// ====================
// This code is released under the SPDX-License-Identifier: `MulanPSL-2.0`.

// MARK: - Yukuaki.PathFinder

extension Yukuaki {
  /// 動態規劃求最佳路徑。與 Homa 的 `Homa.PathFinder` 邏輯相同：
  /// 以「起點」為狀態，逐格推進；同一個目標位置只保留分數最高的前驅。
  public enum PathFinder {
    /// 一條邊（一次幅節選擇）。
    public struct GramState: Hashable, Sendable {
      public let gram: Yukuaki.Gram?
      public let isExplicit: Bool
      public let segLength: Int
    }

    /// 求解最佳路徑，並把沿途選定的 gram 寫回節點格。
    /// - Parameters:
    ///   - segments: 節點格。會被就地寫回（節點的當前 gram 會同步成路徑上的選擇）。
    ///   - keyCount: 讀音總數。
    /// - Returns: 最佳路徑與其總分。無解時回傳空路徑與 0。
    public static func run(
      segments: inout [Int: Yukuaki.Segment],
      keyCount: Int
    )
      -> (path: [Yukuaki.GramInPath], score: Double) {
      guard !segments.isEmpty, keyCount > 0 else { return ([], 0) }
      var dp = [Double](repeating: -Double.infinity, count: keyCount + 1)
      var parent = [Int: GramState]()
      dp[0] = 0

      for currentStart in 0 ..< keyCount {
        guard dp[currentStart] > -Double.infinity else { continue }
        guard let segment = segments[currentStart], !segment.isEmpty else { continue }
        let previousValue = parent[currentStart]?.gram?.current
        let anteriorValue: String? = {
          guard let state = parent[currentStart], let gram = state.gram else { return nil }
          let previousStart = currentStart - state.segLength
          guard let previousState = parent[previousStart] else { return nil }
          guard let previousGram = previousState.gram else { return nil }
          _ = gram
          return previousGram.current
        }()
        for (segLength, node) in segment {
          let nextStart = currentStart + segLength
          guard nextStart <= keyCount, segLength > 0 else { continue }
          var nodeCopy = node
          let score = nodeCopy.adopt(previous: previousValue, anterior: anteriorValue)
          let candidateScore = dp[currentStart] + score
          guard candidateScore > dp[nextStart] else { continue }
          dp[nextStart] = candidateScore
          parent[nextStart] = .init(
            gram: nodeCopy.currentGram,
            isExplicit: nodeCopy.isExplicitlyOverridden,
            segLength: segLength
          )
          segments[currentStart]?[segLength] = nodeCopy
        }
      }

      guard dp[keyCount] > -Double.infinity else { return ([], 0) }
      var path = [Yukuaki.GramInPath]()
      var cursor = keyCount
      while cursor > 0 {
        guard let state = parent[cursor], let gram = state.gram, state.segLength > 0 else { return ([], 0) }
        path.append(.init(gram: gram, isExplicit: state.isExplicit))
        cursor -= state.segLength
      }
      return (Array(path.reversed()), dp[keyCount])
    }
  }
}

extension Yukuaki.Assembler {
  /// 重新求解一次最佳路徑，並把結果寫進組態。
  @discardableResult
  public func assemble() -> [Yukuaki.GramInPath] {
    let outcome = assembleWithScore()
    config.assembledSentence = outcome.path
    return outcome.path
  }

  /// 求解最佳路徑與其總分。
  public func assembleWithScore() -> (path: [Yukuaki.GramInPath], score: Double) {
    let outcome = Yukuaki.PathFinder.run(segments: &segments, keyCount: keys.count)
    return (outcome.path, outcome.score)
  }
}
