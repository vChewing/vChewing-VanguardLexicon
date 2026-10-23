// (c) 2025 and onwards The vChewing Project (MulanPSL-2.0 License).
// ====================
// This code is released under the SPDX-License-Identifier: `MulanPSL-2.0`.

import Testing
@testable import Yukuaki

// MARK: - IncomingContextLexicon

/// 三個案例共用的辭典。分數不是語料統計值，而是「讓三個案例同時成立」的示範值。
///
/// 令 a = 在(−5.009)、b = 再(−5.5)、u = 這樣 的 unigram(−5.2)、d = 的 的 unigram(−1.5)：
/// - 案例 2 要求 `B01 > a + u − b = −4.709`（不然「再」贏不了「在」）。
/// - 案例 3 要求 `T01 > B01 + (b − a) + d − u = B01 + 3.209`，又 T01 ≤ 0，
///   故 `B01 < −3.209`。也就是說 **B01 只有落在 (−4.709, −3.209) 這個窗口裡**，
///   三個案例才有可能同時成立。
///
/// 這個窗口本身就是 P325 的結論之一：在現行「語境加成須高於同名節點 unigram 基線、
/// 且逐項對數相加」的計分模型下，右文脈 n-gram 的可用權重範圍是被案例本身夾死的。
private enum IncomingContextLexicon {
  // MARK: Internal

  static let baseGrams: [Yukuaki.Gram] = [
    uni("ㄅㄨˋ", "不", -4.5),
    uni("ㄧㄠˋ", "要", -4.0),
    uni("ㄗㄞˋ", "在", -5.009),
    uni("ㄗㄞˋ", "再", -5.5),
    uni("ㄓㄜˋ", "這", -2.5),
    uni("ㄧㄤˋ", "樣", -5.0),
    uni("ㄌㄧˇ", "裡", -5.2),
    multi(["ㄓㄜˋ", "ㄧㄤˋ"], "這樣", -5.2),
    multi(["ㄓㄜˋ", "ㄌㄧˇ"], "這裡", -5.5),
    uni("ㄉㄜ˙", "的", -1.5),
  ]

  /// [B01]：「再」後面的「這樣」。
  static let bigram = multi(["ㄓㄜˋ", "ㄧㄤˋ"], "這樣", -4.0, previous: "再")

  /// [T01]：「在」→「這樣」之間的「的」，用來抵銷 B01。
  static let trigram = multi(["ㄉㄜ˙"], "的", -0.5, previous: "這樣", anterior: "在")

  static func assembler(withBigram: Bool = true, withTrigram: Bool = true) -> Yukuaki.Assembler {
    var grams = baseGrams
    if withBigram { grams.append(bigram) }
    if withTrigram { grams.append(trigram) }
    let lexicon = Lexicon(grams: grams)
    return lexicon.assembler(maxSegLength: 10)
  }

  // MARK: Private

  private struct Lexicon {
    let grams: [Yukuaki.Gram]

    func querier(_ keys: [Yukuaki.PossibleKey]) -> [Yukuaki.Gram] {
      let wanted = keys.representativeKeys
      return grams.filter { $0.keyArray == wanted }
    }

    func checker(_ keys: [String]) -> Bool {
      grams.contains { $0.keyArray == keys }
    }

    func assembler(maxSegLength: Int) -> Yukuaki.Assembler {
      Yukuaki.Assembler(
        gramQuerier: querier,
        gramAvailabilityChecker: checker,
        config: Yukuaki.Config(maxSegLength: maxSegLength)
      )
    }
  }

  private static func uni(_ key: String, _ value: String, _ probability: Double) -> Yukuaki.Gram {
    Yukuaki.Gram(keyArray: [key], current: value, probability: probability)
  }

  private static func multi(
    _ keys: [String],
    _ value: String,
    _ probability: Double,
    previous: String? = nil,
    anterior: String? = nil
  )
    -> Yukuaki.Gram {
    Yukuaki.Gram(
      keyArray: keys,
      current: value,
      previous: previous,
      anterior: anterior,
      probability: probability
    )
  }
}

// MARK: - YukuakiIncomingContextTests

/// 「右文脈」＝組句當下的前文不足以定案、必須等右邊的詞進來才知道該選哪個同音詞。
///
/// 這三支測試若改回「只以位置為 DP 狀態」的舊演算法，第二、三支會失敗：
/// 「再」在「要」後面就先輸給「在」而被砍掉，之後「這樣」帶來的 B01 加成永遠沒機會生效。
@Suite("Yukuaki：右文脈 DP")
struct YukuakiIncomingContextTests {
  @Test("案例 1：預設就該選「在」，不需要任何 n-gram 資料")
  func caseOneDefaultsToZai4() throws {
    let assembler = IncomingContextLexicon.assembler(withBigram: false, withTrigram: false)
    try assembler.insertKeys(["ㄅㄨˋ", "ㄧㄠˋ", "ㄗㄞˋ", "ㄓㄜˋ", "ㄌㄧˇ"])
    // 組句會就地把勝出之 gram 寫回節點，故一律先取值再斷言（Swift Testing 失敗診斷會二次求值）。
    let result = assembler.assembleWithScore()
    #expect(result.path.map(\.value) == ["不", "要", "在", "這裡"])
    #expect(abs(result.score - -19.009) < 1e-6)
  }

  @Test("案例 2：B01 讓「再」翻盤")
  func caseTwoFlipsToZai4WithBigram() throws {
    let assembler = IncomingContextLexicon.assembler(withTrigram: false)
    try assembler.insertKeys(["ㄅㄨˋ", "ㄧㄠˋ", "ㄗㄞˋ", "ㄓㄜˋ", "ㄧㄤˋ"])
    let result = assembler.assembleWithScore()
    #expect(result.path.map(\.value) == ["不", "要", "再", "這樣"])
    #expect(abs(result.score - -18.0) < 1e-6)
  }

  @Test("案例 2 的負控：拿掉 B01 就退回「在」")
  func caseTwoFallsBackWithoutBigram() throws {
    let assembler = IncomingContextLexicon.assembler(withBigram: false, withTrigram: false)
    try assembler.insertKeys(["ㄅㄨˋ", "ㄧㄠˋ", "ㄗㄞˋ", "ㄓㄜˋ", "ㄧㄤˋ"])
    let result = assembler.assembleWithScore()
    #expect(result.path.map(\.value) == ["不", "要", "在", "這樣"])
  }

  /// 總分反映計分模型（P326）：`的` 節點以單元圖基線 −1.5 起算，T01 的增益
  /// （原始機率 −0.5，較基線高 1.0）按鏈長 3 計兩次 ⇒ 節點分數 −1.5 + 2.0 = +0.5，
  /// 總分因而由舊模型的 −19.209 提高 1.0 至 −18.209。
  @Test("案例 3：T01 用前前驗詞把「在」扳回來")
  func caseThreeRestoresZai4WithTrigram() throws {
    let assembler = IncomingContextLexicon.assembler()
    try assembler.insertKeys(["ㄅㄨˋ", "ㄧㄠˋ", "ㄗㄞˋ", "ㄓㄜˋ", "ㄧㄤˋ", "ㄉㄜ˙"])
    let result = assembler.assembleWithScore()
    #expect(result.path.map(\.value) == ["不", "要", "在", "這樣", "的"])
    #expect(abs(result.score - -18.209) < 1e-6)
  }

  @Test("案例 3 的負控：拿掉 T01 就退回「再」")
  func caseThreeFallsBackWithoutTrigram() throws {
    let assembler = IncomingContextLexicon.assembler(withTrigram: false)
    try assembler.insertKeys(["ㄅㄨˋ", "ㄧㄠˋ", "ㄗㄞˋ", "ㄓㄜˋ", "ㄧㄤˋ", "ㄉㄜ˙"])
    let result = assembler.assembleWithScore()
    #expect(result.path.map(\.value) == ["不", "要", "再", "這樣", "的"])
  }

  @Test("重複組句不會漂移")
  func assemblyIsIdempotent() throws {
    let assembler = IncomingContextLexicon.assembler()
    try assembler.insertKeys(["ㄅㄨˋ", "ㄧㄠˋ", "ㄗㄞˋ", "ㄓㄜˋ", "ㄧㄤˋ", "ㄉㄜ˙"])
    let first = assembler.assemble().map(\.value)
    let second = assembler.assemble().map(\.value)
    let third = assembler.assemble().map(\.value)
    #expect(second == first)
    #expect(third == second)
  }

  /// 計分模型（P326）：`baseline + (chainLength − 1) × (probability − baseline)`。
  ///
  /// - 雙元圖的結果恰為原始機率，與舊模型逐位元相同（既有語料的計分不會漂移）。
  /// - 三元圖把增益算兩次；四階以上再由鏈長自然外推。
  /// - 鏈長數的是「詞鏈」而非讀音：多音節詞的單元圖仍是 1。
  @Test("計分模型：按鏈長計次")
  func chainLengthWeighting() throws {
    let baseline = -1.5
    func gram(previous: String?, anterior: String?, probability: Double) -> Yukuaki.Gram {
      .init(
        keyArray: ["ㄉㄜ˙"],
        current: "的",
        previous: previous,
        anterior: anterior,
        probability: probability
      )
    }
    let unigram = gram(previous: nil, anterior: nil, probability: -1.5)
    let bigram = gram(previous: "這樣", anterior: nil, probability: -0.6)
    let trigram = gram(previous: "這樣", anterior: "在", probability: -0.5)
    #expect(unigram.chainLength == 1)
    #expect(bigram.chainLength == 2)
    #expect(trigram.chainLength == 3)
    #expect(abs(unigram.weightedScore(against: baseline) - -1.5) < 1e-9)
    #expect(abs(bigram.weightedScore(against: baseline) - -0.6) < 1e-9)
    #expect(abs(trigram.weightedScore(against: baseline) - 0.5) < 1e-9)
  }
}
