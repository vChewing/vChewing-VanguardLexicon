// (c) 2021 and onwards The vChewing Project (BSD-3-Clause).
// ====================
// This code is released under the SPDX-License-Identifier: `BSD-3-Clause`.

import Foundation

// MARK: - VCDataBuilder

public enum VCDataBuilder {}

extension VCDataBuilder {
  public static func exportTextTemplates(to directory: URL) throws {
    let fileNames = [
      "template-associatedPhrases-chs.txt",
      "template-associatedPhrases-cht.txt",
    ]
    let bundle = Bundle.module
    for fileName in fileNames {
      // The resources are likely in "Resources/components/chs" or "cht" in source,
      // but Bundle.module flatifies them or keeps folder structure?
      // Apple's resource bundler usually flattens simple resources, or keeps structure if .process is directory?
      // The Package.swift says .process("./Resources/").
      // Resources in subfolders usually need directory lookup or are flattened if file-by-file.
      // Since it's .process("Resources/"), the structure Resources/... is preserved?
      // Actually usually `findFiles` or `path(forResource:...)` finds them.
      // Let's rely on `url(forResource:withExtension:)` which searches recursively?
      // No, bundle.url(forResource:...) is flat unless subdirectory is specified.

      // We can try to find them.
      let nameStem = (fileName as NSString).deletingPathExtension
      let ext = (fileName as NSString).pathExtension
      // Try finding anywhere
      guard let sourceURL = bundle.url(forResource: nameStem, withExtension: ext) else {
        NSLog("Error: Could not find resource \(fileName) in bundle.")
        continue
      }

      let destURL = directory.appendingPathComponent(fileName)
      if FileManager.default.fileExists(atPath: destURL.path) {
        try FileManager.default.removeItem(at: destURL)
      }
      try FileManager.default.copyItem(at: sourceURL, to: destURL)
    }
  }
}
