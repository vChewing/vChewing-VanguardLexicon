// (c) 2025 and onwards The vChewing Project (LGPL v3.0 License or later).
// ====================
// This code is released under the SPDX-License-Identifier: `LGPL-3.0-or-later`.

import Foundation

// MARK: - VanguardTrie.TrieIO

extension VanguardTrie {
  /// 提供 Trie 資料結構的高效二進位序列化與反序列化功能
  public enum TrieIO {
    // MARK: - 例外型別

    /// Trie 輸入輸出操作可能發生的例外狀況
    public enum Exception: Swift.Error, LocalizedError {
      /// 序列化失敗
      case serializationFailed(Swift.Error)
      /// 反序列化失敗
      case deserializationFailed(Swift.Error)
      /// 檔案儲存失敗
      case fileSaveFailed(Swift.Error)
      /// 檔案載入失敗
      case fileLoadFailed(Swift.Error)

      // MARK: Public

      public var errorDescription: String? {
        switch self {
        case let .serializationFailed(error):
          return "序列化 Trie 失敗: \(error.localizedDescription)"
        case let .deserializationFailed(error):
          return "反序列化 Trie 失敗: \(error.localizedDescription)"
        case let .fileSaveFailed(error):
          return "儲存 Trie 至檔案失敗: \(error.localizedDescription)"
        case let .fileLoadFailed(error):
          return "從檔案載入 Trie 失敗: \(error.localizedDescription)"
        }
      }
    }

    // MARK: - 公開方法

    /// 將 Trie 序列化為二進位資料
    /// - Parameter trie: 要序列化的 Trie 結構
    /// - Returns: 二進位資料
    /// - Throws: 序列化過程中的例外狀況
    public static func serialize(_ trie: Trie) throws -> Data {
      do {
        // 使用 PropertyListEncoder 序列化為二進位格式
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        return try encoder.encode(trie)
      } catch {
        throw Exception.serializationFailed(error)
      }
    }

    /// 從二進位資料反序列化 Trie 結構
    /// - Parameter data: 二進位資料
    /// - Returns: 反序列化的 Trie 結構
    /// - Throws: 反序列化過程中的例外狀況
    public static func deserialize(_ data: Data) throws -> Trie {
      do {
        // 使用 PropertyListDecoder 反序列化
        let decoder = PropertyListDecoder()
        return try decoder.decode(Trie.self, from: data)
      } catch {
        throw Exception.deserializationFailed(error)
      }
    }

    /// 將 Trie 儲存到指定路徑
    /// - Parameters:
    ///   - trie: 要儲存的 Trie 結構
    ///   - url: 儲存路徑
    /// - Throws: 序列化或檔案寫入過程中的例外狀況
    public static func save(_ trie: Trie, to url: URL) throws {
      let data = try serialize(trie)

      do {
        try data.write(to: url, options: .atomic)
      } catch {
        throw Exception.fileSaveFailed(error)
      }
    }

    /// 從指定路徑載入 Trie
    /// - Parameter url: Trie 檔案路徑
    /// - Returns: 載入的 Trie 結構
    /// - Throws: 檔案讀取或反序列化過程中的例外狀況
    public static func load(from url: URL) throws -> Trie {
      do {
        let data = try Data(contentsOf: url)
        return try deserialize(data)
      } catch let error as Exception {
        throw error
      } catch {
        throw Exception.fileLoadFailed(error)
      }
    }

    // MARK: - 驗證方法

    /// 驗證 Trie 結構的正確性
    /// - Parameter trie: 要驗證的 Trie 結構
    /// - Returns: 驗證結果與可能的錯誤資訊
    public static func validate(_ trie: Trie) -> (isValid: Bool, errors: [String]) {
      var errors = [String]()

      // 檢查根節點
      if trie.root.id != 1 {
        errors.append("根節點 ID 不正確：期望為 1，實際為 \(String(describing: trie.root.id))")
      }

      // 檢查節點辭典中的根節點
      if trie.nodes[1] == nil {
        errors.append("節點辭典中缺少根節點")
      }

      // 檢查節點關係的一致性
      for (id, node) in trie.nodes {
        // 檢查 ID 一致性
        if node.id != id {
          errors.append("節點 ID 不一致：辭典鍵為 \(id)，節點 ID 為 \(String(describing: node.id))")
        }

        // 檢查父節點關係
        if let parentID = node.parentID, trie.nodes[parentID] == nil {
          errors.append("節點 \(id) 引用了不存在的父節點 \(parentID)")
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
