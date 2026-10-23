// (c) 2025 and onwards The vChewing Project (MulanPSL-2.0 License).
// ====================
// This code is released under the SPDX-License-Identifier: `MulanPSL-2.0`.

extension Yukuaki {
  /// 漢語拼音（ASCII 數字標調）→ 注音符號的轉換器。
  ///
  /// 支援的拼寫形態：
  /// - 聲母與韻母的一般拼法，例如 `dian4`、`zhong1`、`xiong2`。
  /// - `ü` 的三種 ASCII 寫法：`v`（`lv4`）、`u`（僅限 j／q／x 之後，`ju4`）、`ü`（`lü4`）。
  /// - 零聲母的 y／w 拼法，例如 `yi1`、`wu3`、`yue4`、`weng1`。
  /// - 嘆詞與鼻音音節：`eh`、`ê`、`m`、`n`、`ng`、`hm`、`hng`、`yo`、`yai`。
  ///
  /// 不支援、也不會猜測的形態：`u:`／`v` 之外的 ü 變體、以及缺聲調數字的音節。
  /// 對照表本身是漢語拼音與注音符號之間的語言事實對照，不是從別的專案抄來的資料表。
  public enum PinyinConverter {
    // MARK: Public

    /// 將以 `separator` 銜接的漢語拼音鏈轉成注音音節陣列。
    /// - Parameters:
    ///   - chain: 例如 `dian4-nao3-ai4-hao4-zhe3`。
    ///   - separator: 音節分隔符，預設為 `-`。
    public static func readingChain(from chain: String, separator: Character = "-") throws -> [String] {
      let segments = chain.split(separator: separator).map(String.init)
      guard !segments.isEmpty else { throw Yukuaki.Exception.invalidReadingChain("音節鏈為空。") }
      return try segments.map { segment in
        guard let converted = bopomofo(fromPinyin: segment) else {
          throw Yukuaki.Exception.invalidReadingChain(
            "「\(segment)」不是可辨識的漢語拼音音節（需為 ASCII 字母＋聲調數字 1…5）。"
          )
        }
        return converted
      }
    }

    /// 將單一漢語拼音音節轉成注音音節。無法辨識時回傳 `nil`。
    ///
    /// 聲調數字是必要條件：缺了聲調的 `dian` 一律視為無法辨識，不做「一聲」的猜測。
    public static func bopomofo(fromPinyin syllable: String) -> String? {
      let normalized = syllable.lowercased()
      guard !normalized.isEmpty else { return nil }
      var body = normalized
      guard let last = body.last, let digit = last.wholeNumberValue, (1 ... 5).contains(digit) else {
        return nil
      }
      body.removeLast()
      guard let bopomofo = table[body], !bopomofo.isEmpty else { return nil }
      return bopomofo + toneMarks[digit - 1]
    }

    /// 該音節鏈是否看起來是漢語拼音（含 ASCII 字母）。
    public static func looksLikePinyin(_ chain: String) -> Bool {
      chain.unicodeScalars.contains { $0.isASCII && $0.properties.isAlphabetic }
    }

    // MARK: Internal

    /// 聲調符號（索引 0 對應一聲）。與辭典資料一致：輕聲的 `˙` 採後置。
    static let toneMarks = ["", "ˊ", "ˇ", "ˋ", "˙"]

    /// 拼音音節（不含聲調）→ 注音音節的對照表。
    static let table: [String: String] = makeTable()

    // MARK: Private

    /// 一般聲母可接的韻母。
    private static let plainFinals: [String: String] = [
      "a": "ㄚ", "o": "ㄛ", "e": "ㄜ", "ai": "ㄞ", "ei": "ㄟ", "ao": "ㄠ", "ou": "ㄡ",
      "an": "ㄢ", "en": "ㄣ", "ang": "ㄤ", "eng": "ㄥ",
      "i": "ㄧ", "ia": "ㄧㄚ", "ie": "ㄧㄝ", "iao": "ㄧㄠ", "iu": "ㄧㄡ",
      "ian": "ㄧㄢ", "in": "ㄧㄣ", "iang": "ㄧㄤ", "ing": "ㄧㄥ", "ong": "ㄨㄥ",
      "u": "ㄨ", "ua": "ㄨㄚ", "uo": "ㄨㄛ", "uai": "ㄨㄞ", "ui": "ㄨㄟ",
      "uan": "ㄨㄢ", "un": "ㄨㄣ", "uang": "ㄨㄤ",
    ]

    /// 舌尖前／後聲母（此時 `i` 不另寫 ㄧ）。
    private static let apicalInitials: Set<String> = ["z", "c", "s", "zh", "ch", "sh", "r"]

    /// 聲母表。長者優先（`zh` 先於 `z`）。
    private static let initials: [(String, String)] = [
      ("zh", "ㄓ"), ("ch", "ㄔ"), ("sh", "ㄕ"),
      ("b", "ㄅ"), ("p", "ㄆ"), ("m", "ㄇ"), ("f", "ㄈ"),
      ("d", "ㄉ"), ("t", "ㄊ"), ("n", "ㄋ"), ("l", "ㄌ"),
      ("g", "ㄍ"), ("k", "ㄎ"), ("h", "ㄏ"),
      ("j", "ㄐ"), ("q", "ㄑ"), ("x", "ㄒ"),
      ("r", "ㄖ"), ("z", "ㄗ"), ("c", "ㄘ"), ("s", "ㄙ"),
    ]

    /// 零聲母音節（含 y／w 拼法、嘆詞與鼻音音節）。
    private static let zeroInitialFinals: [String: String] = [
      "a": "ㄚ", "o": "ㄛ", "e": "ㄜ", "ê": "ㄝ", "eh": "ㄝ",
      "ai": "ㄞ", "ei": "ㄟ", "ao": "ㄠ", "ou": "ㄡ",
      "an": "ㄢ", "en": "ㄣ", "ang": "ㄤ", "eng": "ㄥ", "er": "ㄦ",
      "yi": "ㄧ", "ya": "ㄧㄚ", "yo": "ㄧㄛ", "ye": "ㄧㄝ", "yao": "ㄧㄠ", "you": "ㄧㄡ",
      "yan": "ㄧㄢ", "yin": "ㄧㄣ", "yang": "ㄧㄤ", "ying": "ㄧㄥ", "yong": "ㄩㄥ",
      "yai": "ㄧㄞ",
      "wu": "ㄨ", "wa": "ㄨㄚ", "wo": "ㄨㄛ", "wai": "ㄨㄞ", "wei": "ㄨㄟ",
      "wan": "ㄨㄢ", "wen": "ㄨㄣ", "wang": "ㄨㄤ", "weng": "ㄨㄥ",
      "yu": "ㄩ", "yue": "ㄩㄝ", "yuan": "ㄩㄢ", "yun": "ㄩㄣ",
      "m": "ㄇ", "n": "ㄋ", "ng": "ㄫ", "hm": "ㄏㄇ", "hng": "ㄏㄫ",
    ]

    /// j／q／x 之後的 ü 韻（拼寫上寫成 u）。
    private static let palatalFinals: [String: String] = [
      "i": "ㄧ", "ia": "ㄧㄚ", "ie": "ㄧㄝ", "iao": "ㄧㄠ", "iu": "ㄧㄡ",
      "ian": "ㄧㄢ", "in": "ㄧㄣ", "iang": "ㄧㄤ", "ing": "ㄧㄥ", "iong": "ㄩㄥ",
      "u": "ㄩ", "ue": "ㄩㄝ", "uan": "ㄩㄢ", "un": "ㄩㄣ",
    ]

    /// n／l 之後的 ü 韻（ASCII 寫成 v，或直接寫 ü）。
    private static let nasalLateralFinals: [String: String] = [
      "v": "ㄩ", "ve": "ㄩㄝ", "van": "ㄩㄢ", "vn": "ㄩㄣ",
      "ü": "ㄩ", "üe": "ㄩㄝ", "üan": "ㄩㄢ", "ün": "ㄩㄣ",
    ]

    private static func makeTable() -> [String: String] {
      var table = zeroInitialFinals
      for (initial, bopomofoInitial) in initials {
        let finals: [String: String]
        switch initial {
        case _ where apicalInitials.contains(initial):
          var adjusted = plainFinals
          adjusted["i"] = ""
          finals = adjusted
        case "j", "q", "x":
          finals = palatalFinals
        case "l", "n":
          finals = plainFinals.merging(nasalLateralFinals) { current, _ in current }
        default:
          finals = plainFinals
        }
        for (final, bopomofoFinal) in finals {
          table[initial + final] = bopomofoInitial + bopomofoFinal
        }
      }
      return table
    }
  }
}
