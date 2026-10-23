// (c) 2025 and onwards The vChewing Project (MulanPSL-2.0 License).
// ====================
// This code is released under the SPDX-License-Identifier: `MulanPSL-2.0`.

import Foundation

extension Yukuaki {
  /// Yukuaki 的錯誤類型。
  public enum Exception: Error, LocalizedError {
    /// 給定的按鍵內容為空、或含有空字串的替代讀音。
    case givenKeyIsEmpty
    /// 給定的按鍵在辭典內查不到任何詞條。
    case givenKeyHasNoResults([String])
    /// 組句時一個節點都沒有建立起來。
    case noNodesAssigned
    /// 組句器內沒有任何按鍵。
    case assemblerIsEmpty
    /// 該節點內沒有可用的 gram。
    case nodeHasNoCurrentGram
    /// 讀音鏈無法剖析（例如拼音缺少聲調數字、或含有無法辨識的音節）。
    case invalidReadingChain(String)
    /// 期望結果的字數與讀音數量不一致。
    case expectedReadingMismatch(expected: Int, reading: Int)
    /// 無法為期望結果找到任何可行的分段方式。
    case noFeasibleSegmentation(String)
    /// 逆推時所需的詞頻超出了辭典正規化基準所能容許的量級。
    case proposalOutOfRange(String)

    // MARK: Public

    public var errorDescription: String? {
      switch self {
      case .givenKeyIsEmpty:
        return "給定的讀音為空。"
      case let .givenKeyHasNoResults(keys):
        return "辭典內查不到讀音「\(keys.joined(separator: "-"))」的任何詞條。"
      case .noNodesAssigned:
        return "組句時未能建立任何節點。"
      case .assemblerIsEmpty:
        return "組句器內沒有任何按鍵。"
      case .nodeHasNoCurrentGram:
        return "該節點內沒有可用的 gram。"
      case let .invalidReadingChain(reason):
        return "讀音鏈無法剖析：\(reason)"
      case let .expectedReadingMismatch(expected, reading):
        return "期望結果有 \(expected) 個字，但讀音鏈有 \(reading) 個音節；本工具目前只支援兩者等長的情形。"
      case let .noFeasibleSegmentation(expected):
        return "無法為「\(expected)」找到任何可行的分段方式。"
      case let .proposalOutOfRange(reason):
        return "逆推失敗：\(reason)"
      }
    }
  }
}
