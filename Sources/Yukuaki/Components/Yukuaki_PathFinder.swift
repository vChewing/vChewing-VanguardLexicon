// (c) 2025 and onwards The vChewing Project (MulanPSL-2.0 License).
// ====================
// This code is released under the SPDX-License-Identifier: `MulanPSL-2.0`.

// MARK: - Yukuaki.PathFinder

extension Yukuaki {
  /// 動態規劃求最佳路徑。與 Homa 的 `Homa.PathFinder` 邏輯相同：
  /// 逐格推進，同一個「狀態」只保留分數最高的前驅。
  ///
  /// 這裡的狀態不是單純的「位置」，而是「位置＋前文」：到達某一格時，除了「走到哪裡」
  /// 之外還得記住「前面兩個詞分別是什麼」，因為同一個節點在不同前文下的分數不同
  /// （n-gram 加成只在命中前文時才生效）。
  ///
  /// 若只用「位置」當狀態（P324 之前的做法），就會在「左文脈還不足以定案」的格子提早
  /// 丟掉之後可能翻盤的候選：例如「要 ㄗㄞˋ ㄓㄜˋㄧㄤˋ」在走到「再」時只看得到
  /// 「要」，「再這樣」的加成要等到「這樣」被加入時才知道，於是「在」那條路早就被砍了，
  /// 右文脈的 n-gram 永遠沒有機會生效。把「前文」納入狀態之後，「在」與「再」兩條
  /// 假設都會活到「這樣」被評分的那一刻，再一起比較。
  public enum PathFinder {
    // MARK: Public

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

      // 只有出現在某條 gram 的前驗／前前驗欄位當中的詞值，才可能影響之後的估值。
      // 其餘詞值即使被記進狀態，也永遠命不中任何 n-gram，對未來等價於「沒有前文」，
      // 故一律收斂成 nil。這讓「沒有 n-gram 資料」的普通句子永遠只有一個狀態
      // （與 P324 之前的 1D DP 完全等價、不多花任何成本），真的有 n-gram 資料時
      // 才會分裂成多條假設。
      let relevantValues = Self.contextValues(in: segments)
      func canonicalized(_ value: String?) -> String? {
        guard let value, !value.isEmpty, relevantValues.contains(value) else { return nil }
        return value
      }

      var states = [State]()
      var layers = [[Int]](repeating: [], count: keyCount + 1)
      var layerLookup = [[Ctxt: Int]](repeating: [:], count: keyCount + 1)

      states.append(.init(
        position: 0,
        previous: nil,
        anterior: nil,
        score: 0,
        parentID: -1,
        gram: nil,
        isExplicit: false,
        segLength: 0
      ))
      layers[0].append(0)
      layerLookup[0][Ctxt(previous: nil, anterior: nil)] = 0

      for currentStart in 0 ..< keyCount {
        guard !layers[currentStart].isEmpty else { continue }
        guard let segment = segments[currentStart], !segment.isEmpty else { continue }
        let lengths = segment.keys.sorted()
        for stateID in layers[currentStart] {
          let state = states[stateID]
          for segLength in lengths {
            let nextStart = currentStart + segLength
            guard segLength > 0, nextStart <= keyCount, let node = segment[segLength] else { continue }
            for candidate in Self.candidates(
              of: node,
              previous: state.previous,
              anterior: state.anterior,
              relevantValues: relevantValues
            ) {
              let candidateScore = state.score + candidate.score
              let ctxt = Ctxt(
                previous: canonicalized(candidate.gram.current),
                anterior: canonicalized(state.previous)
              )
              if let existingID = layerLookup[nextStart][ctxt] {
                // 同分時首見者勝：先到的那條路徑留著，與既有行為一致。
                guard candidateScore > states[existingID].score else { continue }
                states[existingID] = .init(
                  position: currentStart,
                  previous: ctxt.previous,
                  anterior: ctxt.anterior,
                  score: candidateScore,
                  parentID: stateID,
                  gram: candidate.gram,
                  isExplicit: node.isExplicitlyOverridden,
                  segLength: segLength
                )
              } else {
                let newID = states.count
                states.append(
                  .init(
                    position: currentStart,
                    previous: ctxt.previous,
                    anterior: ctxt.anterior,
                    score: candidateScore,
                    parentID: stateID,
                    gram: candidate.gram,
                    isExplicit: node.isExplicitlyOverridden,
                    segLength: segLength
                  )
                )
                layerLookup[nextStart][ctxt] = newID
                layers[nextStart].append(newID)
              }
            }
          }
        }
      }

      // 終點的狀態可能不只一個（尾端還有沒被用掉的前文），取分數最高者；同分首見者勝。
      guard var bestID = layers[keyCount].first else { return ([], 0) }
      for stateID in layers[keyCount] where states[stateID].score > states[bestID].score {
        bestID = stateID
      }

      var path = [Yukuaki.GramInPath]()
      var cursor = bestID
      while cursor >= 0 {
        let state = states[cursor]
        if let gram = state.gram {
          path.append(.init(gram: gram, isExplicit: state.isExplicit))
          // 只在已經確定的勝出路徑上寫回節點狀態。DP 進行中不去動節點，
          // 否則同一節點會被「最後一次估值」污染，多假設之間的比較就不再可信。
          segments[state.position]?[state.segLength]?.adopt(gram: gram)
        }
        cursor = state.parentID
      }
      return (Array(path.reversed()), states[bestID].score)
    }

    // MARK: Internal

    /// 一筆 DP 狀態：到達 `position` 時，前兩詞分別是 `previous` 與 `anterior`。
    struct State {
      let position: Int
      let previous: String?
      let anterior: String?
      let score: Double
      let parentID: Int
      let gram: Yukuaki.Gram?
      let isExplicit: Bool
      let segLength: Int
    }

    /// DP 狀態鍵當中的前文部分。
    struct Ctxt: Hashable {
      let previous: String?
      let anterior: String?
    }

    /// 收集節點格裡所有被當作前驗詞／前前驗詞使用過的詞值。
    static func contextValues(in segments: [Int: Yukuaki.Segment]) -> Set<String> {
      var result = Set<String>()
      for segment in segments.values {
        for node in segment.values {
          for gram in node.grams {
            if let previous = gram.previous, !previous.isEmpty { result.insert(previous) }
            if let anterior = gram.anterior, !anterior.isEmpty { result.insert(anterior) }
          }
        }
      }
      return result
    }

    /// 枚舉一個節點在此前文下「所有值得繼續走下去的候選 gram」。
    ///
    /// 這是 P325 的另一半。只把「前文」塞進 DP 狀態還不夠：同一個節點（同一組讀音）
    /// 底下掛著多個同音詞時，若還是讓節點自己「挑一個最好的 gram」，那麼「在」與「再」
    /// 在節點內部就已經分出勝負了，右文脈的加成永遠沒有機會表態。
    /// 故這裡把「節點挑一個」改成「節點列出候選」，由 DP 帶著每條假設往前走。
    ///
    /// 候選的取捨（皆為精確規則，不是 beam）：
    /// - 每個「會被之後的 n-gram 引用到的詞值」各留一條假設（同詞值取機率最高的那條）。
    /// - 其餘 unigram 對未來而言彼此等價（都不會命中任何 n-gram），只留機率最高者。
    /// - 命中前文的 bigram／trigram 只要原始分數高過該節點的 unigram 基底，就是候選
    ///   （沿用 P324 既有的「加成須高於基底」門檻，避免低分的 junk n-gram 反客為主）；
    ///   其計分則按鏈長計次（`Gram.weightedScore(against:)`，P326 計分模型）：
    ///   bigram 的增益算一次（與舊行為相同）、trigram 算兩次。
    /// - 整個節點連一條 unigram 都沒有時，退回排序後的第一條 gram，與
    ///   `Yukuaki.Node.evaluate` 的無前文分支一致。
    static func candidates(
      of node: Yukuaki.Node,
      previous: String?,
      anterior: String?,
      relevantValues: Set<String>
    )
      -> [(gram: Yukuaki.Gram, score: Double)] {
      guard !node.grams.isEmpty else { return [] }
      switch node.currentOverrideType {
      case .withSpecified:
        guard let gram = node.currentGram ?? node.topUnigramGram else { return [] }
        return [(gram, node.overridingScore)]
      case .withTopGramScore:
        let gram = node.currentGram ?? node.grams[0]
        return [(gram, node.topUnigramGram?.probability ?? gram.probability)]
      case nil:
        break
      }

      let baseline = node.topUnigramGram?.probability ?? -.infinity
      var result = [(gram: Yukuaki.Gram, score: Double)]()
      var bestIrrelevantUnigram: (gram: Yukuaki.Gram, score: Double)?
      var bestRelevantUnigrams = [String: (gram: Yukuaki.Gram, score: Double)]()
      var hasUnigram = false
      for gram in node.grams {
        guard gram.isUnigram else {
          guard let previous, !previous.isEmpty, gram.previous == previous else { continue }
          guard gram.anterior == nil || gram.anterior == anterior else { continue }
          guard gram.probability > baseline else { continue }
          result.append((gram, gram.weightedScore(against: baseline)))
          continue
        }
        hasUnigram = true
        if relevantValues.contains(gram.current) {
          if let existing = bestRelevantUnigrams[gram.current], existing.score >= gram.probability { continue }
          bestRelevantUnigrams[gram.current] = (gram, gram.probability)
        } else if gram.probability > (bestIrrelevantUnigram?.score ?? -.infinity) {
          bestIrrelevantUnigram = (gram, gram.probability)
        }
      }
      result.append(contentsOf: bestRelevantUnigrams.values.sorted { $0.gram.current < $1.gram.current })
      if let bestIrrelevantUnigram { result.append(bestIrrelevantUnigram) }
      // 一條 unigram 都沒有的節點：退回排序後的第一條 gram，與 `Node.evaluate` 的無前文分支一致。
      guard hasUnigram || !result.isEmpty else { return [(node.grams[0], node.grams[0].probability)] }
      return result
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
