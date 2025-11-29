#!/usr/bin/env swift

// (c) 2021 and onwards The vChewing Project (BSD-3-Clause).
// ====================
// This code is released under the SPDX-License-Identifier: `BSD-3-Clause`.

// 開發用私人腳本，將自己記錄的新詞的內容同步到先鋒語料庫內。

import Foundation

// MARK: - Phrase

struct Phrase {
  static var cellTitlesForReport: [String] {
    ["字詞 次數 讀音", "電玩", "複寫", "錯字檢查"]
  }

  static var bareCellTitlesForReport: [String] {
    ["字詞 次數 讀音"]
  }

  let text: String
  let pronunciation: String
  var count = 4
  var isOverridden = false
  var requireKanjiCheck = false
  var isGame = false

  var reportAsCells: [String] {
    [
      "\(text) \(count) \(pronunciation)",
      isGame ? "#電玩" : "",
      isOverridden ? "#複寫" : "",
      requireKanjiCheck ? "#錯字檢查" : "",
    ]
  }

  var reportAsBareCells: [String] {
    ["\(text) \(count) \(pronunciation)"]
  }
}

// MARK: - Constants

let chsFilterRaw =
  try? String(
    contentsOfFile: "/Users/shikisuen/Library/Mobile Documents/com~apple~CloudDocs/vChewing/userdata-chs.txt",
    encoding: .utf8
  )
let chtFilterRaw =
  try? String(
    contentsOfFile: "/Users/shikisuen/Library/Mobile Documents/com~apple~CloudDocs/vChewing/userdata-cht.txt",
    encoding: .utf8
  )
let urlCHS = URL(fileURLWithPath: "./Sources/LibVanguardChewingData/Resources/components/chs/")
let urlCHT = URL(fileURLWithPath: "./Sources/LibVanguardChewingData/Resources/components/cht/")

guard let chsFilterRaw = chsFilterRaw, let chtFilterRaw = chtFilterRaw else { exit(0) }

func makeFilter(from rawString: String) -> [Phrase] {
  var phrases: [Phrase] = []
  rawString.enumerateLines { line, _ in
    let cells = line.split(separator: " ")
    guard cells.count >= 2, cells.first != "#" else { return }
    let reading = cells[1].replacing("-", with: " ")
    var phrase = Phrase(text: cells[0].description, pronunciation: reading.description)
    if line.contains(" #𝙃𝙪𝙢𝙖𝙣𝘾𝙝𝙚𝙘𝙠𝙍𝙚𝙦𝙪𝙞𝙧𝙚𝙙") { phrase.requireKanjiCheck = true }
    if line.contains(" #𝙾𝚟𝚎𝚛𝚛𝚒𝚍𝚎") { phrase.isOverridden = true } // 得手動檢查升頻值。
    if line.contains(" #GAME") { phrase.isGame = true } // 得手動檢查升頻值。
    if cells.count >= 3, let weightValue = Double(cells[2].description) {
      switch weightValue {
      case ..<(-114): phrase.count = 0
      case -114 ..< 0: phrase.count = 2
      default: phrase.count = phrase.isOverridden ? 4_444_444 : 4
      }
    }
    phrases.append(phrase)
  }
  return phrases
}

let chsFilter: [Phrase] = makeFilter(from: chsFilterRaw)
let chtFilter: [Phrase] = makeFilter(from: chtFilterRaw)

// MARK: - Extensions

extension Array where Element == Phrase {
  func makeReport(bare: Bool = false) -> String {
    let result = NSMutableString(string: "")
    result
      .append(
        bare ? Phrase.bareCellTitlesForReport.joined(separator: "\t") : Phrase
          .cellTitlesForReport.joined(separator: "\t")
      )
    result.append("\n")
    forEach { phrase in
      result
        .append(
          bare ? phrase.reportAsBareCells.joined(separator: "\t") : phrase.reportAsCells
            .joined(separator: "\t")
        )
      result.append("\n")
    }
    return result.description
  }
}

extension Bool {
  var nyet: Bool { !self }
}

print(chsFilter.filter(\.isGame.nyet).makeReport(bare: true))
print(chtFilter.filter(\.isGame.nyet).makeReport(bare: true))
