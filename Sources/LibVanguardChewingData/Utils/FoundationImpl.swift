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
  public static let urlCurrentFolder = URL(
    fileURLWithPath: FileManager.default
      .currentDirectoryPath
  )
}

// MARK: - Regex Implementations.

extension String {
  public mutating func regReplace(pattern: String, replaceWith: String = "") {
    // Ref: https://stackoverflow.com/a/40993403/4162914 && https://stackoverflow.com/a/71291137/4162914
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
  /// Search for files in the bundle using a pattern
  /// - Parameters:
  ///   - pattern: Regular expression pattern to match filenames
  ///   - extension: Optional file extension filter
  /// - Returns: Array of matched filenames or paths
  public func findFiles(
    matching pattern: String,
    extension: String? = nil
  ) throws
    -> [URL] {
    // Create NSRegularExpression - works on both Linux and Apple platforms
    let regex: NSRegularExpression
    do {
      regex = try NSRegularExpression(pattern: pattern, options: [])
    } catch {
      throw BundleSearchError.regexError("Invalid regex pattern: \(error.localizedDescription)")
    }

    // Get resources with optional extension filter
    guard let urls = urls(forResourcesWithExtension: `extension`, subdirectory: nil) else {
      throw BundleSearchError.bundleResourcesNotFound
    }

    return urls.compactMap { url in
      let filename = url.lastPathComponent
      let range = NSRange(location: 0, length: filename.utf16.count)

      // Check if filename matches the pattern
      if regex.firstMatch(in: filename, options: [], range: range) != nil {
        return url
      }
      return nil
    }
  }

  /// Search for files in the bundle matching multiple patterns
  /// - Parameters:
  ///   - patterns: Array of regex patterns to match
  ///   - matchAll: If true, file must match all patterns. If false, matching any pattern is sufficient
  /// - Returns: Array of matched filenames
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

    guard let resources = urls(forResourcesWithExtension: nil, subdirectory: nil) else {
      throw BundleSearchError.bundleResourcesNotFound
    }

    return resources.compactMap { url in
      let filename = url.lastPathComponent
      let range = NSRange(location: 0, length: filename.utf16.count)

      if matchAll {
        // Must match all patterns
        let matchesAll = regexPatterns.allSatisfy { regex in
          regex.firstMatch(in: filename, options: [], range: range) != nil
        }
        return matchesAll ? url : nil
      } else {
        // Match any pattern
        let matchesAny = regexPatterns.contains { regex in
          regex.firstMatch(in: filename, options: [], range: range) != nil
        }
        return matchesAny ? url : nil
      }
    }
  }
}
