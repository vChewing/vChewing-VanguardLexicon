// (c) 2021 and onwards The vChewing Project (BSD-3-Clause).
// ====================
// This code is released under the SPDX-License-Identifier: `BSD-3-Clause`.

import Foundation
@testable import LibVanguardChewingData
import Testing

@Test
func testExecDoesNotInterpretMetaCharacters() {
  #if os(Windows)
    // 在 Windows 上執行 powershell 並確保引數以字面形式傳遞。
    // Windows 10 附帶 Powershell v5，但可執行檔路徑仍為 v1.0：
    let cmd = ShellHelper.exec(
      "C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\powershell.exe",
      args: ["-NoProfile", "-Command", "Write-Output '; echo INJECTION'"]
    )
    #if canImport(Foundation)
      // 輸出應包含字串字面值，包括 '; echo INJECTION'
      #expect(cmd.exitCode == 0)
      #expect(cmd.output.trimmingCharacters(in: .whitespacesAndNewlines).contains("; echo INJECTION"))
    #endif
  #else
    // 在 Unix 上，/bin/echo 將第一個引數視為字面值；如果使用 shell '-c'，';' 可能會成為運算子。
    let cmd = ShellHelper.exec("/bin/echo", args: ["; echo INJECTION"]) // 包含分號的引數
    #expect(cmd.exitCode == 0)
    // 輸出應該是字面引數，而非執行 `echo INJECTION` 作為單獨的命令。
    #expect(cmd.output.trimmingCharacters(in: .whitespacesAndNewlines) == "; echo INJECTION")
  #endif
}
