// (c) 2025 and onwards The vChewing Project (MulanPSL-2.0 License).
// ====================
// This code is released under the SPDX-License-Identifier: `MulanPSL-2.0`.

import Foundation
import LibVanguardChewingData
import Testing
@testable import VanguardLexiconDebugger
import Yukuaki

// MARK: - NGramVerifyTests

@Suite("n-gram #VERIFY 自檢")
struct NGramVerifyTests {
  // MARK: Internal

  struct VerifyCase {
    let isCHS: Bool
    let sentence: String
    let keys: [String]
    let source: String
  }

  @Test("phrases-ngram 的 #VERIFY 例句都能組出")
  func verifiesComments() async throws {
    let textMapURL = try await renderTextMap()
    defer { try? FileManager.default.removeItem(at: textMapURL) }
    let cases = try loadCases()
    #expect(!cases.isEmpty)

    let chtReader = try VanguardTextMapReader(url: textMapURL, locale: .cht)
    let chsReader = try VanguardTextMapReader(url: textMapURL, locale: .chs)
    for item in cases {
      let reader = item.isCHS ? chsReader : chtReader
      let assembler = Yukuaki.Assembler(
        gramQuerier: { [reader] keys in reader.grams(forKeys: keys.representativeKeys) },
        gramAvailabilityChecker: { [reader] keys in reader.hasGrams(forKeys: keys) },
        config: Yukuaki.Config(maxSegLength: 10)
      )
      try assembler.insertKeys(item.keys)
      let outcome = assembler.assembleWithScore()
      #expect(outcome.path.joinedSentence == item.sentence, "\(item.source)")
    }
  }

  // MARK: Private

  private func renderTextMap() async throws -> URL {
    let builder = try #require(await VCDataBuilder.VanguardTextMapDataBuilder(isCHS: nil))
    let iterator = try await builder.getIteratorForLexiconAssemblyTask()
    var data = Data()
    for try await chunk in iterator { data.append(chunk.data) }
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("ngram-verify-\(UUID().uuidString).txtMap")
    try data.write(to: url)
    return url
  }

  private func loadCases() throws -> [VerifyCase] {
    let repoRoot = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
    let components = repoRoot.appendingPathComponent(
      "Sources/LibVanguardChewingData/Resources/components"
    )
    let files: [(URL, Bool)] = [
      (components.appendingPathComponent("cht/phrases-ngram-cht.txt"), false),
      (components.appendingPathComponent("chs/phrases-ngram-chs.txt"), true),
    ]

    var result = [VerifyCase]()
    for (url, isCHS) in files {
      let text = try String(contentsOf: url, encoding: .utf8)
      for (index, line) in text.components(separatedBy: .newlines).enumerated() {
        let cells = line.split(whereSeparator: \.isWhitespace).map(String.init)
        guard cells.count == 6, cells[5].hasPrefix("#") else { continue }
        // 第 6 欄是單一 token；多個例句以 `#VERIFY:` 相接：
        //   #VERIFY:句1|讀音1#VERIFY:句2|讀音2
        for segment in cells[5].components(separatedBy: "#VERIFY:").dropFirst() {
          let parts = segment.split(separator: "|", maxSplits: 1).map(String.init)
          guard parts.count == 2 else { continue }
          let keys = parts[1].split(separator: "-").map(String.init)
          guard !keys.isEmpty else { continue }
          result.append(
            VerifyCase(
              isCHS: isCHS,
              sentence: parts[0],
              keys: keys,
              source: "\(url.lastPathComponent):\(index + 1)"
            )
          )
        }
      }
    }
    return result
  }
}
