// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import XCTest

@testable import SwiftMTPCore
import SwiftMTPQuirks
import SwiftMTPTestKit

/// Tests that the QuirkDatabase correctly loads all 26 entries and produces accurate
/// policy flags for each known device via VID/PID matching.
final class QuirkMatchingTests: XCTestCase {

  var db: QuirkDatabase!

  override func setUpWithError() throws {
    db = try QuirkDatabase.load()
  }

  // MARK: - Database Loading

  func testDatabaseLoads26OrMoreEntries() throws {
    XCTAssertGreaterThanOrEqual(db.entries.count, 26, "Expected at least 26 quirk entries")
  }

  func testAllEntriesHaveUniqueIDs() {
    let ids = db.entries.map { $0.id }
    XCTAssertEqual(ids.count, Set(ids).count, "Duplicate quirk IDs found")
  }

  func testAllEntriesHaveStatusField() {
    for entry in db.entries {
      XCTAssertNotNil(entry.status, "Entry \(entry.id) is missing status field")
    }
  }

  func testPromotedEntriesHaveEvidenceRequired() {
    for entry in db.entries where entry.status == .promoted {
      let ev = entry.evidenceRequired ?? []
      XCTAssertFalse(ev.isEmpty, "Promoted entry \(entry.id) must have non-empty evidenceRequired")
    }
  }

  // MARK: - Match Helpers

  /// Match by VID+PID, probing the common interface class/subclass/protocol combos used by real
  /// MTP/PTP devices. In production the exact values come from USB enumeration; in tests we try
  /// all known combinations.
  private func match(vid: UInt16, pid: UInt16, ifaceClass: UInt8? = nil) -> DeviceQuirk? {
    if let ic = ifaceClass {
      return db.match(
        vid: vid, pid: pid, bcdDevice: nil,
        ifaceClass: ic, ifaceSubclass: nil, ifaceProtocol: nil)
    }
    // Probe: (class, subclass, protocol)
    // 0x06/0x01/0x01 = USB Still Image / PTP (cameras, some Android PTP-mode)
    // 0xff/nil/nil    = Android vendor-class MTP
    // 0x08/nil/nil    = USB Mass Storage (rare fallback)
    let combos: [(UInt8, UInt8?, UInt8?)] = [
      (0x06, 0x01, 0x01),
      (0xff, nil, nil),
      (0x08, nil, nil),
    ]
    for (ic, isc, ipr) in combos {
      if let q = db.match(
        vid: vid, pid: pid, bcdDevice: nil,
        ifaceClass: ic, ifaceSubclass: isc, ifaceProtocol: ipr)
      {
        return q
      }
    }
    return nil
  }

  private func flags(vid: UInt16, pid: UInt16, ifaceClass: UInt8? = nil) -> QuirkFlags {
    match(vid: vid, pid: pid, ifaceClass: ifaceClass)?.resolvedFlags() ?? QuirkFlags()
  }

  // MARK: - Xiaomi

  func testXiaomiMiNote2FF10_Matched() {
    XCTAssertNotNil(match(vid: 0x2717, pid: 0xff10))
  }

  func testXiaomiMiNote2FF10_NoPropList() {
    XCTAssertEqual(flags(vid: 0x2717, pid: 0xff10).supportsGetObjectPropList, false)
  }

  func testXiaomiMiNote2FF10_RequiresKernelDetach() {
    let q = match(vid: 0x2717, pid: 0xff10)!
    XCTAssertEqual(q.flags?.requiresKernelDetach, true)
  }

  func testXiaomiMiNote2FF40_Matched() {
    XCTAssertNotNil(match(vid: 0x2717, pid: 0xff40))
  }

  func testXiaomiMiNote2FF40_NoPropList() {
    XCTAssertEqual(flags(vid: 0x2717, pid: 0xff40).supportsGetObjectPropList, false)
  }

  // MARK: - Samsung

  func testSamsungGalaxy6860_Matched() {
    XCTAssertNotNil(match(vid: 0x04e8, pid: 0x6860))
  }

  func testSamsungGalaxy6860_SupportsPropList() {
    XCTAssertEqual(flags(vid: 0x04e8, pid: 0x6860).supportsGetObjectPropList, true)
  }

  func testSamsungGalaxy6860_LongTimeout() {
    let q = match(vid: 0x04e8, pid: 0x6860)!
    XCTAssertGreaterThanOrEqual(q.ioTimeoutMs ?? 0, 10000)
  }

  func testSamsungGalaxyMtpAdb685c_Matched() {
    XCTAssertNotNil(match(vid: 0x04e8, pid: 0x685c))
  }

  func testSamsungGalaxyMtpAdb685c_NoPropList() {
    XCTAssertEqual(flags(vid: 0x04e8, pid: 0x685c).supportsGetObjectPropList, false)
  }

  func testSamsungGalaxyMtpAdb685c_LongTimeout() {
    let q = match(vid: 0x04e8, pid: 0x685c)!
    XCTAssertGreaterThanOrEqual(q.ioTimeoutMs ?? 0, 20000)
  }

  // MARK: - Google Pixel/Nexus

  func testGooglePixel7_4ee1_Matched() {
    XCTAssertNotNil(match(vid: 0x18d1, pid: 0x4ee1))
  }

  func testGooglePixel7_4ee1_SupportsPropList() {
    XCTAssertEqual(flags(vid: 0x18d1, pid: 0x4ee1).supportsGetObjectPropList, true)
  }

  func testGoogleNexusMtpAdb_4ee2_Matched() {
    XCTAssertNotNil(match(vid: 0x18d1, pid: 0x4ee2))
  }

  func testGoogleNexusMtpAdb_4ee2_NoPropList() {
    XCTAssertEqual(flags(vid: 0x18d1, pid: 0x4ee2).supportsGetObjectPropList, false)
  }

  func testGooglePixel34_4eed_Matched() {
    XCTAssertNotNil(match(vid: 0x18d1, pid: 0x4eed))
  }

  func testGooglePixel34_4eed_SupportsPropList() {
    XCTAssertEqual(flags(vid: 0x18d1, pid: 0x4eed).supportsGetObjectPropList, true)
  }

  // MARK: - OnePlus

  func testOnePlus3t_f003_Matched() {
    XCTAssertNotNil(match(vid: 0x2a70, pid: 0xf003))
  }

  func testOnePlus3t_f003_NoPropList() {
    XCTAssertEqual(flags(vid: 0x2a70, pid: 0xf003).supportsGetObjectPropList, false)
  }

  func testOnePlus9_9011_Matched() {
    XCTAssertNotNil(match(vid: 0x2a70, pid: 0x9011))
  }

  func testOnePlus9_9011_SupportsPropList() {
    XCTAssertEqual(flags(vid: 0x2a70, pid: 0x9011).supportsGetObjectPropList, true)
  }

  // MARK: - Motorola

  func testMotorolaMtp_2e82_Matched() {
    XCTAssertNotNil(match(vid: 0x22b8, pid: 0x2e82))
  }

  func testMotorolaMtp_2e82_SupportsPropList() {
    XCTAssertEqual(flags(vid: 0x22b8, pid: 0x2e82).supportsGetObjectPropList, true)
  }

  func testMotorolaMtpAdb_2e76_Matched() {
    XCTAssertNotNil(match(vid: 0x22b8, pid: 0x2e76))
  }

  func testMotorolaMtpAdb_2e76_NoPropList() {
    XCTAssertEqual(flags(vid: 0x22b8, pid: 0x2e76).supportsGetObjectPropList, false)
  }

  // MARK: - Sony Xperia

  func testSonyXperiaZ_0193_Matched() {
    XCTAssertNotNil(match(vid: 0x0fce, pid: 0x0193))
  }

  func testSonyXperiaZ_0193_SupportsPropList() {
    XCTAssertEqual(flags(vid: 0x0fce, pid: 0x0193).supportsGetObjectPropList, true)
  }

  func testSonyXperiaZ3_01ba_Matched() {
    XCTAssertNotNil(match(vid: 0x0fce, pid: 0x01ba))
  }

  func testSonyXperiaXZ1_01f3_Matched() {
    XCTAssertNotNil(match(vid: 0x0fce, pid: 0x01f3))
  }

  // MARK: - LG

  func testLGAndroid_633e_Matched() {
    XCTAssertNotNil(match(vid: 0x1004, pid: 0x633e))
  }

  func testLGAndroid_633e_NoPropList() {
    XCTAssertEqual(flags(vid: 0x1004, pid: 0x633e).supportsGetObjectPropList, false)
  }

  func testLGAndroid_6300_Matched() {
    XCTAssertNotNil(match(vid: 0x1004, pid: 0x6300))
  }

  // MARK: - HTC

  func testHTCAndroid_0f15_Matched() {
    XCTAssertNotNil(match(vid: 0x0bb4, pid: 0x0f15))
  }

  func testHTCAndroid_0f15_NoPropList() {
    XCTAssertEqual(flags(vid: 0x0bb4, pid: 0x0f15).supportsGetObjectPropList, false)
  }

  // MARK: - Huawei

  func testHuaweiAndroid_107e_Matched() {
    XCTAssertNotNil(match(vid: 0x12d1, pid: 0x107e))
  }

  func testHuaweiAndroid_107e_NoPropList() {
    XCTAssertEqual(flags(vid: 0x12d1, pid: 0x107e).supportsGetObjectPropList, false)
  }

  // MARK: - Canon

  func testCanonEOSRebel_3139_Matched() {
    XCTAssertNotNil(match(vid: 0x04a9, pid: 0x3139))
  }

  func testCanonEOSRebel_3139_NoPropList() {
    XCTAssertEqual(flags(vid: 0x04a9, pid: 0x3139).supportsGetObjectPropList, false)
  }

  func testCanonEOS5D3_3234_Matched() {
    XCTAssertNotNil(match(vid: 0x04a9, pid: 0x3234))
  }

  func testCanonEOS5D3_3234_SupportsPropList() {
    XCTAssertEqual(flags(vid: 0x04a9, pid: 0x3234).supportsGetObjectPropList, true)
  }

  func testCanonEOSR5_32b4_Matched() {
    XCTAssertNotNil(match(vid: 0x04a9, pid: 0x32b4))
  }

  func testCanonEOSR5_32b4_SupportsPropList() {
    XCTAssertEqual(flags(vid: 0x04a9, pid: 0x32b4).supportsGetObjectPropList, true)
  }

  func testCanonEOSR3_32b5_Matched() {
    XCTAssertNotNil(match(vid: 0x04a9, pid: 0x32b5))
  }

  // MARK: - Nikon

  func testNikonDSLR_0410_Matched() {
    XCTAssertNotNil(match(vid: 0x04b0, pid: 0x0410))
  }

  func testNikonDSLR_0410_NoPropList() {
    XCTAssertEqual(flags(vid: 0x04b0, pid: 0x0410).supportsGetObjectPropList, false)
  }

  func testNikonZ6Z7_0441_Matched() {
    XCTAssertNotNil(match(vid: 0x04b0, pid: 0x0441))
  }

  func testNikonZ6Z7_0441_NoPropList() {
    XCTAssertEqual(flags(vid: 0x04b0, pid: 0x0441).supportsGetObjectPropList, false)
  }

  func testNikonZ6IIZ7II_0442_Matched() {
    XCTAssertNotNil(match(vid: 0x04b0, pid: 0x0442))
  }

  // MARK: - Fujifilm

  func testFujifilmXSeries_0104_Matched() {
    XCTAssertNotNil(match(vid: 0x04cb, pid: 0x0104))
  }

  func testFujifilmXSeries_0104_NoPropList() {
    XCTAssertEqual(flags(vid: 0x04cb, pid: 0x0104).supportsGetObjectPropList, false)
  }

  // MARK: - No-match guard

  func testUnknownDevice_ReturnsNil() {
    XCTAssertNil(match(vid: 0xdead, pid: 0xbeef))
  }

  func testWrongPID_ReturnsNil() {
    // Correct Xiaomi VID but wrong PID
    XCTAssertNil(match(vid: 0x2717, pid: 0x0001))
  }

  // MARK: - Timeout / tuning spot-checks

  func testCanonLongTimeout() {
    let q = match(vid: 0x04a9, pid: 0x3139)!
    XCTAssertGreaterThanOrEqual(q.ioTimeoutMs ?? 0, 20000, "Cameras need long I/O timeout")
  }

  func testNikonLongTimeout() {
    let q = match(vid: 0x04b0, pid: 0x0410)!
    XCTAssertGreaterThanOrEqual(q.ioTimeoutMs ?? 0, 20000, "Cameras need long I/O timeout")
  }

  func testXiaomiTimeout() {
    let q = match(vid: 0x2717, pid: 0xff10)!
    XCTAssertGreaterThanOrEqual(q.ioTimeoutMs ?? 0, 10000)
  }

  // MARK: - VirtualDeviceConfig factory smoke tests

  func testSamsungGalaxyPreset_MatchesQuirk() {
    let cfg = VirtualDeviceConfig.samsungGalaxy
    XCTAssertNotNil(
      match(vid: cfg.summary.vendorID!, pid: cfg.summary.productID!),
      "samsungGalaxy preset should match a quirk entry")
  }

  func testSamsungGalaxyMtpAdbPreset_MatchesQuirk() {
    let cfg = VirtualDeviceConfig.samsungGalaxyMtpAdb
    XCTAssertNotNil(match(vid: cfg.summary.vendorID!, pid: cfg.summary.productID!))
  }

  func testGooglePixelAdbPreset_MatchesQuirk() {
    let cfg = VirtualDeviceConfig.googlePixelAdb
    XCTAssertNotNil(match(vid: cfg.summary.vendorID!, pid: cfg.summary.productID!))
  }

  func testMotorolaMotoGPreset_MatchesQuirk() {
    let cfg = VirtualDeviceConfig.motorolaMotoG
    XCTAssertNotNil(match(vid: cfg.summary.vendorID!, pid: cfg.summary.productID!))
  }

  func testSonyXperiaZPreset_MatchesQuirk() {
    let cfg = VirtualDeviceConfig.sonyXperiaZ
    XCTAssertNotNil(match(vid: cfg.summary.vendorID!, pid: cfg.summary.productID!))
  }

  func testCanonEOSR5Preset_MatchesQuirk() {
    let cfg = VirtualDeviceConfig.canonEOSR5
    XCTAssertNotNil(match(vid: cfg.summary.vendorID!, pid: cfg.summary.productID!))
  }

  func testNikonZ6Preset_MatchesQuirk() {
    let cfg = VirtualDeviceConfig.nikonZ6
    XCTAssertNotNil(match(vid: cfg.summary.vendorID!, pid: cfg.summary.productID!))
  }

  func testOnePlus9Preset_MatchesQuirk() {
    let cfg = VirtualDeviceConfig.onePlus9
    XCTAssertNotNil(match(vid: cfg.summary.vendorID!, pid: cfg.summary.productID!))
  }

  func testLGAndroidPreset_MatchesQuirk() {
    let cfg = VirtualDeviceConfig.lgAndroid
    XCTAssertNotNil(
      match(vid: cfg.summary.vendorID!, pid: cfg.summary.productID!),
      "lgAndroid preset should match lg-android-633e quirk entry")
  }

  func testHTCAndroidPreset_MatchesQuirk() {
    let cfg = VirtualDeviceConfig.htcAndroid
    XCTAssertNotNil(
      match(vid: cfg.summary.vendorID!, pid: cfg.summary.productID!),
      "htcAndroid preset should match htc-android-0f15 quirk entry")
  }

  func testHuaweiAndroidPreset_MatchesQuirk() {
    let cfg = VirtualDeviceConfig.huaweiAndroid
    XCTAssertNotNil(
      match(vid: cfg.summary.vendorID!, pid: cfg.summary.productID!),
      "huaweiAndroid preset should match huawei-android-107e quirk entry")
  }

  func testFujifilmXPreset_MatchesQuirk() {
    let cfg = VirtualDeviceConfig.fujifilmX
    XCTAssertNotNil(
      match(vid: cfg.summary.vendorID!, pid: cfg.summary.productID!),
      "fujifilmX preset should match fujifilm-x-series-0104 quirk entry")
  }

  func testLGAndroid_NoPropList() {
    let cfg = VirtualDeviceConfig.lgAndroid
    XCTAssertFalse(
      flags(vid: cfg.summary.vendorID!, pid: cfg.summary.productID!).supportsGetObjectPropList)
    XCTAssertFalse(cfg.info.operationsSupported.contains(0x9805))
  }

  func testHuawei_NoPropList() {
    let cfg = VirtualDeviceConfig.huaweiAndroid
    XCTAssertFalse(
      flags(vid: cfg.summary.vendorID!, pid: cfg.summary.productID!).supportsGetObjectPropList)
    XCTAssertFalse(cfg.info.operationsSupported.contains(0x9805))
  }

  func testFujifilm_SupportsPropList() {
    // fujifilm-x-series-0104 quirk has supportsGetObjectPropList=false; verify preset is consistent
    let cfg = VirtualDeviceConfig.fujifilmX
    let f = flags(vid: cfg.summary.vendorID!, pid: cfg.summary.productID!)
    let presetHasPropList = cfg.info.operationsSupported.contains(0x9805)
    XCTAssertEqual(presetHasPropList, f.supportsGetObjectPropList)
  }

  // MARK: - Policy consistency: VirtualDeviceConfig propList support matches quirk

  func testSamsungGalaxy_PresetOpsPropListConsistentWithQuirk() {
    let cfg = VirtualDeviceConfig.samsungGalaxy
    let f = flags(vid: cfg.summary.vendorID!, pid: cfg.summary.productID!)
    let presetHasPropList = cfg.info.operationsSupported.contains(0x9805)
    XCTAssertEqual(
      presetHasPropList, f.supportsGetObjectPropList,
      "samsungGalaxy preset propList ops must match quirk flags")
  }

  func testSamsungGalaxyMtpAdb_PresetOpsPropListConsistentWithQuirk() {
    let cfg = VirtualDeviceConfig.samsungGalaxyMtpAdb
    let f = flags(vid: cfg.summary.vendorID!, pid: cfg.summary.productID!)
    let presetHasPropList = cfg.info.operationsSupported.contains(0x9805)
    XCTAssertEqual(presetHasPropList, f.supportsGetObjectPropList)
  }

  func testMotorolaMotoG_PresetOpsPropListConsistentWithQuirk() {
    let cfg = VirtualDeviceConfig.motorolaMotoG
    let f = flags(vid: cfg.summary.vendorID!, pid: cfg.summary.productID!)
    let presetHasPropList = cfg.info.operationsSupported.contains(0x9805)
    XCTAssertEqual(presetHasPropList, f.supportsGetObjectPropList)
  }

  // MARK: - PTP class-based heuristic (unrecognized camera)

  func testUnrecognizedPTPCamera_GetsHeuristicPropListEnabled() {
    // An unrecognized device (unknown VID:PID) with PTP class 0x06 should get
    // supportsGetObjectPropList=true via the class-based heuristic.
    let policy = EffectiveTuningBuilder.buildPolicy(
      capabilities: [:],
      learned: nil,
      quirk: nil,
      overrides: nil,
      ifaceClass: 0x06
    )
    XCTAssertTrue(
      policy.flags.supportsGetObjectPropList,
      "Unrecognized PTP-class camera should default to supportsGetObjectPropList=true")
    XCTAssertFalse(
      policy.flags.requiresKernelDetach,
      "PTP-class camera should not require kernel detach")
  }

  func testUnrecognizedAndroidDevice_GetConservativeDefaults() {
    // An unrecognized vendor-class (0xff) device should get conservative defaults
    // (no proplist) since we can't know if it supports it.
    let policy = EffectiveTuningBuilder.buildPolicy(
      capabilities: [:],
      learned: nil,
      quirk: nil,
      overrides: nil,
      ifaceClass: 0xFF
    )
    XCTAssertFalse(
      policy.flags.supportsGetObjectPropList,
      "Unrecognized vendor-class device should default to supportsGetObjectPropList=false")
  }

  func testUnrecognizedNoClass_GetConservativeDefaults() {
    // No quirk, no class → conservative defaults
    let policy = EffectiveTuningBuilder.buildPolicy(
      capabilities: [:],
      learned: nil,
      quirk: nil,
      overrides: nil,
      ifaceClass: nil
    )
    XCTAssertFalse(policy.flags.supportsGetObjectPropList)
  }

  // MARK: - Wave-3 new brand smoke tests

  func testDatabase222OrMoreEntries() {
    XCTAssertGreaterThanOrEqual(db.entries.count, 222, "Expected at least 222 quirk entries")
  }

  func testDatabase395OrMoreEntries() {
    XCTAssertGreaterThanOrEqual(db.entries.count, 10500, "Expected at least 10500 quirk entries")
  }

  // Nokia
  func testNokiaAndroid_MatchesQuirk() {
    XCTAssertNotNil(match(vid: 0x2e04, pid: 0xc025), "Nokia 6 should match a quirk")
  }

  func testNokiaAndroid_NoPropList() {
    XCTAssertEqual(flags(vid: 0x2e04, pid: 0xc025).supportsGetObjectPropList, false)
  }

  // ZTE
  func testZTEAndroid_MatchesQuirk() {
    XCTAssertNotNil(match(vid: 0x19d2, pid: 0x0306), "ZTE Blade 3 should match a quirk")
  }

  func testZTEAndroid_NoPropList() {
    XCTAssertEqual(flags(vid: 0x19d2, pid: 0x0306).supportsGetObjectPropList, false)
  }

  // Amazon
  func testAmazonKindleFire_MatchesQuirk() {
    XCTAssertNotNil(match(vid: 0x1949, pid: 0x0007), "Amazon Kindle Fire should match a quirk")
  }

  func testAmazonKindleFire_NoPropList() {
    XCTAssertEqual(flags(vid: 0x1949, pid: 0x0007).supportsGetObjectPropList, false)
  }

  // Lenovo
  func testLenovoAndroid_MatchesQuirk() {
    XCTAssertNotNil(match(vid: 0x17ef, pid: 0x740a), "Lenovo K1 should match a quirk")
  }

  func testLenovoAndroid_NoPropList() {
    XCTAssertEqual(flags(vid: 0x17ef, pid: 0x740a).supportsGetObjectPropList, false)
  }

  // Nikon mirrorless (Z6, proplist supported)
  func testNikonMirrorless_MatchesQuirk() {
    XCTAssertNotNil(match(vid: 0x04b0, pid: 0x0443), "Nikon Z6 should match a quirk")
  }

  func testNikonMirrorless_SupportsPropList() {
    XCTAssertEqual(flags(vid: 0x04b0, pid: 0x0443).supportsGetObjectPropList, true)
  }

  // Canon EOS R
  func testCanonEOSR_MatchesQuirk() {
    XCTAssertNotNil(match(vid: 0x04a9, pid: 0x32da), "Canon EOS R should match a quirk")
  }

  func testCanonEOSR_SupportsPropList() {
    XCTAssertEqual(flags(vid: 0x04a9, pid: 0x32da).supportsGetObjectPropList, true)
  }

  // Sony Alpha
  func testSonyAlpha_MatchesQuirk() {
    XCTAssertNotNil(match(vid: 0x054c, pid: 0x0c03), "Sony Alpha a7 III should match a quirk")
  }

  func testSonyAlpha_SupportsPropList() {
    XCTAssertEqual(flags(vid: 0x054c, pid: 0x0c03).supportsGetObjectPropList, true)
  }

  // Leica
  func testLeica_MatchesQuirk() {
    XCTAssertNotNil(match(vid: 0x1a98, pid: 0x2041), "Leica SL should match a quirk")
  }

  func testLeica_SupportsPropList() {
    XCTAssertEqual(flags(vid: 0x1a98, pid: 0x2041).supportsGetObjectPropList, true)
  }

  // GoPro
  func testGoProHero_MatchesQuirk() {
    XCTAssertNotNil(match(vid: 0x2672, pid: 0x0056), "GoPro HERO10 Black should match a quirk")
  }

  func testGoProHero_SupportsPropList() {
    XCTAssertEqual(flags(vid: 0x2672, pid: 0x0056).supportsGetObjectPropList, true)
  }

  // Wave-3 preset smoke tests
  func testNokiaAndroidPreset_MatchesQuirk() {
    let cfg = VirtualDeviceConfig.nokiaAndroid
    XCTAssertNotNil(match(vid: cfg.summary.vendorID!, pid: cfg.summary.productID!))
  }

  func testZTEAndroidPreset_MatchesQuirk() {
    let cfg = VirtualDeviceConfig.zteAndroid
    XCTAssertNotNil(match(vid: cfg.summary.vendorID!, pid: cfg.summary.productID!))
  }

  func testAmazonKindleFirePreset_MatchesQuirk() {
    let cfg = VirtualDeviceConfig.amazonKindleFire
    XCTAssertNotNil(match(vid: cfg.summary.vendorID!, pid: cfg.summary.productID!))
  }

  func testLenovoAndroidPreset_MatchesQuirk() {
    let cfg = VirtualDeviceConfig.lenovoAndroid
    XCTAssertNotNil(match(vid: cfg.summary.vendorID!, pid: cfg.summary.productID!))
  }

  func testNikonMirrorlessPreset_MatchesQuirk() {
    let cfg = VirtualDeviceConfig.nikonMirrorless
    XCTAssertNotNil(match(vid: cfg.summary.vendorID!, pid: cfg.summary.productID!))
  }

  func testCanonEOSRPreset_MatchesQuirk() {
    let cfg = VirtualDeviceConfig.canonEOSR
    XCTAssertNotNil(match(vid: cfg.summary.vendorID!, pid: cfg.summary.productID!))
  }

  func testSonyAlphaPreset_MatchesQuirk() {
    let cfg = VirtualDeviceConfig.sonyAlpha
    XCTAssertNotNil(match(vid: cfg.summary.vendorID!, pid: cfg.summary.productID!))
  }

  func testLeicaPreset_MatchesQuirk() {
    let cfg = VirtualDeviceConfig.leica
    XCTAssertNotNil(match(vid: cfg.summary.vendorID!, pid: cfg.summary.productID!))
  }

  func testGoProHeroPreset_MatchesQuirk() {
    let cfg = VirtualDeviceConfig.goProHero
    XCTAssertNotNil(match(vid: cfg.summary.vendorID!, pid: cfg.summary.productID!))
  }

  // MARK: - Wave-5 brand tests

  // Alcatel/TCL
  func testAlcatelAndroid_MatchesQuirk() {
    XCTAssertNotNil(match(vid: 0x1bbb, pid: 0x901b), "Alcatel A405DL should match a quirk")
  }

  func testAlcatelAndroid_NoPropList() {
    XCTAssertEqual(flags(vid: 0x1bbb, pid: 0x901b).supportsGetObjectPropList, false)
  }

  // Sharp
  func testSharpAquos_MatchesQuirk() {
    XCTAssertNotNil(match(vid: 0x04dd, pid: 0x99d2), "Sharp AQUOS U should match a quirk")
  }

  func testSharpAquos_NoPropList() {
    XCTAssertEqual(flags(vid: 0x04dd, pid: 0x99d2).supportsGetObjectPropList, false)
  }

  // Kyocera
  func testKyoceraAndroid_MatchesQuirk() {
    XCTAssertNotNil(match(vid: 0x0482, pid: 0x0571), "Kyocera Rise should match a quirk")
  }

  func testKyoceraAndroid_NoPropList() {
    XCTAssertEqual(flags(vid: 0x0482, pid: 0x0571).supportsGetObjectPropList, false)
  }

  // Fairphone
  func testFairphone2_MatchesQuirk() {
    XCTAssertNotNil(match(vid: 0x2ae5, pid: 0x6764), "Fairphone 2 should match a quirk")
  }

  func testFairphone2_NoPropList() {
    XCTAssertEqual(flags(vid: 0x2ae5, pid: 0x6764).supportsGetObjectPropList, false)
  }

  // Fujifilm X-T10
  func testFujifilmXT10_MatchesQuirk() {
    XCTAssertNotNil(match(vid: 0x04cb, pid: 0x02c8), "Fujifilm X-T10 should match a quirk")
  }

  func testFujifilmXT10_SupportsPropList() {
    XCTAssertEqual(flags(vid: 0x04cb, pid: 0x02c8).supportsGetObjectPropList, true)
  }

  // Casio Exilim
  func testCasioExilim_MatchesQuirk() {
    XCTAssertNotNil(match(vid: 0x07cf, pid: 0x1042), "Casio Exilim should match a quirk")
  }

  func testCasioExilim_SupportsPropList() {
    XCTAssertEqual(flags(vid: 0x07cf, pid: 0x1042).supportsGetObjectPropList, true)
  }

  // GoPro HERO11
  func testGoproHero11_MatchesQuirk() {
    XCTAssertNotNil(match(vid: 0x2672, pid: 0x0059), "GoPro HERO11 Black should match a quirk")
  }

  func testGoproHero11_SupportsPropList() {
    XCTAssertEqual(flags(vid: 0x2672, pid: 0x0059).supportsGetObjectPropList, true)
  }

  // Garmin Fenix
  func testGarminFenix_MatchesQuirk() {
    XCTAssertNotNil(match(vid: 0x091e, pid: 0x4cda), "Garmin Fenix 6 Pro should match a quirk")
  }

  func testGarminFenix_NoPropList() {
    XCTAssertEqual(flags(vid: 0x091e, pid: 0x4cda).supportsGetObjectPropList, false)
  }

  // Honor
  func testHonorAndroid_MatchesQuirk() {
    XCTAssertNotNil(match(vid: 0x339b, pid: 0x107d), "Honor X8/X9 5G should match a quirk")
  }

  func testHonorAndroid_NoPropList() {
    XCTAssertEqual(flags(vid: 0x339b, pid: 0x107d).supportsGetObjectPropList, false)
  }

  // Wave-5 preset smoke tests
  func testAlcatelAndroidPreset_MatchesQuirk() {
    let cfg = VirtualDeviceConfig.alcatelAndroid
    XCTAssertNotNil(match(vid: cfg.summary.vendorID!, pid: cfg.summary.productID!))
  }

  func testSharpAquosPreset_MatchesQuirk() {
    let cfg = VirtualDeviceConfig.sharpAquos
    XCTAssertNotNil(match(vid: cfg.summary.vendorID!, pid: cfg.summary.productID!))
  }

  func testKyoceraAndroidPreset_MatchesQuirk() {
    let cfg = VirtualDeviceConfig.kyoceraAndroid
    XCTAssertNotNil(match(vid: cfg.summary.vendorID!, pid: cfg.summary.productID!))
  }

  func testFairphone2Preset_MatchesQuirk() {
    let cfg = VirtualDeviceConfig.fairphone2
    XCTAssertNotNil(match(vid: cfg.summary.vendorID!, pid: cfg.summary.productID!))
  }

  func testFujifilmXT10Preset_MatchesQuirk() {
    let cfg = VirtualDeviceConfig.fujifilmXT10
    XCTAssertNotNil(match(vid: cfg.summary.vendorID!, pid: cfg.summary.productID!))
  }

  func testCasioExilimPreset_MatchesQuirk() {
    let cfg = VirtualDeviceConfig.casioExilim
    XCTAssertNotNil(match(vid: cfg.summary.vendorID!, pid: cfg.summary.productID!))
  }

  func testGoproHero11Preset_MatchesQuirk() {
    let cfg = VirtualDeviceConfig.goproHero11
    XCTAssertNotNil(match(vid: cfg.summary.vendorID!, pid: cfg.summary.productID!))
  }

  func testGarminFenixPreset_MatchesQuirk() {
    let cfg = VirtualDeviceConfig.garminFenix
    XCTAssertNotNil(match(vid: cfg.summary.vendorID!, pid: cfg.summary.productID!))
  }

  func testHonorAndroidPreset_MatchesQuirk() {
    let cfg = VirtualDeviceConfig.honorAndroid
    XCTAssertNotNil(match(vid: cfg.summary.vendorID!, pid: cfg.summary.productID!))
  }
}
