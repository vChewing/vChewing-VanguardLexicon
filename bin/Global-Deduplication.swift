#!/usr/bin/env swift

// Copyright (c) 2021 and onwards The vChewing Project (MIT-NTL License).
/*
Permission is hereby granted, free of charge, to any person obtaining a copy of
this software and associated documentation files (the "Software"), to deal in
the Software without restriction, including without limitation the rights to
use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of
the Software, and to permit persons to whom the Software is furnished to do so,
subject to the following conditions:

1. The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

2. No trademark license is granted to use the trade names, trademarks, service
marks, or product names of Contributor, except as required to fulfill notice
requirements above.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS
FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR
COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER
IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
*/

import Foundation

extension String {
	mutating func regReplace(pattern: String, replaceWith: String = "") {
		do {
			let regex = try NSRegularExpression(
				pattern: pattern, options: [.caseInsensitive, .anchorsMatchLines])
			let range = NSRange(self.startIndex..., in: self)
			self = regex.stringByReplacingMatches(
				in: self, options: [], range: range, withTemplate: replaceWith)
		} catch { return }
	}
}

func getDocumentsDirectory() -> URL {
	let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
	return paths[0]
}

let urlCHSforMCBP = "../components/chs/phrases-mcbp-chs.txt"
let urlCHSforMOE = "../components/chs/phrases-moe-chs.txt"
let urlCHSforVCHEW = "../components/chs/phrases-vchewing-chs.txt"
let urlCHTforMCBP = "../components/cht/phrases-mcbp-cht.txt"
let urlCHTforMOE = "../components/cht/phrases-moe-cht.txt"
let urlCHTforVCHEW = "../components/cht/phrases-vchewing-cht.txt"

var textCHS = ""
var textCHT = ""

// 档案载入
do {
	textCHS += "@# phrases-moe-chs.txt\n"
	textCHS += try String(contentsOfFile: urlCHSforMOE, encoding: .utf8)
	textCHS += "\n@# phrases-mcbp-chs.txt\n"
	textCHS += try String(contentsOfFile: urlCHSforMCBP, encoding: .utf8)
	textCHS += "\n@# phrases-moe-vchewing.txt\n"
	textCHS += try String(contentsOfFile: urlCHSforVCHEW, encoding: .utf8)
} catch { print("Exception happened when reading raw CHS data.") }

do {
	textCHT += "@# phrases-moe-cht.txt\n"
	textCHT += try String(contentsOfFile: urlCHTforMOE, encoding: .utf8)
	textCHT += "\n@# phrases-mcbp-cht.txt\n"
	textCHT += try String(contentsOfFile: urlCHTforMCBP, encoding: .utf8)
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
