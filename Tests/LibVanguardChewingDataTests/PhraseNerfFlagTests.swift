// (c) 2026 and onwards The vChewing Project (MulanPSL-2.0 License).
// ====================
// This code is released under the SPDX-License-Identifier: `MulanPSL-2.0`.

import Foundation
@testable import LibVanguardChewingData
import Testing

// MARK: - PhraseNerfFlagTests

@Suite("詞列：`#NERFED` 旗標")
struct PhraseNerfFlagTests {
  @Test("帶 `#NERFED` 之列：讀音不含旗標、頻次為 0")
  func parsesNerfedRow() throws {
    let row = try #require(
      try VCDataBuilder.Unigram.parsePhraseRow("不下 0 ㄅㄨˋ-ㄒㄧㄚˋ #NERFED")
    )
    #expect(row.value == "不下")
    #expect(row.reading == "ㄅㄨˋ-ㄒㄧㄚˋ")
    #expect(row.isNerfed)
    #expect(row.count * 1 == 0)
  }

  @Test("多格讀音與旗標並存：旗標不進讀音鍵")
  func flagDoesNotEnterReading() throws {
    let row = try #require(
      try VCDataBuilder.Unigram.parsePhraseRow("不到 7 ㄅㄨˋ ㄉㄠˋ #NERFED")
    )
    #expect(row.reading == "ㄅㄨˋ-ㄉㄠˋ")
    #expect(row.count * 1 == 0)
  }

  @Test("頻次欄寫非 0 時仍以 0 計")
  func nerfedRowForcesZeroCount() throws {
    let row = try #require(
      try VCDataBuilder.Unigram.parsePhraseRow("不下 114 ㄅㄨˋ-ㄒㄧㄚˋ #NERFED")
    )
    #expect(row.count * 1 == 0)
    let gram = VCDataBuilder.Unigram(
      key: row.reading,
      value: row.value,
      score: 0,
      count: 114,
      category: .custom,
      isNerfed: row.isNerfed
    )
    #expect(gram.count * 1 == 0)
  }

  @Test("旗標不分大小寫")
  func flagIsCaseInsensitive() throws {
    let row = try #require(
      try VCDataBuilder.Unigram.parsePhraseRow("不下 0 ㄅㄨˋ-ㄒㄧㄚˋ #nerfed")
    )
    #expect(row.isNerfed)
  }

  @Test("未帶旗標之列不受影響")
  func plainRowIsNotNerfed() throws {
    let row = try #require(
      try VCDataBuilder.Unigram.parsePhraseRow("不下 114 ㄅㄨˋ-ㄒㄧㄚˋ")
    )
    #expect(!row.isNerfed)
    #expect(row.count == 114)
  }

  @Test("未知旗標會報錯，不靜默略過")
  func unknownFlagIsRejected() {
    #expect(throws: VCDataBuilder.PhraseRowParseError.self) {
      try VCDataBuilder.Unigram.parsePhraseRow("不下 0 ㄅㄨˋ-ㄒㄧㄚˋ #NERF")
    }
  }

  @Test("讀音格落於旗標之後會報錯")
  func readingAfterFlagIsRejected() {
    #expect(throws: VCDataBuilder.PhraseRowParseError.self) {
      try VCDataBuilder.Unigram.parsePhraseRow("不下 0 #NERFED ㄅㄨˋ-ㄒㄧㄚˋ")
    }
  }

  @Test("欄位不足與頻次非整數仍照舊報錯")
  func malformedRowsStayRejected() {
    for raw in ["不下 0", "不下 零 ㄅㄨˋ-ㄒㄧㄚˋ"] {
      #expect(throws: VCDataBuilder.PhraseRowParseError.self) {
        try VCDataBuilder.Unigram.parsePhraseRow(raw)
      }
    }
  }

  @Test("`#NERFED` 之權重恆為 -114.514，不隨正規化基準漂移")
  func nerfedWeightIsFixed() {
    for norm in [1_000.0, 374_388_831.9686408] {
      let gram = VCDataBuilder.Unigram(
        key: "ㄅㄨˋ-ㄒㄧㄚˋ",
        value: "不下",
        score: 0,
        count: 0,
        category: .custom,
        isNerfed: true
      )
      gram.weighten(norm: norm)
      #expect(gram.score == -114.514)
    }
  }

  @Test("未帶旗標之零頻次詞條仍走原本之低頻折算")
  func plainZeroCountKeepsOrdinaryWeight() {
    let gram = VCDataBuilder.Unigram(
      key: "ㄅㄨˋ",
      value: "不",
      score: 0,
      count: 0,
      category: .custom
    )
    gram.weighten(norm: 374_388_831.9686408)
    #expect(gram.score != -114.514)
    #expect(gram.score < 0)
    #expect(gram.score > -114.514)
  }

  @Test("旗標隨 Codable 往返，且解碼後頻次仍為 0")
  func flagSurvivesCodableRoundTrip() throws {
    let gram = VCDataBuilder.Unigram(
      key: "ㄅㄨˋ-ㄒㄧㄚˋ",
      value: "不下",
      score: 0,
      count: 0,
      category: .custom,
      isNerfed: true
    )
    gram.weighten(norm: 1_000)
    let decoded = try JSONDecoder().decode(
      VCDataBuilder.Unigram.self,
      from: try JSONEncoder().encode(gram)
    )
    #expect(decoded.isNerfed)
    #expect(decoded.count * 1 == 0)
    #expect(decoded.score == -114.514)
  }

  @Test("詞條進 Trie 時帶的就是懲戒權重")
  func trieEntryCarriesNerfedWeight() throws {
    let gram = VCDataBuilder.Unigram(
      key: "ㄅㄨˋ-ㄒㄧㄚˋ",
      value: "不下",
      score: 0,
      count: 0,
      category: .custom,
      isNerfed: true
    )
    gram.weighten(norm: 1_000)
    let entry = try #require(gram.asEntry(type: .cht)?.0)
    #expect(entry.probability == -114.514)
    #expect(entry.context.isEmpty)
  }

  @Test("KVS 表之 NERF 列另附 `#NERFED` 旗標格，其餘列仍是三欄")
  func kvsLineAppendsNerfFlag() {
    let nerfed = VCDataBuilder.Unigram(
      key: "ㄅㄨˋ-ㄒㄧㄚˋ",
      value: "不下",
      score: 0,
      count: 0,
      category: .custom,
      isNerfed: true
    )
    nerfed.weighten(norm: 1_000)
    #expect(
      VCDataBuilder.TextKVSTableDataBuilder.makeLine(for: nerfed)
        == "ㄅㄨˋ-ㄒㄧㄚˋ 不下 -114.514 #NERFED"
    )

    let plain = VCDataBuilder.Unigram(
      key: "ㄅㄨˋ",
      value: "不",
      score: 0,
      count: 114,
      category: .custom
    )
    plain.weighten(norm: 1_000_000)
    let cells = VCDataBuilder.TextKVSTableDataBuilder.makeLine(for: plain)
      .split(separator: " ").map(String.init)
    #expect(cells.count == 3)
  }

  @Test("健檢之重複偵查不看旗標：帶旗標與未帶者仍是同一個詞音配對")
  func duplicateScanIgnoresFlags() {
    let groups = VCDataBuilder.Collector.collectDuplicateGroups(
      in: [
        .init(name: "a.txt", content: "不下 0 ㄅㄨˋ-ㄒㄧㄚˋ #NERFED", readingFieldIndex: 2),
        .init(name: "b.txt", content: "不下 114 ㄅㄨˋ-ㄒㄧㄚˋ", readingFieldIndex: 2),
      ],
      compatibleMode: false
    )
    #expect(groups.count == 1)
    #expect(groups.first?.records.count == 2)
    #expect(groups.first?.signature == "不下\tㄅㄨˋ-ㄒㄧㄚˋ")
  }

  @Test("被 nerf 之詞條無權參與 NORM 統計")
  func nerfedEntriesStayOutOfNorm() throws {
    func gram(count: Int, isNerfed: Bool) -> VCDataBuilder.Unigram {
      VCDataBuilder.Unigram(
        key: "ㄅㄨˋ-ㄒㄧㄚˋ",
        value: "不下",
        score: 0,
        count: count,
        category: .moe,
        isNerfed: isNerfed
      )
    }

    // `.moe` 係會計入 `_NORM` 之類別，故這裡排除的因由只能是旗標本身。
    let nerfed = gram(count: 1_000_000, isNerfed: true)
    #expect(nerfed.normDelta == nil)
    let plain = gram(count: 1_000_000, isNerfed: false)
    let plainDelta = try #require(plain.normDelta)
    #expect(plainDelta > 0)
    // 未帶旗標之零頻次者仍「參與」統計，只是量為 0——與 NERF 之「不參與」不同。
    #expect(gram(count: 0, isNerfed: false).normDelta == 0)

    // 盤點之加總：nerfed 一筆不添任何量。
    let tally = [plain, nerfed].compactMap(\.normDelta).reduce(0, +)
    #expect(tally == plainDelta)
  }

  @Test("n-gram 列不支援 `#NERFED`：第 6 欄之註解位亦不例外")
  func ngramRowsRejectNerfFlag() {
    for raw in [
      "的 120 ㄉㄜ˙ 在|* 500 #NERFED", // 第 6 欄（註解位）
      "的 120 ㄉㄜ˙ 在 500 #NERFED 7", // 七欄
      "的 120 ㄉㄜ˙ 在|* 500 #nerfed", // 大小寫不拘
    ] {
      #expect(throws: VCDataBuilder.Exception.self) {
        try VCDataBuilder.Unigram.parseNgramLines(
          raw,
          isCHS: false,
          norm: 1_000,
          counts: ["在": 500]
        )
      }
    }
  }

  @Test("n-gram 之一般註解仍可寫在第 6 欄")
  func ngramRowsStillAcceptPlainComments() throws {
    let records = try VCDataBuilder.Unigram.parseNgramLines(
      "的 120 ㄉㄜ˙ 在 500 #VERIFY:在場的",
      isCHS: false,
      norm: 1_000,
      counts: ["在": 500]
    )
    #expect(records.count == 1)
    #expect(records.first?.context == ["在"])
  }
}
