// (c) 2025 and onwards The vChewing Project (MulanPSL-2.0 License).
// ====================
// This code is released under the SPDX-License-Identifier: `MulanPSL-2.0`.

import Foundation

// MARK: - CorpusMiner

/// 由已分詞語料統計「值得補進 n-gram 表」的候選列。
///
/// 判準與引擎的載入端完全一致（見 `Collector_Ngram.parseNgramLines`）：
/// 一列 `value\tcount\treading\tcontext\tcontextCount` 在重建後之機率為
/// `p = log10(e^(len/3-1) * count / count(context))`；
/// 唯有 `p` 嚴格大於同詞之單元圖分數時，該列才會在組句時勝出。
/// 因此本工具反解出「至少需要多少次共現」，再與語料實測次數比對。
///
/// 分母一律取自**同一批分詞語料**：bigram 用 `count(context)`、
/// trigram 用完整前文之 `count(context)`。凡在語料中沒有所求後繼位置的前文
/// （句尾詞、句尾詞對）不計入分母，使條件機率在同一政策下正規化。
struct CorpusMiner {
  // MARK: Internal

  enum AmbiguousReadings: String, CaseIterable {
    case skip
    case primary
    case all
  }

  struct Options {
    var minCount = 5
    var minContextCount = 5
    var margin = 0.02
    /// 條件機率之下界門檻（Wilson 95% 下界）。0 表示不設限。
    var minLowerBound = 0.0
    var ambiguousReadings: AmbiguousReadings = .skip
  }

  struct Candidate {
    let context: [String]
    let value: String
    let reading: [String]
    let corpusCount: Int
    /// 分母：完整前文在語料中的出現次數（只計存在所求後繼位置者）。
    let contextCount: Int
    let requiredCount: Int
    let lift: Double
    /// `corpusCount / contextCount` 的 Wilson 95% 下界。
    let lowerBound: Double
    let assumedReading: Bool
  }

  /// 只統計含漢字的詞；純標點與純 ASCII 片段不參與 n-gram 統計。
  static func isWordlike(_ token: String) -> Bool {
    token.contains { $0.unicodeScalars.first.map { $0.properties.isIdeographic } ?? false }
  }

  /// `corpusCount / contextCount` 的 Wilson 95% 下界。
  ///
  /// 分子分母同出一批語料，比值是 MLE；`contextCount` 小的時候它系統性誇大——兩次觀察
  /// 得 2/2 便斷言「必接」，正是 P332 之前無法直接收錄的原因。下界回答的是「至少這麼多」，
  /// 讓 `--min-lower-bound` 能一刀切掉撐不起來的列，而不必逐列人眼複核。
  static func wilsonLowerBound(successes: Int, trials: Int, z: Double = 1.96) -> Double {
    guard trials > 0, successes >= 0, successes <= trials else { return 0 }
    let n = Double(trials)
    let p = Double(successes) / n
    let z2 = z * z
    let margin = z * (p * (1 - p) / n + z2 / (4 * n * n)).squareRoot()
    return max(0, (p + z2 / (2 * n) - margin) / (1 + z2 / n))
  }

  private static func isBacklogValueSafe(_ value: String) -> Bool {
    !value.isEmpty && !value.unicodeScalars.contains {
      $0.properties.generalCategory == .control || CharacterSet.newlines.contains($0)
    }
  }

  private static func isBacklogTokenSafe(_ token: String) -> Bool {
    isBacklogValueSafe(token) && !token.contains("|") && !token.unicodeScalars.contains {
      $0.isASCII && CharacterSet.whitespacesAndNewlines.contains($0)
    }
  }

  struct MiningResult {
    var candidates: [Candidate] = []
    var ambiguous: [(value: String, occurrences: Int, readings: [[String]], reason: String)] = []
    var unknownRuns: [String: Int] = [:]
    var stats: [(key: String, value: String)] = []
  }

  private(set) var sentenceCount = 0
  private(set) var tokenCount = 0
  private(set) var unigramCounts = [String: Int]()
  private var bigramCounts = [[String]: Int]()
  private var trigramCounts = [[String]: Int]()
  /// `count(y)`：只計存在所求後繼位置的前文（句尾詞不計）。
  private var contextUnigramCounts = [String: Int]()
  /// `count(x, y)`：只計存在所求後繼位置的前文詞對。
  private var contextBigramCounts = [[String]: Int]()

  mutating func ingest(words: [String]) {
    guard !words.isEmpty else { return }
    sentenceCount += 1
    tokenCount += words.count
    for word in words { unigramCounts[word, default: 0] += 1 }
    guard words.count >= 2 else { return }
    for index in 1 ..< words.count {
      bigramCounts[[words[index - 1], words[index]], default: 0] += 1
      // 位置 index-1 的詞在此句尚有後繼，故計入 `count(y)`。
      contextUnigramCounts[words[index - 1], default: 0] += 1
    }
    guard words.count >= 3 else { return }
    for index in 2 ..< words.count {
      trigramCounts[[words[index - 2], words[index - 1], words[index]], default: 0] += 1
      // 位置 index-2、index-1 的詞對在此句尚有後繼，故計入 `count(x, y)`。
      contextBigramCounts[[words[index - 2], words[index - 1]], default: 0] += 1
    }
  }

  mutating func ingest(unknownRuns: [String]) {
    for run in unknownRuns { self.unknownRuns[run, default: 0] += 1 }
  }

  private(set) var unknownRuns = [String: Int]()

  var bigramTypeCount: Int { bigramCounts.count }
  var trigramTypeCount: Int { trigramCounts.count }

  func mine(index: TxtMapUnigramIndex, options: Options) -> MiningResult {
    var result = MiningResult()
    var ambiguous = [String: (occurrences: Int, readings: [[String]], reason: String)]()

    func consider(chain: [String], corpusCount: Int) {
      guard corpusCount >= options.minCount, chain.count >= 2 else { return }
      let context = Array(chain.dropLast())
      guard let lastContext = context.last else { return }
      let value = chain[chain.count - 1]
      guard Self.isWordlike(value), Self.isWordlike(lastContext),
            Self.isBacklogValueSafe(value),
            context.allSatisfy(Self.isBacklogTokenSafe)
      else { return }
      guard let unigram = index.unigram(value) else { return }
      // 分母取自同一批語料：bigram 用 `count(y)`、trigram 用 `count(x, y)`。
      let contextCount = chain.count >= 3
        ? contextBigramCounts[context] ?? 0
        : contextUnigramCounts[lastContext] ?? 0
      guard contextCount >= options.minContextCount else { return }
      let denominator = Double(contextCount)

      var readings = unigram.readings
      if readings.isEmpty { readings = [(key: [], probability: unigram.probability)] }
      var chosen = readings
      var assumedReading = false
      if readings.count > 1 {
        switch options.ambiguousReadings {
        case .skip:
          ambiguous[value] = (
            occurrences: unigramCounts[value] ?? corpusCount,
            readings: readings.map(\.key),
            reason: "多讀音"
          )
          return
        case .primary:
          // 最高頻並列者不可抽籤。詞庫對 `和` 的 ㄏㄜˊ 與 ㄏㄢˋ 給同一個機率（`著`
          // 三讀同分亦然），`max(by:)` 只會回傳先出現的那一條，等於憑檔案順序定讀音。
          let best = readings.map(\.probability).max() ?? -Double.infinity
          let top = readings.filter { $0.probability == best }
          guard top.count == 1 else {
            ambiguous[value] = (
              occurrences: unigramCounts[value] ?? corpusCount,
              readings: readings.map(\.key),
              reason: "最高頻並列"
            )
            return
          }
          chosen = top
          assumedReading = true
        case .all:
          break
        }
      }

      let scale = exp(Double(value.count) / 3 - 1)
      let probability = log10(scale * Double(corpusCount) / denominator)
      let gate = unigram.probability + options.margin
      guard probability > gate else { return }
      let lowerBound = Self.wilsonLowerBound(successes: corpusCount, trials: contextCount)
      guard lowerBound >= options.minLowerBound else { return }
      let required = Int((denominator * pow(10, gate) / scale).rounded(.up))
      for reading in chosen {
        guard reading.key.allSatisfy(Self.isBacklogTokenSafe) else { continue }
        result.candidates.append(
          .init(
            context: context,
            value: value,
            reading: reading.key,
            corpusCount: corpusCount,
            contextCount: contextCount,
            requiredCount: max(required, options.minCount),
            lift: probability - unigram.probability,
            lowerBound: lowerBound,
            assumedReading: assumedReading
          )
        )
      }
    }

    for (chain, count) in bigramCounts { consider(chain: chain, corpusCount: count) }
    for (chain, count) in trigramCounts { consider(chain: chain, corpusCount: count) }

    result.candidates.sort {
      if $0.lift != $1.lift { return $0.lift > $1.lift }
      if $0.corpusCount != $1.corpusCount { return $0.corpusCount > $1.corpusCount }
      return $0.value < $1.value
    }
    result.ambiguous = ambiguous
      .map {
        (
          value: $0.key,
          occurrences: $0.value.occurrences,
          readings: $0.value.readings,
          reason: $0.value.reason
        )
      }
      .sorted { $0.occurrences > $1.occurrences }
    result.unknownRuns = unknownRuns
    return result
  }
}

// MARK: - CorpusMiner.Row rendering

extension CorpusMiner.Candidate {
  /// 可直接黏進 `phrases-ngram-*.txt` 之一列；含會破壞 TSV 結構的字元時不輸出。
  func renderedLine() -> String? {
    guard CorpusMiner.isBacklogValueSafe(value),
          context.allSatisfy(CorpusMiner.isBacklogTokenSafe),
          reading.allSatisfy(CorpusMiner.isBacklogTokenSafe)
    else { return nil }
    let readingCell = reading.joined(separator: "-")
    var comment =
      "#lift=\(String(format: "%.3f", lift));corpus=\(corpusCount);context=\(contextCount);required=\(requiredCount);lb=\(String(format: "%.3f", lowerBound))"
    if assumedReading { comment += ";assumed-reading" }
    let contextCell = context.joined(separator: "|")
    // 第 2 欄寫真實共現次數：載入端以 `count(c, w) / count(c)` 復算機率，若在此處灌水，
    // 復算結果便與本行宣稱的 lift 不符。
    return "\(value) \(corpusCount) \(readingCell) \(contextCell) \(contextCount) \(comment)"
  }
}
