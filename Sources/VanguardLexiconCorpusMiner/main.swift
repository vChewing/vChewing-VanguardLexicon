// (c) 2025 and onwards The vChewing Project (MulanPSL-2.0 License).
// ====================
// This code is released under the SPDX-License-Identifier: `MulanPSL-2.0`.

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif
#if canImport(WinSDK)
  import WinSDK
#endif
import Foundation

// MARK: - 常數

// MARK: - 入口

func minerMain() throws {
  var arguments = Array(CommandLine.arguments.dropFirst())
  guard let command = arguments.first else {
    printHelp()
    terminateProcess(2)
  }
  if arguments.contains("-h") || arguments.contains("--help") {
    printHelp()
    terminateProcess(0)
  }
  arguments.removeFirst()
  let options = ParsedArguments(arguments)

  switch command {
  case "fetch": try runFetch(options)
  case "segment": try runSegment(options)
  case "mine": try runMine(options)
  case "help":
    printHelp()
  default:
    FileHandle.standardError.write(Data("未知的子命令：\(command)\n\n".utf8))
    printHelp()
    terminateProcess(2)
  }
}

do {
  try minerMain()
} catch {
  FileHandle.standardError.write(Data("錯誤：\(error)\n".utf8))
  terminateProcess(1)
}

// MARK: - ParsedArguments

struct ParsedArguments {
  let flags: [String: String]
  let switches: Set<String>

  init(_ arguments: [String]) {
    var flags = [String: String]()
    var switches = Set<String>()
    var index = 0
    while index < arguments.count {
      let argument = arguments[index]
      guard argument.hasPrefix("--") else {
        index += 1
        continue
      }
      let body = String(argument.dropFirst(2))
      if let separator = body.firstIndex(of: "=") {
        flags[String(body[..<separator])] = String(body[body.index(after: separator)...])
        index += 1
      } else if index + 1 < arguments.count, !arguments[index + 1].hasPrefix("--") {
        flags[body] = arguments[index + 1]
        index += 2
      } else {
        switches.insert(body)
        index += 1
      }
    }
    self.flags = flags
    self.switches = switches
  }

  func string(_ key: String) -> String? { flags[key] }
  func int(_ key: String) -> Int? { flags[key].flatMap(Int.init) }
  func double(_ key: String) -> Double? { flags[key].flatMap(Double.init) }
  func has(_ key: String) -> Bool { switches.contains(key) || flags[key] != nil }
}

// MARK: - fetch

func runFetch(_ options: ParsedArguments) throws {
  let outputURL = URL(fileURLWithPath: options.string("out") ?? "corpus-raw.jsonl")
  let variant = options.string("variant") ?? "zh-cn"
  let endpoint = URL(string: options.string("endpoint") ?? "https://zh.wikipedia.org/w/api.php")!
  var titles = DefaultTitles.list
  if let titlesURL = options.string("titles") {
    titles = try String(contentsOf: URL(fileURLWithPath: titlesURL), encoding: .utf8)
      .components(separatedBy: .newlines)
      .map { $0.trimmingCharacters(in: .whitespaces) }
      .filter { !$0.isEmpty }
  }
  if let limit = options.int("pages") { titles = Array(titles.prefix(limit)) }

  let fetcher = WikipediaFetcher(endpoint: endpoint, variant: variant)
  let pages = try fetcher.fetch(titles: titles)
  var lines = [String]()
  for page in pages {
    let dictionary = ["title": page.title, "text": page.text]
    let data = try JSONSerialization.data(withJSONObject: dictionary)
    lines.append(String(decoding: data, as: UTF8.self))
  }
  try (lines.joined(separator: "\n") + "\n").write(to: outputURL, atomically: true, encoding: .utf8)
  print("已抓取 \(pages.count) 篇（\(titles.count) 個標題）→ \(outputURL.path)")
}

// MARK: - segment

/// 分詞之最長詞長預設值：詞表實測最長詞遠長於此，交給 DAG 逐一試探只浪費時間；
/// 六字已涵蓋成語與專名，亦與 `--max-token-length` 之 CLI 預設一致。
let kDefaultMaximumTokenLength = 6

func makeSegmenter(index: TxtMapUnigramIndex, options: ParsedArguments) -> UnigramSegmenter {
  let cap = options.int("max-token-length") ?? kDefaultMaximumTokenLength
  return UnigramSegmenter(index: index, maximumWordLength: max(1, cap))
}

func runSegment(_ options: ParsedArguments) throws {
  guard let inputPath = options.string("in"), let outputPath = options.string("out"),
        let indexPath = options.string("index")
  else { throw MinerError.missingArgument("segment 需要 `--in`、`--out`、`--index`。") }
  let locale = TxtMapUnigramIndex.Locale(rawValue: options.string("locale") ?? "chs") ?? .chs
  let index = try TxtMapUnigramIndex(url: URL(fileURLWithPath: indexPath), locale: locale)
  let segmenter = makeSegmenter(index: index, options: options)

  let inputContent = try String(contentsOfFile: inputPath, encoding: .utf8)
  var output = ""
  var unknownRunCount = 0
  var sentenceCount = 0
  for line in inputContent.components(separatedBy: "\n") where !line.isEmpty {
    guard let data = line.data(using: .utf8),
          let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
          let text = object["text"] as? String
    else { continue }
    let result = segmenter.segment(text)
    sentenceCount += 1
    unknownRunCount += result.unknownRuns.count
    var payload: [String: Any] = ["words": result.words]
    if let title = object["title"] { payload["title"] = title }
    let encoded = try JSONSerialization.data(withJSONObject: payload)
    output += String(decoding: encoded, as: UTF8.self) + "\n"
  }
  try output.write(toFile: outputPath, atomically: true, encoding: .utf8)
  print("已分詞 \(sentenceCount) 篇、\(unknownRunCount) 個疑似缺詞片段 → \(outputPath)")
}

// MARK: - mine

func runMine(_ options: ParsedArguments) throws {
  guard let corpusPath = options.string("corpus"), let indexPath = options.string("index")
  else { throw MinerError.missingArgument("mine 需要 `--corpus` 與 `--index`。") }
  let outputDirectory = URL(fileURLWithPath: options.string("out-dir") ?? "mining-output")
  try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

  let locale = TxtMapUnigramIndex.Locale(rawValue: options.string("locale") ?? "chs") ?? .chs
  let index = try TxtMapUnigramIndex(url: URL(fileURLWithPath: indexPath), locale: locale)
  let segmenter = makeSegmenter(index: index, options: options)

  var miner = CorpusMiner()
  let corpusContent = try String(contentsOfFile: corpusPath, encoding: .utf8)
  for line in corpusContent.components(separatedBy: "\n") where !line.isEmpty {
    guard let data = line.data(using: .utf8),
          let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    else { continue }
    let words: [String] = if let words = object["words"] as? [String] {
      words
    } else if let text = object["text"] as? String {
      segmenter.segment(text).words
    } else {
      []
    }
    guard !words.isEmpty else { continue }
    miner.ingest(words: words)
    miner.ingest(unknownRuns: UnigramSegmenter.unknownRuns(in: words, index: index))
  }

  var miningOptions = CorpusMiner.Options()
  if let value = options.int("min-count") { miningOptions.minCount = value }
  if let value = options.int("min-context-count") { miningOptions.minContextCount = value }
  if let value = options.double("margin") { miningOptions.margin = value }
  if let rawValue = options.string("ambiguous-readings"),
     let policy = CorpusMiner.AmbiguousReadings(rawValue: rawValue) {
    miningOptions.ambiguousReadings = policy
  }

  let result = miner.mine(index: index, options: miningOptions)

  let backlogHeader = "# 由 VanguardLexiconCorpusMiner 產生；行格式：值\t次數\t讀音（空格分隔）\t前驗詞鏈（空格分隔、由舊至新）。\n"
  let backlog = backlogHeader + result.candidates.map { $0.renderedLine() }.joined(separator: "\n") + "\n"
  try backlog.write(to: outputDirectory.appendingPathComponent("backlog.tsv"), atomically: true, encoding: .utf8)

  let unknownRuns = result.unknownRuns.sorted { $0.value > $1.value }
    .map { "\($0.key)\t\($0.value)" }.joined(separator: "\n") + "\n"
  try ("疑似缺詞片段\t出現次數\n" + unknownRuns)
    .write(to: outputDirectory.appendingPathComponent("unknown-runs.tsv"), atomically: true, encoding: .utf8)

  let ambiguous = result.ambiguous
    .map { "\($0.value)\\t\($0.occurrences)\\t" + $0.readings.map { $0.joined(separator: " ") }.joined(separator: " / ") }
    .joined(separator: "\n") + "\n"
  try ("詞值\t出現次數\t各讀音\n" + ambiguous)
    .write(to: outputDirectory.appendingPathComponent("ambiguous.tsv"), atomically: true, encoding: .utf8)

  let stats: [String: Any] = [
    "sentences": miner.sentenceCount,
    "tokens": miner.tokenCount,
    "unigram_types": miner.unigramCounts.count,
    "bigram_types": miner.bigramTypeCount,
    "trigram_types": miner.trigramTypeCount,
    "candidates": result.candidates.count,
    "unknown_runs": result.unknownRuns.count,
    "ambiguous_values": result.ambiguous.count,
    "norm": index.norm,
    "build_timestamp": index.buildTimestamp,
    "index": indexPath,
    "index_sha256": try sha256(of: URL(fileURLWithPath: indexPath)),
    "options": [
      "min_count": miningOptions.minCount,
      "min_context_count": miningOptions.minContextCount,
      "margin": miningOptions.margin,
      "ambiguous_readings": miningOptions.ambiguousReadings.rawValue,
      "locale": String(describing: locale),
    ],
  ]
  let statsData = try JSONSerialization.data(withJSONObject: stats, options: [.prettyPrinted, .sortedKeys])
  try statsData.write(to: outputDirectory.appendingPathComponent("stats.json"))

  print("語料 \(miner.sentenceCount) 句／\(miner.tokenCount) 詞；候選 \(result.candidates.count) 列；疑似缺詞 \(result.unknownRuns.count) 種；多讀音 \(result.ambiguous.count) 詞。")
  print("輸出目錄：\(outputDirectory.path)")
}

// MARK: - 輔助

/// 跨平台結束行程：Windows 沒有 POSIX `exit`，得走 `ExitProcess`。
func terminateProcess(_ code: Int32) -> Never {
  #if canImport(WinSDK)
    ExitProcess(UInt32(bitPattern: code))
  #else
    exit(code)
  #endif
}

func sha256(of url: URL) throws -> String {
  let data = try Data(contentsOf: url)
  return SHA256.hexDigest(data)
}

// MARK: - MinerError

enum MinerError: Error, CustomStringConvertible {
  case missingArgument(String)

  var description: String {
    switch self {
    case let .missingArgument(message): message
    }
  }
}

// MARK: - 用法

func printHelp() {
  print(
    """
    VanguardLexiconCorpusMiner — 以引擎自己的單元圖分詞、挖掘 n-gram 候選。

    用法：
      VanguardLexiconCorpusMiner <子命令> [選項]
      VanguardLexiconCorpusMiner --help

    子命令：
      fetch     由中文維基百科抓取原文，輸出 raw.jsonl（每行 {"text": …}）。
      segment   以 txtMap 之單元圖做 Viterbi 分詞，輸出 corpus.jsonl。
      mine      統計已分詞語料之共現，輸出可貼進 phrases-ngram-*.txt 之候選列。

    fetch 之選項：
      --out <path>            輸出檔（必填），如 raw.jsonl。
      --titles <path>         標題清單，每行一個標題；預設用內建之簡體標題集。
      --pages <n>             最多抓取篇數（預設 40）。
      --variant <zh-cn|…>     MediaWiki 之字體變體（預設 zh-cn）。
      --api <url>             端點（預設 https://zh.wikipedia.org/w/api.php）。

    segment 之選項：
      --in <path>             輸入 raw.jsonl（必填）。
      --out <path>            輸出 corpus.jsonl（必填）。
      --index <path>          .txtMap 路徑（必填）。
      --locale <chs|cht|both> 取用何種語言資料（預設 chs）。
      --max-token-length <n>  分詞時最長試探之詞長（預設 6，最小 1）。
                              詞表最長詞遠長於六字，逐字試探只增開銷；
                              值越小越快，但超過上限的長詞會被切碎。

    mine 之選項：
      --corpus <path>         輸入 corpus.jsonl，或 raw.jsonl（此時就地分詞）（必填）。
      --index <path>          .txtMap 路徑（必填）。
      --out-dir <dir>         輸出目錄（預設 mining-output）。
      --min-count <n>         候選在語料中之最小出現次數（預設 5）。
      --min-context-count <n> 前文詞在語料中之最小出現次數（預設 5）。
      --margin <x>            候選機率須比同詞之單元圖分數高出之餘裕（預設 0.02）。
      --ambiguous-readings <skip|primary|all>
                              多讀音詞條之處置（預設 skip；primary 取機率最高之讀音、
                              all 逐讀音出列）。
      --max-token-length <n>  同 segment；僅在 --corpus 指向 raw.jsonl 時生效。

    mine 之輸出（均在 --out-dir 下）：
      backlog.tsv      值\t次數\t讀音\t前驗詞鏈\t# lift=… corpus=… required=…
                       （required 為「要壓過現行組句所需之最少量」，僅供決策參考）
      unknown-runs.tsv 詞表外之連續單字片段（單字多已列於字表，故此檔常為空）。
      ambiguous.tsv    多讀音詞條及其所有讀音。
      stats.json       語料規模、txtMap 之 _NORM／建置時間／SHA-256、選項快照。

    範例：
      VanguardLexiconCorpusMiner fetch  --out raw.jsonl --pages 200
      VanguardLexiconCorpusMiner segment --in raw.jsonl --out corpus.jsonl \
          --index Build/Release/vanguard-textmap/VanguardFactoryDict4Typing.txtMap
      VanguardLexiconCorpusMiner mine --corpus corpus.jsonl --out-dir out --min-count 50 \
          --index Build/Release/vanguard-textmap/VanguardFactoryDict4Typing.txtMap

    注意：分詞與候選同據一份 txtMap，屬循環論證；候選列仍須以
    VanguardLexiconDebugger 逐條比對後再收。
    """
  )
}
