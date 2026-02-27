// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import XCTest
import SnapshotTesting
@testable import SwiftMTPCore
import SwiftMTPQuirks

/// Snapshot tests for quirk policy resolution.
///
/// Each test builds a `DevicePolicy` for a well-known (or synthetic) device and snapshots
/// the key tuning/flag fields.  Any code change that alters policy output — e.g. silently
/// toggling `requiresKernelDetach` for all PTP cameras, or breaking the stabilisation
/// flag for Xiaomi-class devices — will immediately surface as a snapshot diff.
///
/// Snapshot directory: `__Snapshots__/QuirkPolicySnapshots/`
final class QuirkPolicySnapshotTests: XCTestCase {

  // MARK: - Test Configuration

  override func setUpWithError() throws {
    try super.setUpWithError()
    SnapshotTesting.diffTool = "ksdiff"
    try XCTSkipUnless(
      ProcessInfo.processInfo.environment["SWIFTMTP_SNAPSHOT_TESTS"] == "1",
      "Set SWIFTMTP_SNAPSHOT_TESTS=1 to run snapshot reference assertions (run-all-tests.sh enables this by default)."
    )
  }

  // MARK: - Known Device Policy Snapshots

  /// Google Pixel 7 — Android device with stabilisation quirk and kernel-detach requirement.
  func testPixel7Policy() throws {
    let db = try QuirkDatabase.load()
    assertSnapshot(
      of: policySnapshot(vid: "18d1", pid: "4ee1", database: db),
      as: .json, named: "policy-pixel7"
    )
  }

  /// Canon EOS Rebel / EOS 2000D — PTP still-image camera with stabilisation hook.
  func testCanonEOSRebelPolicy() throws {
    let db = try QuirkDatabase.load()
    assertSnapshot(
      of: policySnapshot(vid: "04a9", pid: "3139", database: db),
      as: .json, named: "policy-canon-eos-rebel"
    )
  }

  /// Nikon DSLR / D-series — PTP still-image camera with stabilisation hook.
  func testNikonDSLRPolicy() throws {
    let db = try QuirkDatabase.load()
    assertSnapshot(
      of: policySnapshot(vid: "04b0", pid: "0410", database: db),
      as: .json, named: "policy-nikon-dslr"
    )
  }

  /// GoPro MAX — action camera (PTP class, no kernel detach, prop-list enumeration).
  func testGoPROMaxPolicy() throws {
    let db = try QuirkDatabase.load()
    assertSnapshot(
      of: policySnapshot(vid: "2672", pid: "004b", database: db),
      as: .json, named: "policy-gopro-max"
    )
  }

  // MARK: - Heuristic (No Quirk) Snapshots

  /// Unrecognized PTP camera (USB class 0x06) — should apply `ptpCameraDefaults()` heuristic,
  /// meaning `requiresKernelDetach = false` and `supportsGetObjectPropList = true`.
  func testUnrecognizedPTPCameraPolicy() throws {
    let db = try QuirkDatabase.load()
    assertSnapshot(
      of: policySnapshot(vid: "ffff", pid: "0001", ifaceClass: "06", database: db),
      as: .json, named: "policy-unrecognized-ptp"
    )
  }

  /// Unrecognized vendor-specific Android device (USB class 0xff) — should use conservative
  /// `QuirkFlags()` defaults: `requiresKernelDetach = true`, `supportsGetObjectPropList = false`.
  func testUnrecognizedAndroidPolicy() throws {
    let db = try QuirkDatabase.load()
    assertSnapshot(
      of: policySnapshot(vid: "ffff", pid: "0002", ifaceClass: "ff", database: db),
      as: .json, named: "policy-unrecognized-android"
    )
  }

  // MARK: - Database Count

  /// Documents the number of quirk database entries.  Fails loudly if entries are removed
  /// accidentally; any intentional reduction should come with a deliberate snapshot update.
  func testQuirkDatabaseEntryCount() throws {
    let db = try QuirkDatabase.load()
    XCTAssertGreaterThanOrEqual(
      db.entries.count, 222,
      "QuirkDatabase has fewer entries than expected; was a batch of entries accidentally removed?"
    )
    assertSnapshot(
      of: ["quirkDatabaseEntryCount": db.entries.count],
      as: .json, named: "quirk-database-count"
    )
  }

  // MARK: - Helpers

  /// Build a `PolicySnapshot` for the given VID/PID using the live quirk database.
  private func policySnapshot(
    vid: String,
    pid: String,
    ifaceClass: String = "06",
    database db: QuirkDatabase
  ) -> PolicySnapshot {
    let fingerprint = MTPDeviceFingerprint(
      vid: vid, pid: pid, bcdDevice: nil,
      interfaceTriple: InterfaceTriple(class: ifaceClass, subclass: "01", protocol: "01"),
      endpointAddresses: EndpointAddresses(input: "81", output: "01", event: "82"),
      deviceInfoHash: nil
    )
    let policy = QuirkResolver.resolve(fingerprint: fingerprint, database: db)
    let vidInt = UInt16(vid, radix: 16) ?? 0
    let pidInt = UInt16(pid, radix: 16) ?? 0
    let ifaceClassInt = UInt8(ifaceClass, radix: 16)
    let matchedQuirkID = db.match(
      vid: vidInt, pid: pidInt, bcdDevice: nil,
      ifaceClass: ifaceClassInt, ifaceSubclass: 0x01, ifaceProtocol: 0x01
    )?.id
    return PolicySnapshot(quirkID: matchedQuirkID, policy: policy)
  }
}

// MARK: - PolicySnapshot

/// Codable summary of key `DevicePolicy` fields used for regression snapshot testing.
private struct PolicySnapshot: Codable {
  // Provenance
  let quirkID: String?
  let flagsSource: String

  // Tuning parameters most likely to regress
  let ioTimeoutMs: Int
  let stabilizeMs: Int
  let maxChunkBytes: Int

  // Flags most likely to regress
  let requiresKernelDetach: Bool
  let supportsGetObjectPropList: Bool
  let prefersPropListEnumeration: Bool
  let supportsPartialRead64: Bool
  let requireStabilization: Bool
  let resetOnOpen: Bool
  let skipPTPReset: Bool

  init(quirkID: String?, policy: DevicePolicy) {
    self.quirkID = quirkID
    self.flagsSource = policy.sources.flagsSource.rawValue
    self.ioTimeoutMs = policy.tuning.ioTimeoutMs
    self.stabilizeMs = policy.tuning.stabilizeMs
    self.maxChunkBytes = policy.tuning.maxChunkBytes
    self.requiresKernelDetach = policy.flags.requiresKernelDetach
    self.supportsGetObjectPropList = policy.flags.supportsGetObjectPropList
    self.prefersPropListEnumeration = policy.flags.prefersPropListEnumeration
    self.supportsPartialRead64 = policy.flags.supportsPartialRead64
    self.requireStabilization = policy.flags.requireStabilization
    self.resetOnOpen = policy.flags.resetOnOpen
    self.skipPTPReset = policy.flags.skipPTPReset
  }
}
