// (c) 2025 and onwards The vChewing Project (MulanPSL-2.0 License).
// ====================
// This code is released under the SPDX-License-Identifier: `MulanPSL-2.0`.

import Foundation
import Yukuaki

// MARK: - VerifyRunner

/// 「以組句結果為準」的候選驗證：讀 `CorpusMiner` 產出的 `backlog.tsv` 與 `corpus.jsonl`，
/// 對每一列候選在語料句子上實際組句兩次（收列前／收列後），看路徑是否如預期翻轉。
///
/// - Note: 這是「挖掘」與「裁決」的分工：`CorpusMiner` 只做統計與篩選，真正的效果由引擎判定。
enum VerifyRunner {
  struct Options {
    var backlogURL: URL
    var corpusURL: URL
    var limit: Int = 50
    var caseLimit: Int = 5
    var maxChunkLength: Int = 6
    var showsJSON = false
    var isVerbose = false
  }

  enum Verdict: String {
    /// 收列前錯、收列後對：真的補到了。
    case fixed
    /// 收列前對、收列後錯：收列會惡化。
    case regressed
    /// 收列前後都對：本來就不缺。
    case unnecessary
    /// 收列前後都錯，但組句不同：有影響、只是沒能完全翻轉。
    case affected
    /// 收列前後都錯且結果相同：無效。
    case ineffective
  }

  struct CaseOutcome {
    let sentenceIndex: Int
    let expected: String
    let before: String
    let after: String
    let verdict: Verdict
  }

  struct RowReport {
    let value: String
    let context: [String]
    let cases: [CaseOutcome]
    var verdict: Verdict {
      if cases.contains(where: { $0.verdict == .regressed }) { return .regressed }
      if cases.contains(where: { $0.verdict == .fixed }) { return .fixed }
      if cases.contains(where: { $0.verdict == .affected }) { return .affected }
      if cases.contains(where: { $0.verdict == .unnecessary }) { return .unnecessary }
      return .ineffective
    }
  }

  static func run(_ options: Options, reader: VanguardTextMapReader) throws
    -> [RowReport]
  {
    let rows = try loadBacklog(options.backlogURL).prefix(options.limit)
    let sentences = try loadCorpus(options.corpusURL)
    guard !sentences.isEmpty else {
      throw VerifyError.emptyCorpus
    }

    var corpusCounts = [String: Int]()
    for words in sentences {
      for word in words { corpusCounts[word, default: 0] += 1 }
    }

    let neededValues = Set(sentences.joined())
    var readingsIndex = reader.readingsIndex(forValues: neededValues)
    if options.isVerbose {
      FileHandle.standardError.write(
        Data("反查讀音：\(readingsIndex.count) 型／語料 \(sentences.count) 句\n".utf8)
      )
    }

    var pairIndex = [[String]: [Int]]()
    for (index, words) in sentences.enumerated() {
      guard words.count >= 2 else { continue }
      for offset in 0 ..< words.count - 1 {
        let pair = [words[offset], words[offset + 1]]
        if pairIndex[pair, default: []].count < options.caseLimit {
          pairIndex[pair, default: []].append(index)
        }
      }
    }

    var reports = [RowReport]()
    for row in rows {
      let pair = row.context + [row.value]
      guard pair.count >= 2,
            let candidates = pairIndex[Array(pair.suffix(2))]
      else {
        reports.append(RowReport(value: row.value, context: row.context, cases: []))
        continue
      }
      let denominator = Double(corpusCounts[pair[pair.count - 2]] ?? 1)
      let probability = max(
        row.probability,
        analyticProbability(reading: row.reading, countText: "\(row.count)", denominator: denominator)
      )
      let gram = Yukuaki.Gram(
        keyArray: row.reading,
        current: row.value,
        previous: pair.count >= 3 ? pair[pair.count - 2] : nil,
        anterior: pair.count >= 4 ? pair[pair.count - 3] : nil,
        probability: probability
      )
      var outcomes = [CaseOutcome]()
      for sentenceIndex in candidates {
        let words = sentences[sentenceIndex]
        guard let chain = readingChain(for: words, index: &readingsIndex) else { continue }
        let expected = words.joined()
        let before = try assemble(
          chain: chain,
          reader: reader,
          injected: [],
          maxChunkLength: options.maxChunkLength
        )
        let after = try assemble(
          chain: chain,
          reader: reader,
          injected: [gram],
          maxChunkLength: options.maxChunkLength
        )
        let verdict: Verdict = switch (before == expected, after == expected) {
        case (false, true): .fixed
        case (true, false): .regressed
        case (true, true): .unnecessary
        case (false, false): before == after ? .ineffective : .affected
        }
        outcomes.append(
          CaseOutcome(
            sentenceIndex: sentenceIndex,
            expected: expected,
            before: before,
            after: after,
            verdict: verdict
          )
        )
      }
      reports.append(RowReport(value: row.value, context: row.context, cases: outcomes))
    }
    return reports
  }

  // MARK: Private

  struct BacklogRow {
    let value: String
    let reading: [String]
    let context: [String]
    let count: Int
    /// 以「每列自身」為分母的粗估機率；實際注入時會改用語料中的前驗詞次數重算。
    let probability: Double
  }

  static func loadBacklog(_ url: URL) throws -> [BacklogRow] {
    let text = try String(contentsOf: url, encoding: .utf8)
    return text.split(separator: "\n").compactMap { line in
      guard !line.hasPrefix("#"), !line.hasPrefix("\t"), !line.isEmpty else { return nil }
      let fields = line.components(separatedBy: "\t")
      guard fields.count >= 3 else { return nil }
      let reading = fields[2].split(separator: " ").map(String.init)
      guard !reading.isEmpty else { return nil }
      let context: [String] = fields.count >= 4
        ? fields[3].split(separator: " ").map(String.init)
        : []
      let probability = analyticProbability(
        reading: reading,
        countText: fields[1],
        denominator: 1
      )
      return BacklogRow(
        value: fields[0],
        reading: reading,
        context: context,
        count: Int(fields[1]) ?? 1,
        probability: probability
      )
    }
  }

  /// 以「語料次數」重建一列 n-gram 的機率：與 `Collector_Ngram` 的 `weighten` 同式。
  static func analyticProbability(
    reading: [String],
    countText: String,
    denominator: Double
  )
    -> Double
  {
    guard let count = Double(countText), count > 0, denominator > 0 else { return -8.164 }
    let length = reading.reduce(0) { $0 + $1.count } + max(0, reading.count - 1)
    return log10(exp(Double(length) / 3 - 1) * count / denominator)
  }

  private static func loadCorpus(_ url: URL) throws -> [[String]] {
    let text = try String(contentsOf: url, encoding: .utf8)
    let decoder = JSONDecoder()
    return text.split(separator: "\n").compactMap { line in
      guard let data = line.data(using: .utf8),
            let sentence = try? decoder.decode(CorpusSentence.self, from: data)
      else { return nil }
      return sentence.words
    }
  }

  private struct CorpusSentence: Decodable {
    let words: [String]
  }

  /// 逐詞取讀音；任一詞查無讀音即整句略過（回 nil）。
  private static func readingChain(
    for words: [String],
    index: inout [String: [[String]]]
  )
    -> [String]?
  {
    var chain = [String]()
    for word in words {
      guard let readings = index[word]?.first else { return nil }
      chain.append(contentsOf: readings)
    }
    return chain
  }

  private static func assemble(
    chain: [String],
    reader: VanguardTextMapReader,
    injected: [Yukuaki.Gram],
    maxChunkLength: Int
  )
    throws -> String
  {
    let assembler = Yukuaki.Assembler(
      gramQuerier: { keys in
        let representative = keys.representativeKeys
        var grams = reader.grams(forKeys: representative)
        if !injected.isEmpty { grams += injected.filter { $0.keyArray == representative } }
        return grams
      },
      gramAvailabilityChecker: { keys in
        reader.hasGrams(forKeys: keys) || injected.contains { $0.keyArray == keys }
      },
      config: Yukuaki.Config(maxSegLength: maxChunkLength)
    )
    try assembler.insertKeys(chain.map { Yukuaki.PossibleKey.singleKey($0) })
    return assembler.assembledSentence.map { $0.gram.current }.joined()
  }
}

// MARK: - VerifyError

enum VerifyError: Error, CustomStringConvertible {
  case emptyCorpus

  var description: String {
    switch self {
    case .emptyCorpus: "語料沒有可用的句子；請先以 `VanguardLexiconCorpusMiner segment` 產生。"
    }
  }
}
