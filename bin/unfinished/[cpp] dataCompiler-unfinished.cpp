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
#include <string>
#include <syslog.h>

# pragma mark - Basic Functions and Structure

std::string readFileIntoString(const std::string& path) {
    std::ifstream input_file(path);
    if (!input_file.is_open()) {
        std::cerr << "Could not open the file - '"
        << path << "'" << std::endl;
        exit(EXIT_FAILURE);
    }
    return std::string((std::istreambuf_iterator<char>(input_file)), std::istreambuf_iterator<char>());
}

// using convert_type = std::codecvt_utf8<wchar_t>;
// std::wstring_convert<convert_type, wchar_t> converter;

struct Entry {
    std::string valPhone = "";
    std::string valPhrase = "";
    float valWeight = -1.0;
    unsigned int valCount = 0;
};


# pragma mark - Constants

const char* url_CHS_Custom = "../../components/chs/phrases-custom-chs.txt";
const char* url_CHS_MCBP = "../../components/chs/phrases-mcbp-chs.txt";
const char* url_CHS_MOE = "../../components/chs/phrases-moe-chs.txt";
const char* url_CHS_VCHEW = "../../components/chs/phrases-vchewing-chs.txt";

const char* url_CHT_Custom = "../../components/cht/phrases-custom-cht.txt";
const char* url_CHT_MCBP = "../../components/cht/phrases-mcbp-cht.txt";
const char* url_CHT_MOE = "../../components/cht/phrases-moe-cht.txt";
const char* url_CHT_VCHEW = "../../components/cht/phrases-vchewing-cht.txt";

const char* urlKanjiCore = "../../components/common/char-kanji-core.txt";
const char* urlPunctuation = "../../components/common/data-punctuations.txt";
const char* urlMiscBPMF = "../../components/common/char-misc-bpmf.txt";
const char* urlMiscNonKanji = "../../components/common/char-misc-nonkanji.txt";

const char* urlOutputCHS = "./data-chs.txt";
const char* urlOutputCHT = "./data-cht.txt";

# pragma mark - Functions

std::vector<std::string> lineBleacher(std::string path, std::vector<std::string> vec) {
    std::string strIncoming = readFileIntoString(path);
    std::string strBuffer = "";
    strIncoming = std::regex_replace(strIncoming, std::regex("( +|　+| +|\\t+)+"), " "); // Space Concatenation
    strIncoming = std::regex_replace(strIncoming, std::regex("(^ | $)"), ""); // 去除行尾行首空格
    strIncoming = std::regex_replace(strIncoming, std::regex("(\\f+|\\r+|\\n+)+"), "\n"); // CR & Form Feed to LF, 且去除重複行
    strIncoming = std::regex_replace(strIncoming, std::regex("^(#.*|.*#WIN32.*)$\n"), ""); // 以#開頭的行都淨空 & 去掉所有 WIN32 特有的行
    std::stringstream strStream(strIncoming);    
    while(std::getline(strStream, strBuffer, '\n')){
        vec.push_back(strBuffer);
    }
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
