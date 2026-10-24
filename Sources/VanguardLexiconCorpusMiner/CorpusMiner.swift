// (c) 2025 and onwards The vChewing Project (MulanPSL-2.0 License).
// ====================
// This code is released under the SPDX-License-Identifier: `MulanPSL-2.0`.

import Foundation

// MARK: - CorpusMiner

/// 由已分詞語料統計「值得補進 n-gram 表」的候選列。
///
/// 判準與引擎的載入端完全一致（見 `Collector_Ngram.parseNgramLines`）：
/// 一列 `value\tcount\treading\tcontext` 在重建後之機率為
/// `p = log10(e^(len/3-1) * count / count(context.last))`；
/// 唯有 `p` 嚴格大於同詞之單元圖分數時，該列才會在組句時勝出。
/// 因此本工具反解出「至少需要多少次共現」，再與語料實測次數比對。
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
    var ambiguousReadings: AmbiguousReadings = .skip
  }

  struct Candidate {
    let context: [String]
    let value: String
    let reading: [String]
    let corpusCount: Int
    let requiredCount: Int
    let lift: Double
    let assumedReading: Bool
  }

  /// 只統計含漢字的詞；純標點與純 ASCII 片段不參與 n-gram 統計。
  static func isWordlike(_ token: String) -> Bool {
    token.contains { $0.unicodeScalars.first.map { $0.properties.isIdeographic } ?? false }
  }

  struct MiningResult {
    var candidates: [Candidate] = []
    var ambiguous: [(value: String, occurrences: Int, readings: [[String]])] = []
    var unknownRuns: [String: Int] = [:]
    var stats: [(key: String, value: String)] = []
  }

  private(set) var sentenceCount = 0
  private(set) var tokenCount = 0
  private(set) var unigramCounts = [String: Int]()
  private var bigramCounts = [[String]: Int]()
  private var trigramCounts = [[String]: Int]()

  mutating func ingest(words: [String]) {
    guard !words.isEmpty else { return }
    sentenceCount += 1
    tokenCount += words.count
    for word in words { unigramCounts[word, default: 0] += 1 }
    guard words.count >= 2 else { return }
    for index in 1 ..< words.count {
      bigramCounts[[words[index - 1], words[index]], default: 0] += 1
    }
    guard words.count >= 3 else { return }
    for index in 2 ..< words.count {
      trigramCounts[[words[index - 2], words[index - 1], words[index]], default: 0] += 1
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
    var ambiguous = [String: (occurrences: Int, readings: [[String]])]()

    func consider(chain: [String], corpusCount: Int) {
      guard corpusCount >= options.minCount, chain.count >= 2 else { return }
      let context = Array(chain.dropLast())
      guard let lastContext = context.last else { return }
      let value = chain[chain.count - 1]
      guard CorpusMiner.isWordlike(value), CorpusMiner.isWordlike(lastContext) else { return }
      guard let unigram = index.unigram(value) else { return }
      let denominator = index.count(of: lastContext)
      guard denominator >= Double(options.minContextCount) else { return }

      var readings = unigram.readings
      if readings.isEmpty { readings = [(key: [], probability: unigram.probability)] }
      var chosen = readings
      var assumedReading = false
      if readings.count > 1 {
        switch options.ambiguousReadings {
        case .skip:
          ambiguous[value] = (occurrences: unigramCounts[value] ?? corpusCount, readings: readings.map(\.key))
          return
        case .primary:
          chosen = [readings.max { $0.probability < $1.probability }!]
          assumedReading = true
        case .all:
          break
        }
      }

      let scale = exp(Double(value.count) / 3 - 1)
      let probability = log10(scale * Double(corpusCount) / denominator)
      let gate = unigram.probability + options.margin
      guard probability > gate else { return }
      let required = Int((denominator * pow(10, gate) / scale).rounded(.up))
      for reading in chosen {
        result.candidates.append(
          .init(
            context: context,
            value: value,
            reading: reading.key,
            corpusCount: corpusCount,
            requiredCount: max(required, options.minCount),
            lift: probability - unigram.probability,
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
      .map { (value: $0.key, occurrences: $0.value.occurrences, readings: $0.value.readings) }
      .sorted { $0.occurrences > $1.occurrences }
    result.unknownRuns = unknownRuns
    return result
  }
}

// MARK: - CorpusMiner.Row rendering

extension CorpusMiner.Candidate {
  /// 可直接黏進 `phrases-ngram-*.txt` 之一列。
  func renderedLine() -> String {
    let reading = self.reading.joined(separator: " ")
    var comment = "# lift=\(String(format: "%.3f", lift)) corpus=\(corpusCount) required=\(requiredCount)"
    if assumedReading { comment += " assumed-reading" }
    return "\(value)\t\(max(requiredCount, corpusCount))\t\(reading)\t\(context.joined(separator: " "))\t\(comment)"
  }
}
