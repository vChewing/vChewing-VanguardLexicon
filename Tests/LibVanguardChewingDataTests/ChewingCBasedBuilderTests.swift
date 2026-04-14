// (c) 2021 and onwards The vChewing Project (BSD-3-Clause).
// ====================
// This code is released under the SPDX-License-Identifier: `BSD-3-Clause`.

import Foundation
@testable import LibVanguardChewingData
import Testing

@Suite
struct ChewingCBasedBuilderTests {
  @Test
  func testIgnoringNegativeFrequencyForSingleCharEntries() throws {
    let phoneCin = """
    %chardef begin
    18 ば
    %chardef end
    """

    let tsiSrc = """
    ば -1 ㄅㄚ
    ば 0 ㄅㄚ
    """

    let artifacts = try ChewingCBasedDatabaseGenerator.generateArtifacts(
      phoneCin: phoneCin, tsiSrc: tsiSrc
    )

    #expect(String(decoding: artifacts.dictionary, as: UTF8.self) == "ば\u{0}")
    #expect(artifacts.indexTree.count == 24)
  }

  @Test
  func testRejectingNegativeFrequencyForMultiCharPhrases() throws {
    let phoneCin = """
    %chardef begin
    18 ば
    %chardef end
    """

    let tsiSrc = "ばば -1 ㄅㄚ ㄅㄚ\n"

    #expect(throws: Error.self) {
      try ChewingCBasedDatabaseGenerator.generateArtifacts(
        phoneCin: phoneCin, tsiSrc: tsiSrc
      )
    }
  }
}
