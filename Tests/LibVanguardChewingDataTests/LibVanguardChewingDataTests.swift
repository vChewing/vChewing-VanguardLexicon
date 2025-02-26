// (c) 2021 and onwards The vChewing Project (BSD-3-Clause).
// ====================
// This code is released under the SPDX-License-Identifier: `BSD-3-Clause`.

import Foundation
@testable import LibVanguardChewingData
import Testing

@Test
func testCollectorInitialization() async throws {
  let actorTested = try VCDataBuilder.Collector(isCHS: nil, cns: true)
  NSLog("Collector booting complete with all files collected.")
  let norm = await actorTested.norm
  NSLog("Star propagating weights using norm: \(norm)")
  let startDate = Date.now
  await actorTested.propagateWeights()
  let secondsDelta = Date.now.timeIntervalSince1970 - startDate.timeIntervalSince1970
  NSLog("Weight propagation complete. Time costed as seconds: \(secondsDelta)")
  print(await actorTested.unigramsCHS.values.map(\.values.count).reduce(0, +))
  print(await actorTested.unigramsCHT.values.map(\.values.count).reduce(0, +))
  print(await actorTested.reverseLookupTable.count)
  print(await actorTested.reverseLookupTable4NonKanji.count)
  print(await actorTested.tableKanjiCNS.values.map(\.count).reduce(0, +))
  print(await actorTested.reverseLookupTable4CNS.count)
}

@Test
func testCollectorSanityCheckCHS() async throws {
  let actorTested = try VCDataBuilder.Collector(isCHS: true)
  NSLog("Collector booting complete with all files collected.")
  let norm = await actorTested.norm
  NSLog("Star propagating weights using norm: \(norm)")
  let startDate = Date.now
  await actorTested.propagateWeights()
  let secondsDelta = Date.now.timeIntervalSince1970 - startDate.timeIntervalSince1970
  NSLog("Weight propagation complete. Time costed as seconds: \(secondsDelta)")
  print(await actorTested.unigramsCHS.values.map(\.values.count).reduce(0, +))
  print(await actorTested.healthCheck(isCHS: true))
}

@Test
func testCollectorSanityCheckCHT() async throws {
  let actorTested = try VCDataBuilder.Collector(isCHS: false)
  NSLog("Collector booting complete with all files collected.")
  let norm = await actorTested.norm
  NSLog("Star propagating weights using norm: \(norm)")
  let startDate = Date.now
  await actorTested.propagateWeights()
  let secondsDelta = Date.now.timeIntervalSince1970 - startDate.timeIntervalSince1970
  NSLog("Weight propagation complete. Time costed as seconds: \(secondsDelta)")
  print(await actorTested.unigramsCHT.values.map(\.values.count).reduce(0, +))
  print(await actorTested.healthCheck(isCHS: false))
}
