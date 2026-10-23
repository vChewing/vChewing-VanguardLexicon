// (c) 2025 and onwards The vChewing Project (MulanPSL-2.0 License).
// ====================
// This code is released under the SPDX-License-Identifier: `MulanPSL-2.0`.

import Foundation

extension Yukuaki {
  /// Yukuaki 的另一半面相：給定讀音與期望結果之後，逆推「還缺哪些 bigram／trigram、
  /// 以及它們大約需要多高的出現頻次」。
  ///
  /// 作法是「先提議、再模擬驗證」：
  /// 1. 把期望結果切成所有可能的分詞；
  /// 2. 選一條與辭典落差最小的分詞；
  /// 3. 對該分詞上的每個詞、每個相鄰詞界、每個三詞窗，提議對應的 gram；
  /// 4. 以「詞典 ＋ 覆寫層」重新模擬組句，搜出「剛好夠用」的分數邊距；
  /// 5. 用該分數反推 count。
  ///
  /// 全程不涉及審字（perception）、不涉及輸入法狀態，也不會去改動辭典資料本身。
  public final class Advisor: @unchecked Sendable {
    // MARK: Lifecycle

    public init(
      gramQuerier: @escaping Yukuaki.GramQuerier,
      norm: Double? = nil,
      options: Options = .init()
    ) {
      self.gramQuerier = gramQuerier
      self.norm = norm
      self.options = options
    }

    // MARK: Public

    /// 逆推時的可調參數。
    public struct Options: Sendable {
      // MARK: Lifecycle

      public init() {}

      // MARK: Public

      /// 單一詞段的讀音上限。
      public var maxChunkLength = 10
      /// 最多枚舉幾種分詞。
      public var maxAlignments = 4_096
      /// 分數邊距的起點（log10 單位）。
      public var marginFloor = 0.001
      /// 分數邊距的上限。
      public var marginCeiling = 1_000_000.0
      /// 二分搜的精度。
      public var marginTolerance = 1e-4
      /// 分數邊距的倍增次數上限。
      public var maxMarginDoubling = 64
      /// 允許「新造詞」的讀音長度上限（既有詞條不受此限）。
      public var maxNewWordLength = 4
      /// 最多嘗試幾種分詞方式。
      public var maxAlignmentAttempts = 24
      /// 辭典內查無任何競品時，追補詞條所需分數的預設基準。
      ///
      /// 這個值對應 vChewing 詞庫編譯器的 `DEFAULT_PROB_9`（即「九字以下詞條的缺省分數」）。
      public var fallbackBaseline = -13.0
    }

    /// 一次逆推的完整結果。
    public struct Report: Codable, Sendable {
      /// 模擬驗證的結果。
      public struct Validation: Codable, Sendable {
        public let isSatisfied: Bool
        public let margin: Double
        public let finalText: String
        public let finalScore: Double
      }

      public let readingChain: [String]
      public let expected: String
      public let assembledText: String
      public let assembledScore: Double
      public let assembledPath: [Yukuaki.GramInPath]
      public let isMatched: Bool
      public let alignmentCount: Int
      public let alignment: [Yukuaki.Segmenter.Chunk]
      public let proposals: [Yukuaki.GramSpec]
      public let validation: Validation?
      public let notes: [String]
    }

    public let options: Options
    public let norm: Double?

    /// 執行一次逆推。
    public func analyze(readingChain: [String], expected: String) throws -> Report {
      let values = Array(expected)
      guard values.count == readingChain.count else {
        throw Yukuaki.Exception.expectedReadingMismatch(
          expected: values.count,
          reading: readingChain.count
        )
      }
      guard !readingChain.isEmpty else { throw Yukuaki.Exception.invalidReadingChain("讀音鏈為空。") }
      baseQueryCache.removeAll()
      seenContextual = false

      guard let current = assemble(readingChain: readingChain, overrides: [:]) else {
        throw Yukuaki.Exception.noFeasibleSegmentation(readingChain.joined(separator: "-"))
      }
      var notes = [String]()
      if !seenContextual {
        notes.append("目前的詞庫資料內沒有任何 bigram／trigram：所有候選詞條都是 unigram，故前文永遠不會參與評分。")
      }

      guard current.path.joinedSentence != expected else {
        return Report(
          readingChain: readingChain,
          expected: expected,
          assembledText: current.path.joinedSentence,
          assembledScore: current.score,
          assembledPath: current.path,
          isMatched: true,
          alignmentCount: 0,
          alignment: [],
          proposals: [],
          validation: nil,
          notes: notes + ["預設組句結果與期望結果一致，無需追補任何詞條。"]
        )
      }

      let alignments = Yukuaki.Segmenter.alignments(
        values: values,
        keys: readingChain,
        maxChunkLength: options.maxChunkLength,
        limit: options.maxAlignments
      )
      guard !alignments.isEmpty else {
        throw Yukuaki.Exception.noFeasibleSegmentation(expected)
      }

      /// 需要新造的詞，其讀音長度不得超過上限；既有詞條不受此限。
      func acceptable(_ alignment: [Yukuaki.Segmenter.Chunk]) -> Bool {
        alignment.allSatisfy { chunk in
          guard chunk.segLength > options.maxNewWordLength else { return true }
          return exists(Yukuaki.Gram(keyArray: chunk.keyArray, current: chunk.value))
        }
      }
      func ordered(_ candidates: [[Yukuaki.Segmenter.Chunk]]) -> [[Yukuaki.Segmenter.Chunk]] {
        candidates
          .map { (alignment: $0, penalty: penaltyOf(alignment: $0)) }
          .sorted { lhs, rhs in
            if lhs.penalty != rhs.penalty { return lhs.penalty < rhs.penalty }
            if lhs.alignment.count != rhs.alignment.count {
              return lhs.alignment.count < rhs.alignment.count
            }
            return lhs.alignment.map(\.value).joined() < rhs.alignment.map(\.value).joined()
          }
          .map(\.alignment)
      }
      let filtered = ordered(alignments.filter(acceptable))
      let orderedAlignments = filtered.isEmpty ? ordered(alignments) : filtered

      var fallbackReport: Report?
      for alignment in orderedAlignments.prefix(max(1, options.maxAlignmentAttempts)) {
        /// 貴的排前面：`minimize` 由前刪起，於是它會優先扔掉證據成本高的提案。
        let candidates = proposalCandidates(for: alignment, current: current.path)
          .sorted { tier(of: $0) > tier(of: $1) }
        guard !candidates.isEmpty else { continue }
        guard let workingMargin = searchWorkingMargin(
          readingChain: readingChain,
          expected: expected,
          candidates: candidates
        ) else { continue }
        let minimal = consolidate(
          minimize(
            candidates: candidates,
            readingChain: readingChain,
            expected: expected,
            margin: workingMargin
          ),
          readingChain: readingChain,
          expected: expected
        )
        guard let minimalMargin = searchWorkingMargin(
          readingChain: readingChain,
          expected: expected,
          candidates: minimal
        ) else { continue }
        let tightMargin = tighten(
          candidates: minimal,
          readingChain: readingChain,
          expected: expected,
          workingMargin: minimalMargin
        )
        let validation = validate(
          candidates: minimal,
          readingChain: readingChain,
          expected: expected,
          margin: tightMargin
        )
        let specs = minimal
          .map { spec in
            Yukuaki.GramSpec(
              gram: spec,
              role: roleOf(spec, alignment: alignment),
              requiredProbability: baselineProbability(of: spec) + tightMargin,
              norm: norm,
              tier: tier(of: spec)
            )
          }
          .sorted { lhs, rhs in
            if lhs.tier != rhs.tier { return lhs.tier < rhs.tier }
            return lhs.keyArray.count > rhs.keyArray.count
          }
        var attemptNotes = notes
        if norm == nil {
          attemptNotes.append("未取得辭典的正規化基準（_NORM），故無法逆推 count。")
        }
        if specs.contains(where: { !$0.isCountExpressive }) {
          attemptNotes.append("有提案的逆推 count 不到 1：這代表以現行正規化基準而言，單靠詞頻已經抬不到那個分數，需要改動正規化、或改以更高階的 n-gram 處理。")
        }
        attemptNotes.append("已排除審字因素：本工具只考慮「讀音 → 詞」的評分，不考慮半衰記憶、聯想、候選字輪替等輸入法行為。")
        let report = Report(
          readingChain: readingChain,
          expected: expected,
          assembledText: current.path.joinedSentence,
          assembledScore: current.score,
          assembledPath: current.path,
          isMatched: false,
          alignmentCount: alignments.count,
          alignment: alignment,
          proposals: specs,
          validation: validation,
          notes: attemptNotes
        )
        /// 能以整數頻次表達者優先；否則先留著，繼續試下一個分詞方式。
        if norm == nil || specs.allSatisfy(\.isCountExpressive) { return report }
        if fallbackReport == nil { fallbackReport = report }
      }
      if let fallbackReport { return fallbackReport }

      return Report(
        readingChain: readingChain,
        expected: expected,
        assembledText: current.path.joinedSentence,
        assembledScore: current.score,
        assembledPath: current.path,
        isMatched: false,
        alignmentCount: alignments.count,
        alignment: orderedAlignments.first ?? [],
        proposals: [],
        validation: nil,
        notes: notes + ["期望結果的每個詞都在辭典內、分數卻仍不足以勝出：此情形無法靠追補詞條解決（除非改動既有的競爭詞條）。"]
      )
    }

    /// 以給定的提案集合重新組句。
    ///
    /// 這是「跨句交叉驗證」的入口：把甲句的提案套到乙句上，看它會不會把乙句弄壞。
    /// 單句逆推永遠無法發現這種衝突，因為它只看得見自己這一句。
    public func assembling(
      readingChain: [String],
      specs: [Yukuaki.GramSpec]
    )
      -> (text: String, score: Double)? {
      baseQueryCache.removeAll()
      var table = [GramKey: Yukuaki.Gram]()
      for spec in specs {
        table[GramKey(spec.gram)] = spec.gram
      }
      guard let outcome = assemble(readingChain: readingChain, overrides: table) else { return nil }
      return (text: outcome.path.joinedSentence, score: outcome.score)
    }

    // MARK: Private

    /// gram 的無識別碼鍵值。
    private struct GramKey: Hashable {
      // MARK: Lifecycle

      init(_ gram: Yukuaki.Gram) {
        self.keyArray = gram.keyArray
        self.current = gram.current
        self.previous = gram.previous
        self.anterior = gram.anterior
      }

      // MARK: Internal

      let keyArray: [String]
      let current: String
      let previous: String?
      let anterior: String?
    }

    private let gramQuerier: Yukuaki.GramQuerier
    private var baseQueryCache = [String: [Yukuaki.Gram]]()
    private var seenContextual = false

    // MARK: 辭典存取

    private func baseGrams(keys: [String]) -> [Yukuaki.Gram] {
      let cacheKey = keys.joined(separator: "-")
      if let cached = baseQueryCache[cacheKey] { return cached }
      let grams = gramQuerier(keys.map { Yukuaki.PossibleKey.singleKey($0) })
      if grams.contains(where: { !$0.isUnigram }) { seenContextual = true }
      baseQueryCache[cacheKey] = grams
      return grams
    }

    private func grams(keys: [String], overrides: [GramKey: Yukuaki.Gram]) -> [Yukuaki.Gram] {
      var result = baseGrams(keys: keys)
      let relevant = overrides.values.filter { $0.keyArray == keys }
      guard !relevant.isEmpty else { return result }
      let replaced = Set(relevant.map(GramKey.init))
      result.removeAll { replaced.contains(GramKey($0)) }
      result.append(contentsOf: relevant)
      return result.sorted(by: Yukuaki.Node.sortGram)
    }

    private func assemble(
      readingChain: [String],
      overrides: [GramKey: Yukuaki.Gram]
    )
      -> (path: [Yukuaki.GramInPath], score: Double)? {
      let assembler = Yukuaki.Assembler(
        gramQuerier: { [weak self] possibleKeys in
          guard let self else { return [] }
          return self.grams(keys: possibleKeys.representativeKeys, overrides: overrides)
        },
        config: Yukuaki.Config(maxSegLength: options.maxChunkLength)
      )
      do {
        try assembler.insertKeys(readingChain.map { Yukuaki.PossibleKey.singleKey($0) })
      } catch {
        return nil
      }
      return assembler.assembleWithScore()
    }

    private func works(
      _ candidates: [Yukuaki.Gram],
      margin: Double,
      readingChain: [String],
      expected: String
    )
      -> Bool {
      let table = overrides(candidates: candidates, margin: margin)
      guard let outcome = assemble(readingChain: readingChain, overrides: table) else { return false }
      return outcome.path.joinedSentence == expected
    }

    // MARK: 提案

    /// 該讀音下的競品基準分數（不含期望詞本身）。
    private func baselineProbability(of spec: Yukuaki.Gram) -> Double {
      let competitors = baseGrams(keys: spec.keyArray).filter { GramKey($0) != GramKey(spec) }
      let best = competitors.map(\.probability).max() ?? options.fallbackBaseline
      return max(best, options.fallbackBaseline)
    }

    /// 零頻次基線：`count = 0` 時 `Unigram.weighten` 給出的分數。
    ///
    /// `score = log10(e^(長度/3 − 1) × 0.25 / norm)`——詞頻為 0 的詞條，
    /// 其分數只由長度與正規化基準決定，故同長度的零頻次詞條分數全等。
    private func zeroCountBaseline(length: Int) -> Double? {
      guard let norm, norm > 0 else { return nil }
      return log10(exp(Double(length) / 3 - 1) * 0.25 / norm)
    }

    /// 該詞條的證據等級。
    private func tier(of gram: Yukuaki.Gram) -> Yukuaki.GramSpec.Tier {
      if gram.isTrigram { return .addTrigram }
      if gram.isBigram { return .addBigram }
      let key = GramKey(gram)
      guard let existing = baseGrams(keys: gram.keyArray).first(where: { GramKey($0) == key }) else {
        return .addUnigram
      }
      if let baseline = zeroCountBaseline(length: gram.current.count), existing.probability <= baseline + 1e-6 {
        return .fillMissingCount
      }
      return .adjustCount
    }

    private func exists(_ spec: Yukuaki.Gram) -> Bool {
      let key = GramKey(spec)
      return baseGrams(keys: spec.keyArray).contains { GramKey($0) == key }
    }

    /// 該分詞與辭典的落差。
    ///
    /// 缺詞的代價隨詞長平方成長（一字 4、兩字 9、三字 16……），因為「新造一個長詞」遠比
    /// 「補一條 bigram」更不可能成立；缺詞界 bigram 記 2 分、缺 trigram 記 1 分。
    private func penaltyOf(alignment: [Yukuaki.Segmenter.Chunk]) -> Int {
      var penalty = 0
      for chunk in alignment where !exists(Yukuaki.Gram(keyArray: chunk.keyArray, current: chunk.value)) {
        penalty += (chunk.segLength + 1) * (chunk.segLength + 1)
      }
      for index in 1 ..< alignment.count {
        let spec = Yukuaki.Gram(
          keyArray: alignment[index].keyArray,
          current: alignment[index].value,
          previous: alignment[index - 1].value
        )
        if !exists(spec) { penalty += 2 }
      }
      if alignment.count >= 3 {
        for index in 2 ..< alignment.count {
          let spec = Yukuaki.Gram(
            keyArray: alignment[index].keyArray,
            current: alignment[index].value,
            previous: alignment[index - 1].value,
            anterior: alignment[index - 2].value
          )
          if !exists(spec) { penalty += 1 }
        }
      }
      return penalty
    }

    /// 產生候選提案：先詞、再詞界、再三詞窗，最後補「把詞從現行長詞段裡拔出來」的 bigram。
    private func proposalCandidates(
      for alignment: [Yukuaki.Segmenter.Chunk],
      current: [Yukuaki.GramInPath]
    )
      -> [Yukuaki.Gram] {
      var specs = [Yukuaki.Gram]()
      for chunk in alignment {
        /// 每個詞段都當成候選：既有的詞只是「分數不夠高」，詞庫裡沒有的詞則是
        /// 「得新造」。兩者的差別由 `tier(of:)` 分級，再由 `minimize` 依證據成本
        /// 由貴到便宜地刪——故這裡不必先篩。
        specs.append(Yukuaki.Gram(keyArray: chunk.keyArray, current: chunk.value))
      }
      for index in 1 ..< alignment.count {
        let bigram = Yukuaki.Gram(
          keyArray: alignment[index].keyArray,
          current: alignment[index].value,
          previous: alignment[index - 1].value
        )
        if !exists(bigram) { specs.append(bigram) }
      }
      if alignment.count >= 3 {
        for index in 2 ..< alignment.count {
          let trigram = Yukuaki.Gram(
            keyArray: alignment[index].keyArray,
            current: alignment[index].value,
            previous: alignment[index - 1].value,
            anterior: alignment[index - 2].value
          )
          if !exists(trigram) { specs.append(trigram) }
        }
      }
      // 現行組句結果的「起點 → 詞段」對照。
      var currentSections = [(start: Int, section: Yukuaki.GramInPath)]()
      var position = 0
      for section in current {
        currentSections.append((position, section))
        position += section.segLength
      }
      for chunk in alignment {
        guard let entry = currentSections.first(where: { $0.start == chunk.start }) else { continue }
        guard entry.section.segLength != chunk.segLength || entry.section.value != chunk.value else { continue }
        guard let previousEntry = currentSections.last(where: { $0.start < chunk.start }) else { continue }
        let selecting = Yukuaki.Gram(
          keyArray: chunk.keyArray,
          current: chunk.value,
          previous: previousEntry.section.value
        )
        if !specs.contains(selecting), !exists(selecting) { specs.append(selecting) }
      }
      return specs
    }

    private func roleOf(
      _ spec: Yukuaki.Gram,
      alignment: [Yukuaki.Segmenter.Chunk]
    )
      -> Yukuaki.GramSpec.Role {
      if spec.isUnigram {
        return exists(spec) ? .boosting : .fabricating
      }
      let atExpectedChunk = alignment.contains { $0.keyArray == spec.keyArray && $0.value == spec.current }
      let previousIsNeighbor = alignment.contains { $0.value == spec.previous }
      guard atExpectedChunk, previousIsNeighbor else { return .selecting }
      return .boosting
    }

    // MARK: 模擬驗證

    private func overrides(candidates: [Yukuaki.Gram], margin: Double) -> [GramKey: Yukuaki.Gram] {
      var result = [GramKey: Yukuaki.Gram]()
      for candidate in candidates {
        let required = baselineProbability(of: candidate) + margin
        result[GramKey(candidate)] = Yukuaki.Gram(
          keyArray: candidate.keyArray,
          current: candidate.current,
          previous: candidate.previous,
          anterior: candidate.anterior,
          probability: required
        )
      }
      return result
    }

    /// 倍增搜出第一個可行的邊距。
    private func searchWorkingMargin(
      readingChain: [String],
      expected: String,
      candidates: [Yukuaki.Gram]
    )
      -> Double? {
      var margin = max(options.marginFloor, 1e-9)
      for _ in 0 ..< options.maxMarginDoubling {
        if works(candidates, margin: margin, readingChain: readingChain, expected: expected) {
          return margin
        }
        margin *= 2
        guard margin <= options.marginCeiling else { break }
      }
      return nil
    }

    /// 二分搜最小可行邊距。
    private func tighten(
      candidates: [Yukuaki.Gram],
      readingChain: [String],
      expected: String,
      workingMargin: Double
    )
      -> Double {
      var low = workingMargin / 2
      var high = workingMargin
      var rounds = 0
      while rounds < 32, high - low > options.marginTolerance {
        let middle = (low + high) / 2
        if works(candidates, margin: middle, readingChain: readingChain, expected: expected) {
          high = middle
        } else {
          low = middle
        }
        rounds += 1
      }
      return high
    }

    /// 貪婪縮減提案集合：逐一嘗試移除，若仍能達到期望結果就真的移除。
    private func minimize(
      candidates: [Yukuaki.Gram],
      readingChain: [String],
      expected: String,
      margin: Double
    )
      -> [Yukuaki.Gram] {
      var current = candidates
      var index = 0
      while index < current.count, current.count > 1 {
        var trial = current
        trial.remove(at: index)
        if works(trial, margin: margin, readingChain: readingChain, expected: expected) {
          current = trial
        } else {
          index += 1
        }
      }
      return current
    }

    /// 嘗試把「多條提案的組合」縮成「單一條提案」。
    ///
    /// 單一 n-gram 的假設遠比組合來得可信：組合之所以出現，多半只是因為貪婪縮減
    /// 卡在「恰好打平」的邊界上（兩條路徑同分時，少一條就翻不回來）。與其回報
    /// 兩條互相依賴的提案，不如讓單一條稍微抬高一點。
    private func consolidate(
      _ minimal: [Yukuaki.Gram],
      readingChain: [String],
      expected: String
    )
      -> [Yukuaki.Gram] {
      guard minimal.count > 1 else { return minimal }
      var ordered = minimal.sorted { tier(of: $0) < tier(of: $1) }
      while !ordered.isEmpty {
        let candidate = ordered[0]
        if searchWorkingMargin(
          readingChain: readingChain,
          expected: expected,
          candidates: [candidate]
        ) != nil {
          return [candidate]
        }
        ordered.removeFirst()
      }
      return minimal
    }

    private func validate(
      candidates: [Yukuaki.Gram],
      readingChain: [String],
      expected: String,
      margin: Double
    )
      -> Report.Validation {
      let table = overrides(candidates: candidates, margin: margin)
      let outcome = assemble(readingChain: readingChain, overrides: table)
      return .init(
        isSatisfied: outcome?.path.joinedSentence == expected,
        margin: margin,
        finalText: outcome?.path.joinedSentence ?? "",
        finalScore: outcome?.score ?? 0
      )
    }
  }
}
