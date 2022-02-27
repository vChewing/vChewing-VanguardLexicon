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

#include <sstream>
#include <fstream>
#include <codecvt>
#include <regex>
#include <iostream>

#include <syslog.h>

# pragma mark - Basic Functions and Structure

std::string replace_all(
    std::string& s,
    std::string const& toReplace,
    std::string const& replaceWith
) {
    std::ostringstream oss;
    std::size_t pos = 0;
    std::size_t prevPos = pos;
    
    while (true) {
        prevPos = pos;
        pos = s.find(toReplace, pos);
        if (pos == std::string::npos)
            break;
        oss << s.substr(prevPos, pos - prevPos);
        oss << replaceWith;
        pos += toReplace.size();
    }
    
    oss << s.substr(prevPos);
    return oss.str();
}

std::string readFile(const char* filename)
{
    std::ifstream strInput(filename);
    strInput.imbue(std::locale(std::locale(), new std::codecvt_utf8<wchar_t>));
    std::stringstream strString;
    strString << strInput.rdbuf();
    return strString.str();
}

using convert_type = std::codecvt_utf8<wchar_t>;
std::wstring_convert<convert_type, wchar_t> converter;

struct Entry {
    std::string valPhone = "";
    std::string valPhrase = "";
    float valWeight = -1.0;
    unsigned int valCount = 0;
};


# pragma mark - Constants

const char* url_CHS_Custom = "../Source/Data/components/chs/phrases-custom-chs.txt";
const char* url_CHS_MCBP = "../Source/Data/components/chs/phrases-mcbp-chs.txt";
const char* url_CHS_MOE = "../Source/Data/components/chs/phrases-moe-chs.txt";
const char* url_CHS_VCHEW = "../Source/Data/components/chs/phrases-vchewing-chs.txt";

const char* url_CHT_Custom = "../Source/Data/components/cht/phrases-custom-cht.txt";
const char* url_CHT_MCBP = "../Source/Data/components/cht/phrases-mcbp-cht.txt";
const char* url_CHT_MOE = "../Source/Data/components/cht/phrases-moe-cht.txt";
const char* url_CHT_VCHEW = "../Source/Data/components/cht/phrases-vchewing-cht.txt";

const char* urlKanjiCore = "../Source/Data/components/common/char-kanji-core.txt";
const char* urlPunctuation = "../Source/Data/components/common/data-punctuations.txt";
const char* urlMiscBPMF = "../Source/Data/components/common/char-misc-bpmf.txt";
const char* urlMiscNonKanji = "../Source/Data/components/common/char-misc-nonkanji.txt";

const char* urlOutputCHS = "./data-chs.txt";
const char* urlOutputCHT = "./data-cht.txt";

# pragma mark - Functions

std::vector<std::string> lineBleacher(std::string path, std::vector<std::string> vec) {
    std::ifstream fstr(path);
    while(!fstr.eof()) {
        std::string fstrBuffer;
        getline(fstr, fstrBuffer);
        // 預處理格式
        fstrBuffer = replace_all(fstrBuffer, " #MACOS", ""); // 去掉 macOS 標記
        fstrBuffer = replace_all(fstrBuffer, "　", " "); // CJKWhiteSpace (\x{3000}) to ASCII Space
        fstrBuffer = replace_all(fstrBuffer, " ", " "); // NonBreakWhiteSpace (\x{A0}) to ASCII Space
        fstrBuffer = replace_all(fstrBuffer, "\t", " "); // Tab to ASCII Space
        fstrBuffer = std::regex_replace(fstrBuffer, std::regex("\\f"), "\n"); // Form Feed to LF
        fstrBuffer = replace_all(fstrBuffer, "\r", "\n"); // CR to LF
        fstrBuffer = std::regex_replace(fstrBuffer, std::regex(" +"), " "); // 統整連續空格為一個 ASCII 空格
        fstrBuffer = std::regex_replace(fstrBuffer, std::regex("\\n+"), "\n"); // 統整連續 LF 為一個 LF
        fstrBuffer = std::regex_replace(fstrBuffer, std::regex(" $"), ""); // 去除行尾空格
        fstrBuffer = std::regex_replace(fstrBuffer, std::regex("^ "), ""); // 去除行首空格
        fstrBuffer = std::regex_replace(fstrBuffer, std::regex("^#.*"), ""); // 以#開頭的行都淨空
        fstrBuffer = std::regex_replace(fstrBuffer, std::regex(".*#WIN32.*"), ""); // 去掉所有 WIN32 特有的行
        vec.push_back(fstrBuffer);
    }
    fstr.close();
    return vec;
}

void rawDictForPhrases(bool isCHS) {
    // 讀取內容
    const char* i18n = isCHS ? "簡體中文" : "繁體中文";
    std::string stringPipe = "";
    std::vector<std::string> vecRawAll;
    lineBleacher(isCHS ? url_CHS_Custom : url_CHT_Custom, vecRawAll);
    lineBleacher(isCHS ? url_CHS_MCBP : url_CHT_MCBP, vecRawAll); 
    lineBleacher(isCHS ? url_CHS_MOE : url_CHT_MOE, vecRawAll);
    lineBleacher(isCHS ? url_CHS_VCHEW : url_CHT_VCHEW, vecRawAll);
    vecRawAll.erase(unique(vecRawAll.begin(), vecRawAll.end()), vecRawAll.end()); // 去重複。
    syslog(LOG_CONS, " - %s: 成功生成詞語語料辭典（權重待計算）。", i18n);
    printf(" - %s: 成功生成詞語語料辭典（權重待計算）。\n", i18n);
    // 預處理格式

}

int main()
{
    printf("// 準備編譯繁體中文核心語料檔案。\n");
    rawDictForPhrases(true);
}


