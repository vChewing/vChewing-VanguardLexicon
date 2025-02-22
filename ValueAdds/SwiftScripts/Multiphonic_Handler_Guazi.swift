#!/usr/bin/env swift

// RUN THE GLOBAL DEDUPLICATOR MANUALLY FIRST!!!!

import Foundation

extension String {
  // by 瓜子
  mutating func replacingMatches(of target: String, with replacement: String, keyword: String)
    throws {
    let pattern = "(?<=\(keyword).{0,100})\(target)"
    // 考虑到每一行可能会重复出现需要批配的词的情况，所以先重复三遍。会误伤到同音异字的读音，
    self = try NSRegularExpression(pattern: pattern, options: .caseInsensitive)
      .stringByReplacingMatches(
        in: self, range: .init(startIndex ..< endIndex, in: self),
        withTemplate: replacement
      )
    self = try NSRegularExpression(pattern: pattern, options: .caseInsensitive)
      .stringByReplacingMatches(
        in: self, range: .init(startIndex ..< endIndex, in: self),
        withTemplate: replacement
      )
    self = try NSRegularExpression(pattern: pattern, options: .caseInsensitive)
      .stringByReplacingMatches(
        in: self, range: .init(startIndex ..< endIndex, in: self),
        withTemplate: replacement
      )
  }
}

func getDocumentsDirectory() -> URL {
  let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
  return paths[0]
}

// MARK: - 定義檔案路徑

let urlCHS = "./ToProcess-CHS.txt"
let urlCHT = "./ToProcess-CHT.txt"

// MARK: - 檔案載入

var strClusterCHS = ""
var strClusterCHT = ""

do {
  strClusterCHS = try String(contentsOfFile: urlCHS, encoding: .utf8)
  strClusterCHT = try String(contentsOfFile: urlCHT, encoding: .utf8)
} catch { print("Exception happened when reading raw data.") }

// MARK: - 轉換音韻

var arrClusterCHT = strClusterCHT.components(separatedBy: "\n")
var currentBlobCHT = ""
for blob in arrClusterCHT {
  currentBlobCHT = blob
  try? currentBlobCHT.replacingMatches(of: #"\bㄐㄧ\b"#, with: "ㄐㄧˋ", keyword: "績")
  try? currentBlobCHT.replacingMatches(of: #"\bㄐㄧ\b"#, with: "ㄐㄧˋ", keyword: "蹟")
  try? currentBlobCHT.replacingMatches(of: #"\bㄐㄧ\b"#, with: "ㄐㄧˋ", keyword: "跡")
  try? currentBlobCHT.replacingMatches(of: #"\bㄑㄧㄢ\b"#, with: "ㄑㄧㄢˋ", keyword: "嵌")
  try? currentBlobCHT.replacingMatches(of: #"\bㄎㄨㄤ\b"#, with: "ㄎㄨㄤˋ", keyword: "框")
  try? currentBlobCHS.replacingMatches(of: #"\bㄑㄧˊ\b"#, with: "ㄑㄧ", keyword: "期")
  try? currentBlobCHT.replacingMatches(of: #"\bㄨㄟˊ\b"#, with: "ㄨㄟ", keyword: "微")
  try? currentBlobCHT.replacingMatches(of: #"\bㄨㄟˊ\b"#, with: "ㄨㄟ", keyword: "薇")
  try? currentBlobCHT.replacingMatches(of: #"\bㄊㄨˊ\b"#, with: "ㄊㄨ", keyword: "突")
  try? currentBlobCHT.replacingMatches(of: #"\bㄈㄢˊ\b"#, with: "ㄈㄢ", keyword: "帆")
  try? currentBlobCHT.replacingMatches(of: #"\bㄈㄢˊ\b"#, with: "ㄈㄢ", keyword: "藩")
  try? currentBlobCHT.replacingMatches(of: #"\bㄐㄧˊ\b"#, with: "ㄐㄧ", keyword: "擊")
  try? currentBlobCHT.replacingMatches(of: #"\bㄐㄧㄚˊ\b"#, with: "ㄐㄧㄚ", keyword: "夾")
  try? currentBlobCHT.replacingMatches(of: #"\bㄐㄩˊ\b"#, with: "ㄐㄩ", keyword: "鞠")
  try? currentBlobCHT.replacingMatches(of: #"\bㄋㄧㄢˊ\b"#, with: "ㄋㄧㄢ", keyword: "拈")
  try? currentBlobCHT.replacingMatches(of: #"\bㄒㄧˋ\b"#, with: "ㄒㄧ", keyword: "夕")
  try? currentBlobCHT.replacingMatches(of: #"\bㄒㄧˊ\b"#, with: "ㄒㄧ", keyword: "昔")
  try? currentBlobCHT.replacingMatches(of: #"\bㄒㄧˊ\b"#, with: "ㄒㄧ", keyword: "惜")
  try? currentBlobCHT.replacingMatches(of: #"\bㄒㄧˊ\b"#, with: "ㄒㄧ", keyword: "熄")
  try? currentBlobCHT.replacingMatches(of: #"\bㄒㄧˊ\b"#, with: "ㄒㄧ", keyword: "息")
  try? currentBlobCHT.replacingMatches(of: #"\bㄨㄟˊ\b"#, with: "ㄨㄟ", keyword: "危")
  try? currentBlobCHT.replacingMatches(of: #"\bㄧㄝˊ\b"#, with: "ㄧㄝ", keyword: "椰")
  try? currentBlobCHT.replacingMatches(of: #"\bㄕㄨˊ\b"#, with: "ㄕㄨ", keyword: "叔")
  try? currentBlobCHT.replacingMatches(of: #"\bㄊㄠˊ\b"#, with: "ㄊㄠ", keyword: "濤")
  try? currentBlobCHT.replacingMatches(of: #"\bㄉㄧㄝˊ\b"#, with: "ㄉㄧㄝ", keyword: "跌")
  try? currentBlobCHT.replacingMatches(of: #"\bㄐㄧˊ\b"#, with: "ㄐㄧˋ", keyword: "寂")
  try? currentBlobCHT.replacingMatches(of: #"\bㄋㄧㄥˊ\b"#, with: "ㄋㄧㄥˋ", keyword: "寧")
  try? currentBlobCHT.replacingMatches(of: #"\bㄓㄨㄛˊ\b"#, with: "ㄓㄨㄛˋ", keyword: "築")
  try? currentBlobCHT.replacingMatches(of: #"\bㄒㄩㄣˊ\b"#, with: "ㄒㄩㄣˋ", keyword: "馴")
  try? currentBlobCHT.replacingMatches(of: #"\bㄅㄛˋ\b"#, with: "ㄅㄛ", keyword: "播")
  try? currentBlobCHT.replacingMatches(of: #"\bㄐㄧㄡˋ\b"#, with: "ㄐㄧㄡ", keyword: "究")
  try? currentBlobCHT.replacingMatches(of: #"\bㄉㄥˋ\b"#, with: "ㄉㄥ", keyword: "蹬")
  try? currentBlobCHT.replacingMatches(of: #"\bㄆㄧㄠˋ\b"#, with: "ㄆㄧㄠ", keyword: "剽")
  try? currentBlobCHT.replacingMatches(of: #"\bㄐㄩㄣˋ\b"#, with: "ㄐㄩㄣ", keyword: "菌")
  try? currentBlobCHT.replacingMatches(of: #"\bㄉㄨㄣˋ\b"#, with: "ㄉㄨㄣ", keyword: "噸")
  try? currentBlobCHT.replacingMatches(of: #"\bㄒㄩㄝˋ\b"#, with: "ㄒㄩㄝˊ", keyword: "穴")
  try? currentBlobCHT.replacingMatches(of: #"\bㄌㄧㄡˋ\b"#, with: "ㄌㄧㄡˊ", keyword: "餾")
  try? currentBlobCHT.replacingMatches(of: #"\bㄕˋ\b"#, with: "ㄕˊ", keyword: "識")
  try? currentBlobCHT.replacingMatches(of: #"\bㄑㄧˋ\b"#, with: "ㄑㄧˇ", keyword: "企")
  try? currentBlobCHT.replacingMatches(of: #"\bㄖㄨˋ\b"#, with: "ㄖㄨˇ", keyword: "辱")
  try? currentBlobCHT.replacingMatches(of: #"\bㄕㄨˋ\b"#, with: "ㄕㄨˇ", keyword: "署")
  try? currentBlobCHT.replacingMatches(of: #"\bㄈㄥˋ\b"#, with: "ㄈㄥˇ", keyword: "諷")
  try? currentBlobCHT.replacingMatches(of: #"\bㄎㄠˋ\b"#, with: "ㄎㄠˇ", keyword: "蹈")
  try? currentBlobCHT.replacingMatches(of: #"\bㄨㄟˋ\b"#, with: "ㄨㄟˇ", keyword: "偽")
  try? currentBlobCHT.replacingMatches(of: #"\bㄆㄨˊ\b"#, with: "ㄆㄨˇ", keyword: "樸")
  try? currentBlobCHT.replacingMatches(of: #"\bㄔㄨˊ\b"#, with: "ㄔㄨˇ", keyword: "儲")
  try? currentBlobCHT.replacingMatches(of: #"\bㄈㄚˇ\b"#, with: "ㄈㄚˋ", keyword: "髮")
  try? currentBlobCHT.replacingMatches(of: #"\bㄑㄧㄠˇ\b"#, with: "ㄑㄧㄠ", keyword: "悄")
  try? currentBlobCHT.replacingMatches(of: #"\bㄈㄤ\b"#, with: "ㄈㄤˊ", keyword: "坊")
  try? currentBlobCHT.replacingMatches(of: #"\bㄙㄨㄟ\b"#, with: "ㄙㄨㄟˊ", keyword: "綏")
  try? currentBlobCHT.replacingMatches(of: #"\bㄈㄨˊ\b"#, with: "ㄈㄨˋ", keyword: "縛")
  try? currentBlobCHT.replacingMatches(of: #"\bㄌㄧㄢˋ\b"#, with: "ㄌㄧㄢˇ", keyword: "斂")
  try? currentBlobCHT.replacingMatches(of: #"\bㄒㄧˋ\b"#, with: "ㄒㄧ", keyword: "矽")
  try? currentBlobCHT.replacingMatches(of: #"\bㄗㄨㄥˋ\b"#, with: "ㄗㄨㄥ", keyword: "綜")
  try? currentBlobCHT.replacingMatches(of: #"\bㄆㄛˇ\b"#, with: "ㄆㄛ", keyword: "頗")
  try? currentBlobCHT.replacingMatches(of: #"\bㄩㄥˇ\b"#, with: "ㄩㄥ", keyword: "擁")
  try? currentBlobCHT.replacingMatches(of: #"\bㄐㄧㄠˇ\b"#, with: "ㄐㄧㄠ", keyword: "姣")
  try? currentBlobCHT.replacingMatches(of: #"\bㄉㄤˇ\b"#, with: "ㄉㄤˋ", keyword: "檔")
  try? currentBlobCHT.replacingMatches(of: #"\bㄕㄨˊ\b"#, with: "ㄕㄨ", keyword: "菽")
  try? currentBlobCHT.replacingMatches(of: #"\bㄓㄨㄛˊ\b"#, with: "ㄓㄨㄛˋ", keyword: "築")
  try? currentBlobCHT.replacingMatches(of: #"\bㄊㄧˋ\b"#, with: "ㄊㄧ", keyword: "銻")
  try? currentBlobCHT.replacingMatches(of: #"\bㄉㄨㄛˊ\b"#, with: "ㄉㄨㄛ", keyword: "掇")
  try? currentBlobCHT.replacingMatches(of: #"\bㄢ\b"#, with: "ㄢˇ", keyword: "銨")
  try? currentBlobCHT.replacingMatches(of: #"\bㄐㄩㄣˋ\b"#, with: "ㄐㄩㄣ", keyword: "菌")
  print(currentBlobCHT)
}

print("==========Border=========")
var arrClusterCHS = strClusterCHS.components(separatedBy: "\n")
var currentBlobCHS = ""
for blob in arrClusterCHS {
  currentBlobCHS = blob
  try? currentBlobCHS.replacingMatches(of: #"\bㄐㄧ\b"#, with: "ㄐㄧˋ", keyword: "绩")
  try? currentBlobCHS.replacingMatches(of: #"\bㄐㄧ\b"#, with: "ㄐㄧˋ", keyword: "迹")
  try? currentBlobCHS.replacingMatches(of: #"\bㄑㄧㄢ\b"#, with: "ㄑㄧㄢˋ", keyword: "嵌")
  try? currentBlobCHS.replacingMatches(of: #"\bㄎㄨㄤ\b"#, with: "ㄎㄨㄤˋ", keyword: "框")
  try? currentBlobCHS.replacingMatches(of: #"\bㄑㄧˊ\b"#, with: "ㄑㄧ", keyword: "期")
  try? currentBlobCHS.replacingMatches(of: #"\bㄨㄟˊ\b"#, with: "ㄨㄟ", keyword: "微")
  try? currentBlobCHS.replacingMatches(of: #"\bㄨㄟˊ\b"#, with: "ㄨㄟ", keyword: "薇")
  try? currentBlobCHS.replacingMatches(of: #"\bㄊㄨˊ\b"#, with: "ㄊㄨ", keyword: "突")
  try? currentBlobCHS.replacingMatches(of: #"\bㄈㄢˊ\b"#, with: "ㄈㄢ", keyword: "帆")
  try? currentBlobCHS.replacingMatches(of: #"\bㄈㄢˊ\b"#, with: "ㄈㄢ", keyword: "藩")
  try? currentBlobCHS.replacingMatches(of: #"\bㄐㄧˊ\b"#, with: "ㄐㄧ", keyword: "击")
  try? currentBlobCHS.replacingMatches(of: #"\bㄐㄧㄚˊ\b"#, with: "ㄐㄧㄚ", keyword: "夹")
  try? currentBlobCHS.replacingMatches(of: #"\bㄐㄩˊ\b"#, with: "ㄐㄩ", keyword: "鞠")
  try? currentBlobCHS.replacingMatches(of: #"\bㄋㄧㄢˊ\b"#, with: "ㄋㄧㄢ", keyword: "拈")
  try? currentBlobCHS.replacingMatches(of: #"\bㄒㄧˋ\b"#, with: "ㄒㄧ", keyword: "夕")
  try? currentBlobCHS.replacingMatches(of: #"\bㄒㄧˊ\b"#, with: "ㄒㄧ", keyword: "昔")
  try? currentBlobCHS.replacingMatches(of: #"\bㄒㄧˊ\b"#, with: "ㄒㄧ", keyword: "惜")
  try? currentBlobCHS.replacingMatches(of: #"\bㄒㄧˊ\b"#, with: "ㄒㄧ", keyword: "熄")
  try? currentBlobCHS.replacingMatches(of: #"\bㄒㄧˊ\b"#, with: "ㄒㄧ", keyword: "息")
  try? currentBlobCHS.replacingMatches(of: #"\bㄨㄟˊ\b"#, with: "ㄨㄟ", keyword: "危")
  try? currentBlobCHS.replacingMatches(of: #"\bㄧㄝˊ\b"#, with: "ㄧㄝ", keyword: "椰")
  try? currentBlobCHS.replacingMatches(of: #"\bㄕㄨˊ\b"#, with: "ㄕㄨ", keyword: "叔")
  try? currentBlobCHS.replacingMatches(of: #"\bㄊㄠˊ\b"#, with: "ㄊㄠ", keyword: "涛")
  try? currentBlobCHS.replacingMatches(of: #"\bㄉㄧㄝˊ\b"#, with: "ㄉㄧㄝ", keyword: "跌")
  try? currentBlobCHS.replacingMatches(of: #"\bㄧㄡˊ\b"#, with: "ㄧㄡ", keyword: "尤")
  try? currentBlobCHS.replacingMatches(of: #"\bㄐㄧˊ\b"#, with: "ㄐㄧˋ", keyword: "寂")
  try? currentBlobCHS.replacingMatches(of: #"\bㄋㄧㄥˊ\b"#, with: "ㄋㄧㄥˋ", keyword: "宁")
  try? currentBlobCHS.replacingMatches(of: #"\bㄓㄨㄛˊ\b"#, with: "ㄓㄨㄛˋ", keyword: "筑")
  try? currentBlobCHS.replacingMatches(of: #"\bㄒㄩㄣˊ\b"#, with: "ㄒㄩㄣˋ", keyword: "驯")
  try? currentBlobCHS.replacingMatches(of: #"\bㄅㄛˋ\b"#, with: "ㄅㄛ", keyword: "播")
  try? currentBlobCHS.replacingMatches(of: #"\bㄐㄧㄡˋ\b"#, with: "ㄐㄧㄡ", keyword: "究")
  try? currentBlobCHS.replacingMatches(of: #"\bㄉㄥˋ\b"#, with: "ㄉㄥ", keyword: "蹬")
  try? currentBlobCHS.replacingMatches(of: #"\bㄆㄧㄠˋ\b"#, with: "ㄆㄧㄠ", keyword: "剽")
  try? currentBlobCHS.replacingMatches(of: #"\bㄐㄩㄣˋ\b"#, with: "ㄐㄩㄣ", keyword: "菌")
  try? currentBlobCHS.replacingMatches(of: #"\bㄉㄨㄣˋ\b"#, with: "ㄉㄨㄣ", keyword: "吨")
  try? currentBlobCHS.replacingMatches(of: #"\bㄒㄩㄝˋ\b"#, with: "ㄒㄩㄝˊ", keyword: "穴")
  try? currentBlobCHS.replacingMatches(of: #"\bㄌㄧㄡˋ\b"#, with: "ㄌㄧㄡˊ", keyword: "馏")
  try? currentBlobCHS.replacingMatches(of: #"\bㄕˋ\b"#, with: "ㄕˊ", keyword: "识")
  try? currentBlobCHS.replacingMatches(of: #"\bㄑㄧˋ\b"#, with: "ㄑㄧˇ", keyword: "企")
  try? currentBlobCHS.replacingMatches(of: #"\bㄖㄨˋ\b"#, with: "ㄖㄨˇ", keyword: "辱")
  try? currentBlobCHS.replacingMatches(of: #"\bㄕㄨˋ\b"#, with: "ㄕㄨˇ", keyword: "署")
  try? currentBlobCHS.replacingMatches(of: #"\bㄈㄥˋ\b"#, with: "ㄈㄥˇ", keyword: "讽")
  try? currentBlobCHS.replacingMatches(of: #"\bㄎㄠˋ\b"#, with: "ㄎㄠˇ", keyword: "蹈")
  try? currentBlobCHS.replacingMatches(of: #"\bㄨㄟˋ\b"#, with: "ㄨㄟˇ", keyword: "伪")
  try? currentBlobCHS.replacingMatches(of: #"\bㄆㄨˊ\b"#, with: "ㄆㄨˇ", keyword: "朴")
  try? currentBlobCHS.replacingMatches(of: #"\bㄔㄨˊ\b"#, with: "ㄔㄨˇ", keyword: "储")
  try? currentBlobCHS.replacingMatches(of: #"\bㄈㄚˇ\b"#, with: "ㄈㄚˋ", keyword: "发")
  try? currentBlobCHS.replacingMatches(of: #"\bㄑㄧㄠˇ\b"#, with: "ㄑㄧㄠ", keyword: "悄")
  try? currentBlobCHS.replacingMatches(of: #"\bㄈㄤ\b"#, with: "ㄈㄤˊ", keyword: "坊")
  try? currentBlobCHS.replacingMatches(of: #"\bㄙㄨㄟ\b"#, with: "ㄙㄨㄟˊ", keyword: "绥")
  try? currentBlobCHS.replacingMatches(of: #"\bㄈㄨˊ\b"#, with: "ㄈㄨˋ", keyword: "缚")
  try? currentBlobCHS.replacingMatches(of: #"\bㄌㄧㄢˋ\b"#, with: "ㄌㄧㄢˇ", keyword: "敛")
  try? currentBlobCHS.replacingMatches(of: #"\bㄒㄧˋ\b"#, with: "ㄒㄧ", keyword: "矽")
  try? currentBlobCHS.replacingMatches(of: #"\bㄗㄨㄥˋ\b"#, with: "ㄗㄨㄥ", keyword: "综")
  try? currentBlobCHS.replacingMatches(of: #"\bㄆㄛˇ\b"#, with: "ㄆㄛ", keyword: "颇")
  try? currentBlobCHS.replacingMatches(of: #"\bㄩㄥˇ\b"#, with: "ㄩㄥ", keyword: "拥")
  try? currentBlobCHS.replacingMatches(of: #"\bㄐㄧㄠˇ\b"#, with: "ㄐㄧㄠ", keyword: "姣")
  try? currentBlobCHS.replacingMatches(of: #"\bㄉㄤˇ\b"#, with: "ㄉㄤˋ", keyword: "档")
  try? currentBlobCHS.replacingMatches(of: #"\bㄕㄨˊ\b"#, with: "ㄕㄨ", keyword: "菽")
  try? currentBlobCHS.replacingMatches(of: #"\bㄊㄧˋ\b"#, with: "ㄊㄧ", keyword: "锑")
  try? currentBlobCHS.replacingMatches(of: #"\bㄉㄨㄛˊ\b"#, with: "ㄉㄨㄛ", keyword: "掇")
  try? currentBlobCHS.replacingMatches(of: #"\bㄢ\b"#, with: "ㄢˇ", keyword: "铵")
  print(currentBlobCHS)
}
