// (c) 2025 and onwards The vChewing Project (MulanPSL-2.0 License).
// ====================
// This code is released under the SPDX-License-Identifier: `MulanPSL-2.0`.

extension Yukuaki {
  /// 組句器。餵進一串讀音，吐出一條組句結果。
  ///
  /// 與 Homa 的 `Homa.Assembler` 相比，這裡去掉了游標、輸入法標記、行為感知、
  /// 節點覆寫鏡像與候選字輪替；剩下的就是「建立節點格 → 動態規劃 → 取路徑」。
  public final class Assembler {
    // MARK: Lifecycle

    public init(
      gramQuerier: @escaping Yukuaki.GramQuerier,
      gramAvailabilityChecker: Yukuaki.GramAvailabilityChecker? = nil,
      config: Yukuaki.Config = .init()
    ) {
      self.gramQuerier = gramQuerier
      self.gramAvailabilityChecker = gramAvailabilityChecker
      self.config = config
    }

    // MARK: Public

    /// 一次組句的候選路徑（用於「為什麼不是這一條」的診斷）。
    public struct CandidatePath: Codable, Hashable, Sendable {
      public let grams: [Yukuaki.GramInPath]
      public let score: Double

      public var text: String { grams.joinedSentence }
      public var keyArray: [String] { grams.flattenedKeys }
    }

    /// 節點格的傾印結果。
    public struct NodeDump: Hashable, Sendable {
      public struct Candidate: Hashable, Sendable {
        public let value: String
        public let probability: Double
      }

      public let position: Int
      public let segLength: Int
      public let keyArray: [String]
      public let gramCount: Int
      public let unigramCount: Int
      public let contextualCount: Int
      public let candidates: [Candidate]
    }

    /// 節點格的 Cartesian 展開上限。超過時把幅節上限壓到 4，與 Homa 的做法一致。
    public static let cartesianBudgetLimit = 625

    public internal(set) var config: Yukuaki.Config
    public private(set) var keys = [Yukuaki.PossibleKey]()
    public internal(set) var segments = [Int: Yukuaki.Segment]()

    /// 當前的組句結果。
    public var assembledSentence: [Yukuaki.GramInPath] { config.assembledSentence }

    /// 當前的組句結果攤成的字串。
    public var assembledText: String { config.assembledText }

    /// 該組句器是否為空。
    public var isEmpty: Bool { keys.isEmpty }

    /// 讀音數量。
    public var keyCount: Int { keys.count }

    /// 讀音鏈（每個按鍵取代表讀音）。
    public var representativeKeys: [String] { keys.representativeKeys }

    /// 清空組句器。
    public func clear() {
      keys.removeAll()
      segments.removeAll()
      gramQueryCache.removeAll()
      config.clear()
    }

    /// 餵入一批讀音並重新組句。
    public func insertKeys(_ possibleKeys: [Yukuaki.PossibleKey]) throws {
      guard !possibleKeys.isEmpty else { throw Yukuaki.Exception.givenKeyIsEmpty }
      guard possibleKeys.allSatisfy(\.isValid) else { throw Yukuaki.Exception.givenKeyIsEmpty }
      for key in possibleKeys {
        guard isKeyAvailable(key) else { throw Yukuaki.Exception.givenKeyHasNoResults(key.allValues) }
      }
      let backup = (keys: keys, segments: segments, sentence: config.assembledSentence)
      keys.append(contentsOf: possibleKeys)
      do {
        try assignNodes()
        let path = assemble()
        config.assembledSentence = path
      } catch {
        keys = backup.keys
        segments = backup.segments
        config.assembledSentence = backup.sentence
        throw error
      }
    }

    /// 以讀音字串餵入並重新組句。
    public func insertKeys(_ possibleKeys: [String]) throws {
      try insertKeys(possibleKeys.map { Yukuaki.PossibleKey.singleKey($0) })
    }

    /// 重建整個節點格。
    public func rebuild() throws {
      guard !keys.isEmpty else { return }
      try assignNodes()
      config.assembledSentence = assemble()
    }

    /// 傾印節點格。
    public func dumpNodes(limitPerNode: Int = 5) -> [NodeDump] {
      segments.keys.sorted().flatMap { position in
        segments[position, default: [:]].keys.sorted().compactMap { length -> NodeDump? in
          guard let node = segments[position]?[length] else { return nil }
          let sortedGrams = node.grams.sorted(by: Yukuaki.Node.sortGram)
          let candidates = sortedGrams
            .filter(\.isUnigram)
            .prefix(limitPerNode)
            .map { NodeDump.Candidate(value: $0.current, probability: $0.probability) }
          return NodeDump(
            position: position,
            segLength: length,
            keyArray: node.keyArray4Query,
            gramCount: node.grams.count,
            unigramCount: node.grams.filter(\.isUnigram).count,
            contextualCount: node.grams.filter { !$0.isUnigram }.count,
            candidates: Array(candidates)
          )
        }
      }
    }

    /// 以 beam search 取得最靠前的若干條候選路徑。
    /// - Note: 這是近似 k-best：每個位置只保留分數最高的 `limit` 條部分路徑。
    public func topPaths(limit: Int = 5) -> [CandidatePath] {
      guard !segments.isEmpty, !keys.isEmpty else { return [] }
      let width = max(1, limit)
      var partials: [Int: [CandidatePath]] = [0: [.init(grams: [], score: 0)]]
      for position in 0 ..< keys.count {
        guard let arrivals = partials[position], !arrivals.isEmpty else { continue }
        guard let segment = segments[position] else { continue }
        for arrival in arrivals {
          let previous = arrival.grams.last?.value
          let anterior = arrival.grams.dropLast().last?.value
          for length in segment.keys.sorted() {
            guard let node = segment[length] else { continue }
            let evaluation = node.evaluate(previous: previous, anterior: anterior)
            guard let gram = evaluation.gram else { continue }
            var grams = arrival.grams
            grams.append(.init(gram: gram, isExplicit: node.isExplicitlyOverridden))
            let next = CandidatePath(grams: grams, score: arrival.score + evaluation.score)
            partials[position + length, default: []].append(next)
          }
        }
        for (arrivalPosition, list) in partials where list.count > width {
          partials[arrivalPosition] = Array(list.sorted { $0.score > $1.score }.prefix(width))
        }
      }
      let finals = partials[keys.count] ?? []
      return Array(finals.sorted { $0.score > $1.score }.prefix(width))
    }

    // MARK: Private

    private struct QueryCacheKey: Hashable {
      let keys: [Yukuaki.PossibleKey]
    }

    private static let maxCachedQueries = 512

    private let gramQuerier: Yukuaki.GramQuerier
    private let gramAvailabilityChecker: Yukuaki.GramAvailabilityChecker?
    private var gramQueryCache = [QueryCacheKey: [Yukuaki.Gram]]()

    /// 依 Cartesian 展開量決定實際可用的幅節上限。
    private static func effectiveMaxSegLength(keys: [Yukuaki.PossibleKey], maxSegLength: Int) -> Int {
      func worstProduct(within maxLength: Int) -> Int {
        var worst = 1
        for position in keys.indices {
          var product = 1
          let upperbound = min(keys.count, position + maxLength)
          for cursor in position ..< upperbound {
            product = min(Int.max / 2, product * max(1, keys[cursor].count))
          }
          worst = max(worst, product)
        }
        return worst
      }
      var effective = maxSegLength
      while effective > 4, worstProduct(within: effective) > cartesianBudgetLimit {
        effective -= 1
      }
      return effective
    }

    /// 檢查該按鍵是否至少有一條詞條。
    private func isKeyAvailable(_ key: Yukuaki.PossibleKey) -> Bool {
      if let gramAvailabilityChecker { return gramAvailabilityChecker(key.allValues) }
      return !queryGrams([key]).isEmpty
    }

    /// 向辭典查詢 gram，並帶去重與快取。
    private func queryGrams(_ keys: [Yukuaki.PossibleKey]) -> [Yukuaki.Gram] {
      let cacheKey = QueryCacheKey(keys: keys)
      if let cached = gramQueryCache[cacheKey] { return cached }
      var seen = Set<Yukuaki.Gram>()
      var result = [Yukuaki.Gram]()
      for gram in gramQuerier(keys) where seen.insert(gram).inserted {
        result.append(gram)
      }
      result.sort(by: Yukuaki.Node.sortGram)
      if gramQueryCache.count >= Self.maxCachedQueries { gramQueryCache.removeAll(keepingCapacity: true) }
      gramQueryCache[cacheKey] = result
      return result
    }

    /// 建立整個節點格。
    private func assignNodes() throws {
      segments.removeAll()
      guard !keys.isEmpty else { throw Yukuaki.Exception.assemblerIsEmpty }
      let effectiveMaxSegLength = Self.effectiveMaxSegLength(keys: keys, maxSegLength: config.maxSegLength)
      var nodeCount = 0
      for position in 0 ..< keys.count {
        let upperbound = min(keys.count, position + effectiveMaxSegLength)
        guard upperbound > position else { continue }
        for length in 1 ... (upperbound - position) {
          let keySlice = Array(keys[position ..< (position + length)])
          let grams = queryGrams(keySlice)
          guard !grams.isEmpty else { continue }
          let node = Yukuaki.Node(keyArray4Query: keySlice.representativeKeys, grams: grams)
          segments[position, default: [:]][length] = node
          nodeCount += 1
        }
      }
      guard nodeCount > 0 else { throw Yukuaki.Exception.noNodesAssigned }
    }
  }
}
