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
      chewingRustCHS    - 新酷音輸入法引擎（0.6.0 開始的 Rust 語言版專用，簡體中文）
      chewingRustCHT    - 新酷音輸入法引擎（0.6.0 開始的 Rust 語言版專用，繁體中文）
      chewingCBasedCHS  - 新酷音輸入法引擎（0.5.1 為止的 C 語言版專用，簡體中文）
      chewingCBasedCHT  - 新酷音輸入法引擎（0.5.1 為止的 C 語言版專用，繁體中文）
      mcbopomofoCHS     - 小麥注音輸入法（簡體中文）// 不支援 PIME 版本
      mcbopomofoCHT     - 小麥注音輸入法（繁體中文）// 不支援 PIME 版本
      vanguardSQLLegacy - vChewing 舊版格式（vChewing 3.x 後期 SQLite格式）

    注意：
      chewingCBasedCHS 與 chewingCBasedCHT 的建置僅可以在下述系統內執行：
        - macOS 10.15 以上（Intel 或 Apple Silicon）
        - Linux（僅 x86_64）
        - Windows NT 10.0 以上（僅 x86_64）
      除非迫不得已，否則請改用以 Rust 語言寫就的次世代新酷音輸入法引擎。
      另外，chewingRustCHS 與 chewingRustCHT 在 Windows 系统下请使用 WSL 环境建置。

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
    // 移除這行，避免重複編譯
    // try await VCDataBuilder.BuilderType.vanguardSQLLegacy.compile()
    for builderType in cases {
      print("正在編譯：\(builderType.rawValue)")
      try await builderType.compile()
    }
    print("建置完成。")
  }
}
