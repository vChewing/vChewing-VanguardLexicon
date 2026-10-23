// (c) 2025 and onwards The vChewing Project (MulanPSL-2.0 License).
// ====================
// This code is released under the SPDX-License-Identifier: `MulanPSL-2.0`.

// MARK: - Yukuaki.PossibleKey

extension Yukuaki {
  /// 一個按鍵可對應的讀音。單一讀音或一組互為替代的讀音。
  public enum PossibleKey: Hashable, Sendable, Codable {
    /// 單一讀音。
    case singleKey(String)
    /// 一組互為替代的讀音（例如撇除聲調之後的多個可能）。
    case multipleKeys([String])

    // MARK: Public

    /// 空字串的替代品，避免 `allValues` 回傳空陣列。
    public static let pokayokeChar = "🛇"

    /// 這組讀音是否沒問題。
    public var isValid: Bool { allValues.allSatisfy { !$0.isEmpty } }

    /// 這組讀音的所有可能取值。空集合時回傳防呆字元。
    public var allValues: [String] {
      switch self {
      case let .singleKey(value):
        return [value]
      case let .multipleKeys(values):
        return values.isEmpty ? [Self.pokayokeChar] : values
      }
    }

    /// 這組讀音的取值數量。
    public var count: Int { allValues.count }

    /// 這組讀音是否為多個替代讀音。
    public var isMultiple: Bool { count > 1 }

    /// 這組讀音的第一個取值，不觸發陣列配置。
    public var first: String { allValues.first ?? Self.pokayokeChar }
  }
}

extension Array where Element == Yukuaki.PossibleKey {
  /// 將一組按鍵攤平成一組讀音字串（每個按鍵取第一個候選）。
  public var representativeKeys: [String] { map(\.first) }
}
