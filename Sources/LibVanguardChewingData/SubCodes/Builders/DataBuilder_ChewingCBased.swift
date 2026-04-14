// (c) 2021 and onwards The vChewing Project (BSD-3-Clause).
// ====================
// This code is released under the SPDX-License-Identifier: `BSD-3-Clause`.

import Foundation

// MARK: - VCDataBuilder.ChewingCBasedDataBuilder

extension VCDataBuilder {
  public actor ChewingCBasedDataBuilder: DataBuilderProtocol {
    // MARK: Lifecycle

    public init?(isCHS: Bool?) async throws {
      guard let isCHS else { return nil }
      self.isCHS = isCHS
      // 新酷音因為有 Windows 版的緣故，所以需要相容模式。
      // Windows 不是所有軟體都有支援高萬字。
      self.data = try Collector(isCHS: isCHS, compatibleMode: true)
    }

    // MARK: Public

    nonisolated public let isCHS: Bool?

    public let data: Collector
  }
}

extension VCDataBuilder.ChewingCBasedDataBuilder {
  fileprivate static let phoneCinFooter = "%chardef  end\n"

  nonisolated public var langSuffix: String {
    (isCHS ?? true) ? "chs" : "cht" // 這個 variable 在這個 Actor 內永遠都不可能是 nil。
  }

  nonisolated public var subFolderNameComponents: [String] {
    ["Intermediate", "chewing-cbased-\(langSuffix)"]
  }

  nonisolated public var subFolderNameComponentsAftermath: [String] {
    ["Release", "chewing-cbased-\(langSuffix)"]
  }

  public func getIteratorForLexiconAssemblyTask() async throws -> VCDataBuilder.ChunkIterator {
    /// 新酷音輸入法在建置 dat 時會自行健檢，所以這裡略過健檢步驟。
    var grams = await data.getAllUnigrams(isCHS: isCHS, sorted: false)
    grams = grams.sorted { lhs, rhs -> Bool in
      (lhs.key, rhs.count, lhs.timestamp) < (rhs.key, lhs.count, rhs.timestamp)
    }

    let phoneHeader = Self.getPhoneCINHeader()
    var estimatedTSISize = 0
    var estimatedPhoneCinSize = phoneHeader.utf8.count + Self.phoneCinFooter.utf8.count

    grams.forEach { gram in
      let keyCells = gram.keyCells
      guard keyCells.count == gram.value.count else { return }
      estimatedTSISize += gram.value.utf8.count + 1 + String(gram.count).utf8.count + 1
      estimatedTSISize += keyCells.reduce(into: 0) { partialResult, cell in
        partialResult += cell.utf8.count
      }
      estimatedTSISize += max(0, keyCells.count - 1) + 1
      if keyCells.count == 1 {
        estimatedPhoneCinSize += gram.key.count + 1 + gram.value.utf8.count + 1
      }
    }

    var dataTsiSRC = Data()
    dataTsiSRC.reserveCapacity(estimatedTSISize)
    var dataCharDef = Data()
    dataCharDef.reserveCapacity(estimatedPhoneCinSize)
    Self.appendUTF8(phoneHeader, to: &dataCharDef)

    grams.forEach { gram in
      let keyCells = gram.keyCells
      guard keyCells.count == gram.value.count else { return }

      Self.appendUTF8(gram.value, to: &dataTsiSRC)
      dataTsiSRC.append(0x20)
      Self.appendUTF8(String(gram.count), to: &dataTsiSRC)
      for keyCell in keyCells {
        dataTsiSRC.append(0x20)
        Self.appendUTF8(keyCell, to: &dataTsiSRC)
      }
      dataTsiSRC.append(0x0A)

      if keyCells.count == 1 {
        Self.appendUTF8(gram.key.asBopomofo2Dachien, to: &dataCharDef)
        dataCharDef.append(0x20)
        Self.appendUTF8(gram.value, to: &dataCharDef)
        dataCharDef.append(0x0A)
      }
    }

    Self.appendUTF8(Self.phoneCinFooter, to: &dataCharDef)

    return AsyncThrowingStream { continuation in
      continuation.yield(.init(fileName: "tsi.src", data: dataTsiSRC, isLastChunk: true))
      continuation.yield(.init(fileName: "phone.cin", data: dataCharDef, isLastChunk: true))
      continuation.finish()
    }
  }

  public func performPostCompilation() async throws {
    let buildRoot = FileManager.urlCurrentFolder.appendingPathComponent("Build")
    let intermediateFolderURL = subFolderNameComponents.reduce(buildRoot) { partial, component in
      partial.appendingPathComponent(component)
    }

    var outputFolderURL = FileManager.urlCurrentFolder
    if ProcessInfo.processInfo.environment["VANGUARD_OUTPUT_DIR"] == nil {
      outputFolderURL.appendPathComponent("Build")
    }
    outputFolderURL = subFolderNameComponentsAftermath.reduce(outputFolderURL) { partial, component in
      partial.appendingPathComponent(component)
    }

    let phoneCinURL = intermediateFolderURL.appendingPathComponent("phone.cin")
    let tsiSrcURL = intermediateFolderURL.appendingPathComponent("tsi.src")

    do {
      try ChewingCBasedDatabaseGenerator.writeArtifacts(
        phoneCinURL: phoneCinURL,
        tsiSrcURL: tsiSrcURL,
        outputDirectory: outputFolderURL
      )
    } catch {
      throw VCDataBuilder.Exception.errMsg("Failed to initialize database:\n\(error.localizedDescription)")
    }

    NSLog("針對 C-Based 新酷音引擎的資料建置已順利完成。")
  }
}

// MARK: - BPMF to Dachen Converter

extension String {
  static let bpmfReplacements: [Character: Character] = [
    "ㄝ": ",", "ㄦ": "-", "ㄡ": ".", "ㄥ": "/", "ㄢ": "0",
    "ㄅ": "1", "ㄉ": "2", "ˇ": "3", "ˋ": "4", "ㄓ": "5",
    "ˊ": "6", "˙": "7", "ㄚ": "8", "ㄞ": "9", "ㄤ": ";",
    "ㄇ": "a", "ㄖ": "b", "ㄏ": "c", "ㄎ": "d", "ㄍ": "e",
    "ㄑ": "f", "ㄕ": "g", "ㄘ": "h", "ㄛ": "i", "ㄨ": "j",
    "ㄜ": "k", "ㄠ": "l", "ㄩ": "m", "ㄙ": "n", "ㄟ": "o",
    "ㄣ": "p", "ㄆ": "q", "ㄐ": "r", "ㄋ": "s", "ㄔ": "t",
    "ㄧ": "u", "ㄒ": "v", "ㄊ": "w", "ㄌ": "x", "ㄗ": "y",
    "ㄈ": "z",
  ]

  var asBopomofo2Dachien: String {
    String(map { Self.bpmfReplacements[$0] ?? $0 })
  }
}

// MARK: - Phone.cin Header

extension VCDataBuilder.ChewingCBasedDataBuilder {
  fileprivate static func appendUTF8(_ string: some StringProtocol, to data: inout Data) {
    data.append(contentsOf: string.utf8)
  }

  fileprivate static func getPhoneCINHeader() -> String {
    let fileNameStem = "phone-header"
    let fileURL = Bundle.module.url(forResource: fileNameStem, withExtension: "txt")
    guard let fileURL else { return "" }
    let dataStr = try? String(contentsOf: fileURL, encoding: .utf8)
    guard let dataStr else { return "" }
    return dataStr
  }
}
