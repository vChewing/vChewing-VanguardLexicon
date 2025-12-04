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

  /// Executes a shell command and returns the output and exit code
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
      // Keep compatibility for scripts but discourage use. Use `exec` for
      // explicit executable + args invocation instead of `shell`.
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

  /// Executes a shell command with a specific PATH environment and returns the output and exit code
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

  /// Executes an executable directly with arguments (no shell parsing).
  /// If `path` is provided it will be used as PATH env var for resolution.
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
      // Try to execute the provided executable directly. If `executable` is a
      // PowerShell snippet or a command, the caller should call PowerShell
      // directly; however for our case we expect an EXE path (or name) and args.
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

  /// Find an executable by searching PATH (or provided path). Returns absolute path or nil.
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
    // fallback: check common locations
    let fallbackCandidates = ["/usr/bin/\(name)", "/bin/\(name)", "/usr/local/bin/\(name)"]
    for c in fallbackCandidates {
      if FileManager.default.isExecutableFile(atPath: c) { return c }
    }
    return nil
  }

  /// Throws an exception with the specified error message and exits
  static func throwError(_ message: String) throws -> Never {
    print("Error: \(message)")
    throw VCDataBuilder.Exception.errMsg(message)
  }

  /// Compare version strings
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
