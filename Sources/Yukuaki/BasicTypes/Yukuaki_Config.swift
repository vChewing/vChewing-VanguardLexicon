// (c) 2025 and onwards The vChewing Project (MulanPSL-2.0 License).
// ====================
// This code is released under the SPDX-License-Identifier: `MulanPSL-2.0`.

extension Yukuaki {
  /// 組句器的組態。與 Homa 的 `Homa.Config` 相比，這裡去掉了游標、輸入法標記、
  /// 行為感知等狀態，只保留組句真正需要的東西。
  public struct Config: Hashable, Sendable {
    // MARK: Lifecycle

    public init(assembledSentence: [GramInPath] = [], maxSegLength: Int = 10) {
      self.assembledSentence = assembledSentence
      /// 與 Homa 相同：幅節長度的下限是 6，否則無法處理「電腦」這類兩字詞之上的長詞。
      self.maxSegLength = max(6, maxSegLength)
    }

    // MARK: Public

    /// 當前的組句結果。
    public var assembledSentence: [GramInPath]
    /// 幅節長度的上限。
    public let maxSegLength: Int

    /// 當前的組句結果攤成的字串。
    public var assembledText: String { assembledSentence.values.joined() }

    /// 該組態的硬拷貝。
    public var hardCopy: Yukuaki.Config { .init(assembledSentence: assembledSentence, maxSegLength: maxSegLength) }

    /// 清空組句結果。
    public mutating func clear() {
      assembledSentence.removeAll()
    }
  }
}
