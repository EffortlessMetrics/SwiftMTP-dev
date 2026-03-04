// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import XCTest
@testable import SwiftMTPCore
import SwiftMTPQuirks

/// Inline snapshot tests for device info display: MTPDeviceInfo fields,
/// MTPDeviceSummary formatting, MTPStorageInfo display, and MTPObjectInfo
/// serialization.  Verifies that info command output fields are stable
/// across refactors.
final class DeviceInfoSnapshotTests: XCTestCase {

  // MARK: - 1. MTPDeviceInfo Field Stability

  func testDeviceInfoManufacturerAndModel() {
    let info = makePixel7DeviceInfo()
    XCTAssertEqual(info.manufacturer, "Google")
    XCTAssertEqual(info.model, "Pixel 7")
    XCTAssertEqual(info.version, "1.0")
    XCTAssertEqual(info.serialNumber, "ABCD1234")
  }

  func testDeviceInfoOperationsSupportedContainsCore() {
    let info = makePixel7DeviceInfo()
    // OpenSession, CloseSession, GetDeviceInfo
    XCTAssertTrue(info.operationsSupported.contains(0x1002))
    XCTAssertTrue(info.operationsSupported.contains(0x1003))
    XCTAssertTrue(info.operationsSupported.contains(0x1001))
  }

  func testDeviceInfoEventsSupportedContainsObjectAdded() {
    let info = makePixel7DeviceInfo()
    XCTAssertTrue(info.eventsSupported.contains(0x4002))  // ObjectAdded
    XCTAssertTrue(info.eventsSupported.contains(0x4003))  // ObjectRemoved
  }

  func testDeviceInfoCodableRoundTrip() throws {
    let info = makePixel7DeviceInfo()
    let data = try JSONEncoder().encode(info)
    let decoded = try JSONDecoder().decode(MTPDeviceInfo.self, from: data)
    XCTAssertEqual(decoded.manufacturer, info.manufacturer)
    XCTAssertEqual(decoded.model, info.model)
    XCTAssertEqual(decoded.version, info.version)
    XCTAssertEqual(decoded.serialNumber, info.serialNumber)
    XCTAssertEqual(decoded.operationsSupported, info.operationsSupported)
    XCTAssertEqual(decoded.eventsSupported, info.eventsSupported)
  }

  // MARK: - 2. MTPDeviceSummary Display Fields

  func testDeviceSummaryFingerprintFormatVIDPID() {
    let summary = makePixel7Summary()
    XCTAssertEqual(summary.fingerprint, "18d1:4ee1")
  }

  func testDeviceSummaryFingerprintUnknownWhenNoIDs() {
    let summary = MTPDeviceSummary(
      id: MTPDeviceID(raw: "unknown-dev"),
      manufacturer: "Unknown",
      model: "Device"
    )
    XCTAssertEqual(summary.fingerprint, "unknown")
  }

  func testDeviceSummaryAllFieldsPopulated() {
    let summary = makePixel7Summary()
    XCTAssertEqual(summary.id.raw, "pixel7-test")
    XCTAssertEqual(summary.manufacturer, "Google")
    XCTAssertEqual(summary.model, "Pixel 7")
    XCTAssertEqual(summary.vendorID, 0x18D1)
    XCTAssertEqual(summary.productID, 0x4EE1)
    XCTAssertEqual(summary.bus, 1)
    XCTAssertEqual(summary.address, 3)
    XCTAssertEqual(summary.usbSerial, "SERIAL123")
  }

  // MARK: - 3. ReceiptDeviceSummary Formatting

  func testReceiptDeviceSummaryVIDPIDHexFormatted() {
    let summary = makePixel7Summary()
    let receipt = ReceiptDeviceSummary(from: summary)
    XCTAssertEqual(receipt.vendorID, "0x18d1")
    XCTAssertEqual(receipt.productID, "0x4ee1")
    XCTAssertEqual(receipt.manufacturer, "Google")
    XCTAssertEqual(receipt.model, "Pixel 7")
  }

  func testReceiptDeviceSummaryNilIDsWhenMissing() {
    let summary = MTPDeviceSummary(
      id: MTPDeviceID(raw: "no-ids"),
      manufacturer: "Test",
      model: "NoIDs"
    )
    let receipt = ReceiptDeviceSummary(from: summary)
    XCTAssertNil(receipt.vendorID)
    XCTAssertNil(receipt.productID)
  }

  // MARK: - 4. MTPStorageInfo Display

  func testStorageInfoDisplayFields() {
    let storage = makeInternalStorage()
    XCTAssertEqual(storage.description, "Internal Storage")
    XCTAssertEqual(storage.capacityBytes, 128_000_000_000)
    XCTAssertEqual(storage.freeBytes, 64_000_000_000)
    XCTAssertFalse(storage.isReadOnly)
  }

  func testStorageInfoReadOnlyFlag() {
    let storage = MTPStorageInfo(
      id: MTPStorageID(raw: 0x00020001),
      description: "SD Card",
      capacityBytes: 32_000_000_000,
      freeBytes: 16_000_000_000,
      isReadOnly: true
    )
    XCTAssertTrue(storage.isReadOnly)
    XCTAssertEqual(storage.description, "SD Card")
  }

  func testStorageInfoCodableRoundTrip() throws {
    let storage = makeInternalStorage()
    let data = try JSONEncoder().encode(storage)
    let decoded = try JSONDecoder().decode(MTPStorageInfo.self, from: data)
    XCTAssertEqual(decoded.description, storage.description)
    XCTAssertEqual(decoded.capacityBytes, storage.capacityBytes)
    XCTAssertEqual(decoded.freeBytes, storage.freeBytes)
    XCTAssertEqual(decoded.isReadOnly, storage.isReadOnly)
  }

  // MARK: - 5. MTPObjectInfo Display

  func testObjectInfoFileDisplay() {
    let obj = makePhotoObject()
    XCTAssertEqual(obj.name, "photo.jpg")
    XCTAssertEqual(obj.sizeBytes, 4_500_000)
    XCTAssertEqual(obj.formatCode, 0x3801)  // EXIF/JPEG
  }

  func testObjectInfoDirectoryDisplay() {
    let dir = MTPObjectInfo(
      handle: 0x00000002,
      storage: MTPStorageID(raw: 0x00010001),
      parent: nil,
      name: "DCIM",
      sizeBytes: nil,
      modified: nil,
      formatCode: 0x3001,  // Association (folder)
      properties: [:]
    )
    XCTAssertEqual(dir.name, "DCIM")
    XCTAssertEqual(dir.formatCode, 0x3001)
    XCTAssertNil(dir.sizeBytes)
  }

  func testObjectInfoCodableRoundTrip() throws {
    let obj = makePhotoObject()
    let enc = JSONEncoder()
    enc.dateEncodingStrategy = .iso8601
    let data = try enc.encode(obj)
    let dec = JSONDecoder()
    dec.dateDecodingStrategy = .iso8601
    let decoded = try dec.decode(MTPObjectInfo.self, from: data)
    XCTAssertEqual(decoded.name, obj.name)
    XCTAssertEqual(decoded.handle, obj.handle)
    XCTAssertEqual(decoded.sizeBytes, obj.sizeBytes)
    XCTAssertEqual(decoded.formatCode, obj.formatCode)
  }

  // MARK: - 6. MTPEvent Description Formatting

  func testEventDescriptionObjectAdded() {
    let event = MTPEvent.objectAdded(0x00001234)
    XCTAssertEqual(event.eventDescription, "ObjectAdded (handle: 0x1234)")
    XCTAssertEqual(event.eventCode, 0x4002)
  }

  func testEventDescriptionStorageRemoved() {
    let event = MTPEvent.storageRemoved(MTPStorageID(raw: 0x00010001))
    XCTAssertEqual(event.eventDescription, "StoreRemoved (storageId: 0x10001)")
    XCTAssertEqual(event.eventCode, 0x4005)
  }

  func testEventDescriptionDeviceReset() {
    let event = MTPEvent.deviceReset
    XCTAssertEqual(event.eventDescription, "DeviceReset")
    XCTAssertEqual(event.eventCode, 0x400B)
  }

  func testEventDescriptionUnknown() {
    let event = MTPEvent.unknown(code: 0xC001, params: [42])
    XCTAssertEqual(event.eventDescription, "Unknown (code: 0xc001, params: [42])")
  }

  func testEventDescriptionCaptureComplete() {
    let event = MTPEvent.captureComplete(transactionId: 7)
    XCTAssertEqual(event.eventDescription, "CaptureComplete (txId: 7)")
    XCTAssertEqual(event.eventCode, 0x400D)
  }

  func testEventDescriptionStoreFull() {
    let event = MTPEvent.storeFull(MTPStorageID(raw: 0x00020001))
    XCTAssertEqual(event.eventDescription, "StoreFull (storageId: 0x20001)")
    XCTAssertEqual(event.eventCode, 0x400A)
  }

  // MARK: - 7. MTPDeviceFingerprint Display

  func testDeviceFingerprintFieldsStable() {
    let fp = MTPDeviceFingerprint(
      vid: "18d1", pid: "4ee1", bcdDevice: "0528",
      interfaceTriple: InterfaceTriple(class: "06", subclass: "01", protocol: "01"),
      endpointAddresses: EndpointAddresses(input: "81", output: "01", event: "82"),
      deviceInfoHash: "test-hash"
    )
    XCTAssertEqual(fp.vid, "18d1")
    XCTAssertEqual(fp.pid, "4ee1")
    XCTAssertEqual(fp.bcdDevice, "0528")
    XCTAssertEqual(fp.interfaceTriple.class, "06")
    XCTAssertEqual(fp.endpointAddresses.input, "81")
    XCTAssertEqual(fp.deviceInfoHash, "test-hash")
  }

  func testDeviceFingerprintCodableRoundTrip() throws {
    let fp = MTPDeviceFingerprint(
      vid: "2717", pid: "ff10", bcdDevice: nil,
      interfaceTriple: InterfaceTriple(class: "06", subclass: "01", protocol: "01"),
      endpointAddresses: EndpointAddresses(input: "81", output: "02", event: "83"),
      deviceInfoHash: nil
    )
    let data = try JSONEncoder().encode(fp)
    let decoded = try JSONDecoder().decode(MTPDeviceFingerprint.self, from: data)
    XCTAssertEqual(decoded.vid, fp.vid)
    XCTAssertEqual(decoded.pid, fp.pid)
    XCTAssertNil(decoded.bcdDevice)
  }

  // MARK: - Helpers

  private func makePixel7DeviceInfo() -> MTPDeviceInfo {
    MTPDeviceInfo(
      manufacturer: "Google",
      model: "Pixel 7",
      version: "1.0",
      serialNumber: "ABCD1234",
      operationsSupported: [0x1001, 0x1002, 0x1003, 0x1004, 0x1005, 0x1006, 0x1007, 0x1008, 0x1009, 0x100A],
      eventsSupported: [0x4001, 0x4002, 0x4003, 0x4004, 0x4005, 0x4008]
    )
  }

  private func makePixel7Summary() -> MTPDeviceSummary {
    MTPDeviceSummary(
      id: MTPDeviceID(raw: "pixel7-test"),
      manufacturer: "Google",
      model: "Pixel 7",
      vendorID: 0x18D1,
      productID: 0x4EE1,
      bus: 1,
      address: 3,
      usbSerial: "SERIAL123"
    )
  }

  private func makeInternalStorage() -> MTPStorageInfo {
    MTPStorageInfo(
      id: MTPStorageID(raw: 0x00010001),
      description: "Internal Storage",
      capacityBytes: 128_000_000_000,
      freeBytes: 64_000_000_000,
      isReadOnly: false
    )
  }

  private func makePhotoObject() -> MTPObjectInfo {
    MTPObjectInfo(
      handle: 0x00000001,
      storage: MTPStorageID(raw: 0x00010001),
      parent: 0x00000002,
      name: "photo.jpg",
      sizeBytes: 4_500_000,
      modified: ISO8601DateFormatter().date(from: "2026-01-15T14:30:00Z"),
      formatCode: 0x3801,
      properties: [0xDC01: "photo.jpg", 0xDC02: "image/jpeg"]
    )
  }
}
