// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import XCTest
@testable import SwiftMTPCore
@testable import SwiftMTPCLI
import SwiftMTPQuirks
import SwiftMTPObservability

/// Inline snapshot tests for CLI output formatting: error envelopes, probe receipts,
/// device summaries, error messages (actionable + localized), storage/object display,
/// and JSON output mode.  Every test uses `XCTAssertEqual` (or `XCTAssertTrue`)
/// against a known expected value — no file-based snapshot infrastructure required.
final class OutputFormatSnapshotTests: XCTestCase {

  // MARK: - 1. CLI Error Envelope JSON Formatting

  func testCLIErrorEnvelopeBasicJSON() throws {
    let envelope = CLIErrorEnvelope(
      "device_not_found",
      timestamp: "2026-02-08T10:00:00Z"
    )
    let data = try sortedJSON(envelope)
    let dict = try JSONSerialization.jsonObject(with: data) as! [String: Any]
    XCTAssertEqual(dict["schemaVersion"] as? String, "1.0")
    XCTAssertEqual(dict["type"] as? String, "error")
    XCTAssertEqual(dict["error"] as? String, "device_not_found")
    XCTAssertEqual(dict["timestamp"] as? String, "2026-02-08T10:00:00Z")
    XCTAssertNil(dict["details"])
    XCTAssertNil(dict["mode"])
  }

  func testCLIErrorEnvelopeWithDetailsJSON() throws {
    let envelope = CLIErrorEnvelope(
      "transfer_failed",
      details: ["file": "photo.jpg", "reason": "storage_full"],
      timestamp: "2026-02-08T10:00:00Z"
    )
    let data = try sortedJSON(envelope)
    let dict = try JSONSerialization.jsonObject(with: data) as! [String: Any]
    let details = dict["details"] as! [String: String]
    XCTAssertEqual(details["file"], "photo.jpg")
    XCTAssertEqual(details["reason"], "storage_full")
  }

  func testCLIErrorEnvelopeWithModeJSON() throws {
    let envelope = CLIErrorEnvelope(
      "permission_denied",
      mode: "probe",
      timestamp: "2026-02-08T10:00:00Z"
    )
    let data = try sortedJSON(envelope)
    let dict = try JSONSerialization.jsonObject(with: data) as! [String: Any]
    XCTAssertEqual(dict["mode"] as? String, "probe")
  }

  // MARK: - 2. Probe Output Formatting

  func testProbeReceiptJSONRoundTrip() throws {
    let receipt = makeTestProbeReceipt()
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    let data = try encoder.encode(receipt)
    let decoded = try JSONDecoder.mtpDecoder().decode(ProbeReceipt.self, from: data)
    XCTAssertEqual(decoded.deviceSummary.manufacturer, "Google")
    XCTAssertEqual(decoded.deviceSummary.model, "Pixel 7")
    XCTAssertEqual(decoded.fingerprint.vid, "18d1")
    XCTAssertEqual(decoded.fingerprint.pid, "4ee1")
    XCTAssertEqual(decoded.totalProbeTimeMs, 134)
  }

  func testPolicySummaryJSONOutput() throws {
    let db = try QuirkDatabase.load()
    let fingerprint = MTPDeviceFingerprint(
      vid: "2717", pid: "ff10", bcdDevice: nil,
      interfaceTriple: InterfaceTriple(class: "06", subclass: "01", protocol: "01"),
      endpointAddresses: EndpointAddresses(input: "81", output: "01", event: "82"),
      deviceInfoHash: nil
    )
    let policy = QuirkResolver.resolve(fingerprint: fingerprint, database: db)
    let summary = PolicySummary(from: policy)
    let data = try sortedJSON(summary)
    let dict = try JSONSerialization.jsonObject(with: data) as! [String: Any]
    XCTAssertNotNil(dict["maxChunkBytes"])
    XCTAssertNotNil(dict["ioTimeoutMs"])
    XCTAssertNotNil(dict["enumerationStrategy"])
    XCTAssertNotNil(dict["readStrategy"])
    XCTAssertNotNil(dict["writeStrategy"])
    XCTAssertEqual(dict["resetOnOpen"] as? Bool, policy.flags.resetOnOpen)
    XCTAssertEqual(dict["disableEventPump"] as? Bool, policy.flags.disableEventPump)
  }

  func testReceiptDeviceSummaryVIDPIDFormat() {
    let summary = MTPDeviceSummary(
      id: MTPDeviceID(raw: "test-device"),
      manufacturer: "Samsung",
      model: "Galaxy S7",
      vendorID: 0x04E8,
      productID: 0x6860
    )
    let receipt = ReceiptDeviceSummary(from: summary)
    XCTAssertEqual(receipt.vendorID, "0x04e8")
    XCTAssertEqual(receipt.productID, "0x6860")
    XCTAssertEqual(receipt.manufacturer, "Samsung")
    XCTAssertEqual(receipt.model, "Galaxy S7")
  }

  // MARK: - 3. Device Summary Formatting

  func testDeviceSummaryFingerprintFormat() {
    let summary = MTPDeviceSummary(
      id: MTPDeviceID(raw: "pixel7-4ee1"),
      manufacturer: "Google",
      model: "Pixel 7",
      vendorID: 0x18D1,
      productID: 0x4EE1
    )
    XCTAssertEqual(summary.fingerprint, "18d1:4ee1")
  }

  func testDeviceSummaryFingerprintUnknown() {
    let summary = MTPDeviceSummary(
      id: MTPDeviceID(raw: "no-vid-pid"),
      manufacturer: "Unknown",
      model: "Unknown"
    )
    XCTAssertEqual(summary.fingerprint, "unknown")
  }

  func testDeviceInfoTextSnapshot() {
    let info = MTPDeviceInfo(
      manufacturer: "OnePlus",
      model: "ONEPLUS A3010",
      version: "1.0",
      serialNumber: "ABC123",
      operationsSupported: [0x1001, 0x1002, 0x1003, 0x1004],
      eventsSupported: [0x4002, 0x4003]
    )
    XCTAssertEqual(info.manufacturer, "OnePlus")
    XCTAssertEqual(info.model, "ONEPLUS A3010")
    XCTAssertEqual(info.version, "1.0")
    XCTAssertEqual(info.serialNumber, "ABC123")
    XCTAssertEqual(info.operationsSupported.count, 4)
    XCTAssertTrue(info.operationsSupported.contains(PTPOp.getDeviceInfo.rawValue))
    XCTAssertTrue(info.operationsSupported.contains(PTPOp.openSession.rawValue))
  }

  // MARK: - 4. Error Message Formatting (Actionable)

  func testActionableErrorBusyMessage() {
    let err = MTPError.busy
    XCTAssertEqual(
      err.actionableDescription,
      "Device appears to be in charging mode. Unlock your device and select 'File Transfer'."
    )
  }

  func testActionableErrorPermissionDenied() {
    let err = MTPError.permissionDenied
    XCTAssertEqual(
      err.actionableDescription,
      "USB access denied. Check System Settings > Privacy & Security and re-approve device access."
    )
  }

  func testActionableErrorDeviceDisconnected() {
    let err = MTPError.deviceDisconnected
    XCTAssertEqual(
      err.actionableDescription,
      "Device disconnected. Reconnect the cable and ensure the device is unlocked."
    )
  }

  func testActionableTransportNoDevice() {
    let err = TransportError.noDevice
    XCTAssertEqual(
      err.actionableDescription,
      "No MTP device found. Ensure the device is connected, unlocked, and set to File Transfer mode."
    )
  }

  func testActionableTransportAccessDenied() {
    let err = TransportError.accessDenied
    XCTAssertEqual(
      err.actionableDescription,
      "USB access denied. Close Android File Transfer, adb, or Smart Switch, then check System Settings > Privacy & Security."
    )
  }

  func testActionableTransportTimeoutInPhase() {
    let err = TransportError.timeoutInPhase(.bulkIn)
    XCTAssertEqual(
      err.actionableDescription,
      "USB transfer timed out (bulk-in phase). Ensure the device is unlocked and check the cable."
    )
  }

  // MARK: - 5. Error Recovery Suggestion Formatting

  func testRecoverySuggestionProtocolError() {
    let err = MTPError.protocolError(code: 0x201D, message: "InvalidParameter")
    XCTAssertEqual(
      err.recoverySuggestion,
      "Write to a writable folder (for example Download, DCIM, or a nested folder) instead of root."
    )
  }

  func testRecoverySuggestionTransportNoDevice() {
    let err = TransportError.noDevice
    XCTAssertEqual(
      err.recoverySuggestion,
      "Unplug and replug the device, confirm screen unlocked and trust prompt accepted."
    )
  }

  // MARK: - 6. Storage Info Display Formatting

  func testStorageInfoDisplaySnapshot() {
    let storage = MTPStorageInfo(
      id: MTPStorageID(raw: 0x00010001),
      description: "Internal shared storage",
      capacityBytes: 128_000_000_000,
      freeBytes: 42_000_000_000,
      isReadOnly: false
    )
    XCTAssertEqual(storage.description, "Internal shared storage")
    XCTAssertEqual(storage.capacityBytes, 128_000_000_000)
    XCTAssertEqual(storage.freeBytes, 42_000_000_000)
    XCTAssertEqual(storage.isReadOnly, false)
    XCTAssertEqual(storage.id.raw, 0x00010001)
  }

  func testStorageInfoReadOnlyDisplay() {
    let storage = MTPStorageInfo(
      id: MTPStorageID(raw: 0x00020001),
      description: "SD Card",
      capacityBytes: 64_000_000_000,
      freeBytes: 0,
      isReadOnly: true
    )
    XCTAssertEqual(storage.description, "SD Card")
    XCTAssertTrue(storage.isReadOnly)
    XCTAssertEqual(storage.freeBytes, 0)
  }

  // MARK: - 7. Object Info Display Formatting

  func testObjectInfoFileSnapshot() {
    let obj = MTPObjectInfo(
      handle: 42,
      storage: MTPStorageID(raw: 0x00010001),
      parent: 1,
      name: "vacation-photo.jpg",
      sizeBytes: 4_200_000,
      modified: ISO8601DateFormatter().date(from: "2026-01-15T14:30:00Z"),
      formatCode: 0x3801,
      properties: [:]
    )
    XCTAssertEqual(obj.name, "vacation-photo.jpg")
    XCTAssertEqual(obj.handle, 42)
    XCTAssertEqual(obj.sizeBytes, 4_200_000)
    XCTAssertEqual(obj.formatCode, 0x3801)  // EXIF/JPEG
    XCTAssertEqual(obj.parent, 1)
  }

  func testObjectInfoDirectorySnapshot() {
    let obj = MTPObjectInfo(
      handle: 10,
      storage: MTPStorageID(raw: 0x00010001),
      parent: nil,
      name: "DCIM",
      sizeBytes: nil,
      modified: nil,
      formatCode: 0x3001,  // Association (folder)
      properties: [:]
    )
    XCTAssertEqual(obj.name, "DCIM")
    XCTAssertEqual(obj.formatCode, 0x3001)
    XCTAssertNil(obj.parent)
    XCTAssertNil(obj.sizeBytes)
  }

  // MARK: - 8. JSON Output Mode

  func testJSONOutputSortedKeys() throws {
    let envelope = CLIErrorEnvelope(
      "test_error",
      details: ["z_key": "last", "a_key": "first"],
      timestamp: "2026-02-08T10:00:00Z"
    )
    let enc = JSONEncoder()
    enc.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    let data = try enc.encode(envelope)
    let json = String(data: data, encoding: .utf8)!
    // Keys should appear in alphabetical order in the top-level object
    let detailsRange = json.range(of: "\"details\"")!
    let errorRange = json.range(of: "\"error\"")!
    let typeRange = json.range(of: "\"type\"")!
    XCTAssertTrue(detailsRange.lowerBound < errorRange.lowerBound)
    XCTAssertTrue(errorRange.lowerBound < typeRange.lowerBound)
  }

  func testJSONOutputNoEscapingSlashes() throws {
    let envelope = CLIErrorEnvelope(
      "path/to/file",
      timestamp: "2026-02-08T10:00:00Z"
    )
    let enc = JSONEncoder()
    enc.outputFormatting = [.withoutEscapingSlashes]
    let data = try enc.encode(envelope)
    let json = String(data: data, encoding: .utf8)!
    XCTAssertTrue(json.contains("path/to/file"))
    XCTAssertFalse(json.contains("path\\/to\\/file"))
  }

  // MARK: - 9. Quirks Output Formatting

  func testQuirkResolverOutputForKnownDevice() throws {
    let db = try QuirkDatabase.load()
    let match = db.match(
      vid: 0x2717, pid: 0xFF10,
      bcdDevice: nil, ifaceClass: 0x06, ifaceSubclass: 0x01, ifaceProtocol: 0x01
    )
    XCTAssertNotNil(match)
    XCTAssertEqual(match?.id, "xiaomi-mi-note-2-ff10")
  }

  // MARK: - Helpers

  private func sortedJSON<T: Encodable>(_ value: T) throws -> Data {
    let enc = JSONEncoder()
    enc.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    return try enc.encode(value)
  }

  private func makeTestProbeReceipt() -> ProbeReceipt {
    let fingerprint = MTPDeviceFingerprint(
      vid: "18d1",
      pid: "4ee1",
      bcdDevice: "0528",
      interfaceTriple: InterfaceTriple(class: "06", subclass: "01", protocol: "01"),
      endpointAddresses: EndpointAddresses(input: "81", output: "01", event: "82"),
      deviceInfoHash: "google-pixel-7-hash"
    )
    let summary = MTPDeviceSummary(
      id: MTPDeviceID(raw: "pixel7-test"),
      manufacturer: "Google",
      model: "Pixel 7",
      vendorID: 0x18D1,
      productID: 0x4EE1,
      usbSerial: "TESTSERIAL"
    )
    var receipt = ProbeReceipt(
      timestamp: ISO8601DateFormatter().date(from: "2026-02-08T10:00:00Z")!,
      deviceSummary: ReceiptDeviceSummary(from: summary),
      fingerprint: fingerprint
    )
    receipt.totalProbeTimeMs = 134
    receipt.capabilities = [
      "supportsGetPartialObject64": true,
      "supportsEvents": true,
    ]
    receipt.fallbackResults = [
      "enumeration": "propList5",
      "read": "partial64",
    ]
    return receipt
  }
}

// MARK: - JSONDecoder convenience

private extension JSONDecoder {
  static func mtpDecoder() -> JSONDecoder {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return decoder
  }
}
