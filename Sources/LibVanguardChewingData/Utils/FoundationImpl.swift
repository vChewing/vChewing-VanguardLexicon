// (c) 2021 and onwards The vChewing Project (BSD-3-Clause).
// ====================
// This code is released under the SPDX-License-Identifier: `BSD-3-Clause`.

import Foundation

// MARK: - StringView Ranges Extension (by Isaac Xen)

extension StringProtocol {
  /// 分析傳入的原始辭典檔案（UTF-8 TXT）的資料。
  /// - Parameters:
  ///   - separator: 行內單元分隔符。
  ///   - task: 要執行的外包任務。
  func parse(
    splitee separator: Element,
    task: (_ theRange: Range<String.Index>) -> ()
  ) {
    var startIndex = startIndex
    split(separator: separator).forEach { substring in
      let theRange = range(of: substring, range: startIndex ..< endIndex)
      guard let theRange = theRange else { return }
      task(theRange)
      startIndex = theRange.upperBound
    }
  }
}

// MARK: - 引入小數點位數控制函式

extension Double {
  public func rounded(toPlaces places: Int) -> Double {
    let divisor = pow(10.0, Double(places))
    return (self * divisor).rounded() / divisor
  }
}

// MARK: - 引入冪乘函式

precedencegroup ExponentiationPrecedence {
  associativity: right
  higherThan: MultiplicationPrecedence
}

infix operator **: ExponentiationPrecedence

public func ** (_ base: Double, _ exp: Double) -> Double {
  pow(base, exp)
}

extension FileManager {
  public static let urlCurrentFolder: URL = {
    if let envPath = ProcessInfo.processInfo.environment["VANGUARD_OUTPUT_DIR"] {
      return URL(fileURLWithPath: envPath)
    }
    return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
  }()
}

// MARK: - Regex Implementations.

extension String {
  public mutating func regReplace(pattern: String, replaceWith: String = "") {
    // 參考：https://stackoverflow.com/a/40993403/4162914 && https://stackoverflow.com/a/71291137/4162914
    do {
      let regex = try NSRegularExpression(
        pattern: pattern, options: [.caseInsensitive, .anchorsMatchLines]
      )
      let range = NSRange(startIndex..., in: self)
      self = regex.stringByReplacingMatches(
        in: self, options: [], range: range, withTemplate: replaceWith
      )
    } catch { return }
  }

  public func matches(pattern: String) throws -> Bool {
    do {
      let regex = try NSRegularExpression(pattern: pattern, options: [])
      let range = NSRange(location: 0, length: utf16.count)
      return regex.firstMatch(in: self, options: [], range: range) != nil
    } catch {
      throw BundleSearchError.regexError("Invalid regex pattern: \(error.localizedDescription)")
    }
  }
}

// MARK: - BundleSearchError

enum BundleSearchError: Error {
  case invalidPattern
  case bundleResourcesNotFound
  case regexError(String)
}

extension Bundle {
  /// 使用模式在 bundle 中搜尋檔案
  /// - Parameters:
  ///   - pattern: 用於匹配檔案名稱的正規表達式模式
  ///   - extension: 可選的檔案副檔名篩選器
  /// - Returns: 匹配的檔案名稱或路徑陣列
  public func findFiles(
    matching pattern: String,
    extension: String? = nil
  ) throws
    -> [URL] {
    // 建立 NSRegularExpression - 在 Linux 和 Apple 平台上都可運作
    let regex: NSRegularExpression
    do {
      regex = try NSRegularExpression(pattern: pattern, options: [])
    } catch {
      throw BundleSearchError.regexError("Invalid regex pattern: \(error.localizedDescription)")
    }

    // 取得資源，可選擇性地使用副檔名篩選器
    guard let nsURLs = urls(forResourcesWithExtension: `extension`, subdirectory: nil) else {
      throw BundleSearchError.bundleResourcesNotFound
    }
    let urls = nsURLs.compactMap { URL(string: $0.absoluteString) }
    return urls.compactMap { url in
      if let filename = url.pathComponents.last {
        let range = NSRange(location: 0, length: filename.utf16.count)

        // 檢查檔案名稱是否符合模式
        if regex.firstMatch(in: filename, options: [], range: range) != nil {
          return url
        }
      }
      return nil
    }
  }

  /// 在 bundle 中搜尋符合多個模式的檔案
  /// - Parameters:
  ///   - patterns: 要匹配的正規表達式模式陣列
  ///   - matchAll: 若為 true，檔案必須符合所有模式。若為 false，符合任一模式即可
  /// - Returns: 匹配的檔案名稱陣列
  public func findFiles(
    matching patterns: [String],
    matchAll: Bool = false
  ) throws
    -> [URL] {
    let regexPatterns = try patterns.map { pattern -> NSRegularExpression in
      do {
        return try NSRegularExpression(pattern: pattern, options: [])
      } catch {
        throw BundleSearchError
          .regexError("Invalid regex pattern '\(pattern)': \(error.localizedDescription)")
      }
    }

    guard let resourcesNSURLs = urls(forResourcesWithExtension: nil, subdirectory: nil) else {
      throw BundleSearchError.bundleResourcesNotFound
    }
    let resources = resourcesNSURLs.compactMap { URL(string: $0.absoluteString) }

    return resources.compactMap { url in
      if let filename = url.pathComponents.last {
        let range = NSRange(location: 0, length: filename.utf16.count)

        if matchAll {
          // 必須符合所有模式
          let matchesAll = regexPatterns.allSatisfy { regex in
            regex.firstMatch(in: filename, options: [], range: range) != nil
          }
          return matchesAll ? url : nil
        } else {
          // 符合任一模式
          let matchesAny = regexPatterns.contains { regex in
            regex.firstMatch(in: filename, options: [], range: range) != nil
          }
          return matchesAny ? url : nil
        }
      }
      return nil
    }
  }
}
