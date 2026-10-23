// (c) 2025 and onwards The vChewing Project (MulanPSL-2.0 License).
// ====================
// This code is released under the SPDX-License-Identifier: `MulanPSL-2.0`.

import Foundation
import Yukuaki

// MARK: - DebuggerError

enum DebuggerError: Error, LocalizedError {
  case usage(String)
  case malformedTextMap(String)
  case textMapNotFound([String])

  // MARK: Internal

  var errorDescription: String? {
    switch self {
    case let .usage(message):
      return "參數錯誤：\(message)"
    case let .malformedTextMap(message):
      return "詞庫格式無法辨識：\(message)"
    case let .textMapNotFound(candidates):
      return "找不到詞庫檔案。已嘗試：\n" + candidates.map { "  - \($0)" }.joined(separator: "\n")
    }
  }
}

// MARK: - DebuggerOptions

struct DebuggerOptions {
  // MARK: Lifecycle

  init(arguments: [String]) throws {
    var index = 0
    while index < arguments.count {
      let argument = arguments[index]
      let (flag, inlineValue) = Self.split(argument)
      func nextValue() throws -> String {
        if let inlineValue { return inlineValue }
        index += 1
        guard index < arguments.count else {
          throw DebuggerError.usage("`\(flag)` 之後缺少參數值。")
        }
        return arguments[index]
      }
      switch flag {
      case "--readingChain", "-k":
        readingChains.append(try nextValue())
      case "--expected", "-e":
        expecteds.append(try nextValue())
      case "--textMap", "-d":
        self.textMapPath = try nextValue()
      case "--dumpKey":
        self.dumpKey = try nextValue()
      case "--lang":
        let raw = try nextValue()
        guard let parsed = parseLocaleTag(raw) else {
          throw DebuggerError.usage("`--lang` 只接受 `zh-Hant` 或 `zh-Hans`。")
        }
        self.locale = parsed
      case "--separator":
        let raw = try nextValue()
        guard raw.count == 1, let character = raw.first else {
          throw DebuggerError.usage("`--separator` 只能是一個字元。")
        }
        self.separator = character
      case "--top", "-n":
        let raw = try nextValue()
        guard let value = Int(raw), value > 0 else {
          throw DebuggerError.usage("`--top` 需要正整數。")
        }
        self.topPathCount = value
      case "--maxChunkLength":
        let raw = try nextValue()
        guard let value = Int(raw), value > 0 else {
          throw DebuggerError.usage("`--maxChunkLength` 需要正整數。")
        }
        self.maxChunkLength = value
      case "--json", "-j":
        self.wantsJSON = true
      case "--verbose", "-v":
        self.isVerbose = true
      case "--noAdvice":
        self.wantsAdvice = false
      case "--help", "-h":
        self.showsHelp = true
      default:
        throw DebuggerError.usage("未知的參數 `\(argument)`。使用 `--help` 查閱用法。")
      }
      index += 1
    }
  }

  // MARK: Internal

  static let usage = """
  VanguardLexiconDebugger — 在給定讀音的前提下驗證組句結果、並逆推需要追補的 n-gram 詞條。

  用法：
    VanguardLexiconDebugger --readingChain <讀音鏈> [--expected <期望結果>] [選項]

  必要參數：
    --readingChain, -k <字串>
        以 `-` 銜接的讀音鏈。支援兩種標記法：
          * 注音：`ㄉㄧㄢˋ-ㄋㄠˇ-ㄞˋ-ㄏㄠˋ-ㄓㄜˇ`
          * 漢語拼音（ASCII 數字標調）：`dian4-nao3-ai4-hao4-zhe3`
        混用會失敗；程式會自動判斷整條鏈屬於哪一種。
        可重複給定多次：每次一個案例，並依序與 `--expected` 配對。多案例
        之間會互相檢查提案是否衝突（見下）。

  選項：
    --expected, -e <字串>
        期望的組句結果。給定之後，程式會比對預設組句結果，並在兩者不符時
        逆推「還需要哪些 bigram／trigram、它們大約需要多高的出現頻次」。
        與 `--readingChain` 按序成對；也可只給一部份（少給的案例就只組句）。
        提案按「證據等級」排序，等級越高代表越容易成立：
          * 抬高既有詞條的頻次（unigram 的 count 只是零頻次預設值）
          * 調整既有詞條的頻次
          * 新增 bigram／trigram（語料裡最難補的一類）
          * 新增 unigram（詞庫裡根本沒有這個詞）
        多案例之間若甲的提案會讓乙偏離其 `--expected`，會列為衝突並以離開碼 2 結束。
    --textMap, -d <路徑>
        詞庫 .txtMap 路徑。預設依序尋找：
          Build/Release/vanguard-textmap/VanguardFactoryDict4Typing.txtMap
          ../Build/Release/vanguard-textmap/VanguardFactoryDict4Typing.txtMap
    --top, -n <正整數>
        額外顯示前 n 條候選組句路徑（預設 3）。
    --maxChunkLength <正整數>
        單一詞段的讀音上限（預設 10）。
    --separator <字元>
        讀音鏈的分隔符（預設 `-`）。
    --lang <zh-Hant|zh-Hans>
        詞條語系軌（預設 `zh-Hant`）。兩軌的詞條一律收下，語系只決定計分權重：
        本軌照該行機率計分，另一軌獨有的詞條以零頻次權重
        `log10(e^(字數/3 - 1) × 0.25 / norm)` 排在後面（故繁體模式仍打得出
        簡體字、反之亦然）。`--json` 的 `crossLaneValueCount` 會計數。
    --dumpKey <讀音鏈>
        傾印某個讀音（可為多音節，以分隔符相連）在詞庫內的全部詞條，
        然後結束。這是在兩個語系軌之間比較同一組讀音之權重的好用入口。
    --json, -j
        以 JSON 輸出（便於 LLM 或其他工具消費）。
    --verbose, -v
        額外傾印節點格（每個起點、每個幅節長度底下的候選詞條）。
    --noAdvice
        只做組句，不做逆推。
    --help, -h
        顯示本說明。

  離開碼：
    0  正常結束（未給 `--expected`，或已命中）
    1  參數錯誤、詞庫讀不到或格式不認得
    2  給了 `--expected` 但組句結果與之不符，或案例之間存在提案衝突

  範例：
    VanguardLexiconDebugger -k dian4-nao3-ai4-hao4-zhe3
    VanguardLexiconDebugger -k dian4-nao3 -e 電腦 -v
    VanguardLexiconDebugger -k ㄨㄛˇ-ㄕˋ-ㄍㄨㄥ-ㄔㄥˊ-ㄕ -e 我是工程師 --json
  """

  var readingChains = [String]()
  var expecteds = [String]()
  var textMapPath: String?
  var dumpKey: String?
  var locale: VanguardTextMapReader.Locale = .cht

  var separator: Character?
  var topPathCount = 3
  var maxChunkLength = 10
  var wantsJSON = false
  var isVerbose = false
  var wantsAdvice = true
  var showsHelp = false

  /// 對外的語系標籤。
  var langTag: String {
    switch locale {
    case .cht: return "zh-Hant"
    case .chs: return "zh-Hans"
    case .both: return "both"
    }
  }

  var helpRequested: Bool { showsHelp }
  var usesPinyin: Bool {
    guard let first = readingChains.first else { return false }
    return Yukuaki.PinyinConverter.looksLikePinyin(first)
  }

  // MARK: Private

  private static func split(_ argument: String) -> (flag: String, value: String?) {
    guard argument.hasPrefix("-"), let separatorIndex = argument.firstIndex(of: "=") else {
      return (argument, nil)
    }
    let flag = String(argument[..<separatorIndex])
    let value = String(argument[argument.index(after: separatorIndex)...])
    return (flag, value.isEmpty ? nil : value)
  }
}

// MARK: - ReadingChainResolver

enum ReadingChainResolver {
  /// 把使用者給的讀音鏈轉成注音音節陣列。
  static func resolve(_ raw: String, separator: Character?) throws -> (chain: [String], notation: String) {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
      throw DebuggerError.usage("`--readingChain` 不可為空。")
    }
    let actualSeparator: Character = separator ?? (trimmed.contains("-") ? "-" : " ")
    if Yukuaki.PinyinConverter.looksLikePinyin(trimmed) {
      do {
        return (try Yukuaki.PinyinConverter.readingChain(from: trimmed, separator: actualSeparator), "hanyu-pinyin")
      } catch {
        throw DebuggerError.usage(error.localizedDescription)
      }
    }
    let chain = trimmed.split(separator: actualSeparator).map(String.init)
    guard !chain.isEmpty else { throw DebuggerError.usage("`--readingChain` 不可為空。") }
    return (chain, "bopomofo")
  }
}

// MARK: - ReportPrinter

enum ReportPrinter {
  static func format(_ value: Double, places: Int = 4) -> String {
    String(format: "%.\(places)f", value)
  }

  static func formatCount(_ value: Double?) -> String {
    guard let value, value.isFinite else { return "無法逆推" }
    if value >= 1e9 { return String(format: "%.3e", value) }
    if value >= 1 { return String(format: "%.0f", value.rounded()) }
    return String(format: "%.2e", value)
  }

  static func header(_ title: String) -> String {
    "=== \(title) ==="
  }
}

// MARK: - DebuggerRunner

struct DebuggerRunner {
  // MARK: Internal

  /// 一次執行的單句結果。
  struct CaseRun {
    let raw: String
    let resolved: (chain: [String], notation: String)
    let assembler: Yukuaki.Assembler
    let outcome: (path: [Yukuaki.GramInPath], score: Double)
    let advice: Yukuaki.Advisor.Report?
  }

  /// 一句的提案套到另一句上所造成的破壞。
  struct Conflict {
    let source: Int
    let target: Int
    let expected: String
    let actual: String
    let specs: [Yukuaki.GramSpec]
  }

  let options: DebuggerOptions
  let reader: VanguardTextMapReader

  /// 回傳 `false` 表示「有給 `--expected` 但組句結果與之不符」，或有跨句衝突。
  @discardableResult
  func run() throws -> Bool {
    if let dumpKey = options.dumpKey {
      try dump(key: dumpKey)
      return true
    }
    guard !options.readingChains.isEmpty else {
      throw DebuggerError.usage("需要 `--readingChain`；使用 `--help` 查閱用法。")
    }
    guard options.expecteds.isEmpty || options.expecteds.count == options.readingChains.count else {
      throw DebuggerError.usage("`--expected` 必須與 `--readingChain` 成對（數量相同），或完全不給。")
    }

    let advisor = Yukuaki.Advisor(
      gramQuerier: gramQuerier,
      norm: reader.norm,
      options: {
        var options = Yukuaki.Advisor.Options()
        options.maxChunkLength = self.options.maxChunkLength
        return options
      }()
    )

    var cases = [CaseRun]()
    for (index, rawChain) in options.readingChains.enumerated() {
      let resolved = try ReadingChainResolver.resolve(rawChain, separator: options.separator)
      let assembler = Yukuaki.Assembler(
        gramQuerier: gramQuerier,
        gramAvailabilityChecker: { [reader] keys in reader.hasGrams(forKeys: keys) },
        config: Yukuaki.Config(maxSegLength: options.maxChunkLength)
      )
      do {
        try assembler.insertKeys(resolved.chain.map { Yukuaki.PossibleKey.singleKey($0) })
      } catch {
        throw DebuggerError.usage(error.localizedDescription)
      }
      let expected = options.expecteds.indices.contains(index) ? options.expecteds[index] : nil
      var advice: Yukuaki.Advisor.Report?
      if let expected, options.wantsAdvice {
        advice = try advisor.analyze(readingChain: resolved.chain, expected: expected)
      }
      cases.append(
        CaseRun(
          raw: rawChain,
          resolved: resolved,
          assembler: assembler,
          outcome: assembler.assembleWithScore(),
          advice: advice
        )
      )
    }

    /// 跨句交叉驗證：甲句的提案套到乙句上，會不會把乙句弄壞。
    let conflicts = detectConflicts(cases, advisor: advisor)

    if options.wantsJSON {
      try printJSON(cases: cases, conflicts: conflicts)
    } else {
      for (index, item) in cases.enumerated() {
        if cases.count > 1 {
          print(ReportPrinter.header("案例 \(index + 1)／\(cases.count)"))
        }
        printText(item: item, separator: String(reader.readingSeparator))
      }
      printConflicts(conflicts)
    }

    let isMatched = cases.allSatisfy { $0.advice?.isMatched ?? true }
    return isMatched && conflicts.isEmpty
  }

  // MARK: Private

  /// 組句器使用的詞庫查詢閉包。
  private var gramQuerier: Yukuaki.GramQuerier {
    { [reader] possibleKeys in
      reader.grams(forKeys: possibleKeys.representativeKeys)
    }
  }

  private func detectConflicts(_ cases: [CaseRun], advisor: Yukuaki.Advisor) -> [Conflict] {
    guard cases.count > 1 else { return [] }
    var result = [Conflict]()
    for (sourceIndex, source) in cases.enumerated() {
      guard let advice = source.advice, !advice.proposals.isEmpty else { continue }
      for (targetIndex, target) in cases.enumerated() where targetIndex != sourceIndex {
        guard let targetAdvice = target.advice, targetAdvice.isMatched else { continue }
        guard let predicted = advisor.assembling(readingChain: target.resolved.chain, specs: advice.proposals)
        else { continue }
        guard predicted.text != targetAdvice.expected else { continue }
        result.append(
          Conflict(
            source: sourceIndex,
            target: targetIndex,
            expected: targetAdvice.expected,
            actual: predicted.text,
            specs: advice.proposals
          )
        )
      }
    }
    return result
  }

  private func printConflicts(_ conflicts: [Conflict]) {
    guard !conflicts.isEmpty else {
      guard options.readingChains.count > 1 else { return }
      print("")
      print(ReportPrinter.header("交叉驗證"))
      print("結果：各句的提案互不衝突。")
      return
    }
    print("")
    print(ReportPrinter.header("交叉驗證"))
    for conflict in conflicts {
      print(
        "衝突：案例 \(conflict.source + 1) 的提案套到案例 \(conflict.target + 1) 之後，"
          + "組句變成「\(conflict.actual)」，與該句期望「\(conflict.expected)」不符。"
      )
      for spec in conflict.specs {
        print("  - \(spec.summary())")
      }
    }
  }

  private func dump(key rawKey: String) throws {
    let resolved = try ReadingChainResolver.resolve(rawKey, separator: options.separator)
    let key = resolved.chain
    let grams = reader.grams(forKeys: key)
    print(ReportPrinter.header("讀音詞條"))
    print("讀音：\(key.joined(separator: String(reader.readingSeparator)))")
    print("詞條數：\(grams.count)")
    for gram in grams.sorted(by: Yukuaki.Node.sortGram) {
      var line = "  \(gram.current)\t\(ReportPrinter.format(gram.probability))"
      if let previous = gram.previous {
        line += "\t前文：\(previous)"
        if let anterior = gram.anterior { line += "｜前前文：\(anterior)" }
      }
      print(line)
    }
  }

  private func printJSON(cases: [CaseRun], conflicts: [Conflict]) throws {
    struct AssemblyPayload: Codable {
      let input: String
      let notation: String
      let readingChain: [String]
      let text: String
      let score: Double
      let path: [Yukuaki.GramInPath]
      let topPaths: [Yukuaki.Assembler.CandidatePath]
    }
    struct ConflictPayload: Codable {
      let sourceCase: Int
      let targetCase: Int
      let expected: String
      let actual: String
      let proposals: [Yukuaki.GramSpec]
    }
    struct Envelope: Codable {
      let textMap: String
      let lang: String
      let crossLaneValueCount: Int
      let norm: Double?
      let keyCount: Int
      let entryLineCount: Int
      let hasContextualEntries: Bool
      let assembly: AssemblyPayload
      let advice: Yukuaki.Advisor.Report?
    }
    struct MultiEnvelope: Codable {
      let cases: [Envelope]
      let conflicts: [ConflictPayload]
    }
    let envelopes = cases.map { item in
      Envelope(
        textMap: reader.url.path,
        lang: options.langTag,
        crossLaneValueCount: reader.crossLaneValueCount,
        norm: reader.norm,
        keyCount: reader.keyCount,
        entryLineCount: reader.entryLineCount,
        hasContextualEntries: reader.hasContextualEntries,
        assembly: AssemblyPayload(
          input: item.raw,
          notation: item.resolved.notation,
          readingChain: item.resolved.chain,
          text: item.outcome.path.joinedSentence,
          score: item.outcome.score,
          path: item.outcome.path,
          topPaths: item.assembler.topPaths(limit: options.topPathCount)
        ),
        advice: item.advice
      )
    }
    let payloads = conflicts.map { conflict in
      ConflictPayload(
        sourceCase: conflict.source + 1,
        targetCase: conflict.target + 1,
        expected: conflict.expected,
        actual: conflict.actual,
        proposals: conflict.specs
      )
    }
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    let data: Data
    if envelopes.count == 1, payloads.isEmpty {
      data = try encoder.encode(envelopes[0])
    } else {
      data = try encoder.encode(MultiEnvelope(cases: envelopes, conflicts: payloads))
    }
    guard let text = String(data: data, encoding: .utf8) else {
      throw DebuggerError.usage("JSON 輸出編碼失敗。")
    }
    print(text)
  }

  private func printText(item: CaseRun, separator: String) {
    let resolved = item.resolved
    let outcome = item.outcome
    let assembler = item.assembler
    let advice = item.advice
    let separator = String(reader.readingSeparator)
    print(ReportPrinter.header("詞庫"))
    print("檔案：\(reader.url.path)")
    var langLine = "語系：\(options.langTag)"
    if reader.crossLaneValueCount > 0 {
      langLine += "（另一語系軌另有 \(reader.crossLaneValueCount) 條詞條，以零頻次權重排在後面）"
    }
    print(langLine)
    print("詞條行數：\(reader.entryLineCount)｜讀音數：\(reader.keyCount)")
    print("正規化基準：\(reader.norm.map { ReportPrinter.format($0, places: 3) } ?? "（未提供）")")
    print("前文詞條（bigram／trigram）：\(reader.hasContextualEntries ? "有" : "無（本資料集僅有 unigram）")")
    print("")

    print(ReportPrinter.header("組句"))
    if resolved.notation == "hanyu-pinyin" {
      print("輸入：\(item.raw)（漢語拼音，ASCII 數字標調）")
    }
    print("讀音鏈（\(resolved.chain.count) 音節）：\(resolved.chain.joined(separator: separator))")
    print("組句結果：\(outcome.path.joinedSentence)")
    print("總分：\(ReportPrinter.format(outcome.score))")
    print("分節：")
    for (index, section) in outcome.path.enumerated() {
      var line = String(format: "  %02d. ", index + 1)
      line += "\(section.joinedCurrentKey(by: separator)) → \(section.value)"
      line += "（\(ReportPrinter.format(section.score))"
      line += section.isUnigram ? "，unigram）" : "，前文「\(section.previous ?? "")」）"
      print(line)
    }

    let topPaths = assembler.topPaths(limit: options.topPathCount)
    if topPaths.count > 1 {
      print("候選路徑：")
      for (index, candidate) in topPaths.enumerated() {
        let segments = candidate.grams.map(\.value).joined(separator: "｜")
        let detail = segments == candidate.text ? "" : "；分詞 \(segments)"
        print("  \(index + 1). \(candidate.text)（\(ReportPrinter.format(candidate.score))\(detail)）")
      }
    }

    if options.isVerbose {
      print("")
      print(ReportPrinter.header("節點格"))
      for node in assembler.dumpNodes() {
        print("  起點 \(node.position)｜幅節 \(node.segLength)｜\(node.keyArray.joined(separator: separator))")
        print("    詞條 \(node.gramCount) 條（unigram \(node.unigramCount)、含前文 \(node.contextualCount)）")
        for candidate in node.candidates {
          print("      - \(candidate.value)（\(ReportPrinter.format(candidate.probability))）")
        }
      }
    }

    guard let advice else { return }
    print("")
    print(ReportPrinter.header("逆推"))
    print("期望結果：\(advice.expected)")
    if advice.isMatched {
      print("結果：已命中，無需追補任何詞條。")
    } else {
      print("結果：未命中（預設組句為「\(advice.assembledText)」）")
      print("候選分詞數：\(advice.alignmentCount)")
      print("取用分詞：\(advice.alignment.map(\.value).joined(separator: " | "))")
      if advice.proposals.isEmpty {
        print("建議追補：無法靠追補詞條解決。")
      } else {
        print("建議追補（\(advice.proposals.count) 條）：")
        for (index, spec) in advice.proposals.enumerated() {
          print("  \(index + 1). \(spec.summary(separator: separator))")
          if let count = spec.requiredCount {
            print(
              "     → 需要的 count 形態：約 \(ReportPrinter.formatCount(count))\(spec.isCountExpressive ? "" : "（低於 1，現行正規化基準無法達成）")"
            )
            if let norm = spec.norm {
              print("     → 依正規化基準 \(ReportPrinter.format(norm, places: 3)) 逆推")
            }
          }
        }
      }
      if let validation = advice.validation {
        print(
          "模擬驗證：\(validation.isSatisfied ? "已達成" : "未達成")（邊距 \(ReportPrinter.format(validation.margin, places: 4))，最終組句「\(validation.finalText)」）"
        )
      }
    }
    if !advice.notes.isEmpty {
      print("備註：")
      for note in advice.notes {
        print("  - \(note)")
      }
    }
  }
}

// MARK: - LocaleTag

/// CLI 只認 BCP 47 的語系標籤：`zh-Hant`（繁）與 `zh-Hans`（簡）。
///
/// 記憶體內的取捨模型仍是 `VanguardTextMapReader.Locale`（`cht`／`chs`／`both`），
/// 這裡只做標籤到該模型的映射。
private func parseLocaleTag(_ rawTag: String) -> VanguardTextMapReader.Locale? {
  switch rawTag.lowercased() {
  case "zh_hant", "zh-hant": return .cht
  case "zh_hans", "zh-hans": return .chs
  default: return nil
  }
}

// MARK: - 進入點

do {
  let options = try DebuggerOptions(arguments: Array(CommandLine.arguments.dropFirst()))
  if options.showsHelp {
    print(DebuggerOptions.usage)
    exit(0)
  }
  let url = try TextMapLocator.locate(override: options.textMapPath)
  let reader = try VanguardTextMapReader(url: url, locale: options.locale)
  let isMatched = try DebuggerRunner(options: options, reader: reader).run()
  exit(isMatched ? 0 : 2)
} catch {
  let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
  FileHandle.standardError.write(Data("錯誤：\(message)\n".utf8))
  exit(1)
}

// MARK: - TextMapLocator

enum TextMapLocator {
  static let defaultRelativePaths = [
    "Build/Release/vanguard-textmap/VanguardFactoryDict4Typing.txtMap",
    "../Build/Release/vanguard-textmap/VanguardFactoryDict4Typing.txtMap",
    "../../Build/Release/vanguard-textmap/VanguardFactoryDict4Typing.txtMap",
  ]

  static func locate(override: String?) throws -> URL {
    let fileManager = FileManager.default
    if let override, !override.isEmpty {
      let url = URL(fileURLWithPath: override).standardizedFileURL
      guard fileManager.fileExists(atPath: url.path) else {
        throw DebuggerError.textMapNotFound([url.path])
      }
      return url
    }
    var candidates = [String]()
    for relative in defaultRelativePaths {
      let url = URL(fileURLWithPath: relative).standardizedFileURL
      candidates.append(url.path)
      if fileManager.fileExists(atPath: url.path) { return url }
    }
    throw DebuggerError.textMapNotFound(candidates)
  }
}
