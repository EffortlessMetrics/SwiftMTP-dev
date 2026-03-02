// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import XCTest

@testable import SwiftMTPQuirks

/// Motorola (VID 0x22b8) and LG (VID 0x1004) quirks tests.
///
/// Both are major Android OEMs with unique MTP implementations:
/// - Motorola: near-stock Android MTP, but libmtp documents
///   DEVICE_FLAG_BROKEN_SET_OBJECT_PROPLIST across the entire vendor range.
///   Newer Moto E/G/Z devices (0x2e82) have a fixed MTP stack that
///   supports GetObjectPropList, while older devices do not.
/// - LG: Android-based MTP with DEVICE_FLAGS_ANDROID_BUGS in libmtp.
///   Older feature phones (VX8550, GR-500, KM900) have broken
///   GetObjectPropList. Android phones use standard Android MTP stack.
final class MotorolaLGQuirksTests: XCTestCase {

  // MARK: - Constants

  private static let motorolaVID: UInt16 = 0x22b8
  private static let lgVID: UInt16 = 0x1004

  // MARK: - Properties

  private var db: QuirkDatabase!
  private var motorolaEntries: [DeviceQuirk]!
  private var lgEntries: [DeviceQuirk]!

  override func setUpWithError() throws {
    db = try QuirkDatabase.load()
    motorolaEntries = db.entries.filter { $0.vid == Self.motorolaVID }
    lgEntries = db.entries.filter { $0.vid == Self.lgVID }
  }

  // MARK: - Motorola VID Consistency

  func testAllMotorolaEntriesHaveCorrectVID() {
    for entry in motorolaEntries {
      XCTAssertEqual(
        entry.vid, Self.motorolaVID,
        "Motorola entry '\(entry.id)' has unexpected VID 0x\(String(entry.vid, radix: 16))")
    }
  }

  func testMotorolaEntriesExist() {
    XCTAssertGreaterThan(
      motorolaEntries.count, 100,
      "Expected a substantial Motorola device database, found only \(motorolaEntries.count)")
  }

  // MARK: - LG VID Consistency

  func testAllLGEntriesHaveCorrectVID() {
    for entry in lgEntries {
      XCTAssertEqual(
        entry.vid, Self.lgVID,
        "LG entry '\(entry.id)' has unexpected VID 0x\(String(entry.vid, radix: 16))")
    }
  }

  func testLGEntriesExist() {
    XCTAssertGreaterThan(
      lgEntries.count, 50,
      "Expected a substantial LG device database, found only \(lgEntries.count)")
  }

  // MARK: - No Duplicate Product IDs

  func testNoDuplicateMotorolaProductIDs() {
    var seen = [UInt16: String]()
    var duplicates = [(UInt16, String, String)]()
    for entry in motorolaEntries {
      if let first = seen[entry.pid] {
        duplicates.append((entry.pid, first, entry.id))
      } else {
        seen[entry.pid] = entry.id
      }
    }
    XCTAssertTrue(
      duplicates.isEmpty,
      "Duplicate Motorola PIDs: \(duplicates.prefix(10).map { "0x\(String($0.0, radix: 16)) [\($0.1), \($0.2)]" })"
    )
  }

  func testNoDuplicateLGProductIDs() {
    var seen = [UInt16: String]()
    var duplicates = [(UInt16, String, String)]()
    for entry in lgEntries {
      if let first = seen[entry.pid] {
        duplicates.append((entry.pid, first, entry.id))
      } else {
        seen[entry.pid] = entry.id
      }
    }
    XCTAssertTrue(
      duplicates.isEmpty,
      "Duplicate LG PIDs: \(duplicates.prefix(10).map { "0x\(String($0.0, radix: 16)) [\($0.1), \($0.2)]" })"
    )
  }

  // MARK: - Naming Conventions

  func testMajorityOfMotorolaIDsStartWithMotorola() {
    // Some entries use "moto-" prefix (e.g. moto-edge-50-ultra) which is acceptable
    let motorolaPrefixed = motorolaEntries.filter {
      $0.id.hasPrefix("motorola-") || $0.id.hasPrefix("moto-")
    }
    let ratio = Double(motorolaPrefixed.count) / Double(motorolaEntries.count)
    XCTAssertGreaterThan(
      ratio, 0.95,
      "At least 95% of VID 0x22b8 entries should start with 'motorola-' or 'moto-' (\(motorolaPrefixed.count)/\(motorolaEntries.count))"
    )
  }

  func testMajorityOfLGIDsStartWithLG() {
    let lgPrefixed = lgEntries.filter { $0.id.hasPrefix("lg-") }
    let ratio = Double(lgPrefixed.count) / Double(lgEntries.count)
    XCTAssertGreaterThan(
      ratio, 0.95,
      "At least 95% of VID 0x1004 entries should start with 'lg-' (\(lgPrefixed.count)/\(lgEntries.count))"
    )
  }

  // MARK: - Category Validation

  func testMotorolaPhonesAreCategorizedAsPhone() {
    let phones = motorolaEntries.filter {
      $0.id.contains("moto") && !$0.id.contains("xoom") && !$0.id.contains("ideapad")
    }
    for entry in phones {
      if let cat = entry.category {
        XCTAssertTrue(
          cat == "phone" || cat == "body-camera",
          "Motorola entry '\(entry.id)' has unexpected category '\(cat)'")
      }
    }
  }

  func testMotorolaCategoriesAreValid() {
    let validCategories: Set<String> = ["phone", "body-camera", "tablet"]
    for entry in motorolaEntries {
      if let cat = entry.category {
        XCTAssertTrue(
          validCategories.contains(cat),
          "Motorola entry '\(entry.id)' has invalid category '\(cat)', expected one of \(validCategories)"
        )
      }
    }
  }

  func testLGPhonesAreCategorizedAsPhone() {
    let phones = lgEntries.filter {
      $0.id.contains("lg-g") || $0.id.contains("lg-v") || $0.id.contains("lg-android")
        || $0.id.contains("optimus")
    }
    for entry in phones {
      if let cat = entry.category {
        XCTAssertTrue(
          cat == "phone",
          "LG phone entry '\(entry.id)' has unexpected category '\(cat)'")
      }
    }
  }

  func testLGCategoriesAreValid() {
    let validCategories: Set<String> = ["phone", "wearable", "camera", "tablet"]
    for entry in lgEntries {
      if let cat = entry.category {
        XCTAssertTrue(
          validCategories.contains(cat),
          "LG entry '\(entry.id)' has invalid category '\(cat)', expected one of \(validCategories)"
        )
      }
    }
  }

  func testLGWearablesAreCategorizedCorrectly() {
    let watches = lgEntries.filter { $0.id.contains("watch") }
    for entry in watches {
      XCTAssertEqual(
        entry.category, "wearable",
        "LG watch entry '\(entry.id)' should have category 'wearable', got '\(entry.category ?? "nil")'"
      )
    }
  }

  // MARK: - Key Motorola PIDs

  func testPrimaryMotoMTPModePIDExists() {
    // 0x2e82 is the primary MTP PID used by Moto E/G/Z series
    let primary = motorolaEntries.first { $0.pid == 0x2e82 }
    XCTAssertNotNil(primary, "Missing primary Motorola MTP PID 0x2e82 (Moto E/G/Z)")
  }

  func testMotoMTPADBModePIDExists() {
    // 0x2e76 is MTP+ADB mode for Moto E/G series
    let mtpAdb = motorolaEntries.first { $0.pid == 0x2e76 }
    XCTAssertNotNil(mtpAdb, "Missing Motorola MTP+ADB PID 0x2e76")
  }

  func testMotoXoomMTPPIDExists() {
    // 0x70a8 is Xoom tablet MTP mode
    let xoom = motorolaEntries.first { $0.pid == 0x70a8 }
    XCTAssertNotNil(xoom, "Missing Motorola Xoom MTP PID 0x70a8")
  }

  // MARK: - Key LG PIDs

  func testLGAndroidPhonePrimaryPIDExists() {
    // 0x631c is used by many LG E and P model phones
    let primary = lgEntries.first { $0.pid == 0x631c }
    XCTAssertNotNil(primary, "Missing LG Various E/P models PID 0x631c")
  }

  func testLGG3PIDExists() {
    // 0x627f is LG G3
    let g3 = lgEntries.first { $0.pid == 0x627f }
    XCTAssertNotNil(g3, "Missing LG G3 PID 0x627f")
  }

  func testLGV20G5G6PIDExists() {
    // 0x61f1 is used by LG V20, G5, G6
    let v20 = lgEntries.first { $0.pid == 0x61f1 }
    XCTAssertNotNil(v20, "Missing LG V20/G5/G6 PID 0x61f1")
  }

  // MARK: - Motorola MTP Quirks (Broken Set Object PropList)

  /// libmtp documents: "Assume DEVICE_FLAG_BROKEN_SET_OBJECT_PROPLIST on all [Motorola devices]."
  /// Older Motorola phones (pre-Moto E/G era) typically have GetObjectPropList disabled.
  func testOlderMotorolaDevicesDisableGetObjectPropList() {
    // Older device entries (RAZR, Droid series) should not claim prop list support
    let olderDevices = motorolaEntries.filter {
      $0.id.contains("razr-hd") || $0.id.contains("droid-turbo") || $0.id.contains("droid-maxx")
        || $0.id.contains("droid-ultra")
    }
    XCTAssertFalse(olderDevices.isEmpty, "Expected older Motorola device entries")
    for entry in olderDevices {
      let flags = entry.resolvedFlags()
      XCTAssertFalse(
        flags.supportsGetObjectPropList,
        "Older Motorola entry '\(entry.id)' should not support GetObjectPropList (broken set object proplist per libmtp)"
      )
    }
  }

  /// The verified Moto E/G entries (0x2e82) are a notable exception: libmtp explicitly
  /// clears BROKEN_MTPGETOBJPROPLIST flags for this PID, indicating a fixed MTP stack.
  func testVerifiedMotoEGSupportsGetObjectPropList() {
    let motoEG = motorolaEntries.first { $0.pid == 0x2e82 }
    XCTAssertNotNil(motoEG, "Missing Moto E/G MTP entry 0x2e82")
    if let entry = motoEG {
      let flags = entry.resolvedFlags()
      XCTAssertTrue(
        flags.supportsGetObjectPropList,
        "Verified Moto E/G (0x2e82) should support GetObjectPropList (libmtp clears broken flag for this PID)"
      )
    }
  }

  // MARK: - LG MTP Behavior

  /// LG Android phones use the standard Android MTP stack, which has typical
  /// Android MTP bugs (documented as DEVICE_FLAGS_ANDROID_BUGS in libmtp).
  /// Most LG phones should require kernel detach on macOS.
  func testCoreLGEntriesRequireKernelDetach() {
    let coreEntries = lgEntries.filter {
      $0.flags != nil
    }
    let withKernelDetach = coreEntries.filter { $0.resolvedFlags().requiresKernelDetach }
    let ratio = Double(withKernelDetach.count) / Double(max(coreEntries.count, 1))
    XCTAssertGreaterThan(
      ratio, 0.5,
      "Most LG entries with flags should require kernel detach (\(withKernelDetach.count)/\(coreEntries.count))"
    )
  }

  /// Older LG feature phones (VX8550, GR-500, KM900, LG8575) have
  /// DEVICE_FLAG_BROKEN_MTPGETOBJPROPLIST in libmtp, meaning they cannot
  /// reliably use GetObjectPropList for enumeration.
  func testLGPhoneEntriesDisableGetObjectPropList() {
    let lgPhones = lgEntries.filter { $0.category == "phone" }
    // Most LG phones should have proplist disabled (conservative default)
    let withPropListDisabled = lgPhones.filter {
      !$0.resolvedFlags().supportsGetObjectPropList
    }
    XCTAssertGreaterThan(
      withPropListDisabled.count, lgPhones.count / 2,
      "Most LG phone entries should have GetObjectPropList disabled as conservative default")
  }

  // MARK: - Motorola Category Distribution

  func testMotorolaHasPhoneAndBodyCameraEntries() {
    let phones = motorolaEntries.filter { $0.category == "phone" }.count
    let bodyCameras = motorolaEntries.filter { $0.category == "body-camera" }.count

    XCTAssertGreaterThan(phones, 100, "Expected significant Motorola phone entries")
    XCTAssertGreaterThan(bodyCameras, 5, "Expected Motorola body camera entries")
  }

  // MARK: - LG Category Distribution

  func testLGHasPhoneAndWearableEntries() {
    let phones = lgEntries.filter { $0.category == "phone" }.count
    let wearables = lgEntries.filter { $0.category == "wearable" }.count

    XCTAssertGreaterThan(phones, 50, "Expected significant LG phone entries")
    XCTAssertGreaterThanOrEqual(wearables, 1, "Expected at least one LG wearable entry")
  }

  // MARK: - Motorola Kernel Detach

  func testMotorolaVerifiedEntriesRequireKernelDetach() {
    let verified = motorolaEntries.filter {
      $0.status == .verified || $0.status == .promoted
    }
    for entry in verified {
      let flags = entry.resolvedFlags()
      XCTAssertTrue(
        flags.requiresKernelDetach,
        "Verified Motorola entry '\(entry.id)' should require kernel detach for macOS compatibility"
      )
    }
  }

  // MARK: - Motorola Android Extensions

  func testNewerMotorolaDevicesUseAndroidExtensions() {
    // Recent Moto devices (Stylus, Edge, G-series 2021+) use Android MTP extensions
    let newerDevices = motorolaEntries.filter {
      $0.id.contains("stylus") || $0.id.contains("edge-2021") || $0.id.contains("edge-30")
        || $0.id.contains("edge-40")
    }
    for entry in newerDevices {
      if let ops = entry.operations, let usesAndroid = ops["useAndroidExtensions"] {
        XCTAssertTrue(
          usesAndroid,
          "Newer Motorola entry '\(entry.id)' should use Android MTP extensions")
      }
    }
  }
}
