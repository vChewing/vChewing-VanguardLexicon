// (c) 2025 and onwards The vChewing Project (LGPL v3.0 License or later).
// ====================
// This code is released under the SPDX-License-Identifier: `LGPL-3.0-or-later`.

// MARK: - VanguardTrie.TrieIO

extension VanguardTrie {
  /// Trie 結構驗證工具。
  ///
  /// - Note: 本副本不含任何序列化／反序列化入口；`.txtMap` 的產出由
  ///   `VCDataBuilder.VanguardTextMapDataBuilder` 直接完成。
  public enum TrieIO {
    // MARK: - 驗證方法

    /// 驗證 Trie 結構的正確性
    /// - Parameter trie: 要驗證的 Trie 結構
    /// - Returns: 驗證結果與可能的錯誤資訊
    public static func validate(_ trie: Trie) -> (isValid: Bool, errors: [String]) {
      var errors = [String]()

      // 檢查根節點（`Trie.init(separator:)` 與 `clearAllContents()` 皆把根節點固定為 ID 0。）
      if trie.root.id != 0 {
        errors.append("根節點 ID 不正確：期望為 0，實際為 \(String(describing: trie.root.id))")
      }

      // 檢查節點辭典中的根節點
      if trie.nodes[0] == nil {
        errors.append("節點辭典中缺少根節點")
      }

      // 檢查節點關係的一致性
      for (id, node) in trie.nodes {
        // 檢查 ID 一致性
        if node.id != id {
          errors.append("節點 ID 不一致：辭典鍵為 \(id)，節點 ID 為 \(String(describing: node.id))")
        }

        // 檢查子節點關係
        for (_, childID) in node.children {
          if trie.nodes[childID] == nil {
            errors.append("節點 \(id) 引用了不存在的子節點 \(childID)")
          }
        }
      }

      return (errors.isEmpty, errors)
    }
  }
}
