// (c) 2021 and onwards The vChewing Project (BSD-3-Clause).
// ====================
// This code is released under the SPDX-License-Identifier: `BSD-3-Clause`.

import Foundation
@testable import LibVanguardChewingData
import Testing

@Test
func testFindExecutableResolvesCommonSystemCommands() {
  #if os(Windows)
    // On Windows, powershell.exe should exist on the system
    let pwshPath = ShellHelper.findExecutable("powershell.exe", path: ProcessInfo.processInfo.environment["PATH"]) ?? ""
    assert(!pwshPath.isEmpty)
  #else
    // On Darwin/Linux `swiftc` or `sh` should be present. Try 'swiftc' first, fallback to 'sh'.
    var found = ShellHelper.findExecutable("swiftc", path: ProcessInfo.processInfo.environment["PATH"]) != nil
    if !found { found = ShellHelper.findExecutable("sh", path: ProcessInfo.processInfo.environment["PATH"]) != nil }
    assert(found)
  #endif
}
