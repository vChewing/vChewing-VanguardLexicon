#!/usr/bin/env swift

// (c) 2021 and onwards The vChewing Project (MIT-NTL License).
// ====================
// This code is released under the MIT license (SPDX-License-Identifier: MIT)
// ... with NTL restriction stating that:
// No trademark license is granted to use the trade names, trademarks, service
// marks, or product names of Contributor, except as required to fulfill notice
// requirements defined in MIT License.

import Foundation

extension String {
  mutating func regReplace(pattern: String, replaceWith: String = "") {
    do {
      let regex = try NSRegularExpression(
        pattern: pattern, options: [.caseInsensitive, .anchorsMatchLines]
      )
      let range = NSRange(startIndex..., in: self)
      self = regex.stringByReplacingMatches(
        in: self, options: [], range: range, withTemplate: replaceWith
      )
    } catch { return }
  }
}

func getDocumentsDirectory() -> URL {
  let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
  return paths[0]
}

let urlCHSforTABE = "../components/chs/phrases-tabe-chs.txt"
let urlCHSforMOE = "../components/chs/phrases-moe-chs.txt"
let urlCHSforVCHEW = "../components/chs/phrases-vchewing-chs.txt"
let urlCHTforTABE = "../components/cht/phrases-tabe-cht.txt"
let urlCHTforMOE = "../components/cht/phrases-moe-cht.txt"
let urlCHTforVCHEW = "../components/cht/phrases-vchewing-cht.txt"

var textCHS = ""
var textCHT = ""

// 档案载入
do {
  textCHS += "@# phrases-moe-chs.txt\n"
  textCHS += try String(contentsOfFile: urlCHSforMOE, encoding: .utf8)
  textCHS += "\n@# phrases-tabe-chs.txt\n"
  textCHS += try String(contentsOfFile: urlCHSforTABE, encoding: .utf8)
  textCHS += "\n@# phrases-moe-vchewing.txt\n"
  textCHS += try String(contentsOfFile: urlCHSforVCHEW, encoding: .utf8)
} catch { print("Exception happened when reading raw CHS data.") }

do {
  textCHT += "@# phrases-moe-cht.txt\n"
  textCHT += try String(contentsOfFile: urlCHTforMOE, encoding: .utf8)
  textCHT += "\n@# phrases-tabe-cht.txt\n"
  textCHT += try String(contentsOfFile: urlCHTforTABE, encoding: .utf8)
  textCHT += "\n@# phrases-moe-vchewing.txt\n"
  textCHT += try String(contentsOfFile: urlCHTforVCHEW, encoding: .utf8)
} catch { print("Exception happened when reading raw CHT data.") }

// Regex Pre-Processing
textCHT.regReplace(pattern: #"( +|　+| +|\t+)+"#, replaceWith: " ")  // Concatenating Spaces
textCHT.regReplace(pattern: #"(^ | $)"#, replaceWith: "")  // 去除行尾行首空格
textCHT.regReplace(pattern: #"(\f+|\r+|\n+)+"#, replaceWith: "\n")  // CR & Form Feed to LF, 且去除重複行
textCHS.regReplace(pattern: #"( +|　+| +|\t+)+"#, replaceWith: " ")  // Concatenating Spaces
textCHS.regReplace(pattern: #"(^ | $)"#, replaceWith: "")  // 去除行尾行首空格
textCHS.regReplace(pattern: #"(\f+|\r+|\n+)+"#, replaceWith: "\n")  // CR & Form Feed to LF, 且去除重複行

// 转成 Vector
var arrData = textCHS.components(separatedBy: "\n")
var varLineData = ""
var strProcessed = ""
for lineData in arrData {
  varLineData = lineData
  varLineData.regReplace(pattern: "^#.*$", replaceWith: "")  // Make Comment Lines Empty
  strProcessed += varLineData
  strProcessed += "\n"
}

arrData = strProcessed.components(separatedBy: "\n")
let arrCHS = Array(NSOrderedSet(array: arrData).array as! [String])  // Deduplication

arrData = textCHT.components(separatedBy: "\n")
varLineData = ""
strProcessed = ""
for lineData in arrData {
  varLineData = lineData
  varLineData.regReplace(pattern: "^#.*$", replaceWith: "")  // Make Comment Lines Empty
  strProcessed += varLineData
  strProcessed += "\n"
}

arrData = strProcessed.components(separatedBy: "\n")
let arrCHT = Array(NSOrderedSet(array: arrData).array as! [String])  // Deduplication

// Print Out
for lineData in arrCHT {
  varLineData = lineData
  print(varLineData)
}

print("@@@@@@@@@@@@@@@@@@@@")
for lineData in arrCHS {
  varLineData = lineData
  print(varLineData)
}
