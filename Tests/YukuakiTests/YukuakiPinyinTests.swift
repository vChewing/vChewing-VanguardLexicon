// (c) 2025 and onwards The vChewing Project (MulanPSL-2.0 License).
// ====================
// This code is released under the SPDX-License-Identifier: `MulanPSL-2.0`.

import Testing
@testable import Yukuaki

@Suite("Yukuaki：漢語拼音轉注音")
struct YukuakiPinyinTests {
  @Test(
    "基本音節",
    arguments: [
      ("dian4", "ㄉㄧㄢˋ"),
      ("nao3", "ㄋㄠˇ"),
      ("ai4", "ㄞˋ"),
      ("hao4", "ㄏㄠˋ"),
      ("zhe3", "ㄓㄜˇ"),
      ("zhong1", "ㄓㄨㄥ"),
      ("guo2", "ㄍㄨㄛˊ"),
      ("ren2", "ㄖㄣˊ"),
      ("wo3", "ㄨㄛˇ"),
      ("shi4", "ㄕˋ"),
      ("ma5", "ㄇㄚ˙"),
    ]
  )
  func basicSyllables(input: String, expected: String) {
    #expect(Yukuaki.PinyinConverter.bopomofo(fromPinyin: input) == expected)
  }

  @Test(
    "ü 韻與零聲母",
    arguments: [
      ("lv4", "ㄌㄩˋ"),
      ("nv3", "ㄋㄩˇ"),
      ("ju4", "ㄐㄩˋ"),
      ("xue2", "ㄒㄩㄝˊ"),
      ("yue4", "ㄩㄝˋ"),
      ("yuan2", "ㄩㄢˊ"),
      ("er2", "ㄦˊ"),
      ("yi1", "ㄧ"),
      ("wu3", "ㄨˇ"),
      ("weng1", "ㄨㄥ"),
      ("yo1", "ㄧㄛ"),
      ("jiong3", "ㄐㄩㄥˇ"),
      ("zhi1", "ㄓ"),
      ("ci2", "ㄘˊ"),
      ("si4", "ㄙˋ")
    ]
  )
  func finalsAndZeroInitials(input: String, expected: String) {
    #expect(Yukuaki.PinyinConverter.bopomofo(fromPinyin: input) == expected)
  }

  @Test("整條讀音鏈的轉換")
  func wholeChain() throws {
    let chain = try Yukuaki.PinyinConverter.readingChain(from: "dian4-nao3-ai4-hao4-zhe3")
    #expect(chain == ["ㄉㄧㄢˋ", "ㄋㄠˇ", "ㄞˋ", "ㄏㄠˋ", "ㄓㄜˇ"])
  }

  @Test("字母大小寫不影響結果")
  func caseInsensitive() {
    #expect(Yukuaki.PinyinConverter.bopomofo(fromPinyin: "Dian4") == "ㄉㄧㄢˋ")
  }

  @Test("缺聲調數字時視為無法辨識")
  func missingToneDigitFails() {
    #expect(Yukuaki.PinyinConverter.bopomofo(fromPinyin: "dian") == nil)
    #expect(throws: Yukuaki.Exception.self) {
      try Yukuaki.PinyinConverter.readingChain(from: "dian-nao3")
    }
  }

  @Test("無法辨識的音節會拋錯")
  func invalidSyllableThrows() {
    #expect(Yukuaki.PinyinConverter.bopomofo(fromPinyin: "zzz4") == nil)
    #expect(throws: Yukuaki.Exception.self) {
      try Yukuaki.PinyinConverter.readingChain(from: "dian4-zzz4")
    }
  }

  @Test("空音節鏈會拋錯")
  func emptyChainThrows() {
    #expect(throws: Yukuaki.Exception.self) {
      try Yukuaki.PinyinConverter.readingChain(from: "")
    }
  }

  @Test("looksLikePinyin 只對含 ASCII 字母的字串回傳 true")
  func looksLikePinyinDetection() {
    #expect(Yukuaki.PinyinConverter.looksLikePinyin("dian4-nao3"))
    #expect(!Yukuaki.PinyinConverter.looksLikePinyin("ㄉㄧㄢˋ-ㄋㄠˇ"))
  }

  @Test("對照表沒有空音節")
  func tableHasNoEmptyValues() {
    #expect(Yukuaki.PinyinConverter.table.values.allSatisfy { !$0.isEmpty })
  }

  @Test("聲調符號與辭典資料一致（輕聲後置）")
  func toneMarksMatchLexicon() {
    #expect(Yukuaki.PinyinConverter.toneMarks == ["", "ˊ", "ˇ", "ˋ", "˙"])
  }
}
