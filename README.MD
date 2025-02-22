# 威注音输入法语汇库

## 简介

威注音输入法的语料库，目前仍在完善中。

## 组译方法

针对以下组译对象的组译过程均需要 swift 脚本支援，且 swift 版本不小于 5.5。<br />理想状态就是至少 macOS Catalina 且安装了带有对应版本 swift 支援的 Xcode 命令列工具。

Linux 系统的话，请注意两个先决条件：
1. 洽 [swiftlygo.xyz](https://swiftlygo.xyz/) 网站提供的指引、来安装 Swift 语言。
2. 安装最新 Rust 稳定版之后、通过 `cargo install chewing-cli` 命令安装 chewing-cli。

- Ubuntu / Debian 的话，可以直接跑 `make deploy-swift-env-linux` 来完成 Swift 的安装。
	- Deepin 20 也可以。之后 Deepin 要是脱离 Debian 的话就难讲了。

------

- 针对威注音 macOS 版组译核心语汇库：
    - `make macv` 直接生成核心词库档案 data-chs.txt 与 data-cht.txt。
    - `make install` 直接将生成的核心词库档案部署到当前系统安装的威注音输入法内（会破坏 app 签名，但会自动申请 gatekeeper 绕行）。
- 针对 libchewing 新酷音引擎组译其原始语料档案：
    - 系统内需要有最新稳定版的 Swift 语言与 Rust 语言。（后者乃 chewing-cli 所需。）
    - 根据当前系统与 CPU 种类，事先执行 `make prepare-macos` 或者 `prepare-linux-amd64` 以部署工具链。
    - 之后再：
        - `make libv-chs` 直接生成简体中文版 tsi.src、phone.cin 及 phone.cin-CNS11643-complete.patch。
            - 同时会在 ./Build/Release/LibChewing-CHS 目录下生成可以给任何平台的新酷音输入法使用的 dictionary.dat 与 index_tree.dat 这两个资料库档案。
        - `make libv-cht` 直接生成繁体中文版 tsi.src、phone.cin 及 phone.cin-CNS11643-complete.patch。
            - 同时会在 ./Build/Release/LibChewing-CHT 目录下生成可以给任何平台的新酷音输入法使用的 dictionary.dat 与 index_tree.dat 这两个资料库档案。
    - 使用这些生成的档案来完成 libchewing 自身的组译工作。
        - 如果您的 libchewing 本地克隆体存放在 `~/Repos/libchewing` 资料夹内的话，您还可以用 `make debug` 快速测试这些档案的合规性。
            - 比如 `make libv-cht debug` 就一条龙组译＋单元测试。
	- Windows 平台编译要求至少 Windows 10 且需要用 WSL (Debian 或 Ubuntu) 来按照上文的方法安装 Swift 支援（生成的档案倒是可以给 Windows 版新酷音使用）。不然的话，Windows 单独安装 Swift 编译起来会非常麻烦，你还得去安装硕大的 Visual Studio 和 Windows SDK。
		- 其实也不是没考虑过 C#，但 C# 对 .net framework 的版本一致性、以及 Windows 不原生具备对 C# 脚本的支援，这些都是头痛点。
- 针对 FCITX5 平台的小麦注音（fcitx5-mcbopomofo）编译其核心语汇库（不包含注音文与绘文字符号支援）：
    - `make fcitx5-chs` 直接生成简体中文版 mcbopomofo-data.txt。
    - `make fcitx5-cht` 直接生成繁体中文版 mcbopomofo-data.txt。
    - 以上 `mcbopomofo-data.txt` 得直接放在 `/usr/share/fcitx5/data/` 内。
        - 如果是要对输入法仓库开刀的话，要取代的档案会是 `./data/data.txt`。
    - 虽然也能拿给 macOS 版小麦注音使用，但 [macOS 版威注音输入法更香](https://gitee.com/vchewing/vChewing-macOS)。
    - 如果是针对此目标编译了威注音词库、却发现 FCITX5 小麦输入法变得无法使用的话，请考虑重新编译输入法、对输入法源码做个改动：
        - `src/Engine/ParselessLM.cpp`：检索 `/*validate_pragme=*/` 这句所在的行，且将其下一行的 true 改成 false。
- 针对 RIME 平台的编译，**暂时想不明白该怎么去支持**，因为下述原因：
    - RIME 原厂的八股文资料库仅支援康熙繁体，而威注音的繁体中文词库是台湾繁体。
    - RIME 哪怕是自订八股文词库、也无法针对同一个词的不同的词语读音设立不同的频次。

## 来由

世间原本只有一款原生简体中文注音输入法，就是自 2007 版以来至今的微软新注音（虽然 Windows 8 内建的新注音暂时移除了这个功能）。但是呢？微软拖了十四年都故意不去修正这个输入法的简体中文模式敲不了「略」「虐」音。而且 macOS 平台也是需要原生的简体中文注音输入法的。能够打繁出简的雅虎奇摩注音到现在仍是不死小强，但注定是只能活在 Intel Mac 时代。

眼下空谈新的解决方案的话未免太假掰，先从一个中立语汇库开始着手吧。

## 资料收录宗旨

中国大陆、台澎金马、新加坡的读音都会收录，以方便这些市场的使用者们都能够受益于任何使用了该资料库的输入法。

## 资料来源

原厂词库主要词语资料来源：

- 《重编国语辞典修订本 2015》的六字以内的词语资料 (CC BY-ND 3.0)。
- 《CNS11643中文标准交换码全字库(简称全字库)》 (OGDv1 License)。
- LibTaBE (by Pai-Hsiang Hsiao under 3-Clause BSD License)。
- [《新加坡华语资料库》](https://www.languagecouncils.sg/mandarin/ch/learning-resources/singaporean-mandarin-database)。
- 原始词频资料取自 NAER，有经过换算处理与按需调整。
    - 威注音并未使用由 LibTaBE 内建的来自 Sinica 语料库的词频资料。
- 威注音语汇库作者自行维护新增的词语资料，包括：
    - 尽可能所有字词的陆规审音与齐铁恨广播读音。
    - 中国大陆常用资讯电子术语等常用语，以确保简体中文母语者在使用输入法时不会受到审音差异的困扰。
- 其他使用者建议收录的资料。

部分读音资料来源：

- 通用规范汉字表：http://unicode.org/L2/L2019/19160-adding-ktghz-2013.pdf
- 《〈国语一字多音审订表〉读音适用性与现况之研究》：http://ntcuir.ntcu.edu.tw/bitstream/987654321/7327/1/096NTCTC461009-001.pdf

语料库资料来源：

仅抓取被通用规范汉字表收录的汉字、及其对应的台湾繁体汉字的字频。但不一定会被实际套用。特别是新闻报纸类的文章当中的字频数据严重缺乏一些口语交流用字的字频优先权重。

- 新华教育部语言文字应用研究所计算语言学研究室：http://corpus.zhonghuayuwen.org/
- 「国教院」语料库覆盖率统计系统：https://coct.naer.edu.tw/tools/

## 授权

3-Clause BSD License：https://opensource.org/licenses/BSD-3-Clause

注一：该仓库的 Swift 脚本编译系统虽有对新酷音词库格式的支持，却并未使用新酷音的字词库与频率语料，故不受其 LGPLv2 协议之约束。

注二：该仓库随赠一套 LibChewing 酷音输入法引擎的辞典编译程式「init_database」的修改版本（可以辨识高于 65535 的词频资料），方便大陆使用者「哪怕无法存取 GitHub、也能编译出用于新酷音的词库档案」。这套档案继承酷音输入法引擎的授权「LGPL 2.1」。另外，这个 binary 仅针对以 C 语言写就的新酷音引擎。至于以 Rust 写就的新酷音引擎所需要的档案，敝仓库也会同时正常建置、且建置过程不依赖这个 binary。

$ EOF.
