// (c) 2021 and onwards The vChewing Project (MulanPSL-2.0 License).
// ====================
// This code is released under the SPDX-License-Identifier: `MulanPSL-2.0`.

import Foundation
@testable import LibVanguardChewingData
import Testing

@Test
func testFindExecutableResolvesCommonSystemCommands() {
  #if os(Windows)
    // 在 Windows 上，系統應該存在 powershell.exe
    let pwshPath = ShellHelper.findExecutable("powershell.exe", path: ProcessInfo.processInfo.environment["PATH"]) ?? ""
    #expect(!pwshPath.isEmpty)
  #else
    // 在 Darwin/Linux 上應該有 `swiftc` 或 `sh`。先嘗試 'swiftc'，後備方案是 'sh'。
    var found = ShellHelper.findExecutable("swiftc", path: ProcessInfo.processInfo.environment["PATH"]) != nil
    if !found { found = ShellHelper.findExecutable("sh", path: ProcessInfo.processInfo.environment["PATH"]) != nil }
    #expect(found)
  #endif
}
