# 先锋语料库 (Vanguard Corpus)

## 简介

先锋语料库是一套给包括唯音输入法在内的几款注音输入法准备的语料库。目前仍在完善中。

## 组译方法

> [!WARNING]
> 敝专案所支持的的目标建置格式当中的 VanguardTextMap 格式会因为 Git 的 CRLF / LF 自动转换行为而出现一些异常。这些异常并非不可逆转，但仍会带来一些管理层面上的麻烦。详见敝专案的 `./ValueAdds/Specs/VanguardTextMapSpec.md` 档案。

针对以下组译对象的组译过程均需要 swift 脚本支援，且 swift 版本不小于 5.10。除非你要支持非常老的 macOS 系统，否则最好使用至少 Swift 6.2。Windows 的话建议 Swift 6.3+。<br />理想状态就是至少 macOS Catalina 且安装了带有对应版本 swift 支援的 Xcode 命令列工具。

Linux 系统的话，请注意两个先决条件：
1. 洽 [swiftlygo.xyz](https://swiftlygo.xyz/) 网站提供的指引、来安装 Swift 语言。
    - 关于在 Linux / WinNT / macOS 系统下安装 Swift 语言的更通用的方法，请洽 [Swift 官方网站](https://www.swift.org/)。
2. 如果要建置給（0.6.1 版开始的以 Rust 语言写就的）新酷音輸入法使用的話，你得在安裝最新 Rust 稳定版之后、通过 `cargo install chewing-cli` 命令安装 chewing-cli。
    - 关于 Rust 语言的安装方法请洽 [Rust 官方网站](https://www.rust-lang.org/)。

------

目前整个仓库的建置代码已经全部重写。Makefile 目前的内容并未能反应该仓库的这次重写的变化，故只有下述三道命令可以正常使用：

- `make clean`
- `make lint`
- `make format`

本仓库的格式化往往是 `make lint; make format` 按照这个顺序一次性执行格式化操作。

如果要验证 `SMALL_TESTABLE_SAMPLE` 模式下的建置产物是否保持恆定，可以直接在仓库根目录运行：

- `./verify_tiny_sample_determinism.sh`

这道脚本会连续建置 `vanguardSQLLegacy`、`vanguardTriePlist`、`vanguardTrieSQL`、`vanguardTextMap` 各两次，并在比较时忽略 `_BUILD_TIMESTAMP` 这项刻意允许漂移的元资料；其余内容若有差异，会直接打印为 `DIFF`。

在使用本仓库时，请在仓库根目录下运行 `swift run`，会出现类似下述格式的使用说明：

```
    VCDataBuilder - 先鋒語料庫辭典建置工具。
    版本：2024.02.27

    VCDataBuilder 建置前的用法（請在建置辭典時注意當前目錄必須得是專案目錄）：
      swift run VCDataBuilder <type> [type2] [type3] ...
      swift run VCDataBuilder all

    VCDataBuilder 建置後的用法（請在建置辭典時注意當前目錄必須得是專案目錄）：
      VCDataBuilder <type> [type2] [type3] ...
      VCDataBuilder all

    可用的辭典建置目標：
      vanguardTrieSQL   - 先鋒引擎原廠辭典格式（Trie, SQLite）
      vanguardTriePlist - 先鋒引擎原廠辭典格式（Trie, Plist）
      chewingRustCHS    - 新酷音輸入法引擎（0.6.0 開始的 Rust 語言版專用，簡體中文）
      chewingRustCHT    - 新酷音輸入法引擎（0.6.0 開始的 Rust 語言版專用，繁體中文）
      chewingCBasedCHS  - 新酷音輸入法引擎（0.5.1 為止的 C 語言版專用，簡體中文，純 Swift 生成器）
      chewingCBasedCHT  - 新酷音輸入法引擎（0.5.1 為止的 C 語言版專用，繁體中文，純 Swift 生成器）
      mcbopomofoCHS     - 小麥注音輸入法（簡體中文）// 不支援 PIME 版本
      mcbopomofoCHT     - 小麥注音輸入法（繁體中文）// 不支援 PIME 版本
      vanguardSQLLegacy - vChewing 舊版格式（vChewing 3.x 後期 SQLite 格式）

    注意：
      1. chewingCBasedCHS 與 chewingCBasedCHT 現由本倉庫內的純 Swift 產生器直接生成
        `dictionary.dat` 與 `index_tree.dat`，不再依賴 precompiled `init_database` binary。
        除非迫不得已，否則請改用以 Rust 語言寫就的次世代新酷音輸入法引擎。
      2. chewingRustCHS 與 chewingRustCHT 在 Windows 系统下建置的話，
         需要事先安裝「TSF 版」新酷音輸入法、且版本至少 2024.10.1。
         已知該版 TSF 新酷音有同綑 chewing-cli 工具，該工具可以用來建置辭典。
         而敝倉庫會生成用以建置辭典的所有原始檔案格式（tsi.src 與 word.src）。
      3. Windows 系統下建置時需要注意：
           - 需要 PowerShell 5.1 或更高版本
           - 執行策略（Execution Policy）需要允許執行本地腳本
           - 建議使用管理員權限執行，以避免檔案權限問題。

    範例：
      // 給所有的建置目標全部建置一遍：
         VCDataBuilder all
      // 僅建置給新酷音輸入法引擎的 Rust 版（同時建置繁體中文與簡體中文）：
         VCDataBuilder chewingRustCHS chewingRustCHT
```

## 来由

世间原本只有一款原生简体中文注音输入法，就是自 2007 版以来至今的微软新注音（虽然 Windows 8 内建的新注音暂时移除了这个功能）。但是呢？微软从 2007 年开始拖到现在不去修正这个输入法的简体中文模式敲不了「略」「虐」音，导致这个模式根本就不堪用。而且 macOS 平台也是需要原生的简体中文注音输入法的。能够打繁出简的雅虎奇摩注音到现在仍是不死小强，但注定是只能活在 Intel Mac 时代。

先从一个中立语汇库开始着手吧。

## 资料收录宗旨

中国大陆、台澎金马、新加坡的读音都会收录，以方便这些市场的使用者们都能够受益于任何使用了该资料库的输入法。

## 资料来源

> 先鋒語料庫原則上拒收任何「會在法理上妨礙自身在全球傳播」的「與地緣政治及政治意識形態有關」的內容。如有發現相關內容的話，歡迎私下提報。

原厂词库主要词语资料来源：

- 《重编国语辞典修订本 2015》的六字以内的词语资料 (CC BY-ND 3.0)。
- 《CNS11643中文标准交换码全字库(简称全字库)》 (OGDv1 License)。
- LibTaBE (by Pai-Hsiang Hsiao under 3-Clause BSD License)。
- [《新加坡华语资料库》](https://www.languagecouncils.sg/mandarin/ch/learning-resources/singaporean-mandarin-database)。
- 原始词频资料取自 NAER，有经过换算处理与按需调整。
    - 先锋语料库并未使用由 LibTaBE 内建的来自 Sinica 语料库的词频资料。
- 先锋语料库作者自行维护新增的词语资料，包括：
    - 尽可能所有字词的陆规审音与齐铁恨广播读音。
    - 中国大陆常用资讯电子术语等常用语，以确保简体中文母语者在使用输入法时不会受到审音差异的困扰。
- 其他使用者建议收录的资料。

部分读音资料来源：

- 通用规范汉字表：http://unicode.org/L2/L2019/19160-adding-ktghz-2013.pdf
- 何佳儒《〈国语一字多音审订表〉读音适用性与现况之研究》。

语料库资料来源：

仅抓取被通用规范汉字表收录的汉字、及其对应的台湾繁体汉字的字频。但不一定会被实际套用。特别是新闻报纸类的文章当中的字频数据严重缺乏一些口语交流用字的字频优先权重。

- 新华教育部语言文字应用研究所计算语言学研究室：http://corpus.zhonghuayuwen.org/
- NAER 语料库覆盖率统计系统。

## 授权

3-Clause BSD License：https://opensource.org/licenses/BSD-3-Clause

注一：该仓库的 Swift 脚本编译系统虽有对新酷音词库格式的支持，却并未使用新酷音的字词库与频率语料，故不受其 LGPLv2 协议之约束。

注二：自 2026-04-14 起，`chewingCBasedCHS` 与 `chewingCBasedCHT` 所需的 `dictionary.dat` / `index_tree.dat` 由本仓库内的 Swift 产生器直接生成，已不再随附或依赖 `init_database` binary。

注三：VanguardTrieKit 以 LGPLv3 释出。本仓库内的 VanguardTrieKit 是从 LibVanguard 复制出来的个别档案的副本、且不包含对 SQLite API 的直接交互之部分。

$ EOF.
