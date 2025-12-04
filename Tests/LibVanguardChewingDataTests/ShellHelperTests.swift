// (c) 2021 and onwards The vChewing Project (BSD-3-Clause).
// ====================
// This code is released under the SPDX-License-Identifier: `BSD-3-Clause`.

import Foundation
@testable import LibVanguardChewingData
import Testing

@Test
func testExecDoesNotInterpretMetaCharacters() {
  #if os(Windows)
    // On Windows we run powershell and ensure argument literal is passed.
    // Windows 10 ships Powershell v5 but the executable path is still v1.0:
    let cmd = ShellHelper.exec(
      "C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\powershell.exe",
      args: ["-NoProfile", "-Command", "Write-Output '; echo INJECTION'"]
    )
    #if canImport(Foundation)
      // The output should contain the string literal including '; echo INJECTION'
      assert(cmd.exitCode == 0)
      assert(cmd.output.trimmingCharacters(in: .whitespacesAndNewlines).contains("; echo INJECTION"))
    #endif
  #else
    // On Unix, /bin/echo accepts first argument as literal; if we used shell '-c', the ';' might become operator.
    let cmd = ShellHelper.exec("/bin/echo", args: ["; echo INJECTION"]) // arg containing a semicolon
    assert(cmd.exitCode == 0)
    // The output should be the literal argument, not executing the `echo INJECTION` as a separate command.
    assert(cmd.output.trimmingCharacters(in: .whitespacesAndNewlines) == "; echo INJECTION")
  #endif
}
