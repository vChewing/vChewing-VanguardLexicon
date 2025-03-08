// (c) 2021 and onwards The vChewing Project (BSD-3-Clause).
// ====================
// This code is released under the SPDX-License-Identifier: `BSD-3-Clause`.

import Foundation

// MARK: - VCDataBuilder.Exception

extension VCDataBuilder {
  public enum Exception: Error {
    case errMsg(String)
  }
}

extension String {
  fileprivate static let bpmfReplacements4Encryption: [Character: Character] = [
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

  fileprivate static let bpmfReplacements4Decryption: [Character: Character] = [
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
    return String(map { Self.bpmfReplacements4Encryption[$0] ?? $0 })
  }

  var asDecryptedBopomofoKeyChain: String {
    guard first != "_" else { return self }
    return String(map { Self.bpmfReplacements4Decryption[$0] ?? $0 })
  }
}
