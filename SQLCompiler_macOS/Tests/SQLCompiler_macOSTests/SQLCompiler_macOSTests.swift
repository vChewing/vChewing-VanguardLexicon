@testable import SQLCompiler_macOS
import SwiftData
import XCTest

final class SQLCompiler_macOSTests: XCTestCase {
  func testWriteOnce() throws {
    let sqliteFilePath = URL(fileURLWithPath: #file)
      .pathComponents
      .prefix(while: { $0 != "Tests" })
      .joined(separator: "/")
      .dropFirst()
      .appending("/Scratch/test.sqlite")

    Task {
      try DBDataWriter.writeOnce(to: URL(fileURLWithPath: sqliteFilePath)) {
        [
          DBRecordMain(keyArray: ["ㄅㄚ", "ㄩㄝˋ", "ㄓㄨㄥ", "ㄑㄧㄡ"], column: .chs, values: ["八月中秋"]),
          DBRecordMain(keyArray: ["ㄓㄨㄥ", "ㄑㄧㄡ"], column: .chs, values: ["中秋"]),
          DBRecordRev(char: "屌", readings: "ㄉㄧㄠˇ"),
          DBRecordRev(char: "均", readings: "ㄐㄩㄣ"),
        ]
      }
    }
  }
}
