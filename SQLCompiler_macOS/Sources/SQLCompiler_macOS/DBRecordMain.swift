import Foundation
import SwiftData

// MARK: - PersistentModle Implementations.

extension PersistentModel {
  public func insertInto(_ context: ModelContext) throws {
    context.insert(self)
    try context.save()
  }

  public static func clearAllAt(_ context: ModelContext) throws {
    try context.delete(model: DBRecordMain.self)
    try context.save()
  }
}

extension Array where Element == any PersistentModel {
  public func insertInto(_ context: ModelContext) throws {
    var counter = 0
    try forEach {
      context.insert($0)
      counter += 1
      if counter > 300 {
        try context.save()
        counter = 0
      }
    }
    try context.save()
  }
}

// MARK: - DBRecordMain

@Model
public class DBRecordMain {
  // MARK: Lifecycle

  public init(key: String, column: Column, value: String) {
    self.key = key
    switch column {
    case .chs: self.dataCHS = value
    case .cht: self.dataCHT = value
    case .cns: self.dataCNS = value
    case .misc: self.dataMISC = value
    case .symb: self.dataSYMB = value
    case .chew: self.dataCHEW = value
    }
  }

  public init(key: String, column: Column, values: [String]) {
    self.key = key
    switch column {
    case .chs: self.dataCHS = values.joined(separator: "\t")
    case .cht: self.dataCHT = values.joined(separator: "\t")
    case .cns: self.dataCNS = values.joined(separator: "\t")
    case .misc: self.dataMISC = values.joined(separator: "\t")
    case .symb: self.dataSYMB = values.joined(separator: "\t")
    case .chew: self.dataCHEW = values.joined(separator: "\t")
    }
  }

  public init(keyArray: [String], column: Column, values: [String]) {
    self.key = keyArray.joined(separator: "-")
    switch column {
    case .chs: self.dataCHS = values.joined(separator: "\t")
    case .cht: self.dataCHT = values.joined(separator: "\t")
    case .cns: self.dataCNS = values.joined(separator: "\t")
    case .misc: self.dataMISC = values.joined(separator: "\t")
    case .symb: self.dataSYMB = values.joined(separator: "\t")
    case .chew: self.dataCHEW = values.joined(separator: "\t")
    }
  }

  // MARK: Public

  public enum Column: Int {
    case chs = 1
    case cht = 2
    case cns = 3
    case misc = 4
    case symb = 5
    case chew = 6
  }

  @Attribute(.unique)
  public let key: String
  @Attribute
  public let dataCHS: String?
  @Attribute
  public let dataCHT: String?
  @Attribute
  public let dataCNS: String?
  @Attribute
  public let dataMISC: String?
  @Attribute
  public let dataSYMB: String?
  @Attribute
  public let dataCHEW: String?
}

// MARK: - DBRecordRev

@Model
public class DBRecordRev {
  // MARK: Lifecycle

  public init(char: String, readings: [String]) {
    self.char = char
    self.readings = readings.joined(separator: "\t")
  }

  // MARK: Public

  @Attribute(.unique)
  public let char: String
  @Attribute
  public let readings: String
}

// MARK: - DBDataWriter

public struct DBDataWriter {
  // MARK: Lifecycle

  private init?(to sqliteURL: URL) throws {
    self.dbURL = sqliteURL
    self.config = ModelConfiguration(url: dbURL)
    guard let sharedContainer = try? ModelContainer(
      for: DBRecordMain.self,
      DBRecordRev.self,
      configurations: config
    ) else {
      throw Error.initFailure
    }
    self.container = sharedContainer
  }

  // MARK: Public

  public enum Error: LocalizedError {
    case initFailure

    // MARK: Public

    public var errorDescription: String {
      "// 錯誤：無法在目標位置生成/寫入 SQLite 資料。"
    }
  }

  public let dbURL: URL
  public let container: ModelContainer
  public let config: ModelConfiguration

  public static func writeOnce(
    to sqliteURL: URL,
    objects: @escaping () -> [any PersistentModel]
  ) throws {
    guard let writer = try Self(to: sqliteURL) else { return }
    let theContext = ModelContext(writer.container)
    try DBRecordMain.clearAllAt(theContext)
    try DBRecordRev.clearAllAt(theContext)
    try objects().insertInto(theContext)
  }
}

// MARK: - RangeMap Implementations

extension Dictionary where Key == String, Value == [String] {
  func toRevModels() -> [DBRecordRev] {
    var arrResult = [DBRecordRev]()
    forEach { encryptedKey, arrValues in
      arrResult.append(
        .init(char: encryptedKey, readings: arrValues)
      )
    }
    return arrResult
  }

  func toMainModels(_ column: DBRecordMain.Column) -> [DBRecordMain] {
    var arrResult = [DBRecordMain]()
    forEach { encryptedKey, arrValues in
      arrResult.append(
        .init(key: encryptedKey, column: column, values: arrValues)
      )
    }
    return arrResult
  }
}
