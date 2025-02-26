// (c) 2021 and onwards The vChewing Project (BSD-3-Clause).
// ====================
// This code is released under the SPDX-License-Identifier: `BSD-3-Clause`.

import Foundation

// MARK: - VCDataBuilder.Collector

extension VCDataBuilder {
  public actor Collector {
    // MARK: Lifecycle

    public init(
      isCHS: Bool? = nil,
      compatibleMode: Bool = false,
      cns: Bool = false
    ) throws {
      var languages: [Bool] = []
      if let isCHS {
        languages.append(isCHS)
      } else {
        languages = [true, false]
      }
      var norms: [Double] = []
      var temporaryNormShared: Double = 0
      var unigrams4NonKanji: [Unigram.Category: [String: Unigram.GramSet]] = [:]
      var reverseLookupTable: [String: Set<String>] = [:]
      var reverseLookupTable4NonKanji: [String: Set<String>] = [:]
      var reverseLookupTable4CNS: [String: Set<String>] = [:]
      var unigramsCHS: [Unigram.Category: [String: Unigram.GramSet]] = [:]
      var unigramsCHT: [Unigram.Category: [String: Unigram.GramSet]] = [:]
      var unigramsKanjiCHS: [Unigram.Category: [String: Unigram.GramSet]] = [:]
      var unigramsKanjiCHT: [Unigram.Category: [String: Unigram.GramSet]] = [:]
      var tableKanjiCNS: [String: Unigram.GramSet] = [:]
      try Unigram.prepareRawUnigramsForNonKanjis(
        unigramTable: &unigrams4NonKanji,
        reverseLookupTable: &reverseLookupTable4NonKanji,
        compatibleMode: compatibleMode
      )
      try Unigram.prepareRawUnweightedUnigramsForCoreKanjis(
        isCHS: isCHS,
        norm: &temporaryNormShared,
        unigramTableCHS: &unigramsKanjiCHS,
        unigramTableCHT: &unigramsKanjiCHT,
        reverseLookupTable: &reverseLookupTable,
        compatibleMode: compatibleMode
      )
      for isCHSLanguage in languages {
        var temporaryNorm: Double = 0
        var unigrams: [Unigram.Category: [String: Unigram.GramSet]] = [:]
        try Unigram.prepareRawUnweightedUnigramsForPhrases(
          isCHS: isCHSLanguage,
          norm: &temporaryNorm,
          unigramTable: &unigrams,
          compatibleMode: compatibleMode
        )
        _ = isCHSLanguage ? { unigramsCHS = unigrams }() : { unigramsCHT = unigrams }()
        norms.append(temporaryNorm)
      }
      // CNS 的內容放在最後處理。
      if cns {
        try Unigram.prepareRawUnweightedUnigramsForCNSKanjis(
          table: &tableKanjiCNS,
          reverseLookupTable: &reverseLookupTable4CNS
        )
      }
      self.unigramsCHS = unigramsCHS
      self.unigramsCHT = unigramsCHT
      self.unigrams4NonKanji = unigrams4NonKanji
      self.reverseLookupTable = reverseLookupTable
      self.reverseLookupTable4NonKanji = reverseLookupTable4NonKanji
      self.reverseLookupTable4CNS = reverseLookupTable4CNS
      self.norm = temporaryNormShared + (norms.max() ?? 0)
      self.unigramsKanjiCHS = unigramsKanjiCHS
      self.unigramsKanjiCHT = unigramsKanjiCHT
      self.tableKanjiCNS = tableKanjiCNS
    }

    // MARK: Public

    public let tableKanjiCNS: [String: Unigram.GramSet]
    public let unigramsKanjiCHS: [Unigram.Category: [String: Unigram.GramSet]]
    public let unigramsKanjiCHT: [Unigram.Category: [String: Unigram.GramSet]]
    public let unigramsCHS: [Unigram.Category: [String: Unigram.GramSet]]
    public let unigramsCHT: [Unigram.Category: [String: Unigram.GramSet]]
    public let unigrams4NonKanji: [Unigram.Category: [String: Unigram.GramSet]]
    public let reverseLookupTable: [String: Set<String>]
    public let reverseLookupTable4NonKanji: [String: Set<String>]
    public let reverseLookupTable4CNS: [String: Set<String>]
    public let norm: Double
    public private(set) var weightPropagated: Bool = false
    public private(set) var exceptedChars: Set<String> = .init()
  }
}

extension VCDataBuilder.Collector {
  func getAllUnigrams(
    isCHS: Bool?,
    omitCNS: Bool = true,
    sorted: Bool = true
  )
    -> [VCDataBuilder.Unigram] {
    var grams = unigrams4NonKanji.values.flatMap {
      $0.values.flatMap { $0.map { $0 } }
    }
    switch isCHS {
    case .none:
      grams += unigramsKanjiCHS.values.flatMap {
        $0.values.flatMap { $0.map { $0 } }
      }
      grams += unigramsKanjiCHT.values.flatMap {
        $0.values.flatMap { $0.map { $0 } }
      }
      grams += unigramsCHS.values.flatMap {
        $0.values.flatMap { $0.map { $0 } }
      }
      grams += unigramsCHT.values.flatMap {
        $0.values.flatMap { $0.map { $0 } }
      }
    case let .some(isCHSVal):
      switch isCHSVal {
      case true:
        grams += unigramsKanjiCHS.values.flatMap {
          $0.values.flatMap { $0.map { $0 } }
        }
        grams += unigramsCHS.values.flatMap {
          $0.values.flatMap { $0.map { $0 } }
        }
      case false:
        grams += unigramsKanjiCHT.values.flatMap {
          $0.values.flatMap { $0.map { $0 } }
        }
        grams += unigramsCHT.values.flatMap {
          $0.values.flatMap { $0.map { $0 } }
        }
      }
    }
    if !omitCNS, !tableKanjiCNS.isEmpty {
      // 不用在此對 CNS 的內容做去重複的處理，因為相關內容會塞到單獨的 SQL 表內。
      grams += tableKanjiCNS.values.flatMap { $0.map { $0 } }
    }
    guard sorted else { return grams }
    return grams.sorted { lhs, rhs -> Bool in
      (lhs.key, rhs.score, lhs.timestamp) < (rhs.key, lhs.score, rhs.timestamp)
    }
  }

  public func propagateWeights() async {
    await withTaskGroup(of: Void.self) { group in
      group.addTask { [self] in
        unigramsCHS.propagateWeights(norm: norm)
      }
      group.addTask { [self] in
        unigramsCHT.propagateWeights(norm: norm)
      }
      group.addTask { [self] in
        unigrams4NonKanji.propagateWeights(norm: norm)
      }
      await group.waitForAll()
    }
  }
}

extension [VCDataBuilder.Unigram.Category: [String: VCDataBuilder.Unigram.GramSet]] {
  public func propagateWeights(norm: Double) {
    values.forEach { subMap in
      subMap.values.forEach { unigramSet in
        unigramSet.forEach { unigram in
          unigram.weighten(norm: norm)
        }
      }
    }
  }
}

// MARK: - Extending Unigram APIs.

extension VCDataBuilder.Unigram.Category {
  func regex4FileNameMatching4Phrases(isCHS: Bool) -> String? {
    let suffix = isCHS ? "chs" : "cht"
    return switch self {
    case .macv: "phrases-vchewing-\(suffix)"
    case .tabe: "phrases-tabe-\(suffix)"
    case .moe: "phrases-moe-\(suffix)"
    case .custom: #"phrases-custom-.*?"# + "\(suffix)"
    default: nil
    }
  }

  func urlsOfPhraseAssets(isCHS: Bool) throws -> [URL] {
    guard let regexStr = regex4FileNameMatching4Phrases(isCHS: isCHS) else { return [] }
    return try Bundle.module
      .findFiles(matching: regexStr, extension: "txt")
      .sorted {
        $0.absoluteString < $1.absoluteString
      }
  }
}

extension VCDataBuilder.Unigram {
  /// 準備用於預處理的 Regex。
  /// - Parameter compatibleMode: 低版本萬國碼相容模式。
  /// - Returns: Regex 陣列。
  static func preparedRegexPatterns(compatibleMode: Bool) -> [(
    NSRegularExpression,
    String
  )] {
    // 正規表達式
    var patterns: [(String, String)] = [
      // CJKWhiteSpace (\x{3000}) to ASCII Space
      // NonBreakWhiteSpace (\x{A0}) to ASCII Space
      // Tab to ASCII Space
      // 統整連續空格為一個 ASCII 空格
      (#"( +|　+| +|\t+)+"#, " "),
      // 去除行尾行首空格
      (#"(^ | $)"#, ""),
      // CR & Form Feed to LF, 且去除重複行
      (#"(\f+|\r+|\n+)+"#, "\n"),
    ]

    if compatibleMode {
      // 以#開頭的行都淨空+去掉所有 macOS 特有的行
      patterns.append((#"^(#.*|.*?\s+#MACOS.*)$"#, ""))
      // 去除 WIN32 標記
      patterns.append((#" #WIN32"#, ""))
    } else {
      // 以#開頭的行都淨空+去掉所有 WIN32 特有的行
      patterns.append((#"^(#.*|.*?\s+#WIN32.*)$"#, ""))
      // 去除 macOS 標記
      patterns.append((#" #MACOS"#, ""))
    }

    let options: NSRegularExpression.Options = [.caseInsensitive, .anchorsMatchLines]

    return patterns.compactMap {
      let regex = try? NSRegularExpression(pattern: $0.0, options: options)
      guard let regex else { return nil }
      return (regex, $0.1)
    }
  }

  static func prepareRawUnigramsForNonKanjis(
    unigramTable: inout [Category: [String: GramSet]],
    reverseLookupTable: inout [String: Set<String>],
    compatibleMode: Bool = false
  ) throws {
    var strRAW = ""
    // 讀取內容
    do {
      let regexStrings = ["char-misc-bpmf", "char-misc-nonkanji"]
      try regexStrings.forEach { regexStr in
        let fileURL = try Bundle.module.findFiles(matching: regexStr, extension: "txt").first
        guard let fileURL else {
          assertionFailure(" - Exception happened when getting raw core kanji data \(regexStr).")
          return
        }
        strRAW += try String(contentsOf: fileURL, encoding: .utf8)
      }
    } catch {
      NSLog(" - Exception happened when reading raw core kanji data.")
      throw error
    }
    // 批次處理所有正規表達式
    for (regex, replacement) in Self.preparedRegexPatterns(compatibleMode: compatibleMode) {
      strRAW = regex.stringByReplacingMatches(
        in: strRAW,
        options: [],
        range: NSRange(location: 0, length: strRAW.utf16.count),
        withTemplate: replacement
      )
    }
    // 正式整理格式：
    var handledHashes = Set<Int>()
    strRAW.components(separatedBy: .newlines).forEach { lineData in
      guard !handledHashes.contains(lineData.hashValue) else { return }
      handledHashes.insert(lineData.hashValue)
      guard !lineData.isEmpty else { return }
      // 先完成某兩步需要分行處理才能完成的格式整理。
      let arrCells = lineData.components(separatedBy: " ").prefix(3)
      guard arrCells.count == 3 else { return }
      let phone = arrCells[2].description
      let phrase = arrCells[0].description
      let occurrence = Int(arrCells[1]) ?? 0
      // 廢掉空數據；之後無須再這樣處理。
      guard phrase.count * phone.count != 0 else { return }
      // 開始插入資料值。
      reverseLookupTable[phrase, default: []].insert(phone) // RevLookup
      let newUnigram = Self(
        key: phone, value: phrase, score: 0.0,
        count: occurrence, category: .misc
      )
      unigramTable[.misc, default: [:]][phone, default: []].insert(newUnigram)
    }
    NSLog(" - 通用: 成功生成非漢字語料辭典（權重待計算）。")
  }

  static func prepareRawUnweightedUnigramsForPhrases(
    isCHS: Bool,
    norm: inout Double,
    unigramTable: inout [Category: [String: GramSet]],
    compatibleMode: Bool = false
  ) throws {
    let i18n: String = isCHS ? "簡體中文" : "繁體中文"

    // 讀取內容
    do {
      struct ReadingWordPair: Hashable, Sendable, Codable {
        let phrase: String
        let phone: String
      }

      var norms: [Double] = []

      try Category.allCases.forEach { type in
        let urls = try type.urlsOfPhraseAssets(isCHS: isCHS)
        var currentNorm = 0.0
        // 用 Set 來儲存已處理的行，確保不會重複
        var processedPairs = Set<ReadingWordPair>()

        try urls.forEach { fileURL in
          var strRAW = try String(contentsOf: fileURL, encoding: .utf8)
          // 批次處理所有正規表達式
          for (regex, replacement) in Self.preparedRegexPatterns(compatibleMode: compatibleMode) {
            strRAW = regex.stringByReplacingMatches(
              in: strRAW,
              options: [],
              range: NSRange(location: 0, length: strRAW.utf16.count),
              withTemplate: replacement
            )
          }

          var handledHashes = Set<Int>()
          strRAW.components(separatedBy: .newlines).forEach { lineData in
            guard !handledHashes.contains(lineData.hashValue) else { return }
            handledHashes.insert(lineData.hashValue)
            guard !lineData.isEmpty else { return }
            let components = lineData.components(separatedBy: " ")
            guard components.count >= 3 else { return }

            let phrase = components[0].description
            guard let occurrence = Int(components[1]) else { return }
            let phone = components[2...].joined(separator: "-")

            guard !phrase.isEmpty, !phone.isEmpty else { return }

            // 使用 UnigramKey 進行去重檢查
            let key = ReadingWordPair(phrase: phrase, phone: phone)
            guard !processedPairs.contains(key) else { return }
            processedPairs.insert(key)

            // 確保在目標類別中不存在相同的組合
            if let existingSet = unigramTable[type]?[phone] {
              guard !existingSet.contains(where: {
                $0.value == phrase && $0.key == phone
              }) else { return }
            }

            // 建立 Unigram
            let newUnigram = Self(
              key: phone,
              value: phrase,
              score: 0.0,
              count: occurrence,
              category: type
            )

            unigramTable[type, default: [:]][phone, default: []].insert(newUnigram)
            if type != .custom {
              currentNorm += newUnigram.normDelta ?? 0
            }
          }
        }
        norms.append(currentNorm)
      }
      norm += norms.max() ?? 0
    } catch {
      NSLog(" - Exception happened when reading raw phrases data.")
      throw error
    }

    NSLog(" - \(i18n): 成功生成詞語語料辭典（權重待計算）。")
  }

  static func prepareRawUnweightedUnigramsForCoreKanjis(
    isCHS isCHSLanguage: Bool?,
    norm: inout Double,
    unigramTableCHS: inout [Category: [String: GramSet]],
    unigramTableCHT: inout [Category: [String: GramSet]],
    reverseLookupTable: inout [String: Set<String>],
    compatibleMode: Bool = false
  ) throws {
    var strRAW = ""
    // 讀取內容
    do {
      let regexStr = "char-kanji-core"
      let fileURL = try Bundle.module.findFiles(matching: regexStr, extension: "txt").first
      guard let fileURL else {
        assertionFailure(" - Exception happened when getting raw core kanji data \(regexStr).")
        return
      }
      strRAW += try String(contentsOf: fileURL, encoding: .utf8)
    } catch {
      NSLog(" - Exception happened when reading raw core kanji data.")
      throw error
    }
    let i18n: String = {
      if let isCHSLanguage {
        return isCHSLanguage ? "簡體中文" : "繁體中文"
      }
      return "通用"
    }()
    // 批次處理所有正規表達式
    for (regex, replacement) in Self.preparedRegexPatterns(compatibleMode: compatibleMode) {
      strRAW = regex.stringByReplacingMatches(
        in: strRAW,
        options: [],
        range: NSRange(location: 0, length: strRAW.utf16.count),
        withTemplate: replacement
      )
    }
    // 正式整理格式，現在就開始去重複：
    var languages: [Bool] = []
    if let isCHSLanguage {
      languages.append(isCHSLanguage)
    } else {
      languages = [true, false]
    }
    var normCHS: Double = 0
    var normCHT: Double = 0
    var handledHashes = Set<Int>()
    strRAW.components(separatedBy: .newlines).forEach { lineData in
      guard !handledHashes.contains(lineData.hashValue) else { return }
      handledHashes.insert(lineData.hashValue)
      guard !lineData.isEmpty else { return }
      // 簡體中文的話，提取 1,2,4 號單元格；繁體中文的話，提取 1,3,4 號單元格。
      let arrCells = lineData.components(separatedBy: " ")
      guard arrCells.count >= 4 else { return }
      let phone = arrCells[3].description
      let phrase = arrCells[0].description
      // 廢掉空數據；之後無須再這樣處理。
      guard phrase.count * phone.count != 0 else { return }
      languages.forEach { isCHS in
        // 開始插入資料值。
        reverseLookupTable[phrase, default: []].insert(phone) // RevLookup
        let newUnigram = Self(
          key: phone,
          value: phrase,
          score: 0.0,
          count: Int(arrCells[isCHS ? 1 : 2]) ?? 0,
          category: .kanji
        )
        switch isCHS {
        case false:
          unigramTableCHT[.kanji, default: [:]][phone, default: []].insert(newUnigram)
          normCHT += newUnigram.normDelta ?? 0
        case true:
          unigramTableCHS[.kanji, default: [:]][phone, default: []].insert(newUnigram)
          normCHS += newUnigram.normDelta ?? 0
        }
      }
    }
    norm += [normCHS, normCHT].max() ?? 0
    NSLog(" - \(i18n): 成功生成單字語料辭典（權重待計算）。")
  }

  static func prepareRawUnweightedUnigramsForCNSKanjis(
    table: inout [String: VCDataBuilder.Unigram.GramSet],
    reverseLookupTable: inout [String: Set<String>]
  ) throws {
    var strRAW = ""
    // 讀取內容
    do {
      let regexStr = "char-kanji-cns"
      let fileURL = try Bundle.module.findFiles(matching: regexStr, extension: "txt").first
      guard let fileURL else {
        assertionFailure(" - Exception happened when getting cns data \(regexStr).")
        return
      }
      strRAW += try String(contentsOf: fileURL, encoding: .utf8)
    } catch {
      NSLog(" - Exception happened when reading cns data.")
      throw error
    }
    let i18n = "通用"
    // 批次處理所有正規表達式（為了資料保真度，此處不使用相容模式）。
    for (regex, replacement) in Self.preparedRegexPatterns(compatibleMode: false) {
      strRAW = regex.stringByReplacingMatches(
        in: strRAW,
        options: [],
        range: NSRange(location: 0, length: strRAW.utf16.count),
        withTemplate: replacement
      )
    }
    // 正式整理格式，現在就開始去重複：
    var handledHashes = Set<Int>()
    strRAW.components(separatedBy: .newlines).forEach { lineData in
      guard !handledHashes.contains(lineData.hashValue) else { return }
      handledHashes.insert(lineData.hashValue)
      guard !lineData.isEmpty else { return }
      // CNS 僅有兩個 Cell。
      let arrCells = lineData.components(separatedBy: " ").prefix(2)
      guard arrCells.count == 2 else { return }
      let phone = arrCells[1].description
      let phrase = arrCells[0].description
      // 廢掉空數據；之後無須再這樣處理。
      guard phrase.count * phone.count != 0 else { return }
      // 開始插入資料值。
      reverseLookupTable[phrase, default: []].insert(phone) // RevLookup
      let newUnigram = Self(
        key: phone,
        value: phrase,
        score: -11,
        count: 0,
        category: .cns
      )
      table[phone, default: []].insert(newUnigram)
    }
    NSLog(" - \(i18n): 成功生成全字庫語料辭典（權重待計算）。")
  }
}

extension VCDataBuilder.Collector {
  func getZhuyinwen() -> [VCDataBuilder.Unigram] {
    do {
      // Punctuations.
      let fileNameStem = "data-zhuyinwen"
      let fileURL = Bundle.module.url(forResource: fileNameStem, withExtension: "txt")
      guard let fileURL else { return [] }
      let dataStr = try String(contentsOf: fileURL, encoding: .utf8)
      var newUnigrams = [VCDataBuilder.Unigram]()
      dataStr.enumerateLines { currentLine, _ in
        let dataCells = currentLine.split(separator: " ")
        guard dataCells.count == 3 else { return }
        newUnigrams.append(
          .init(
            key: dataCells[1].description,
            value: dataCells[0].description,
            score: -1, // 注音文權重是 -1
            count: 0,
            category: .misc
          )
        )
      }
      return newUnigrams
    } catch {
      return []
    }
  }

  func getSymbols() -> [VCDataBuilder.Unigram] {
    do {
      // Punctuations.
      let fileNameStem = "data-symbols"
      let fileURL = Bundle.module.url(forResource: fileNameStem, withExtension: "txt")
      guard let fileURL else { return [] }
      let dataStr = try String(contentsOf: fileURL, encoding: .utf8)
      var newUnigrams = [VCDataBuilder.Unigram]()
      dataStr.enumerateLines { currentLine, _ in
        let dataCells = currentLine.split(separator: " ")
        guard dataCells.count == 2 else { return }
        newUnigrams.append(
          .init(
            key: dataCells[1].description,
            value: dataCells[0].description,
            score: -13, // 繪文字權重是 -13
            count: 0,
            category: .misc
          )
        )
      }
      return newUnigrams
    } catch {
      return []
    }
  }

  func getPunctuations() -> [VCDataBuilder.Unigram] {
    do {
      // Punctuations.
      let fileNameStem = "data-punctuations"
      let fileURL = Bundle.module.url(forResource: fileNameStem, withExtension: "txt")
      guard let fileURL else { return [] }
      let dataStr = try String(contentsOf: fileURL, encoding: .utf8)
      var newUnigrams = [VCDataBuilder.Unigram]()
      dataStr.enumerateLines { currentLine, _ in
        let dataCells = currentLine.split(separator: " ")
        guard dataCells.count == 3, dataCells.first?.first == "_" else { return }
        newUnigrams.append(
          .init(
            key: dataCells[0].description,
            value: dataCells[1].description,
            score: 0, // 標點權重是 0
            count: 0,
            category: .misc
          )
        )
      }
      return newUnigrams
    } catch {
      return []
    }
  }
}
