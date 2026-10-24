// (c) 2025 and onwards The vChewing Project (MulanPSL-2.0 License).
// ====================
// This code is released under the SPDX-License-Identifier: `MulanPSL-2.0`.

import Foundation

// MARK: - SHA256

/// 純 Swift 之 SHA-256（FIPS 180-4）。
///
/// - Note: 不直接使用 `CryptoKit`：`CryptoKit` 僅存在於 Apple 平台，Linux 與 Windows
///   （WinNT）皆無此模組。本工具只拿雜湊當「檔案的穩定指紋」，自帶一份實作即可換取
///   三個平台一致，且不必為了一顆工具引入外部相依。
enum SHA256 {
  /// 以十六進位小寫回傳給定資料之 SHA-256。
  static func hexDigest(_ data: Data) -> String {
    digest(data).map { String(format: "%02x", $0) }.joined()
  }

  /// 以位元組陣列回傳給定資料之 SHA-256。
  static func digest(_ data: Data) -> [UInt8] {
    var working = [UInt8](data)
    let bitLength = UInt64(data.count) &* 8
    working.append(0x80)
    while working.count % 64 != 56 { working.append(0) }
    for shift in stride(from: 56, through: 0, by: -8) {
      working.append(UInt8(truncatingIfNeeded: bitLength >> UInt64(shift)))
    }

    var hash: [UInt32] = [
      0x6a09_e667, 0xbb67_ae85, 0x3c6e_f372, 0xa54f_f53a,
      0x510e_527f, 0x9b05_688c, 0x1f83_d9ab, 0x5be0_cd19,
    ]

    var schedule = [UInt32](repeating: 0, count: 64)
    for chunkStart in stride(from: 0, to: working.count, by: 64) {
      for i in 0..<16 {
        let offset = chunkStart + i * 4
        schedule[i] = (UInt32(working[offset]) << 24)
          | (UInt32(working[offset + 1]) << 16)
          | (UInt32(working[offset + 2]) << 8)
          | UInt32(working[offset + 3])
      }
      for i in 16..<64 {
        let s0 = rotr(schedule[i - 15], 7) ^ rotr(schedule[i - 15], 18) ^ (schedule[i - 15] >> 3)
        let s1 = rotr(schedule[i - 2], 17) ^ rotr(schedule[i - 2], 19) ^ (schedule[i - 2] >> 10)
        schedule[i] = schedule[i - 16] &+ s0 &+ schedule[i - 7] &+ s1
      }

      var a = hash[0]
      var b = hash[1]
      var c = hash[2]
      var d = hash[3]
      var e = hash[4]
      var f = hash[5]
      var g = hash[6]
      var h = hash[7]

      for i in 0..<64 {
        let s1 = rotr(e, 6) ^ rotr(e, 11) ^ rotr(e, 25)
        let ch = (e & f) ^ (~e & g)
        let temp1 = h &+ s1 &+ ch &+ Self.constants[i] &+ schedule[i]
        let s0 = rotr(a, 2) ^ rotr(a, 13) ^ rotr(a, 22)
        let maj = (a & b) ^ (a & c) ^ (b & c)
        let temp2 = s0 &+ maj
        h = g
        g = f
        f = e
        e = d &+ temp1
        d = c
        c = b
        b = a
        a = temp1 &+ temp2
      }

      hash[0] &+= a
      hash[1] &+= b
      hash[2] &+= c
      hash[3] &+= d
      hash[4] &+= e
      hash[5] &+= f
      hash[6] &+= g
      hash[7] &+= h
    }

    var result = [UInt8]()
    for value in hash {
      result.append(UInt8(truncatingIfNeeded: value >> 24))
      result.append(UInt8(truncatingIfNeeded: value >> 16))
      result.append(UInt8(truncatingIfNeeded: value >> 8))
      result.append(UInt8(truncatingIfNeeded: value))
    }
    return result
  }

  // MARK: Private

  private static func rotr(_ value: UInt32, _ amount: UInt32) -> UInt32 {
    (value >> amount) | (value << (32 - amount))
  }

  private static let constants: [UInt32] = [
    0x428a_2f98, 0x7137_4491, 0xb5c0_fbcf, 0xe9b5_dba5,
    0x3956_c25b, 0x59f1_11f1, 0x923f_82a4, 0xab1c_5ed5,
    0xd807_aa98, 0x1283_5b01, 0x2431_85be, 0x550c_7dc3,
    0x72be_5d74, 0x80de_b1fe, 0x9bdc_06a7, 0xc19b_f174,
    0xe49b_69c1, 0xefbe_4786, 0x0fc1_9dc6, 0x240c_a1cc,
    0x2de9_2c6f, 0x4a74_84aa, 0x5cb0_a9dc, 0x76f9_88da,
    0x983e_5152, 0xa831_c66d, 0xb003_27c8, 0xbf59_7fc7,
    0xc6e0_0bf3, 0xd5a7_9147, 0x06ca_6351, 0x1429_2967,
    0x27b7_0a85, 0x2e1b_2138, 0x4d2c_6dfc, 0x5338_0d13,
    0x650a_7354, 0x766a_0abb, 0x81c2_c92e, 0x9272_2c85,
    0xa2bf_e8a1, 0xa81a_664b, 0xc24b_8b70, 0xc76c_51a3,
    0xd192_e819, 0xd699_0624, 0xf40e_3585, 0x106a_a070,
    0x19a4_c116, 0x1e37_6c08, 0x2748_774c, 0x34b0_bcb5,
    0x391c_0cb3, 0x4ed8_aa4a, 0x5b9c_ca4f, 0x682e_6ff3,
    0x748f_82ee, 0x78a5_636f, 0x84c8_7814, 0x8cc7_0208,
    0x90be_fffa, 0xa450_6ceb, 0xbef9_a3f7, 0xc671_78f2,
  ]
}
