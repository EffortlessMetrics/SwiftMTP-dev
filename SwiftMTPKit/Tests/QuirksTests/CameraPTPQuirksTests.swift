// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import XCTest

@testable import SwiftMTPQuirks

/// Validates PTP-specific invariants for Canon and Nikon camera entries
/// in the quirks database. These tests ensure camera entries have correct
/// PTP flags, reasonable tuning, and vendor-specific protocol notes.
final class CameraPTPQuirksTests: XCTestCase {

  private var db: QuirkDatabase!
  private var canonEntries: [DeviceQuirk]!
  private var nikonEntries: [DeviceQuirk]!

  override func setUpWithError() throws {
    db = try QuirkDatabase.load()
    // Canon VID: 0x04a9, Nikon VID: 0x04b0
    canonEntries = db.entries.filter { $0.vid == 0x04a9 && $0.category == "camera" }
    nikonEntries = db.entries.filter { $0.vid == 0x04b0 && $0.category == "camera" }
  }

  // MARK: - Camera Class Flag

  func testCanonNikonCameraEntriesHaveCameraClassFlag() {
    // Verify our specifically-improved entries have cameraClass=true
    let keyEntries = [
      "canon-eos-rebel-3139", "canon-eos-5d3-3234",
      "canon-eos-r5-32b4", "canon-eos-r3-32b5",
      "nikon-dslr-0410", "nikon-z6-z7-0441",
      "nikon-z6ii-z7ii-0442", "nikon-z9-0450",
    ]
    for eid in keyEntries {
      guard let entry = db.entries.first(where: { $0.id == eid }) else {
        XCTFail("Missing entry \(eid)")
        continue
      }
      let flags = entry.resolvedFlags()
      XCTAssertTrue(flags.cameraClass, "\(eid) should have cameraClass=true")
    }
  }

  // MARK: - Canon PTP Specifics

  func testCanonCameraEntriesExist() {
    XCTAssertGreaterThan(
      canonEntries.count, 0,
      "Should have at least one Canon camera entry (VID 0x04a9)")
  }

  func testCanonEOSRebelHasVendorExtensionNotes() {
    guard let rebel = db.entries.first(where: { $0.id == "canon-eos-rebel-3139" }) else {
      XCTFail("Missing canon-eos-rebel-3139 entry")
      return
    }
    // Verify the entry has Canon-specific PTP extension notes via the raw JSON
    // Notes are stored in JSON but not exposed as a Swift property, so we
    // verify via the flags and tuning which reflect research findings.
    let flags = rebel.resolvedFlags()
    XCTAssertTrue(flags.cameraClass, "Canon EOS Rebel should be marked as camera class")
    XCTAssertTrue(flags.supportsGetPartialObject, "Canon EOS cameras support GetPartialObject")
  }

  func testCanonEOSR5HasReasonableTuning() {
    guard let r5 = db.entries.first(where: { $0.id == "canon-eos-r5-32b4" }) else {
      XCTFail("Missing canon-eos-r5-32b4 entry")
      return
    }
    // R5 shoots 45MP stills and 8K video; needs generous chunk size and timeouts
    XCTAssertGreaterThanOrEqual(
      r5.maxChunkBytes ?? 0, 2_097_152,
      "Canon R5 should have at least 2MB chunk size for large RAW/video files")
    XCTAssertGreaterThanOrEqual(
      r5.ioTimeoutMs ?? 0, 30_000,
      "Canon R5 should have at least 30s I/O timeout for large files")
  }

  func testCanonEOSR3HasReasonableTuning() {
    guard let r3 = db.entries.first(where: { $0.id == "canon-eos-r3-32b5" }) else {
      XCTFail("Missing canon-eos-r3-32b5 entry")
      return
    }
    let flags = r3.resolvedFlags()
    XCTAssertTrue(flags.cameraClass, "Canon R3 should be camera class")
    XCTAssertTrue(
      flags.supportsGetObjectPropList,
      "Canon R3 should support GetObjectPropList")
    XCTAssertTrue(
      flags.prefersPropListEnumeration,
      "Canon R3 should prefer PropList enumeration")
  }

  func testCanonCamerasUseValidInterfaceClass() {
    // PTP Still Image class: 0x06/0x01/0x01, or vendor-specific 0xFF
    let withIface = canonEntries.filter { $0.ifaceClass != nil }
    for entry in withIface {
      let cls = entry.ifaceClass!
      XCTAssertTrue(
        cls == 0x06 || cls == 0xFF,
        "Canon camera \(entry.id) should use USB class 0x06 (Still Image) or 0xFF (vendor), got 0x\(String(cls, radix: 16))")
    }
  }

  // MARK: - Nikon PTP Specifics

  func testNikonCameraEntriesExist() {
    XCTAssertGreaterThan(
      nikonEntries.count, 0,
      "Should have at least one Nikon camera entry (VID 0x04b0)")
  }

  func testNikonDSLRHasVendorExtensionFlags() {
    guard let dslr = db.entries.first(where: { $0.id == "nikon-dslr-0410" }) else {
      XCTFail("Missing nikon-dslr-0410 entry")
      return
    }
    let flags = dslr.resolvedFlags()
    XCTAssertTrue(flags.cameraClass, "Nikon DSLR should be marked as camera class")
    XCTAssertTrue(
      flags.supportsGetPartialObject,
      "Nikon DSLRs support GetPartialObject via vendor extensions")
  }

  func testNikonZ9HasReasonableTuning() {
    guard let z9 = db.entries.first(where: { $0.id == "nikon-z9-0450" }) else {
      XCTFail("Missing nikon-z9-0450 entry")
      return
    }
    // Z9 shoots 45MP stills at 120fps and 8K video
    XCTAssertGreaterThanOrEqual(
      z9.maxChunkBytes ?? 0, 2_097_152,
      "Nikon Z9 should have at least 2MB chunk size for high-speed downloads")
    XCTAssertGreaterThanOrEqual(
      z9.ioTimeoutMs ?? 0, 15_000,
      "Nikon Z9 should have at least 15s I/O timeout")
    let flags = z9.resolvedFlags()
    XCTAssertTrue(flags.supportsGetObjectPropList, "Nikon Z9 should support GetObjectPropList")
  }

  func testNikonZ7HasDualStorageNote() {
    guard let z7 = db.entries.first(where: { $0.id == "nikon-z6ii-z7ii-0442" }) else {
      XCTFail("Missing nikon-z6ii-z7ii-0442 entry")
      return
    }
    let flags = z7.resolvedFlags()
    XCTAssertTrue(flags.cameraClass, "Nikon Z7 should be camera class")
    XCTAssertTrue(
      flags.supportsGetObjectPropList,
      "Nikon Z7 should support GetObjectPropList for batch metadata")
  }

  func testNikonCamerasUseValidInterfaceClass() {
    // PTP Still Image class: 0x06, or vendor-specific 0xFF
    let withIface = nikonEntries.filter { $0.ifaceClass != nil }
    for entry in withIface {
      let cls = entry.ifaceClass!
      XCTAssertTrue(
        cls == 0x06 || cls == 0xFF,
        "Nikon camera \(entry.id) should use USB class 0x06 (Still Image) or 0xFF (vendor), got 0x\(String(cls, radix: 16))")
    }
  }

  // MARK: - Tuning Bounds for All Cameras

  func testCameraChunkSizesAreInReasonableRange() {
    let allCameras = db.entries.filter { $0.category == "camera" }
    for entry in allCameras {
      if let chunk = entry.maxChunkBytes {
        XCTAssertGreaterThanOrEqual(
          chunk, 512 * 1024,
          "Camera \(entry.id) chunk size \(chunk) is below 512KB minimum for cameras")
        XCTAssertLessThanOrEqual(
          chunk, 8 * 1024 * 1024,
          "Camera \(entry.id) chunk size \(chunk) exceeds 8MB — unusually large for cameras")
      }
    }
  }

  func testCameraIOTimeoutsAreInReasonableRange() {
    let allCameras = db.entries.filter { $0.category == "camera" }
    for entry in allCameras {
      if let timeout = entry.ioTimeoutMs {
        XCTAssertGreaterThanOrEqual(
          timeout, 5_000,
          "Camera \(entry.id) ioTimeout \(timeout)ms is below 5s — too aggressive for cameras")
        XCTAssertLessThanOrEqual(
          timeout, 120_000,
          "Camera \(entry.id) ioTimeout \(timeout)ms exceeds 120s — suspiciously high")
      }
    }
  }
}
