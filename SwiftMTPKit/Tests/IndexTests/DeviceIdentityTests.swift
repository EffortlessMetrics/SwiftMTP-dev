// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import XCTest
@testable import SwiftMTPIndex
import SwiftMTPCore

final class DeviceIdentityTests: XCTestCase {
  private var index: SQLiteLiveIndex!

  override func setUp() async throws {
    index = try SQLiteLiveIndex(path: ":memory:")
  }

  // MARK: - Identity Resolution

  func testSameUSBSerialReturnsSameDomainId() async throws {
    let signals1 = DeviceIdentitySignals(
      vendorId: 0x18d1, productId: 0x4ee1,
      usbSerial: "ABC123", mtpSerial: nil,
      manufacturer: "Google", model: "Pixel 7"
    )
    let signals2 = DeviceIdentitySignals(
      vendorId: 0x18d1, productId: 0x4ee1,
      usbSerial: "ABC123", mtpSerial: nil,
      manufacturer: "Google", model: "Pixel 7"
    )

    let identity1 = try await index.resolveIdentity(signals: signals1)
    let identity2 = try await index.resolveIdentity(signals: signals2)

    XCTAssertEqual(identity1.domainId, identity2.domainId)
    XCTAssertEqual(identity1.displayName, "Google Pixel 7")
  }

  func testDifferentSerialReturnsDifferentDomainId() async throws {
    let signals1 = DeviceIdentitySignals(
      vendorId: 0x18d1, productId: 0x4ee1,
      usbSerial: "SERIAL_A", mtpSerial: nil,
      manufacturer: "Google", model: "Pixel 7"
    )
    let signals2 = DeviceIdentitySignals(
      vendorId: 0x18d1, productId: 0x4ee1,
      usbSerial: "SERIAL_B", mtpSerial: nil,
      manufacturer: "Google", model: "Pixel 7"
    )

    let identity1 = try await index.resolveIdentity(signals: signals1)
    let identity2 = try await index.resolveIdentity(signals: signals2)

    XCTAssertNotEqual(identity1.domainId, identity2.domainId)
  }

  func testNoSerialUsesTypeHashFallback() async throws {
    let signals = DeviceIdentitySignals(
      vendorId: 0x04e8, productId: 0x6860,
      usbSerial: nil, mtpSerial: nil,
      manufacturer: "Samsung", model: "Galaxy S21"
    )

    let identity = try await index.resolveIdentity(signals: signals)
    XCTAssertFalse(identity.domainId.isEmpty)
    XCTAssertEqual(identity.displayName, "Samsung Galaxy S21")

    // Same type hash → same domainId
    let identity2 = try await index.resolveIdentity(signals: signals)
    XCTAssertEqual(identity.domainId, identity2.domainId)
  }

  func testMTPSerialFallbackWhenNoUSBSerial() async throws {
    let signals = DeviceIdentitySignals(
      vendorId: 0x04e8, productId: 0x6860,
      usbSerial: nil, mtpSerial: "MTP_SERIAL_123",
      manufacturer: "Samsung", model: "Galaxy S21"
    )

    let identity = try await index.resolveIdentity(signals: signals)
    XCTAssertFalse(identity.domainId.isEmpty)

    // Same MTP serial → same domainId
    let identity2 = try await index.resolveIdentity(signals: signals)
    XCTAssertEqual(identity.domainId, identity2.domainId)
  }

  func testUSBSerialTakesPriorityOverMTPSerial() async throws {
    let signalsWithUSB = DeviceIdentitySignals(
      vendorId: 0x04e8, productId: 0x6860,
      usbSerial: "USB_SERIAL", mtpSerial: "MTP_SERIAL",
      manufacturer: "Samsung", model: "Galaxy S21"
    )
    let signalsWithMTPOnly = DeviceIdentitySignals(
      vendorId: 0x04e8, productId: 0x6860,
      usbSerial: nil, mtpSerial: "MTP_SERIAL",
      manufacturer: "Samsung", model: "Galaxy S21"
    )

    let identity1 = try await index.resolveIdentity(signals: signalsWithUSB)
    let identity2 = try await index.resolveIdentity(signals: signalsWithMTPOnly)

    // Different identity keys (usb: vs mtp:) → different domainIds
    XCTAssertNotEqual(identity1.domainId, identity2.domainId)
  }

  // MARK: - MTP Serial Upgrade

  func testUpdateMTPSerialUpgradesTypeHash() async throws {
    // First resolve with no serial → type hash
    let signals = DeviceIdentitySignals(
      vendorId: 0x04e8, productId: 0x6860,
      usbSerial: nil, mtpSerial: nil,
      manufacturer: "Samsung", model: "Galaxy S21"
    )
    let identity = try await index.resolveIdentity(signals: signals)

    // Update with MTP serial
    try await index.updateMTPSerial(domainId: identity.domainId, mtpSerial: "NEW_MTP_SERIAL")

    // Now resolving with MTP serial should find the same identity
    let signalsWithMTP = DeviceIdentitySignals(
      vendorId: 0x04e8, productId: 0x6860,
      usbSerial: nil, mtpSerial: "NEW_MTP_SERIAL",
      manufacturer: "Samsung", model: "Galaxy S21"
    )
    let identity2 = try await index.resolveIdentity(signals: signalsWithMTP)
    XCTAssertEqual(identity.domainId, identity2.domainId)
  }

  // MARK: - Lifecycle

  func testAllIdentities() async throws {
    let signals1 = DeviceIdentitySignals(
      vendorId: 0x18d1, productId: 0x4ee1,
      usbSerial: "SERIAL_1", mtpSerial: nil,
      manufacturer: "Google", model: "Pixel 7"
    )
    let signals2 = DeviceIdentitySignals(
      vendorId: 0x04e8, productId: 0x6860,
      usbSerial: "SERIAL_2", mtpSerial: nil,
      manufacturer: "Samsung", model: "Galaxy S21"
    )

    _ = try await index.resolveIdentity(signals: signals1)
    _ = try await index.resolveIdentity(signals: signals2)

    let all = try await index.allIdentities()
    XCTAssertEqual(all.count, 2)
  }

  func testRemoveIdentity() async throws {
    let signals = DeviceIdentitySignals(
      vendorId: 0x18d1, productId: 0x4ee1,
      usbSerial: "REMOVE_ME", mtpSerial: nil,
      manufacturer: "Google", model: "Pixel 7"
    )
    let identity = try await index.resolveIdentity(signals: signals)

    try await index.removeIdentity(domainId: identity.domainId)

    let fetched = try await index.identity(for: identity.domainId)
    XCTAssertNil(fetched)
  }

  func testLastSeenAtUpdatedOnResolve() async throws {
    let signals = DeviceIdentitySignals(
      vendorId: 0x18d1, productId: 0x4ee1,
      usbSerial: "TIMESTAMP_TEST", mtpSerial: nil,
      manufacturer: "Google", model: "Pixel 7"
    )
    let identity1 = try await index.resolveIdentity(signals: signals)

    // Small delay to ensure timestamps differ
    try await Task.sleep(nanoseconds: 10_000_000)  // 10ms

    let identity2 = try await index.resolveIdentity(signals: signals)
    XCTAssertEqual(identity1.domainId, identity2.domainId)
    XCTAssertGreaterThanOrEqual(identity2.lastSeenAt, identity1.lastSeenAt)
  }

  // MARK: - Identity Key Generation

  func testIdentityKeyWithUSBSerial() {
    let signals = DeviceIdentitySignals(
      vendorId: 0x18d1, productId: 0x4ee1,
      usbSerial: "ABC123", mtpSerial: "MTP456",
      manufacturer: "Google", model: "Pixel 7"
    )
    XCTAssertEqual(signals.identityKey(), "usb:ABC123")
  }

  func testIdentityKeyWithMTPSerial() {
    let signals = DeviceIdentitySignals(
      vendorId: 0x18d1, productId: 0x4ee1,
      usbSerial: nil, mtpSerial: "MTP456",
      manufacturer: "Google", model: "Pixel 7"
    )
    XCTAssertEqual(signals.identityKey(), "mtp:MTP456")
  }

  func testIdentityKeyTypeHash() {
    let signals = DeviceIdentitySignals(
      vendorId: 0x18d1, productId: 0x4ee1,
      usbSerial: nil, mtpSerial: nil,
      manufacturer: "Google", model: "Pixel 7"
    )
    XCTAssertEqual(signals.identityKey(), "type:18d1:4ee1:Google:Pixel 7")
  }

  // MARK: - Data Migration

  func testMigrateEphemeralDeviceId() async throws {
    // Insert objects with old ephemeral ID
    let oldObj = IndexedObject(
      deviceId: "04e8:6860@1:3", storageId: 1, handle: 100,
      parentHandle: nil, name: "DCIM", pathKey: "/DCIM",
      sizeBytes: nil, mtime: nil, formatCode: 0x3001,
      isDirectory: true, changeCounter: 0
    )
    try await index.upsertObjects([oldObj], deviceId: "04e8:6860@1:3")

    // Migrate to stable domainId
    try index.migrateEphemeralDeviceId(vidPidPattern: "04e8:6860", newDomainId: "stable-uuid-123")

    // Old deviceId should return no results
    let oldChildren = try await index.children(
      deviceId: "04e8:6860@1:3", storageId: 1, parentHandle: nil)
    XCTAssertEqual(oldChildren.count, 0)

    // New domainId should find the migrated object
    let newChildren = try await index.children(
      deviceId: "stable-uuid-123", storageId: 1, parentHandle: nil)
    XCTAssertEqual(newChildren.count, 1)
    XCTAssertEqual(newChildren[0].name, "DCIM")
  }
}
