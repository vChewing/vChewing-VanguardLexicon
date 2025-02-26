// (c) 2021 and onwards The vChewing Project (BSD-3-Clause).
// ====================
// This code is released under the SPDX-License-Identifier: `BSD-3-Clause`.

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
      category: Category
    ) {
      self.key = key
      self.value = value
      self.score = score
      self.count = count
      self.type = category
    }

    public required init(from decoder: any Decoder) throws {
      let container = try decoder.container(keyedBy: CodingKeys.self)
      self.key = try container.decode(String.self, forKey: .key)
      self.value = try container.decode(String.self, forKey: .value)
      self.score = try container.decode(Double.self, forKey: .score)
      self.count = try container.decode(Int.self, forKey: .count)
      self.type = try container.decode(Category.self, forKey: .category)
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
      case cns = "CNS"

      // MARK: Internal

      var description: String { rawValue }
    }

    public static let naturalE: Double = 2.71828

    public let key: String
    public let value: String
    public private(set) var score: Double = -1.0
    public let count: Int
    public let type: Category
    public let timestamp: Double = Date().timeIntervalSince1970

    public var keyValueHash: Int {
      "\(key)\t\(value)".hashValue
    }

    public var normDelta: Double? {
      switch type {
      case .macv: break
      case .tabe: break
      case .moe: break
      case .kanji: break
      case .custom: return nil
      case .misc: return nil
      case .cns: return nil
      }
      return Self.naturalE ** (Double(value.count) / 3.0 - 1.0) * Double(count)
    }

    public var description: String {
      "(\(key), \(value), \(score), \(type)"
    }

    public var keyCells: [String] {
      guard key.last != "-" else { return [key] }
      return key.split(separator: "-").map(\.description)
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
      hasher.combine(timestamp)
    }

    public func encode(to encoder: any Encoder) throws {
      var container = encoder.container(keyedBy: CodingKeys.self)
      try container.encode(key, forKey: .key)
      try container.encode(value, forKey: .value)
      try container.encode(score, forKey: .score)
      try container.encode(count, forKey: .count)
      try container.encode(type, forKey: .category)
      try container.encode(timestamp, forKey: .timestamp)
    }

    public func weighten(norm: Double) {
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

    // MARK: Private

    private enum CodingKeys: String, CodingKey {
      case key = "k"
      case value = "v"
      case score = "s"
      case count = "c"
      case category = "t"
      case timestamp = "d"
    }
  }
}
