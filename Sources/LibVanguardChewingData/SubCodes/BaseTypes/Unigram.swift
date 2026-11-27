// (c) 2021 and onwards The vChewing Project (MulanPSL-2.0 License).
// ====================
// This code is released under the SPDX-License-Identifier: `MulanPSL-2.0`.

import Foundation

// MARK: - VCDataBuilder.Unigram

extension VCDataBuilder {
  public final class Unigram: Codable, Hashable, @unchecked Sendable, CustomStringConvertible {
    // MARK: Lifecycle

    public init(
      key: String,
      value: String,
      score: Double,
      count: Int,
      category: Category,
      isNerfed: Bool = false
    ) {
      self.key = key
      self.value = value
      self.score = score
      self.count = isNerfed ? 0 : count
      self.type = category
      self.isNerfed = isNerfed
      self.timestamp = VCDataBuilder.Unigram.nextStableSerial()
    }

    public required init(from decoder: any Decoder) throws {
      let container = try decoder.container(keyedBy: CodingKeys.self)
      let decodedCount = try container.decode(Int.self, forKey: .count)
      let decodedNerfed = try container.decodeIfPresent(Bool.self, forKey: .isNerfed) ?? false
      self.key = try container.decode(String.self, forKey: .key)
      self.value = try container.decode(String.self, forKey: .value)
      self.score = try container.decode(Double.self, forKey: .score)
      self.count = decodedNerfed ? 0 : decodedCount
      self.type = try container.decode(Category.self, forKey: .category)
      self.isNerfed = decodedNerfed
      self.timestamp = try container.decodeIfPresent(Double.self, forKey: .timestamp)
        ?? VCDataBuilder.Unigram.nextStableSerial()
    }

    // MARK: Public

    public typealias GramSet = Set<VCDataBuilder.Unigram>

    public enum Category: String, Codable, CaseIterable, Sendable {
      case macv = "MACV"
      case tabe = "TABE"
      case moe = "MOED"
      case custom = "CUST"
      case misc = "MISC"
      case kanji = "KANJ"
      case bpmf = "BPMF"
      case cns = "CNS"
      case gbex = "GBEX"

      // MARK: Internal

      var description: String { rawValue }
    }

    public static let naturalE: Double = exp(1.0)

    /// NERF 旗標（`#NERFED`）之懲戒權重：與 LibVanguard 側「保險單元圖」同值。
    ///
    /// 遠低於任何真實單元圖（理想範圍 `[-9.5, 0]`），故帶此權重之詞條在組句時
    /// 除「唯一結果」外不會被取用。
    public static let nerfedWeight: Double = -114.514

    public let key: String
    public let value: String
    public private(set) var score: Double = -1.0
    /// 出現次數。帶 `#NERFED` 旗標者恆為 0。
    public let count: Int
    public let type: Category
    /// 是否帶 `#NERFED` 旗標（懲戒詞條）。
    public let isNerfed: Bool
    public let timestamp: Double

    public var keyValueHash: Int {
      "\(key)\t\(value)".hashValue
    }

    /// 詞頻折算之增量：`weighten` 之前那次全域盤點（`Collector.norm`）的加總項。
    ///
    /// 帶 `#NERFED` 旗標者**無權參與**此統計：其頻次只是「此詞不得勝出」之標記，
    /// 不是樣本證據，故與 `.custom`／`.misc` 同樣回傳 `nil`。**不得**只靠「頻次恰為 0、
    /// 乘出來剛好是 0」這個副作用來排除——頻次政策一旦調整，`_NORM` 就會靜默膨脹。
    public var normDelta: Double? {
      guard !isNerfed else { return nil }
      switch type {
      case .macv: break
      case .tabe: break
      case .moe: break
      case .kanji: break
      case .bpmf: break
      case .custom: return nil
      case .misc: return nil
      case .cns: return nil
      case .gbex: return nil
      }
      guard (1 ... 6).contains(keyCells.count) else { return nil }
      return Self.naturalE ** (Double(value.count) / 3.0 - 1.0) * Double(count)
    }

    public var description: String {
      "(\(key), \(value), \(score), \(type)\(isNerfed ? ", NERFED" : "")"
    }

    public var keyCells: [String] {
      guard key.last != "-" else { return [key] }
      return key.split(separator: "-").map(\.description)
    }

    public var spanLength: Int {
      keyCells.count
    }

    public static func == (lhs: Unigram, rhs: Unigram) -> Bool {
      lhs.hashValue == rhs.hashValue
    }

    public func hash(into hasher: inout Hasher) {
      hasher.combine(key)
      hasher.combine(value)
      hasher.combine(score)
      hasher.combine(count)
      hasher.combine(type)
      hasher.combine(isNerfed)
      hasher.combine(timestamp)
    }

    public func encode(to encoder: any Encoder) throws {
      var container = encoder.container(keyedBy: CodingKeys.self)
      try container.encode(key, forKey: .key)
      try container.encode(value, forKey: .value)
      try container.encode(score, forKey: .score)
      try container.encode(count, forKey: .count)
      try container.encode(type, forKey: .category)
      try container.encode(isNerfed, forKey: .isNerfed)
      try container.encode(timestamp, forKey: .timestamp)
    }

    /// 折算權重。
    ///
    /// 帶 `#NERFED` 旗標者不參與正規化折算：其頻次恆為 0，若照 count 0 之分支折算，
    /// 只會得到約 -11 的普通低頻權重。
    public func weighten(norm: Double) {
      guard !isNerfed else {
        score = Self.nerfedWeight
        return
      }
      var weight: Double = 0
      switch count {
      case -2: // 拗音假名
        weight = -13
      case -1: // 單個假名
        weight = -13
      case 0: // 墊底低頻漢字與詞語
        weight = log10(
          Self.naturalE ** (Double(value.count) / 3.0 - 1.0) * 0.25 / norm
        )
      default:
        weight = log10(
          Self.naturalE ** (Double(value.count) / 3.0 - 1.0) * Double(count) / norm
        )
      }
      let weightRounded: Double = weight.rounded(toPlaces: 3) // 為了節省生成的檔案體積，僅保留小數點後三位。
      score = weightRounded
    }

    // MARK: Internal

    static func sortForSerialization(_ lhs: VCDataBuilder.Unigram, _ rhs: VCDataBuilder.Unigram)
      -> Bool {
      let lhsKey = lhs.key.asEncryptedBopomofoKeyChain
      let rhsKey = rhs.key.asEncryptedBopomofoKeyChain
      if lhsKey != rhsKey {
        return lhsKey < rhsKey
      }
      if lhs.score != rhs.score {
        return lhs.score > rhs.score
      }
      if lhs.timestamp != rhs.timestamp {
        return lhs.timestamp < rhs.timestamp
      }
      if lhs.value != rhs.value {
        return lhs.value < rhs.value
      }
      if lhs.type != rhs.type {
        return lhs.type.description < rhs.type.description
      }
      return lhs.count > rhs.count
    }

    // MARK: Private

    private enum CodingKeys: String, CodingKey {
      case key = "k"
      case value = "v"
      case score = "s"
      case count = "c"
      case category = "t"
      case isNerfed = "n"
      case timestamp = "d"
    }

    private static let stableSerialLock = NSLock()
    nonisolated(unsafe) private static var stableSerialCursor: Double = 0

    private static func nextStableSerial() -> Double {
      stableSerialLock.lock()
      defer { stableSerialLock.unlock() }
      let result = stableSerialCursor
      stableSerialCursor += 1
      return result
    }
  }
}
