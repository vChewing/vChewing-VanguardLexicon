// (c) 2021 and onwards The vChewing Project (BSD-3-Clause).
// ====================
// This code is released under the SPDX-License-Identifier: `BSD-3-Clause`.

import Foundation
import LibVanguardChewingData

// MARK: - Main

@main
struct Main {
  static func main() async throws {
    let helpString = """
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
      chewingCBasedCHS  - 新酷音輸入法引擎（0.5.1 為止的 C 語言版專用，簡體中文）
      chewingCBasedCHT  - 新酷音輸入法引擎（0.5.1 為止的 C 語言版專用，繁體中文）
      mcbopomofoCHS     - 小麥注音輸入法（簡體中文）// 不支援 PIME 版本
      mcbopomofoCHT     - 小麥注音輸入法（繁體中文）// 不支援 PIME 版本
      vanguardSQLLegacy - vChewing 舊版格式（vChewing 3.x 後期 SQLite 格式）

    注意：
      1. chewingCBasedCHS 與 chewingCBasedCHT 的建置僅可以在下述系統內執行：
           - macOS 10.15 以上（Intel 或 Apple Silicon）
           - Linux（僅 x86_64）
           - Windows NT 10.0 以上（僅 x86_64）
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
    """

    let args = CommandLine.arguments.dropFirst(1).map { $0 }
    guard !args.isEmpty else {
      print(helpString)
      exit(1)
    }

    var cases = [VCDataBuilder.BuilderType]()
    let parsedCases = args.compactMap { VCDataBuilder.BuilderType(rawValue: $0) }

    switch args.map(\.localizedLowercase) {
    case ["all"]:
      cases = VCDataBuilder.BuilderType.allCases
    case _ where !parsedCases.isEmpty:
      cases = Array(Set(parsedCases))
    default:
      print("錯誤：無效的參數。請使用 --help 查看使用說明。")
      print(helpString)
      exit(1)
    }

    print("開始建置資料……")
    do {
      for builderType in cases {
        try await builderType.compile()
      }
    } catch {
      NSLog("!! 建置失敗，被迫中斷。")
      switch error {
      case let VCDataBuilder.Exception.errMsg(msg):
        print(msg)
      case let VCDataBuilder.Exception.healthCheckException(msgArray):
        msgArray.forEach { print($0) }
      default:
        print(error)
      }
      exit(1)
    }
    print("建置完成。")
  }
}
