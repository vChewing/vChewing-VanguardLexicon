// (c) 2021 and onwards The vChewing Project (BSD-3-Clause).
// ====================
// This code is released under the SPDX-License-Identifier: `BSD-3-Clause`.

import Foundation

extension VCDataBuilder.Collector {
  private static let lineSeparator4HealthCheck: String = {
    var result = ""
    for _ in 0 ..< 72 { result += "-" }
    return result
  }()

  /// 健檢函式。
  func healthCheckPerMode(isCHS: Bool) throws -> [String] {
    let i18nTag = isCHS ? "簡體中文" : "繁體中文"
    NSLog(" - \(i18nTag): 開始籌集資料、準備執行健康度測試。")
    let data = getAllUnigrams(isCHS: isCHS)
    NSLog(" - \(i18nTag): 開始執行健康度測試。")
    var result = [String]()
    var unigramMonoCharPromotedMap = [String: VCDataBuilder.Unigram]()
    var valueToScore = [String: Double]()
    var unigramMonoChars = [VCDataBuilder.Unigram]()
    var unigramPolyChars = [VCDataBuilder.Unigram]()
    data.forEach { neta in
      // 核心字詞庫的內容頻率一般大於 -10，但也得考慮某些包含假名的合成詞。
      guard neta.score > -14 else { return }
      valueToScore[neta.value] = max(neta.score, valueToScore[neta.value] ?? -14)
      let phoneCells = neta.keyCells
      guard let firstPhone = phoneCells.first else { return }
      switch neta.spanLength {
      case ...0: return
      case 1:
        unigramMonoChars.append(neta)
        if let theRecord = unigramMonoCharPromotedMap[firstPhone] {
          if neta.score > theRecord.score {
            unigramMonoCharPromotedMap[firstPhone] = neta
          }
        } else {
          unigramMonoCharPromotedMap[firstPhone] = neta
        }
      default: unigramPolyChars.append(neta)
      }
    }
    let unigramMonoCharCounter = unigramMonoChars.count
    let unigramPolyCharCounter = unigramPolyChars.count

    var faulty = [[String]: [VCDataBuilder.Unigram]]()
    var indifferents: [(String, String, Double, [VCDataBuilder.Unigram], Double)] = []
    var insufficients: [(String, String, Double, [VCDataBuilder.Unigram], Double)] = []
    var competingUnigrams = [(String, Double, String, Double)]()

    for neta in unigramPolyChars {
      var competants = [VCDataBuilder.Unigram]()
      var tscore: Double = 0
      var bad = false
      let checkPerCharMachingStatus: Bool = neta.spanLength == neta.value.count

      var mispronouncedKanji: [String] = []

      let arrNetaKeys = neta.key.split(separator: "-")
      outerMatchCheck: for (i, x) in arrNetaKeys.enumerated() {
        if !unigramMonoCharPromotedMap.keys.contains(String(x)) {
          if neta.value.count == 1 {
            mispronouncedKanji.append("\(neta.type)@\(neta.value)@\(neta.key)")
          } else if neta.value.count == arrNetaKeys.count {
            mispronouncedKanji
              .append("\(neta.type)@\(neta.value.map(\.description)[i])@\(arrNetaKeys[i])")
          } else {
            mispronouncedKanji.append("\(neta.type)@OTHER@\(String(x))")
          }
          bad = true
          break outerMatchCheck
        }
        innerMatchCheck: if checkPerCharMachingStatus {
          let char = neta.value.map(\.description)[i]
          if exceptedChars.contains(char) { break innerMatchCheck }
          guard let queriedPhones = reverseLookupTable[char] ?? reverseLookupTable4NonKanji[char]
          else {
            mispronouncedKanji.append("\(neta.type)@\(char)@\(String(x))")
            bad = true
            break outerMatchCheck
          }
          for queriedPhone in queriedPhones {
            if queriedPhone == x.description { break innerMatchCheck }
          }
          mispronouncedKanji.append("\(neta.type)@\(char)@\(String(x))")
          bad = true
          break outerMatchCheck
        }
        guard let u = unigramMonoCharPromotedMap[String(x)] else { continue }
        tscore += u.score
        competants.append(u)
      }

      if bad {
        faulty[mispronouncedKanji, default: []].append(neta)
        continue
      }
      if tscore >= neta.score {
        let instance = (neta.key, neta.value, neta.score, competants, neta.score - tscore)
        let valueJoined = String(competants.map(\.value).joined())
        if neta.value == valueJoined {
          indifferents.append(instance)
        } else {
          if valueToScore.keys.contains(valueJoined), neta.value != valueJoined {
            if let valueJoinedScore = valueToScore[valueJoined], neta.score < valueJoinedScore {
              competingUnigrams.append((neta.value, neta.score, valueJoined, valueJoinedScore))
            }
          }
          insufficients.append(instance)
        }
      }
    }

    func printl(_ input: String) {
      result.append(input)
    }

    insufficients = insufficients.sorted(by: { lhs, rhs -> Bool in
      (lhs.2) > (rhs.2)
    })
    competingUnigrams = competingUnigrams.sorted(by: { lhs, rhs -> Bool in
      (lhs.1 - lhs.3) > (rhs.1 - rhs.3)
    })

    printl(Self.lineSeparator4HealthCheck)
    printl("持單個字符的有效單元圖數量：\(unigramMonoCharCounter)")
    printl("持多個字符的有效單元圖數量：\(unigramPolyCharCounter)")
    printl(Self.lineSeparator4HealthCheck)
    let countPercentage = Double(insufficients.count) / Double(unigramPolyCharCounter) * 100.0

    var insufficientsMap = [Int: [(String, String, Double, [VCDataBuilder.Unigram], Double)]]()
    var countedInsufficientsMap = [Int: Int]()
    var insufficientsCounter = 0

    (2 ... 10).forEach { currentSpanLength in
      let foundInsufficientsOfThisSpanLength = insufficients
        .filter { $0.0.split(separator: "-").count == currentSpanLength }
      let countedInsufficientsAmountForThisSpanLength = foundInsufficientsOfThisSpanLength.count
      countedInsufficientsMap[currentSpanLength] = countedInsufficientsAmountForThisSpanLength
      insufficientsCounter += countedInsufficientsAmountForThisSpanLength
      insufficientsMap[currentSpanLength] = foundInsufficientsOfThisSpanLength
    }

    if insufficientsCounter <= 0, indifferents.isEmpty {
      printl("尚未發現有複字單元圖被自身成分讀音對應的其它單字單元圖奪權的問題。")
    } else {
      printl("總結一下那些容易被單個漢字的字頻干擾輸入的詞組單元圖：")
      printl("因干擾組件和字詞本身完全重疊、而不需要處理的單元圖的數量：\(indifferents.count)")
      printl(
        "有 \(insufficients.count) 個複字單元圖被自身成分讀音對應的其它單字單元圖奪權，約佔全部有效單元圖的 \(countPercentage.rounded(toPlaces: 3))%，"
      )
      printl("\n其中有：")
      countedInsufficientsMap.sorted(by: { $0.key < $1.key }).forEach { keyValue in
        printl("  \(keyValue.value) 個有效 \(keyValue.key) 字單元圖")
      }
    }

    (2 ... 10).forEach { currentSpanLength in
      let insufficientsOfThisSpanLength = insufficientsMap[currentSpanLength]
      if let insufficientsOfThisSpanLength, !insufficientsOfThisSpanLength.isEmpty {
        printl(Self.lineSeparator4HealthCheck)
        printl("前二十五個被奪權的有效 \(currentSpanLength) 字單元圖")
        for content in insufficientsOfThisSpanLength.prefix(25) {
          var contentToPrint = "{"
          contentToPrint += "\(content.0),\(content.1),\(content.2),"
          contentToPrint += "[" + content.3.map(\.description).joined(separator: ",") + "]" + ","
          contentToPrint += String(content.4) + "}"
          printl(contentToPrint)
        }
      }
    }

    if !competingUnigrams.isEmpty {
      printl(Self.lineSeparator4HealthCheck)
      printl("也發現有 \(competingUnigrams.count) 個複字單元圖被某些由高頻單字組成的複字單元圖奪權的情況，")
      printl("例如（前二十五例）：")
      for content in competingUnigrams.prefix(25) {
        let contentToPrint = "{\(content.0),\(content.1),\(content.2),\(content.3)}"
        printl(contentToPrint)
      }
    }

    guard faulty.isEmpty else {
      printl(Self.lineSeparator4HealthCheck)
      printl("健檢測試失敗：")
      printl("下述單元圖用到了漢字核心表當中尚未收錄的讀音，可能無法正常輸入：")
      for content in faulty {
        printl("\(content.key): \(content.value)")
      }
      throw VCDataBuilder.Exception.healthCheckException(result)
    }

    return result
  }
}
