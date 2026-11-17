// (c) 2026 and onwards The vChewing Project (MulanPSL-2.0 License).
// ====================
// This code is released under the SPDX-License-Identifier: `MulanPSL-2.0`.

import Foundation
@testable import LibVanguardChewingData
import Testing

// MARK: - TextKVSTableNgramTests

@Suite("TextKVSTable：ngram 匯出")
struct TextKVSTableNgramTests {
  @Test("n-gram 列帶第四欄 #NGRAM 前文鏈，單元圖列仍是三欄")
  func exportsNgramRowsWithCommentCell() async throws {
    let builder = try #require(await VCDataBuilder.TextKVSTableDataBuilder(isCHS: false))
    var data = Data()
    let iterator = try await builder.getIteratorForLexiconAssemblyTask()
    for try await chunk in iterator { data.append(chunk.data) }
    let text = try #require(String(data: data, encoding: .utf8))
    let lines = text.split(whereSeparator: \.isNewline).map(String.init)

    let bigram = try #require(
      lines.first { $0.hasPrefix("ㄓㄜˋ-ㄧㄤˋ 這樣 ") && $0.hasSuffix("#NGRAM:再") }
    )
    let bigramCells = bigram.split(separator: " ").map(String.init)
    #expect(bigramCells.count == 4)
    #expect(bigramCells[3] == "#NGRAM:再")

    let gap = try #require(
      lines.first { $0.hasPrefix("ㄉㄜ˙ 的 ") && $0.hasSuffix("#NGRAM:在|*") }
    )
    let gapCells = gap.split(separator: " ").map(String.init)
    #expect(gapCells.count == 4)
    #expect(gapCells[3] == "#NGRAM:在|*")

    let unigram = try #require(
      lines.first { $0.hasPrefix("ㄓㄜˋ-ㄧㄤˋ 這樣 ") && !$0.contains("#NGRAM:") }
    )
    #expect(unigram.split(separator: " ").count == 3)
  }
}
