// (c) 2021 and onwards The vChewing Project (BSD-3-Clause).
// ====================
// This code is released under the SPDX-License-Identifier: `BSD-3-Clause`.

import Foundation

enum ShellHelper {
  /// Executes a shell command and returns the output and exit code
  static func shell(_ command: String) -> (output: String, exitCode: Int32) {
    let task = Process()
    let pipe = Pipe()

    task.standardOutput = pipe
    task.standardError = pipe
    task.arguments = ["-c", command]
    task.executableURL = URL(fileURLWithPath: "/bin/bash")

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
    task.arguments = ["-c", command]
    task.executableURL = URL(fileURLWithPath: "/bin/bash")

    // Set the environment with the specified PATH
    var environment = ProcessInfo.processInfo.environment
    environment["PATH"] = path
    task.environment = environment

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
