// (c) 2021 and onwards The vChewing Project (BSD-3-Clause).
// ====================
// This code is released under the SPDX-License-Identifier: `BSD-3-Clause`.

import Foundation

enum ShellHelper {
  static func normalizePathForCurrentOS(_ path: String) -> String {
    #if os(Windows)
      return path.replacingOccurrences(of: "/", with: "\\")
    #else
      return path
    #endif
  }

  /// 執行 shell 命令並返回輸出和退出代碼
  static func shell(_ command: String) -> (output: String, exitCode: Int32) {
    let task = Process()
    let pipe = Pipe()

    task.standardOutput = pipe
    task.standardError = pipe

    #if os(Windows)
      task
        .executableURL =
        URL(fileURLWithPath: "C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\powershell.exe")
      // 使用 -NoProfile 來加速啟動，使用 -Command 來執行命令
      task.arguments = ["-NoProfile", "-Command", command]
    #else
      // 為了與腳本保持相容性而保留，但不建議使用。應使用 `exec` 明確指定可執行檔案與引數，而非使用 `shell`。
      task.executableURL = URL(fileURLWithPath: "/bin/bash")
      task.arguments = ["-c", command]
    #endif

    do {
      try task.run()
    } catch {
      print("Error: \(error.localizedDescription)")
      return ("", 1)
    }

    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    let output = String(data: data, encoding: .utf8) ?? ""

    task.waitUntilExit()
    return (output, task.terminationStatus)
  }

  /// 使用特定的 PATH 環境變數執行 shell 命令並返回輸出和退出代碼
  static func shellWithPath(_ command: String, path: String) -> (output: String, exitCode: Int32) {
    let task = Process()
    let pipe = Pipe()

    task.standardOutput = pipe
    task.standardError = pipe

    #if os(Windows)
      task
        .executableURL =
        URL(fileURLWithPath: "C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\powershell.exe")
      // 設定 PATH 環境變數並執行命令
      let pathCmd = "$env:PATH = '" + normalizePathForCurrentOS(path) + "'; " + command
      task.arguments = ["-NoProfile", "-Command", pathCmd]
    #else
      task.executableURL = URL(fileURLWithPath: "/bin/bash")
      task.arguments = ["-c", command]

      var environment = ProcessInfo.processInfo.environment
      environment["PATH"] = path
      task.environment = environment
    #endif

    do {
      try task.run()
    } catch {
      print("Error: \(error.localizedDescription)")
      return ("", 1)
    }

    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    let output = String(data: data, encoding: .utf8) ?? ""

    task.waitUntilExit()
    return (output, task.terminationStatus)
  }

  /// 直接執行可執行檔案並傳遞引數（不經過 shell 解析）。
  /// 如果提供了 `path` 參數，將用作 PATH 環境變數進行解析。
  static func exec(
    _ executable: String,
    args: [String] = [],
    path: String? = nil,
    environment: [String: String]? = nil
  )
    -> (output: String, exitCode: Int32) {
    let task = Process()
    let pipe = Pipe()

    task.standardOutput = pipe
    task.standardError = pipe

    #if os(Windows)
      // 嘗試直接執行提供的可執行檔案。如果 `executable` 是 PowerShell 程式碼片段或命令，
      // 呼叫者應該直接呼叫 PowerShell；然而對於我們的情況，我們期望的是 EXE 路徑（或名稱）和引數。
      task.executableURL = URL(fileURLWithPath: executable)
      task.arguments = args
    #else
      task.executableURL = URL(fileURLWithPath: executable)
      task.arguments = args
    #endif

    var env = ProcessInfo.processInfo.environment
    if let environment = environment {
      for (k, v) in environment { env[k] = v }
    }
    if let p = path { env["PATH"] = p }
    task.environment = env

    do {
      try task.run()
    } catch {
      print("Error: \(error.localizedDescription)")
      return ("", 1)
    }

    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    let output = String(data: data, encoding: .utf8) ?? ""

    task.waitUntilExit()
    return (output, task.terminationStatus)
  }

  /// 透過搜尋 PATH（或提供的路徑）來尋找可執行檔案。返回絕對路徑或 nil。
  static func findExecutable(_ name: String, path: String? = nil) -> String? {
    let defaultPath = "/usr/bin:/bin:/usr/local/bin"
    let searchPath = (path ?? ProcessInfo.processInfo.environment["PATH"]) ??
      ProcessInfo.processInfo.environment["PATH"] ?? defaultPath
    #if os(Windows)
      let parts = searchPath.split(separator: ";").map(String.init)
    #else
      let parts = searchPath.split(separator: ":").map(String.init)
    #endif
    for p in parts {
      let candidate = URL(fileURLWithPath: p).appendingPathComponent(name).path
      if FileManager.default.isExecutableFile(atPath: candidate) { return candidate }
    }
    // 後備方案：檢查常見位置
    let fallbackCandidates = ["/usr/bin/\(name)", "/bin/\(name)", "/usr/local/bin/\(name)"]
    for c in fallbackCandidates {
      if FileManager.default.isExecutableFile(atPath: c) { return c }
    }
    return nil
  }

  /// 拋出帶有指定錯誤訊息的例外並退出
  static func throwError(_ message: String) throws -> Never {
    print("Error: \(message)")
    throw VCDataBuilder.Exception.errMsg(message)
  }

  /// 比較版本字串
  static func compareVersions(_ version1: String, _ version2: String) -> ComparisonResult {
    let v1Components = version1.components(separatedBy: ".")
    let v2Components = version2.components(separatedBy: ".")

    let maxLength = max(v1Components.count, v2Components.count)

    for i in 0 ..< maxLength {
      let v1 = i < v1Components.count ? Int(v1Components[i]) ?? 0 : 0
      let v2 = i < v2Components.count ? Int(v2Components[i]) ?? 0 : 0

      if v1 > v2 {
        return .orderedDescending
      } else if v1 < v2 {
        return .orderedAscending
      }
    }

    return .orderedSame
  }
}
