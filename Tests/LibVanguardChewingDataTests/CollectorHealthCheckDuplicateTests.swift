// (c) 2021 and onwards The vChewing Project (BSD-3-Clause).
// ====================
// This code is released under the SPDX-License-Identifier: `BSD-3-Clause`.

import Foundation
@testable import LibVanguardChewingData
import Testing

@Test
func testHealthCheckDuplicateScanCollectsAllOccurrences() {
  let sources: [VCDataBuilder.Collector.DuplicateScanSource] = [
    .init(
      name: "phrases-a.txt",
      content: "# comment\n甲 1 ㄐㄧㄚˇ\n乙 1 ㄧˇ\n甲 2 ㄐㄧㄚˇ\n",
      readingFieldIndex: 2
    ),
    .init(
      name: "phrases-b.txt",
      content: "甲 3 ㄐㄧㄚˇ\n乙 1 ㄧˋ\n",
      readingFieldIndex: 2
    ),
    .init(
      name: "char-kanji-core.txt",
      content: "字 1 1 ㄗˋ\n字 5 7 ㄗˋ\n字 8 9 ㄓˋ\n",
      readingFieldIndex: 3
    ),
  ]

  let groups = VCDataBuilder.Collector.collectDuplicateGroups(in: sources, compatibleMode: false)
  let groupedRecords = Dictionary(uniqueKeysWithValues: groups.map { ($0.signature, $0.records) })

  #expect(groups.count == 2)
  #expect(groupedRecords["甲\tㄐㄧㄚˇ"]?.count == 3)
  #expect(groupedRecords["字\tㄗˋ"]?.count == 2)
  #expect(groupedRecords["乙\tㄧˇ"] == nil)
}

@Test
func testHealthCheckDuplicateReportMentionsSummaryAndAllOccurrences() {
  // The first source has a leading `# comment` to verify that original
  // line numbers survive normalization (comment lines are stripped but
  // must not shift subsequent line numbers).
  let sources: [VCDataBuilder.Collector.DuplicateScanSource] = [
    .init(
      name: "phrases-a.txt",
      content: "# comment\n甲 1 ㄐㄧㄚˇ\n甲\t2\tㄐㄧㄚˇ\n",
      readingFieldIndex: 2
    ),
    .init(
      name: "phrases-b.txt",
      content: "甲 3 ㄐㄧㄚˇ\n",
      readingFieldIndex: 2
    ),
  ]

  let groups = VCDataBuilder.Collector.collectDuplicateGroups(in: sources, compatibleMode: false)
  let report = VCDataBuilder.Collector.renderDuplicateReport(from: groups).joined(separator: "\n")

  #expect(report.contains("發現 1 組重複詞條，共涉及 3 筆記錄，其中重複項 2 筆。"))
  #expect(report.contains("【甲\tㄐㄧㄚˇ】"))
  // Line numbers must reflect the original file, not post-filter indices.
  #expect(report.contains("[phrases-a.txt:2] 甲 1 ㄐㄧㄚˇ"))
  #expect(report.contains("[phrases-a.txt:3] 甲 2 ㄐㄧㄚˇ"))
  #expect(report.contains("[phrases-b.txt:1] 甲 3 ㄐㄧㄚˇ"))
}
