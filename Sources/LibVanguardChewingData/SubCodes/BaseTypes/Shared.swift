// (c) 2021 and onwards The vChewing Project (BSD-3-Clause).
// ====================
// This code is released under the SPDX-License-Identifier: `BSD-3-Clause`.

import Foundation

// MARK: - VCDataBuilder.Exception

extension VCDataBuilder {
  public enum Exception: Error {
    case errMsg(String)
    case healthCheckException([String])
    case invalidPhraseFormat(file: String, line: String, reason: String)
  }
}

// MARK: - VCDataBuilder.Exception + LocalizedError

extension VCDataBuilder.Exception: LocalizedError {
  public var errorDescription: String? {
    switch self {
    case let .errMsg(msg):
      return msg
    case let .healthCheckException(msgs):
      return "Health check failed:\n" + msgs.joined(separator: "\n")
    case let .invalidPhraseFormat(file, line, reason):
      return """
      ❌ Invalid phrase format in file '\(file)':
      Line content: \(line)
      Error: \(reason)

      Please ensure all phrase entries follow the format: 詞語 頻次 讀音串
      (Word, frequency number, pronunciation chain)
      """
    }
  }
}

extension String {
  fileprivate static let bpmfReplacements4Encryption: [Unicode.Scalar: Unicode.Scalar] = [
    "ㄅ": "b", "ㄆ": "p", "ㄇ": "m", "ㄈ": "f", "ㄉ": "d",
    "ㄊ": "t", "ㄋ": "n", "ㄌ": "l", "ㄍ": "g", "ㄎ": "k",
    "ㄏ": "h", "ㄐ": "j", "ㄑ": "q", "ㄒ": "x", "ㄓ": "Z",
    "ㄔ": "C", "ㄕ": "S", "ㄖ": "r", "ㄗ": "z", "ㄘ": "c",
    "ㄙ": "s", "ㄧ": "i", "ㄨ": "u", "ㄩ": "v", "ㄚ": "a",
    "ㄛ": "o", "ㄜ": "e", "ㄝ": "E", "ㄞ": "B", "ㄟ": "P",
    "ㄠ": "M", "ㄡ": "F", "ㄢ": "D", "ㄣ": "T", "ㄤ": "N",
    "ㄥ": "L", "ㄦ": "R", "ˊ": "2", "ˇ": "3", "ˋ": "4",
    "˙": "5",
  ]

  fileprivate static let bpmfReplacements4Decryption: [Unicode.Scalar: Unicode.Scalar] = [
    "b": "ㄅ", "p": "ㄆ", "m": "ㄇ", "f": "ㄈ", "d": "ㄉ",
    "t": "ㄊ", "n": "ㄋ", "l": "ㄌ", "g": "ㄍ", "k": "ㄎ",
    "h": "ㄏ", "j": "ㄐ", "q": "ㄑ", "x": "ㄒ", "Z": "ㄓ",
    "C": "ㄔ", "S": "ㄕ", "r": "ㄖ", "z": "ㄗ", "c": "ㄘ",
    "s": "ㄙ", "i": "ㄧ", "u": "ㄨ", "v": "ㄩ", "a": "ㄚ",
    "o": "ㄛ", "e": "ㄜ", "E": "ㄝ", "B": "ㄞ", "P": "ㄟ",
    "M": "ㄠ", "F": "ㄡ", "D": "ㄢ", "T": "ㄣ", "N": "ㄤ",
    "L": "ㄥ", "R": "ㄦ", "2": "ˊ", "3": "ˇ", "4": "ˋ",
    "5": "˙",
  ]

  var asEncryptedBopomofoKeyChain: String {
    guard first != "_" else { return self }
    var result = String()
    result.unicodeScalars.reserveCapacity(unicodeScalars.count)
    for scalar in unicodeScalars {
      result.unicodeScalars.append(Self.bpmfReplacements4Encryption[scalar] ?? scalar)
    }
    return result
  }

  var asDecryptedBopomofoKeyChain: String {
    guard first != "_" else { return self }
    var result = String()
    result.unicodeScalars.reserveCapacity(unicodeScalars.count)
    for scalar in unicodeScalars {
      result.unicodeScalars.append(Self.bpmfReplacements4Decryption[scalar] ?? scalar)
    }
    return result
  }
}

// MARK: - NSMutex

/// A simple NSMutex implementation using NSLock for macOS 10.9+ compatibility.
/// Provides thread-safe access to a wrapped value.
public final class NSMutex<Value>: @unchecked Sendable {
  // MARK: Lifecycle

  public init(_ value: Value) {
    self.storedValue = value
  }

  // MARK: Public

  public var value: Value {
    get {
      withLock { $0 }
    }
    set {
      withLock { $0 = newValue }
    }
  }

  /// Access the value with exclusive access (read and write).
  public func withLock<Result>(_ body: (inout Value) throws -> Result) rethrows -> Result {
    try lock.withLock { try body(&storedValue) }
  }

  /// Read the value with exclusive access (read-only).
  public func withLockRead<Result>(_ body: (Value) throws -> Result) rethrows -> Result {
    try lock.withLock { try body(storedValue) }
  }

  // MARK: Private

  nonisolated(unsafe) private var storedValue: Value
  private let lock = NSLock()
}
