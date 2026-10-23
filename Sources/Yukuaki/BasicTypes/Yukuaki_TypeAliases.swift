// (c) 2025 and onwards The vChewing Project (MulanPSL-2.0 License).
// ====================
// This code is released under the SPDX-License-Identifier: `MulanPSL-2.0`.

// MARK: - Yukuaki.TypeAliases

extension Yukuaki {
  public typealias CandidatePairRAW = (keyArray: [String], value: String)

  /// 辭典查詢閉包。給定一組候選讀音（`PossibleKey`），回傳命中的全部 gram。
  public typealias GramQuerier = ([PossibleKey]) -> [Gram]

  /// 辭典可用性檢查閉包。給定一組讀音字串，回傳該讀音是否至少有一條詞條。
  public typealias GramAvailabilityChecker = ([String]) -> Bool

  /// gram 的無識別碼表示法。與 Homa 的同名型別相容。
  public typealias GramRAW = (
    keyArray: [String],
    value: String,
    probability: Double,
    previous: String?,
    anterior: String?
  )
}
