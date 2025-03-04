// (c) 2021 and onwards The vChewing Project (BSD-3-Clause).
// ====================
// This code is released under the SPDX-License-Identifier: `BSD-3-Clause`.

import Foundation

// MARK: - VCDataBuilder.DataBuilderProtocol

extension VCDataBuilder {
  public protocol DataBuilderProtocol {
    init?(isCHS: Bool?) async throws
    var subFolderNameComponents: [String] { get }
    var subFolderNameComponentsAftermath: [String] { get }
    var isCHS: Bool? { get }
    var data: Collector { get }
    func assemble() async throws -> [String: String]
    func performPostCompilation() async throws
  }
}

extension VCDataBuilder.DataBuilderProtocol {
  public init?(isCHS: Bool? = nil) async throws {
    try await self.init(isCHS: isCHS)
  }

  public func runInTextBlock(_ task: () async -> ()) async {
    print("===============================")
    print("-------------------------------")
    defer {
      print("-------------------------------")
      print("===============================")
    }
    await task()
  }

  public func runInTextBlockThrowable(_ task: () async throws -> ()) async throws {
    print("===============================")
    print("-------------------------------")
    defer {
      print("-------------------------------")
      print("===============================")
    }
    try await task()
  }

  public func printHealthCheckReports() async throws {
    let langs: [Bool] = if let isCHS {
      [isCHS]
    } else {
      [true, false]
    }
    try await runInTextBlockThrowable {
      for lang in langs {
        print(try await data.healthCheckPerMode(isCHS: lang))
      }
    }
  }

  public func writeAssembledAssets() async throws {
    let subFolderNameComponentsAftermath = subFolderNameComponentsAftermath
    // Create aftermath folder if necessary.
    aftermath: do {
      guard !subFolderNameComponentsAftermath.isEmpty else { break aftermath }
      var folderURLAftermath = FileManager.urlCurrentFolder.appendingPathComponent("Build")
      subFolderNameComponentsAftermath.forEach { currentComponentName in
        folderURLAftermath = folderURLAftermath.appendingPathComponent(currentComponentName)
      }
      try FileManager.default.createDirectory(
        at: folderURLAftermath,
        withIntermediateDirectories: true
      )
    }
    // Create primary folder.
    var folderURL = FileManager.urlCurrentFolder.appendingPathComponent("Build")
    subFolderNameComponents.forEach { currentComponentName in
      folderURL = folderURL.appendingPathComponent(currentComponentName)
    }
    // Starts assemblying and data output.
    let assembled = try await assemble()
    try assembled.forEach { filename, dataString in
      let fileURL = folderURL.appendingPathComponent(filename)
      try FileManager.default.createDirectory(
        at: folderURL,
        withIntermediateDirectories: true
      )
      if FileManager.default.fileExists(atPath: fileURL.path) {
        try FileManager.default.removeItem(at: fileURL)
      }
      try dataString.write(to: fileURL, atomically: true, encoding: .utf8)
    }
    // Aftermath.
    NSLog(" - 準備執行追加建置過程。")
    try await runInTextBlockThrowable {
      try await performPostCompilation()
    }
    NSLog(" - 成功執行追加建置過程。")
  }
}

// MARK: - VCDataBuilder.BuilderType

extension VCDataBuilder {
  public enum BuilderType: String, CaseIterable, Sendable, Hashable, Codable {
    case chewingRustCHS
    case chewingRustCHT
    case chewingCBasedCHS
    case chewingCBasedCHT
    case mcbopomofoCHS
    case mcbopomofoCHT
    case vanguardSQLLegacy
  }
}

extension VCDataBuilder.BuilderType {
  public func getAssembler() async throws -> (VCDataBuilder.DataBuilderProtocol & Actor)? {
    switch self {
    case .chewingRustCHS: try await VCDataBuilder.ChewingRustDataBuilder(isCHS: true)
    case .chewingRustCHT: try await VCDataBuilder.ChewingRustDataBuilder(isCHS: false)
    case .chewingCBasedCHS: try await VCDataBuilder.ChewingCBasedDataBuilder(isCHS: true)
    case .chewingCBasedCHT: try await VCDataBuilder.ChewingCBasedDataBuilder(isCHS: false)
    case .mcbopomofoCHS: try await VCDataBuilder.McBopomofoDataBuilder(isCHS: true)
    case .mcbopomofoCHT: try await VCDataBuilder.McBopomofoDataBuilder(isCHS: false)
    case .vanguardSQLLegacy: try await VCDataBuilder.VanguardSQLLegacyDataBuilder()
    }
  }

  public func compile() async throws {
    NSLog("// ================ ")
    do {
      NSLog("// 開始建置： \(rawValue) ...")
      let assembler = try await getAssembler()
      guard assembler != nil else {
        NSLog(" ~ 略過處理： \(rawValue) ...")
        return
      }
      try await assembler?.writeAssembledAssets()
      NSLog(" ~ 成功建置： \(rawValue) ...")
    } catch {
      NSLog("!! 建置失敗： \(rawValue) ...")
      NSLog(" - 錯誤內容： \(error) ...")
    }
  }
}
