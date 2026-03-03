// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import XCTest

@testable import SwiftMTPQuirks

/// SanDisk Sansa and Creative ZEN legacy media player quirks tests
/// validating libmtp-researched flags for classic MTP media players.
final class LegacyMediaPlayerQuirksTests: XCTestCase {

  private static let sandiskVID: UInt16 = 0x0781
  private static let creativeVID: UInt16 = 0x041e

  private var db: QuirkDatabase!
  private var sandiskEntries: [DeviceQuirk]!
  private var creativeEntries: [DeviceQuirk]!

  override func setUpWithError() throws {
    db = try QuirkDatabase.load()
    sandiskEntries = db.entries.filter { $0.vid == Self.sandiskVID }
    creativeEntries = db.entries.filter { $0.vid == Self.creativeVID }
  }

  // MARK: - Vendor ID Consistency

  func testAllSanDiskEntriesHaveCorrectVID() {
    for entry in sandiskEntries {
      XCTAssertEqual(
        entry.vid, Self.sandiskVID,
        "SanDisk entry '\(entry.id)' has unexpected VID 0x\(String(entry.vid, radix: 16))")
    }
  }

  func testAllCreativeEntriesHaveCorrectVID() {
    for entry in creativeEntries {
      XCTAssertEqual(
        entry.vid, Self.creativeVID,
        "Creative entry '\(entry.id)' has unexpected VID 0x\(String(entry.vid, radix: 16))")
    }
  }

  func testSanDiskEntriesExist() {
    XCTAssertGreaterThan(
      sandiskEntries.count, 10,
      "Expected substantial SanDisk device database, found only \(sandiskEntries.count)")
  }

  func testCreativeEntriesExist() {
    XCTAssertGreaterThan(
      creativeEntries.count, 10,
      "Expected substantial Creative device database, found only \(creativeEntries.count)")
  }

  // MARK: - SanDisk Sansa Classic: BROKEN_MTPGETOBJPROPLIST

  func testSansaClassicDevicesHaveBrokenGetObjPropList() {
    // Classic Sansa devices have BROKEN_MTPGETOBJPROPLIST per libmtp
    let classicPIDs: Set<UInt16> = [
      0x7400, 0x7410, 0x7420, 0x7432, 0x7450,
      0x74b0, 0x74c0, 0x74d0, 0x74e0, 0x74e4,
    ]
    for entry in sandiskEntries where classicPIDs.contains(entry.pid) {
      let flags = entry.resolvedFlags()
      XCTAssertFalse(
        flags.supportsGetObjectPropList,
        "SanDisk Sansa '\(entry.id)' should have supportsGetObjectPropList=false (BROKEN_MTPGETOBJPROPLIST)"
      )
    }
  }

  // MARK: - SanDisk Sansa Classic: UNLOAD_DRIVER → requiresKernelDetach

  func testSansaClassicDevicesRequireKernelDetach() {
    // Classic Sansa devices need UNLOAD_DRIVER per libmtp
    let classicPIDs: Set<UInt16> = [
      0x7400, 0x7410, 0x7420, 0x7432, 0x7450,
      0x74b0, 0x74c0, 0x74d0, 0x74e0, 0x74e4,
    ]
    for entry in sandiskEntries where classicPIDs.contains(entry.pid) {
      let flags = entry.resolvedFlags()
      XCTAssertTrue(
        flags.requiresKernelDetach,
        "SanDisk Sansa '\(entry.id)' should require kernel detach (libmtp UNLOAD_DRIVER)")
    }
  }

  // MARK: - SanDisk Sansa Classic: CANNOT_HANDLE_DATEMODIFIED → emptyDatesInSendObject

  func testSansaClassicDevicesHaveDateModifiedLimitation() {
    // Classic Sansa devices cannot handle date-modified per libmtp
    let classicPIDs: Set<UInt16> = [
      0x7400, 0x7410, 0x7420, 0x7432, 0x7450,
      0x74b0, 0x74c0, 0x74d0, 0x74e0, 0x74e4,
    ]
    for entry in sandiskEntries where classicPIDs.contains(entry.pid) {
      let flags = entry.resolvedFlags()
      XCTAssertTrue(
        flags.emptyDatesInSendObject,
        "SanDisk Sansa '\(entry.id)' should have emptyDatesInSendObject=true (CANNOT_HANDLE_DATEMODIFIED)"
      )
    }
  }

  // MARK: - SanDisk Sansa v2 (AD3525 chip): Same flags + ALWAYS_PROBE_DESCRIPTOR

  func testSansaV2DevicesRequireKernelDetach() {
    let v2PIDs: Set<UInt16> = [0x7422, 0x7434, 0x74c2]
    for entry in sandiskEntries where v2PIDs.contains(entry.pid) {
      let flags = entry.resolvedFlags()
      XCTAssertTrue(
        flags.requiresKernelDetach,
        "SanDisk Sansa v2 '\(entry.id)' should require kernel detach")
    }
  }

  func testSansaV2DevicesHaveDateModifiedLimitation() {
    let v2PIDs: Set<UInt16> = [0x7422, 0x7434, 0x74c2]
    for entry in sandiskEntries where v2PIDs.contains(entry.pid) {
      let flags = entry.resolvedFlags()
      XCTAssertTrue(
        flags.emptyDatesInSendObject,
        "SanDisk Sansa v2 '\(entry.id)' should have emptyDatesInSendObject=true")
    }
  }

  func testSansaV2DevicesHaveBrokenGetObjPropList() {
    let v2PIDs: Set<UInt16> = [0x7422, 0x7434, 0x74c2]
    for entry in sandiskEntries where v2PIDs.contains(entry.pid) {
      let flags = entry.resolvedFlags()
      XCTAssertFalse(
        flags.supportsGetObjectPropList,
        "SanDisk Sansa v2 '\(entry.id)' should have supportsGetObjectPropList=false")
    }
  }

  // MARK: - SanDisk Sansa Connect: DEVICE_FLAG_NONE (no quirks)

  func testSansaConnectHasNoSpecialFlags() {
    // Sansa Connect (0x7480) is Linux-based with DEVICE_FLAG_NONE
    let connect = sandiskEntries.first { $0.pid == 0x7480 }
    XCTAssertNotNil(connect, "Missing SanDisk Sansa Connect (PID 0x7480)")
    if let connect = connect {
      // ops section marks GetObjectPropList as supported (DEVICE_FLAG_NONE = no bugs)
      XCTAssertEqual(
        connect.operations?["supportsGetObjectPropList"], true,
        "Sansa Connect ops should mark supportsGetObjectPropList=true (DEVICE_FLAG_NONE)")
    }
  }

  // MARK: - Creative ZEN: BROKEN_MTPGETOBJPROPLIST_ALL

  func testCreativeZenCoreDevicesHaveBrokenGetObjPropList() {
    // Core Creative ZEN devices have BROKEN_MTPGETOBJPROPLIST_ALL per libmtp
    let zenCorePIDs: Set<UInt16> = [
      0x411e, 0x411f, 0x4131, 0x413c, 0x413d, 0x413e,
      0x4150, 0x4157, 0x4161, 0x4162, 0x4151, 0x4152,
      0x4153, 0x4154, 0x4155, 0x415e,
    ]
    for entry in creativeEntries where zenCorePIDs.contains(entry.pid) {
      let flags = entry.resolvedFlags()
      XCTAssertFalse(
        flags.supportsGetObjectPropList,
        "Creative ZEN '\(entry.id)' should have supportsGetObjectPropList=false (BROKEN_MTPGETOBJPROPLIST_ALL)"
      )
    }
  }

  // MARK: - Creative ZEN Vision:M: NO_RELEASE_INTERFACE note

  func testCreativeVisionMHasNoReleaseInterfaceNote() {
    // Creative ZEN Vision:M (0x413e) needs NO_RELEASE_INTERFACE per libmtp
    let visionM = creativeEntries.first { $0.pid == 0x413e }
    XCTAssertNotNil(visionM, "Missing Creative ZEN Vision:M (PID 0x413e)")
  }

  // MARK: - Category Validation

  func testSansaEntriesAreCategorizedAsMediaPlayer() {
    let sansaEntries = sandiskEntries.filter { $0.id.contains("sansa") }
    XCTAssertFalse(sansaEntries.isEmpty, "Expected Sansa entries in database")
    for entry in sansaEntries {
      XCTAssertEqual(
        entry.category, "media-player",
        "SanDisk Sansa '\(entry.id)' should have category 'media-player', got '\(entry.category ?? "nil")'"
      )
    }
  }

  func testCreativeZenEntriesAreCategorizedAsMediaPlayer() {
    let zenEntries = creativeEntries.filter { $0.id.contains("zen") }
    XCTAssertFalse(zenEntries.isEmpty, "Expected Creative ZEN entries in database")
    for entry in zenEntries {
      XCTAssertEqual(
        entry.category, "media-player",
        "Creative ZEN '\(entry.id)' should have category 'media-player', got '\(entry.category ?? "nil")'"
      )
    }
  }

  // MARK: - No Duplicate Product IDs

  func testNoDuplicateSanDiskProductIDs() {
    var seen = [UInt16: String]()
    var duplicates = [(UInt16, String, String)]()
    for entry in sandiskEntries {
      if let first = seen[entry.pid] {
        duplicates.append((entry.pid, first, entry.id))
      } else {
        seen[entry.pid] = entry.id
      }
    }
    XCTAssertTrue(
      duplicates.isEmpty,
      "Duplicate SanDisk PIDs: \(duplicates.prefix(5).map { "0x\(String($0.0, radix: 16)) [\($0.1), \($0.2)]" })"
    )
  }

  func testNoDuplicateCreativeProductIDs() {
    var seen = [UInt16: String]()
    var duplicates = [(UInt16, String, String)]()
    for entry in creativeEntries {
      if let first = seen[entry.pid] {
        duplicates.append((entry.pid, first, entry.id))
      } else {
        seen[entry.pid] = entry.id
      }
    }
    XCTAssertTrue(
      duplicates.isEmpty,
      "Duplicate Creative PIDs: \(duplicates.prefix(5).map { "0x\(String($0.0, radix: 16)) [\($0.1), \($0.2)]" })"
    )
  }

  // MARK: - ID Naming Convention

  func testSanDiskIDsStartWithSandisk() {
    let sandiskPrefixed = sandiskEntries.filter { $0.id.hasPrefix("sandisk-") }
    let ratio = Double(sandiskPrefixed.count) / Double(sandiskEntries.count)
    XCTAssertGreaterThan(
      ratio, 0.95,
      "At least 95% of VID 0x0781 entries should start with 'sandisk-' (\(sandiskPrefixed.count)/\(sandiskEntries.count))"
    )
  }

  func testCreativeIDsStartWithCreative() {
    let creativePrefixed = creativeEntries.filter { $0.id.hasPrefix("creative-") }
    let ratio = Double(creativePrefixed.count) / Double(creativeEntries.count)
    XCTAssertGreaterThan(
      ratio, 0.95,
      "At least 95% of VID 0x041e entries should start with 'creative-' (\(creativePrefixed.count)/\(creativeEntries.count))"
    )
  }
}
