// (c) 2021 and onwards The vChewing Project (BSD-3-Clause).
// ====================
// This code is released under the SPDX-License-Identifier: `BSD-3-Clause`.

import Foundation

extension VCDataBuilder.Collector {
  func healthCheck(isCHS: Bool) -> String {
    NSLog("開始籌集資料、準備執行健康度測試。")
    let data = getAllUnigrams(isCHS: isCHS)
    NSLog("開始執行健康度測試。")
    var result = ""
    var unigramMonoChar = [String: VCDataBuilder.Unigram]()
    var valueToScore = [String: Double]()
    let unigramMonoCharCounter = data
      .filter { $0.score > -14 && $0.key.split(separator: "-").count == 1 }.count
    let unigramPolyCharCounter = data
      .filter { $0.score > -14 && $0.key.split(separator: "-").count > 1 }.count

    // 核心字詞庫的內容頻率一般大於 -10，但也得考慮某些包含假名的合成詞。
    for neta in data.filter({ $0.score > -14 }) {
      valueToScore[neta.value] = max(neta.score, valueToScore[neta.value] ?? -14)
      let theKeySliceArr = neta.key.split(separator: "-")
      guard let theKey = theKeySliceArr.first, theKeySliceArr.count == 1 else { continue }
      if unigramMonoChar.keys.contains(String(theKey)),
         let theRecord = unigramMonoChar[String(theKey)] {
        if neta.score > theRecord.score { unigramMonoChar[String(theKey)] = neta }
      } else {
        unigramMonoChar[String(theKey)] = neta
      }
    }

    var faulty = [[String]: [VCDataBuilder.Unigram]]()
    var indifferents: [(String, String, Double, [VCDataBuilder.Unigram], Double)] = []
    var insufficients: [(String, String, Double, [VCDataBuilder.Unigram], Double)] = []
    var competingUnigrams = [(String, Double, String, Double)]()

    for neta in data.filter({ $0.key.split(separator: "-").count >= 2 && $0.score > -14 }) {
      var competants = [VCDataBuilder.Unigram]()
      var tscore: Double = 0
      var bad = false
      let checkPerCharMachingStatus: Bool = neta.key.split(separator: "-").count == neta.value.count

      var mispronouncedKanji: [String] = []

      let arrNetaKeys = neta.key.split(separator: "-")
      outerMatchCheck: for (i, x) in arrNetaKeys.enumerated() {
        if !unigramMonoChar.keys.contains(String(x)) {
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
        guard let u = unigramMonoChar[String(x)] else { continue }
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

    insufficients = insufficients.sorted(by: { lhs, rhs -> Bool in
      (lhs.2) > (rhs.2)
    })
    competingUnigrams = competingUnigrams.sorted(by: { lhs, rhs -> Bool in
      (lhs.1 - lhs.3) > (rhs.1 - rhs.3)
    })

    let separator: String = {
      var result = ""
      for _ in 0 ..< 72 { result += "-" }
      return result
    }()

    func printl(_ input: String) {
      result += input + "\n"
    }

    printl(separator)
    printl("持單個字符的有效單元圖數量：\(unigramMonoCharCounter)")
    printl("持多個字符的有效單元圖數量：\(unigramPolyCharCounter)")

    printl(separator)
    printl("總結一下那些容易被單個漢字的字頻干擾輸入的詞組單元圖：")
    printl("因干擾組件和字詞本身完全重疊、而不需要處理的單元圖的數量：\(indifferents.count)")
    let countPercentage = Double(insufficients.count) / Double(unigramPolyCharCounter) * 100.0
    printl(
      "有 \(insufficients.count) 個複字單元圖被自身成分讀音對應的其它單字單元圖奪權，約佔全部有效單元圖的 \(countPercentage.rounded(toPlaces: 3))%，"
    )
    printl("\n其中有：")

    var insufficientsMap = [Int: [(String, String, Double, [VCDataBuilder.Unigram], Double)]]()
    for x in 2 ... 10 {
      insufficientsMap[x] = insufficients.filter { $0.0.split(separator: "-").count == x }
    }

    printl("  \(insufficientsMap[2]?.count ?? 0) 個有效雙字單元圖")
    printl("  \(insufficientsMap[3]?.count ?? 0) 個有效三字單元圖")
    printl("  \(insufficientsMap[4]?.count ?? 0) 個有效四字單元圖")
    printl("  \(insufficientsMap[5]?.count ?? 0) 個有效五字單元圖")
    printl("  \(insufficientsMap[6]?.count ?? 0) 個有效六字單元圖")
    printl("  \(insufficientsMap[7]?.count ?? 0) 個有效七字單元圖")
    printl("  \(insufficientsMap[8]?.count ?? 0) 個有效八字單元圖")
    printl("  \(insufficientsMap[9]?.count ?? 0) 個有效九字單元圖")
    printl("  \(insufficientsMap[10]?.count ?? 0) 個有效十字單元圖")

    if let insufficientsMap2 = insufficientsMap[2], !insufficientsMap2.isEmpty {
      printl(separator)
      printl("前二十五個被奪權的有效雙字單元圖")
      for (i, content) in insufficientsMap2.enumerated() {
        if i == 25 { break }
        var contentToPrint = "{"
        contentToPrint += content.0 + ","
        contentToPrint += content.1 + ","
        contentToPrint += String(content.2) + ","
        contentToPrint += "[" + content.3.map(\.description).joined(separator: ",") + "]" + ","
        contentToPrint += String(content.4) + "}"
        printl(contentToPrint)
      }
    }

    if let insufficientsMap3 = insufficientsMap[3], !insufficientsMap3.isEmpty {
      printl(separator)
      printl("前二十五個被奪權的有效三字單元圖")
      for (i, content) in insufficientsMap3.enumerated() {
        if i == 25 { break }
        var contentToPrint = "{"
        contentToPrint += content.0 + ","
        contentToPrint += content.1 + ","
        contentToPrint += String(content.2) + ","
        contentToPrint += "[" + content.3.map(\.description).joined(separator: ",") + "]" + ","
        contentToPrint += String(content.4) + "}"
        printl(contentToPrint)
      }
    }

    if let insufficientsMap4 = insufficientsMap[4], !insufficientsMap4.isEmpty {
      printl(separator)
      printl("前二十五個被奪權的有效四字單元圖")
      for (i, content) in insufficientsMap4.enumerated() {
        if i == 25 { break }
        var contentToPrint = "{"
        contentToPrint += content.0 + ","
        contentToPrint += content.1 + ","
        contentToPrint += String(content.2) + ","
        contentToPrint += "[" + content.3.map(\.description).joined(separator: ",") + "]" + ","
        contentToPrint += String(content.4) + "}"
        printl(contentToPrint)
      }
    }

    if let insufficientsMap5 = insufficientsMap[5], !insufficientsMap5.isEmpty {
      printl(separator)
      printl("前二十五個被奪權的有效五字單元圖")
      for (i, content) in insufficientsMap5.enumerated() {
        if i == 25 { break }
        var contentToPrint = "{"
        contentToPrint += content.0 + ","
        contentToPrint += content.1 + ","
        contentToPrint += String(content.2) + ","
        contentToPrint += "[" + content.3.map(\.description).joined(separator: ",") + "]" + ","
        contentToPrint += String(content.4) + "}"
        printl(contentToPrint)
      }
    }

    if let insufficientsMap6 = insufficientsMap[6], !insufficientsMap6.isEmpty {
      printl(separator)
      printl("前二十五個被奪權的有效六字單元圖")
      for (i, content) in insufficientsMap6.enumerated() {
        if i == 25 { break }
        var contentToPrint = "{"
        contentToPrint += content.0 + ","
        contentToPrint += content.1 + ","
        contentToPrint += String(content.2) + ","
        contentToPrint += "[" + content.3.map(\.description).joined(separator: ",") + "]" + ","
        contentToPrint += String(content.4) + "}"
        printl(contentToPrint)
      }
    }

    if let insufficientsMap7 = insufficientsMap[7], !insufficientsMap7.isEmpty {
      printl(separator)
      printl("前二十五個被奪權的有效七字單元圖")
      for (i, content) in insufficientsMap7.enumerated() {
        if i == 25 { break }
        var contentToPrint = "{"
        contentToPrint += content.0 + ","
        contentToPrint += content.1 + ","
        contentToPrint += String(content.2) + ","
        contentToPrint += "[" + content.3.map(\.description).joined(separator: ",") + "]" + ","
        contentToPrint += String(content.4) + "}"
        printl(contentToPrint)
      }
    }

    if let insufficientsMap8 = insufficientsMap[8], !insufficientsMap8.isEmpty {
      printl(separator)
      printl("前二十五個被奪權的有效八字單元圖")
      for (i, content) in insufficientsMap8.enumerated() {
        if i == 25 { break }
        var contentToPrint = "{"
        contentToPrint += content.0 + ","
        contentToPrint += content.1 + ","
        contentToPrint += String(content.2) + ","
        contentToPrint += "[" + content.3.map(\.description).joined(separator: ",") + "]" + ","
        contentToPrint += String(content.4) + "}"
        printl(contentToPrint)
      }
    }

    if let insufficientsMap9 = insufficientsMap[9], !insufficientsMap9.isEmpty {
      printl(separator)
      printl("前二十五個被奪權的有效九字單元圖")
      for (i, content) in insufficientsMap9.enumerated() {
        if i == 25 { break }
        var contentToPrint = "{"
        contentToPrint += content.0 + ","
        contentToPrint += content.1 + ","
        contentToPrint += String(content.2) + ","
        contentToPrint += "[" + content.3.map(\.description).joined(separator: ",") + "]" + ","
        contentToPrint += String(content.4) + "}"
        printl(contentToPrint)
      }
    }

    if let insufficientsMap10 = insufficientsMap[10], !insufficientsMap10.isEmpty {
      printl(separator)
      printl("前二十五個被奪權的有效十字單元圖")
      for (i, content) in insufficientsMap10.enumerated() {
        if i == 25 { break }
        var contentToPrint = "{"
        contentToPrint += content.0 + ","
        contentToPrint += content.1 + ","
        contentToPrint += String(content.2) + ","
        contentToPrint += "[" + content.3.map(\.description).joined(separator: ",") + "]" + ","
        contentToPrint += String(content.4) + "}"
        printl(contentToPrint)
      }
    }

    if !competingUnigrams.isEmpty {
      printl(separator)
      printl("也發現有 \(competingUnigrams.count) 個複字單元圖被某些由高頻單字組成的複字單元圖奪權的情況，")
      printl("例如（前二十五例）：")
      for (i, content) in competingUnigrams.enumerated() {
        if i == 25 { break }
        var contentToPrint = "{"
        contentToPrint += content.0 + ","
        contentToPrint += String(content.1) + ","
        contentToPrint += content.2 + ","
        contentToPrint += String(content.3) + "}"
        printl(contentToPrint)
      }
    }

    if !faulty.isEmpty {
      printl(separator)
      printl("下述單元圖用到了漢字核心表當中尚未收錄的讀音，可能無法正常輸入：")
      for content in faulty {
        printl("\(content.key): \(content.value)")
      }
    }

    result += "\n"
    return result
  }
}
