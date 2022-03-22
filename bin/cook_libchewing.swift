// Copyright (c) 2021 and onwards The vChewing Project (MIT-NTL License).
/*
Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated
documentation files (the "Software"), to deal in the Software without restriction, including without limitation
the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and
to permit persons to whom the Software is furnished to do so, subject to the following conditions:

1. The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

2. No trademark license is granted to use the trade names, trademarks, service marks, or product names of Contributor,
   except as required to fulfill notice requirements above.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED
TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL
THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
*/

import Foundation

// MARK: - 前導工作
fileprivate func getDocumentsDirectory() -> URL {
    let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
    return paths[0]
}

fileprivate extension String {
    mutating func regReplace(pattern: String, replaceWith: String = "") {
        // Ref: https://stackoverflow.com/a/40993403/4162914 && https://stackoverflow.com/a/71291137/4162914
        do {
            let regex = try NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .anchorsMatchLines])
            let range = NSRange(self.startIndex..., in: self)
            self = regex.stringByReplacingMatches(in: self, options: [], range: range, withTemplate: replaceWith)
        } catch { return }
    }
    mutating func selfReplace(_ strOf: String, _ strWith: String = "") {
        self = self.replacingOccurrences(of: strOf, with: strWith)
    }
    mutating func bpmf2Dachien() {
        self.selfReplace("ㄝ", ",")
        self.selfReplace("ㄦ", "-")
        self.selfReplace("ㄡ", ".")
        self.selfReplace("ㄥ", "/")
        self.selfReplace("ㄢ", "0")
        self.selfReplace("ㄅ", "1")
        self.selfReplace("ㄉ", "2")
        self.selfReplace("ˇ", "3")
        self.selfReplace("ˋ", "4")
        self.selfReplace("ㄓ", "5")
        self.selfReplace("ˊ", "6")
        self.selfReplace("˙", "7")
        self.selfReplace("ㄚ", "8")
        self.selfReplace("ㄞ", "9")
        self.selfReplace("ㄤ", ";")
        self.selfReplace("ㄇ", "a")
        self.selfReplace("ㄖ", "b")
        self.selfReplace("ㄏ", "c")
        self.selfReplace("ㄎ", "d")
        self.selfReplace("ㄍ", "e")
        self.selfReplace("ㄑ", "f")
        self.selfReplace("ㄕ", "g")
        self.selfReplace("ㄘ", "h")
        self.selfReplace("ㄛ", "i")
        self.selfReplace("ㄨ", "j")
        self.selfReplace("ㄜ", "k")
        self.selfReplace("ㄠ", "l")
        self.selfReplace("ㄩ", "m")
        self.selfReplace("ㄙ", "n")
        self.selfReplace("ㄟ", "o")
        self.selfReplace("ㄣ", "p")
        self.selfReplace("ㄆ", "q")
        self.selfReplace("ㄐ", "r")
        self.selfReplace("ㄋ", "s")
        self.selfReplace("ㄔ", "t")
        self.selfReplace("ㄧ", "u")
        self.selfReplace("ㄒ", "v")
        self.selfReplace("ㄊ", "w")
        self.selfReplace("ㄌ", "x")
        self.selfReplace("ㄗ", "y")
        self.selfReplace("ㄈ", "z")
    }
}


// MARK: - 引入小數點位數控制函數
// Ref: https://stackoverflow.com/a/32581409/4162914
fileprivate extension Float {
    func rounded(toPlaces places:Int) -> Float {
        let divisor = pow(10.0, Float(places))
        return (self * divisor).rounded() / divisor
    }
}

// MARK: - 引入幂乘函數
// Ref: https://stackoverflow.com/a/41581695/4162914
precedencegroup ExponentiationPrecedence {
    associativity: right
    higherThan: MultiplicationPrecedence
}

infix operator ** : ExponentiationPrecedence

func ** (_ base: Double, _ exp: Double) -> Double {
    return pow(base, exp)
}

func ** (_ base: Float, _ exp: Float) -> Float {
    return pow(base, exp)
}

// MARK: - 定義檔案結構

struct Entry {
    var valPhone: String = ""
    var valPhrase: String = ""
    var valWeight: Float = -1.0
    var valCount: Int = 0
}

// MARK: - 登記全局根常數變數

fileprivate let urlCurrentFolder = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)

fileprivate let url_CHS_Custom: String = "./components/chs/phrases-custom-chs.txt"
fileprivate let url_CHS_MCBP: String = "./components/chs/phrases-mcbp-chs.txt"
fileprivate let url_CHS_MOE: String = "./components/chs/phrases-moe-chs.txt"
fileprivate let url_CHS_VCHEW: String = "./components/chs/phrases-vchewing-chs.txt"

fileprivate let url_CHT_Custom: String = "./components/cht/phrases-custom-cht.txt"
fileprivate let url_CHT_MCBP: String = "./components/cht/phrases-mcbp-cht.txt"
fileprivate let url_CHT_MOE: String = "./components/cht/phrases-moe-cht.txt"
fileprivate let url_CHT_VCHEW: String = "./components/cht/phrases-vchewing-cht.txt"

fileprivate let urlKanjiCore: String = "./components/common/char-kanji-core.txt"
fileprivate let urlKanjiSupplement: String = "./components/common/char-kanji-phrasesonly.txt"
fileprivate let urlKanjiCNS: String = "./components/common/char-kanji-cns.txt"
fileprivate let urlMiscBPMF: String = "./components/common/char-misc-bpmf.txt"
fileprivate let urlMiscNonKanji: String = "./components/common/char-misc-nonkanji.txt"

fileprivate let urlCINHeader: String = "./components/common/phone-header.txt"

fileprivate let urlOutputCHS_Tsi: String = "./Build/tsi-chs.src"
fileprivate let urlOutputCHT_Tsi: String = "./Build/tsi-cht.src"
fileprivate let urlOutputCHS_CIN: String = "./Build/phone-chs.cin"
fileprivate let urlOutputCHT_CIN: String = "./Build/phone-cht.cin"
fileprivate let urlOutputCHS_CINEX: String = "./Build/phone-chs-ex.cin"
fileprivate let urlOutputCHT_CINEX: String = "./Build/phone-cht-ex.cin"

func ensureOutputFolder() {
    if !FileManager.default.fileExists(atPath: "./Build") {
        do {
            try FileManager.default.createDirectory(atPath: "./Build", withIntermediateDirectories: true, attributes: nil)
        } catch {
            NSLog(" - Failed to ensure the existence of build folder.")
        }
    }
}
// MARK: - 載入詞組檔案且輸出數組

func rawDictForPhrases(isCHS: Bool) -> [Entry] {
    var arrEntryRAW: [Entry] = []
    var strRAW: String = ""
    let urlCustom: String = isCHS ? url_CHS_Custom : url_CHT_Custom
    let urlMCBP: String = isCHS ? url_CHS_MCBP : url_CHT_MCBP
    let urlMOE: String = isCHS ? url_CHS_MOE : url_CHT_MOE
    let urlVCHEW: String = isCHS ? url_CHS_VCHEW : url_CHT_VCHEW
    let i18n: String = isCHS ? "簡體中文" : "繁體中文"
    // 讀取內容
    do {
        strRAW += try String(contentsOfFile: urlCustom, encoding: .utf8)
        strRAW += "\n"
        strRAW += try String(contentsOfFile: urlMCBP, encoding: .utf8)
        strRAW += "\n"
        strRAW += try String(contentsOfFile: urlMOE, encoding: .utf8)
        strRAW += "\n"
        strRAW += try String(contentsOfFile: urlVCHEW, encoding: .utf8)
    }
    catch {
        NSLog(" - Exception happened when reading raw phrases data.")
        return []
    }
    // 預處理格式
    strRAW = strRAW.replacingOccurrences(of: " #MACOS", with: "") // 去掉 macOS 標記
    // CJKWhiteSpace (\x{3000}) to ASCII Space
    // NonBreakWhiteSpace (\x{A0}) to ASCII Space
    // Tab to ASCII Space
    // 統整連續空格為一個 ASCII 空格
    strRAW.regReplace(pattern: #"( +|　+| +|\t+)+"#, replaceWith: " ")
    strRAW.regReplace(pattern: #"(^ | $)"#, replaceWith: "") // 去除行尾行首空格
    strRAW.regReplace(pattern: #"(\f+|\r+|\n+)+"#, replaceWith: "\n") // CR & Form Feed to LF, 且去除重複行
    strRAW.regReplace(pattern: #"^(#.*|.*#WIN32.*)$"#, replaceWith: "") // 以#開頭的行都淨空+去掉所有 WIN32 特有的行
    // 正式整理格式，現在就開始去重複：
    let arrData = Array(NSOrderedSet(array: strRAW.components(separatedBy: "\n")).array as! [String])
    for lineData in arrData {
        // 第三欄開始是注音
        let arrLineData = lineData.components(separatedBy: " ")
        var varLineDataProcessed: String = ""
        var count = 0
        for currentCell in arrLineData {
            count += 1
            if count < 3 {
                varLineDataProcessed += currentCell + "\t"
            } else if count < arrLineData.count {
                    varLineDataProcessed += currentCell + " "
            } else {
                varLineDataProcessed += currentCell
            }
        }
        // 然後直接乾脆就轉成 Entry 吧。
        let arrCells : [String] = varLineDataProcessed.components(separatedBy: "\t")
        count = 0 // 不需要再定義，因為之前已經有定義過了。
        var phone = ""
        var phrase = ""
        var occurrence = 0
        for cell in arrCells {
            count += 1
            switch count {
            case 1: phrase = cell
            case 3: phone = cell
            case 2:
                occurrence = Int(cell) ?? 0
                if occurrence < 0 {
                    occurrence = 0
                }
            default: break
            }
        }
        if phrase != "" { // 廢掉空數據；之後無須再這樣處理。
            arrEntryRAW += [Entry.init(valPhone: phone, valPhrase: phrase, valWeight: 0.0, valCount: occurrence)]
        }
    }
    NSLog(" - \(i18n): 成功生成詞語語料辭典（尚未排序）。")
    return arrEntryRAW
}

// MARK: - 載入單字檔案且輸出數組

func rawDictForKanjis(isCHS: Bool, isSupplemetal: Bool = false, isCNS: Bool = false) -> [Entry] {
    var arrEntryRAW: [Entry] = []
    var strRAW: String = ""
    var strRAWOther: String = ""
    let i18n: String = isCHS ? "簡體中文" : "繁體中文"
    // 讀取內容
    do {
        strRAW += try String(contentsOfFile: urlKanjiCore, encoding: .utf8)
        if isSupplemetal {
            strRAWOther += try String(contentsOfFile: urlKanjiSupplement, encoding: .utf8)
            strRAWOther.selfReplace("\t", " ")
        }
        if isCNS {
            strRAWOther += try String(contentsOfFile: urlKanjiCNS, encoding: .utf8)
        }
    }
    catch {
        NSLog(" - Exception happened when reading raw core kanji data.")
        return []
    }
    // 預處理格式
    strRAW = strRAW.replacingOccurrences(of: " #MACOS", with: "") // 去掉 macOS 標記
    // CJKWhiteSpace (\x{3000}) to ASCII Space
    // NonBreakWhiteSpace (\x{A0}) to ASCII Space
    // Tab to ASCII Space
    // 統整連續空格為一個 ASCII 空格
    strRAW.regReplace(pattern: #"( +|　+| +|\t+)+"#, replaceWith: " ")
    strRAW.regReplace(pattern: #"(^ | $)"#, replaceWith: "") // 去除行尾行首空格
    strRAW.regReplace(pattern: #"(\f+|\r+|\n+)+"#, replaceWith: "\n") // CR & Form Feed to LF, 且去除重複行
    strRAW.regReplace(pattern: #"^(#.*|.*#WIN32.*)$"#, replaceWith: "") // 以#開頭的行都淨空+去掉所有 WIN32 特有的行
    // 正式整理格式，現在就開始去重複：
    var arrData = Array(NSOrderedSet(array: strRAW.components(separatedBy: "\n")).array as! [String])
    var varLineData: String = ""
    for lineData in arrData {
        // 簡體中文的話，提取 1,2,4；繁體中文的話，提取 1,3,4。
        let varLineDataPre = lineData.components(separatedBy: " ").prefix(isCHS ? 2 : 1).joined(separator: "\t")
        let varLineDataPost = lineData.components(separatedBy: " ").suffix(isCHS ? 1 : 2).joined(separator: "\t")
        varLineData = varLineDataPre + "\t" + varLineDataPost
        let arrLineData = varLineData.components(separatedBy: " ")
        var varLineDataProcessed: String = ""
        var count = 0
        for currentCell in arrLineData {
            count += 1
            if count < 3 {
                varLineDataProcessed += currentCell + "\t"
            } else if count < arrLineData.count {
                    varLineDataProcessed += currentCell + "-"
            } else {
                varLineDataProcessed += currentCell
            }
        }
        // 然後直接乾脆就轉成 Entry 吧。
        let arrCells : [String] = varLineDataProcessed.components(separatedBy: "\t")
        count = 0 // 不需要再定義，因為之前已經有定義過了。
        var phone = ""
        var phrase = ""
        var occurrence = 0
        for cell in arrCells {
            count += 1
            switch count {
            case 1: phrase = cell
            case 3: phone = cell
            case 2:
                occurrence = Int(cell) ?? 0
                occurrence += 1
            default: break
            }
        }
        if phrase.count == 1 { // 只要單個字符的數據
            arrEntryRAW += [Entry.init(valPhone: phone, valPhrase: phrase, valWeight: 0.0, valCount: occurrence)]
        }
    }
    // - 處理 CNS 等其他單字數據
    strRAWOther.regReplace(pattern: #"^(#.*)$"#, replaceWith: "") // 以#開頭的行都淨空
    arrData = Array(NSOrderedSet(array: strRAWOther.components(separatedBy: "\n")).array as! [String])
    for lineData in arrData {
        let arrCells : [String] = lineData.components(separatedBy: " ")
        var count = 0
        var phone = ""
        var phrase = ""
        let occurrence = 0
        for cell in arrCells {
            count += 1
            switch count {
            case 1: phrase = cell
            case 2: phone = cell
            default: break
            }
        }
        if phrase.count == 1 { // 只要單個字符的數據
            arrEntryRAW += [Entry.init(valPhone: phone, valPhrase: phrase, valWeight: 0.0, valCount: occurrence)]
        }
    }
    NSLog(" - \(i18n): 成功生成單字語料辭典（尚未排序）。")
    return arrEntryRAW
}

// MARK: - 載入非漢字檔案且輸出數組

func rawDictForNonKanjis(isCHS: Bool) -> [Entry] {
    var arrEntryRAW: [Entry] = []
    var strRAW: String = ""
    let i18n: String = isCHS ? "簡體中文" : "繁體中文"
    // 讀取內容
    do {
        strRAW += try String(contentsOfFile: urlMiscBPMF, encoding: .utf8)
        strRAW += "\n"
        strRAW += try String(contentsOfFile: urlMiscNonKanji, encoding: .utf8)
    }
    catch {
        NSLog(" - Exception happened when reading raw core kanji data.")
        return []
    }
    // 預處理格式
    strRAW = strRAW.replacingOccurrences(of: " #MACOS", with: "") // 去掉 macOS 標記
    // CJKWhiteSpace (\x{3000}) to ASCII Space
    // NonBreakWhiteSpace (\x{A0}) to ASCII Space
    // Tab to ASCII Space
    // 統整連續空格為一個 ASCII 空格
    strRAW.regReplace(pattern: #"( +|　+| +|\t+)+"#, replaceWith: " ")
    strRAW.regReplace(pattern: #"(^ | $)"#, replaceWith: "") // 去除行尾行首空格
    strRAW.regReplace(pattern: #"(\f+|\r+|\n+)+"#, replaceWith: "\n") // CR & Form Feed to LF, 且去除重複行
    strRAW.regReplace(pattern: #"^(#.*|.*#WIN32.*)$"#, replaceWith: "") // 以#開頭的行都淨空+去掉所有 WIN32 特有的行
    // 正式整理格式，現在就開始去重複：
    let arrData = Array(NSOrderedSet(array: strRAW.components(separatedBy: "\n")).array as! [String])
    var varLineData: String = ""
    for lineData in arrData {
        varLineData = lineData
        // 先完成某兩步需要分行處理才能完成的格式整理。
        varLineData = varLineData.components(separatedBy: " ").prefix(3).joined(separator: "\t") // 提取前三欄的內容。
        let arrLineData = varLineData.components(separatedBy: " ")
        var varLineDataProcessed: String = ""
        var count = 0
        for currentCell in arrLineData {
            count += 1
            if count < 3 {
                varLineDataProcessed += currentCell + "\t"
            } else if count < arrLineData.count {
                    varLineDataProcessed += currentCell + "-"
            } else {
                varLineDataProcessed += currentCell
            }
        }
        // 然後直接乾脆就轉成 Entry 吧。
        let arrCells : [String] = varLineDataProcessed.components(separatedBy: "\t")
        count = 0 // 不需要再定義，因為之前已經有定義過了。
        var phone = ""
        var phrase = ""
        var occurrence = 0
        for cell in arrCells {
            count += 1
            switch count {
            case 1: phrase = cell
            case 3: phone = cell
            case 2:
                occurrence = Int(cell) ?? 0
                occurrence += 1
            default: break
            }
        }
        if phrase.count == 1 { // 只要單個字符的數據
            arrEntryRAW += [Entry.init(valPhone: phone, valPhrase: phrase, valWeight: 0.0, valCount: occurrence)]
        }
    }
    NSLog(" - \(i18n): 成功生成非漢字語料辭典（尚未排序）。")
    return arrEntryRAW
}

// MARK: - 排序

func SortEntry(_ arrStructUnsorted: [Entry], isCHS: Bool) -> [Entry] {
    let i18n: String = isCHS ? "簡體中文" : "繁體中文"
    // 接下來是排序，先按照注音遞減排序一遍、再按照權重遞減排序一遍。
    let arrStructSorted: [Entry] = arrStructUnsorted.sorted(by: {(lhs, rhs) -> Bool in return (lhs.valPhone, rhs.valCount) < (rhs.valPhone, lhs.valCount)})
    NSLog(" - \(i18n): 排序整理完畢，準備編譯要寫入的檔案內容。")
    return arrStructSorted
}

// MARK: - 生成 CIN

func fileOutputCIN(isCHS: Bool, isCNS: Bool = false) {
    let i18n: String = isCHS ? "簡體中文" : "繁體中文"
    let pathOutput = urlCurrentFolder.appendingPathComponent(isCHS ? (isCNS ? urlOutputCHS_CINEX : urlOutputCHS_CIN) : (isCNS ? urlOutputCHT_CINEX : urlOutputCHT_CIN))
    var strPrintLine = ""
    // 讀取標點內容
    do {
        strPrintLine += try String(contentsOfFile: urlCINHeader, encoding: .utf8)
    }
    catch {
        NSLog(" - \(i18n): Exception happened when reading raw punctuation data.")
    }
    NSLog(" - \(i18n): 成功讀入 CIN 檔案標頭。")
    // 統合辭典內容
    var arrStructUnified: [Entry] = []
    arrStructUnified += rawDictForKanjis(isCHS: isCHS, isSupplemetal: true, isCNS: isCNS)
    arrStructUnified += rawDictForNonKanjis(isCHS: isCHS)
    // 計算權重且排序
    arrStructUnified = SortEntry(arrStructUnified, isCHS: isCHS)

    for entry in arrStructUnified {
        var varDachien = entry.valPhone
        varDachien.bpmf2Dachien()
        strPrintLine += varDachien + " " + entry.valPhrase + "\n"
    }

    strPrintLine += "%chardef  end" + "\n"
    // Deduplication
    let arrPrintLine = Array(NSOrderedSet(array: strPrintLine.components(separatedBy: "\n")).array as! [String])
    strPrintLine = arrPrintLine.joined(separator: "\n")

    NSLog(" - \(i18n): 要寫入 CIN 檔案的內容編譯完畢。")
    do {
        try strPrintLine.write(to: pathOutput, atomically: false, encoding: .utf8)
    }
    catch {
        NSLog(" - \(i18n): Error on writing strings to file: \(error)")
    }
    NSLog(" - \(i18n): 寫入完成。")
}

// MARK: - 生成 TSI

func fileOutputTSI(isCHS: Bool) {
    let i18n: String = isCHS ? "簡體中文" : "繁體中文"
    let pathOutput = urlCurrentFolder.appendingPathComponent(isCHS ? urlOutputCHS_Tsi : urlOutputCHT_Tsi)
    var strPrintLine = ""
    // 統合辭典內容
    var arrStructUnified: [Entry] = []
    arrStructUnified += rawDictForKanjis(isCHS: isCHS)
    arrStructUnified += rawDictForNonKanjis(isCHS: isCHS)
    arrStructUnified += rawDictForPhrases(isCHS: isCHS)
    // 計算權重且排序
    arrStructUnified = SortEntry(arrStructUnified, isCHS: isCHS)
    
    for entry in arrStructUnified {
        strPrintLine += entry.valPhrase + " " + String(entry.valCount) + " " + entry.valPhone + "\n"
    }
    NSLog(" - \(i18n): 要寫入 TSI 檔案的內容編譯完畢。")
    do {
        try strPrintLine.write(to: pathOutput, atomically: false, encoding: .utf8)
    }
    catch {
        NSLog(" - \(i18n): Error on writing strings to file: \(error)")
    }
    NSLog(" - \(i18n): 寫入完成。")
}

// MARK: - 主执行绪
if CommandLine.arguments.count > 1 {
    ensureOutputFolder()
    if CommandLine.arguments[1] == "chs" {
        NSLog("// 準備編譯簡體中文 CIN 檔案-標準集。")
        fileOutputCIN(isCHS: true)
        NSLog("// 準備編譯簡體中文 CIN 檔案-全字庫。")
        fileOutputCIN(isCHS: true, isCNS: true)
        NSLog("// 準備編譯簡體中文 TSI 檔案。")
        fileOutputTSI(isCHS: true)
    }
    if CommandLine.arguments[1] == "cht" {
        NSLog("// 準備編譯繁體中文 CIN 檔案-標準集。")
        fileOutputCIN(isCHS: false)
        NSLog("// 準備編譯繁體中文 CIN 檔案-全字庫。")
        fileOutputCIN(isCHS: false, isCNS: true)
        NSLog("// 準備編譯繁體中文 TSI 檔案。")
        fileOutputTSI(isCHS: false)
    }
}
