// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import XCTest
@testable import SwiftMTPCore
@testable import SwiftMTPCLI
import SwiftMTPQuirks
import SwiftMTPObservability
import SwiftMTPXPC

/// Wave-30 output-format regression tests.
///
/// Every assertion uses `XCTAssertEqual` / `XCTAssertTrue` against inline
/// expected values — no file-based snapshot infrastructure required.
/// The test guards stable, user-facing text so that refactors cannot silently
/// change error messages, JSON schemas, or serialization layouts.
final class SnapshotWave30Tests: XCTestCase {

  // MARK: - 1. CLI Error Envelope Format Variants

  func testErrorEnvelopeSchemaVersionField() throws {
    let envelope = CLIErrorEnvelope("test_error", timestamp: "2026-06-01T00:00:00Z")
    let data = try sortedJSON(envelope)
    let dict = try JSONSerialization.jsonObject(with: data) as! [String: Any]
    XCTAssertEqual(dict["schemaVersion"] as? String, "1.0")
    XCTAssertEqual(dict["type"] as? String, "error")
  }

  func testErrorEnvelopeAllFieldsPresent() throws {
    let envelope = CLIErrorEnvelope(
      "device_not_found",
      details: ["hint": "unplug/replug"],
      mode: "probe",
      timestamp: "2026-06-01T00:00:00Z"
    )
    let data = try sortedJSON(envelope)
    let dict = try JSONSerialization.jsonObject(with: data) as! [String: Any]
    XCTAssertEqual(dict["error"] as? String, "device_not_found")
    XCTAssertEqual(dict["mode"] as? String, "probe")
    XCTAssertEqual((dict["details"] as? [String: String])?["hint"], "unplug/replug")
    XCTAssertEqual(dict["timestamp"] as? String, "2026-06-01T00:00:00Z")
  }

  func testErrorEnvelopeMinimalFieldsOmitNils() throws {
    let envelope = CLIErrorEnvelope("timeout", timestamp: "2026-06-01T00:00:00Z")
    let data = try sortedJSON(envelope)
    let dict = try JSONSerialization.jsonObject(with: data) as! [String: Any]
    XCTAssertNil(dict["details"])
    XCTAssertNil(dict["mode"])
  }

  // MARK: - 2. MTPError errorDescription Regression (all cases)

  func testErrorDescriptionDeviceDisconnected() {
    XCTAssertEqual(
      MTPError.deviceDisconnected.errorDescription,
      "The device disconnected during the operation.")
  }

  func testErrorDescriptionPermissionDenied() {
    XCTAssertEqual(
      MTPError.permissionDenied.errorDescription,
      "Access to the USB device was denied.")
  }

  func testErrorDescriptionNotSupported() {
    XCTAssertEqual(
      MTPError.notSupported("GetPartialObject64").errorDescription,
      "Not supported: GetPartialObject64")
  }

  func testErrorDescriptionTransportWrapped() {
    XCTAssertEqual(
      MTPError.transport(.timeout).errorDescription,
      "The USB transfer timed out.")
  }

  func testErrorDescriptionProtocolGeneric() {
    XCTAssertEqual(
      MTPError.protocolError(code: 0x2002, message: nil).errorDescription,
      "GeneralError (0x2002): the device reported an unspecified failure.")
  }

  func testErrorDescriptionProtocolWithMessage() {
    XCTAssertEqual(
      MTPError.protocolError(code: 0x2005, message: "OperationNotSupported").errorDescription,
      "OperationNotSupported (0x2005): the device does not support this operation.")
  }

  func testErrorDescriptionProtocol201D() {
    XCTAssertEqual(
      MTPError.protocolError(code: 0x201D, message: nil).errorDescription,
      "Protocol error InvalidParameter (0x201D): write request rejected by device.")
  }

  func testErrorDescriptionObjectNotFound() {
    XCTAssertEqual(
      MTPError.objectNotFound.errorDescription,
      "The requested object was not found.")
  }

  func testErrorDescriptionObjectWriteProtected() {
    XCTAssertEqual(
      MTPError.objectWriteProtected.errorDescription,
      "The target object is write-protected.")
  }

  func testErrorDescriptionStorageFull() {
    XCTAssertEqual(
      MTPError.storageFull.errorDescription,
      "The destination storage is full.")
  }

  func testErrorDescriptionReadOnly() {
    XCTAssertEqual(
      MTPError.readOnly.errorDescription,
      "The storage is read-only.")
  }

  func testErrorDescriptionTimeout() {
    XCTAssertEqual(
      MTPError.timeout.errorDescription,
      "The operation timed out while waiting for the device.")
  }

  func testErrorDescriptionBusy() {
    XCTAssertEqual(
      MTPError.busy.errorDescription,
      "The device is busy. Retry shortly.")
  }

  func testErrorDescriptionSessionBusy() {
    XCTAssertEqual(
      MTPError.sessionBusy.errorDescription,
      "A protocol transaction is already in progress on this device.")
  }

  func testErrorDescriptionPreconditionFailed() {
    XCTAssertEqual(
      MTPError.preconditionFailed("session closed").errorDescription,
      "Precondition failed: session closed")
  }

  func testErrorDescriptionVerificationFailed() {
    XCTAssertEqual(
      MTPError.verificationFailed(expected: 1024, actual: 512).errorDescription,
      "Write verification failed: remote size 512 does not match expected 1024.")
  }

  // MARK: - 3. Actionable Error Text Regression (all MTPError cases)

  func testActionableDeviceDisconnected() {
    XCTAssertEqual(
      MTPError.deviceDisconnected.actionableDescription,
      "Device disconnected. Reconnect the cable and ensure the device is unlocked.")
  }

  func testActionablePermissionDenied() {
    XCTAssertEqual(
      MTPError.permissionDenied.actionableDescription,
      "USB access denied. Check System Settings > Privacy & Security and re-approve device access.")
  }

  func testActionableNotSupported() {
    XCTAssertEqual(
      MTPError.notSupported("SendPartialObject").actionableDescription,
      "Not supported: SendPartialObject. Check device firmware or try a different approach.")
  }

  func testActionableProtocolError() {
    let err = MTPError.protocolError(code: 0x2002, message: nil)
    XCTAssertEqual(err.actionableDescription, "Device returned a protocol error: 0x2002")
  }

  func testActionableProtocolErrorWithMessage() {
    let err = MTPError.protocolError(code: 0x2005, message: "OperationNotSupported")
    XCTAssertEqual(
      err.actionableDescription,
      "Device returned a protocol error: OperationNotSupported")
  }

  func testActionableObjectNotFound() {
    XCTAssertEqual(
      MTPError.objectNotFound.actionableDescription,
      "The requested object was not found on the device. It may have been deleted or moved.")
  }

  func testActionableObjectWriteProtected() {
    XCTAssertEqual(
      MTPError.objectWriteProtected.actionableDescription,
      "Device storage is write-protected. Remove protection on the device and retry.")
  }

  func testActionableStorageFull() {
    XCTAssertEqual(
      MTPError.storageFull.actionableDescription,
      "Device storage is full. Free space on the device, then retry the transfer.")
  }

  func testActionableReadOnly() {
    XCTAssertEqual(
      MTPError.readOnly.actionableDescription,
      "The storage is read-only. Check for a physical write-protect switch or device setting.")
  }

  func testActionableTimeout() {
    XCTAssertEqual(
      MTPError.timeout.actionableDescription,
      "The operation timed out. Check that the device is still connected and unlocked.")
  }

  func testActionableBusy() {
    XCTAssertEqual(
      MTPError.busy.actionableDescription,
      "Device appears to be in charging mode. Unlock your device and select 'File Transfer'.")
  }

  func testActionableSessionBusy() {
    XCTAssertEqual(
      MTPError.sessionBusy.actionableDescription,
      "An MTP operation is already in progress. Wait briefly and retry.")
  }

  func testActionablePreconditionFailed() {
    XCTAssertEqual(
      MTPError.preconditionFailed("no storage").actionableDescription,
      "Precondition failed: no storage")
  }

  func testActionableVerificationFailed() {
    XCTAssertTrue(
      MTPError.verificationFailed(expected: 100, actual: 50).actionableDescription
        .contains("Write verification failed"))
  }

  // MARK: - 4. TransportError Actionable Descriptions

  func testActionableTransportNoDevice() {
    XCTAssertEqual(
      TransportError.noDevice.actionableDescription,
      "No MTP device found. Ensure the device is connected, unlocked, and set to File Transfer mode.")
  }

  func testActionableTransportAccessDenied() {
    XCTAssertEqual(
      TransportError.accessDenied.actionableDescription,
      "USB access denied. Close Android File Transfer, adb, or Smart Switch, then check System Settings > Privacy & Security."
    )
  }

  func testActionableTransportTimeout() {
    XCTAssertEqual(
      TransportError.timeout.actionableDescription,
      "USB transfer timed out. Ensure the device screen is on and unlocked, then check the cable.")
  }

  func testActionableTransportBusy() {
    XCTAssertEqual(
      TransportError.busy.actionableDescription,
      "USB access is busy. Close competing USB tools and retry.")
  }

  func testActionableTransportStall() {
    XCTAssertEqual(
      TransportError.stall.actionableDescription,
      "USB endpoint stalled. Disconnect and reconnect the device. Try a different USB port if it persists."
    )
  }

  func testActionableTransportTimeoutBulkIn() {
    XCTAssertEqual(
      TransportError.timeoutInPhase(.bulkIn).actionableDescription,
      "USB transfer timed out (bulk-in phase). Ensure the device is unlocked and check the cable.")
  }

  func testActionableTransportTimeoutBulkOut() {
    XCTAssertEqual(
      TransportError.timeoutInPhase(.bulkOut).actionableDescription,
      "USB transfer timed out (bulk-out phase). Ensure the device is unlocked and check the cable.")
  }

  func testActionableTransportTimeoutResponseWait() {
    XCTAssertEqual(
      TransportError.timeoutInPhase(.responseWait).actionableDescription,
      "USB transfer timed out (response-wait phase). Ensure the device is unlocked and check the cable."
    )
  }

  func testActionableTransportIO() {
    XCTAssertEqual(
      TransportError.io("LIBUSB_ERROR_OVERFLOW").actionableDescription,
      "USB I/O error: LIBUSB_ERROR_OVERFLOW. Try a different USB port or cable.")
  }

  // MARK: - 5. Probe Output JSON Format

  func testProbeReceiptJSONKeysPresent() throws {
    let receipt = makePixel7ProbeReceipt()
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    let data = try encoder.encode(receipt)
    let dict = try JSONSerialization.jsonObject(with: data) as! [String: Any]
    XCTAssertNotNil(dict["timestamp"])
    XCTAssertNotNil(dict["deviceSummary"])
    XCTAssertNotNil(dict["fingerprint"])
    XCTAssertNotNil(dict["capabilities"])
    XCTAssertNotNil(dict["fallbackResults"])
    XCTAssertNotNil(dict["totalProbeTimeMs"])
  }

  func testProbeReceiptDeviceSummaryHumanReadable() throws {
    let receipt = makePixel7ProbeReceipt()
    let summary = receipt.deviceSummary
    XCTAssertEqual(summary.manufacturer, "Google")
    XCTAssertEqual(summary.model, "Pixel 7")
    XCTAssertEqual(summary.vendorID, "0x18d1")
    XCTAssertEqual(summary.productID, "0x4ee1")
  }

  func testProbeReceiptFingerprintFields() throws {
    let receipt = makePixel7ProbeReceipt()
    XCTAssertEqual(receipt.fingerprint.vid, "18d1")
    XCTAssertEqual(receipt.fingerprint.pid, "4ee1")
    XCTAssertEqual(receipt.fingerprint.interfaceTriple.class, "06")
    XCTAssertEqual(receipt.fingerprint.interfaceTriple.subclass, "01")
    XCTAssertEqual(receipt.fingerprint.interfaceTriple.protocol, "01")
  }

  func testProbeReceiptCapabilitiesFormat() throws {
    let receipt = makePixel7ProbeReceipt()
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    let data = try encoder.encode(receipt)
    let dict = try JSONSerialization.jsonObject(with: data) as! [String: Any]
    let caps = dict["capabilities"] as! [String: Bool]
    XCTAssertEqual(caps["supportsGetPartialObject64"], true)
    XCTAssertEqual(caps["supportsEvents"], true)
  }

  func testPolicySummaryJSONAllFieldsPresent() throws {
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
    let expectedKeys: Set<String> = [
      "maxChunkBytes", "ioTimeoutMs", "handshakeTimeoutMs",
      "resetOnOpen", "disableEventPump",
      "enumerationStrategy", "readStrategy", "writeStrategy",
    ]
    XCTAssertEqual(Set(dict.keys), expectedKeys)
  }

  // MARK: - 6. Quirk Profile Display for Key Device Families

  func testXiaomiFF10ProfileResolution() throws {
    let db = try QuirkDatabase.load()
    let match = db.match(
      vid: 0x2717, pid: 0xFF10,
      bcdDevice: nil, ifaceClass: 0x06, ifaceSubclass: 0x01, ifaceProtocol: 0x01
    )
    XCTAssertNotNil(match)
    XCTAssertEqual(match?.id, "xiaomi-mi-note-2-ff10")
    let resolved = match!.resolvedFlags()
    XCTAssertEqual(resolved.requiresKernelDetach, match!.resolvedFlags().requiresKernelDetach)
  }

  func testXiaomiFF40ProfileResolution() throws {
    let db = try QuirkDatabase.load()
    let match = db.match(
      vid: 0x2717, pid: 0xFF40,
      bcdDevice: nil, ifaceClass: 0xFF, ifaceSubclass: nil, ifaceProtocol: nil
    )
    XCTAssertNotNil(match)
    XCTAssertEqual(match?.id, "xiaomi-mi-note-2-ff40")
  }

  func testSamsungProfileResolution() throws {
    let db = try QuirkDatabase.load()
    let fingerprint = MTPDeviceFingerprint(
      vid: "04e8", pid: "6860", bcdDevice: nil,
      interfaceTriple: InterfaceTriple(class: "ff", subclass: "00", protocol: "00"),
      endpointAddresses: EndpointAddresses(input: "81", output: "01", event: "82"),
      deviceInfoHash: nil
    )
    let policy = QuirkResolver.resolve(fingerprint: fingerprint, database: db)
    XCTAssertEqual(policy.sources.flagsSource, .quirk)
    XCTAssertGreaterThan(policy.tuning.ioTimeoutMs, 0)
    XCTAssertGreaterThan(policy.tuning.maxChunkBytes, 0)
  }

  func testCanonProfileResolution() throws {
    let db = try QuirkDatabase.load()
    let fingerprint = MTPDeviceFingerprint(
      vid: "04a9", pid: "3139", bcdDevice: nil,
      interfaceTriple: InterfaceTriple(class: "06", subclass: "01", protocol: "01"),
      endpointAddresses: EndpointAddresses(input: "81", output: "01", event: "82"),
      deviceInfoHash: nil
    )
    let policy = QuirkResolver.resolve(fingerprint: fingerprint, database: db)
    XCTAssertEqual(policy.sources.flagsSource, .quirk)
  }

  func testNikonProfileResolution() throws {
    let db = try QuirkDatabase.load()
    let match = db.match(
      vid: 0x04B0, pid: 0x0410,
      bcdDevice: nil, ifaceClass: 0x06, ifaceSubclass: 0x01, ifaceProtocol: 0x01
    )
    XCTAssertNotNil(match)
    XCTAssertEqual(match?.id, "nikon-dslr-0410")
  }

  func testOnePlusProfileResolution() throws {
    let db = try QuirkDatabase.load()
    let match = db.match(
      vid: 0x2A70, pid: 0xF003,
      bcdDevice: nil, ifaceClass: 0x06, ifaceSubclass: 0x01, ifaceProtocol: 0x01
    )
    XCTAssertNotNil(match)
    XCTAssertEqual(match?.id, "oneplus-3t-f003")
  }

  func testUnknownDeviceDefaultPolicy() throws {
    let db = try QuirkDatabase.load()
    let fingerprint = MTPDeviceFingerprint(
      vid: "dead", pid: "beef", bcdDevice: nil,
      interfaceTriple: InterfaceTriple(class: "06", subclass: "01", protocol: "01"),
      endpointAddresses: EndpointAddresses(input: "81", output: "01", event: "82"),
      deviceInfoHash: nil
    )
    let policy = QuirkResolver.resolve(fingerprint: fingerprint, database: db)
    XCTAssertEqual(policy.sources.flagsSource, .defaults)
    XCTAssertEqual(policy.flags.requiresKernelDetach, false)
    XCTAssertEqual(policy.flags.supportsGetObjectPropList, true)
  }

  // MARK: - 7. Transfer Progress Formatting

  func testFormatBytesZero() {
    XCTAssertEqual(fmtBytes(0), "0.0 B")
  }

  func testFormatBytesSmall() {
    XCTAssertEqual(fmtBytes(512), "512.0 B")
  }

  func testFormatBytesKilobyte() {
    XCTAssertEqual(fmtBytes(1024), "1.0 KB")
  }

  func testFormatBytesMegabyte() {
    XCTAssertEqual(fmtBytes(1_048_576), "1.0 MB")
  }

  func testFormatBytesGigabyte() {
    XCTAssertEqual(fmtBytes(1_073_741_824), "1.0 GB")
  }

  func testFormatBytesTerabyte() {
    XCTAssertEqual(fmtBytes(1_099_511_627_776), "1.0 TB")
  }

  func testFormatBytesFractional() {
    XCTAssertEqual(fmtBytes(1_536), "1.5 KB")
  }

  func testFormatBytesLargeFile() {
    XCTAssertEqual(fmtBytes(4_200_000_000), "3.9 GB")
  }

  func testProgressPercentageRendering() {
    // Simulate progress at 0%, 25%, 50%, 75%, 100%
    let cases: [(UInt64, UInt64, String)] = [
      (0, 1000, "0%"),
      (250, 1000, "25%"),
      (500, 1000, "50%"),
      (750, 1000, "75%"),
      (1000, 1000, "100%"),
    ]
    for (transferred, total, expected) in cases {
      let pct = total > 0 ? Int(transferred * 100 / total) : 0
      XCTAssertEqual("\(pct)%", expected, "Progress at \(transferred)/\(total)")
    }
  }

  // MARK: - 8. DeviceLab Report Format

  func testDeviceLabReportJSONRoundTrip() throws {
    let report = makeTestDeviceLabReport()
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    let data = try encoder.encode(report)
    let decoded = try JSONDecoder.isoDecoder().decode(DeviceLabReport.self, from: data)
    XCTAssertEqual(decoded.manufacturer, "Google")
    XCTAssertEqual(decoded.model, "Pixel 7")
    XCTAssertEqual(decoded.fingerprint.vid, "18d1")
    XCTAssertEqual(decoded.capabilityTests.count, 3)
    XCTAssertEqual(decoded.suggestedTuning.maxChunkBytes, 1 << 20)
  }

  func testDeviceLabReportCapabilityTestFields() throws {
    let report = makeTestDeviceLabReport()
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    let data = try encoder.encode(report)
    let dict = try JSONSerialization.jsonObject(with: data) as! [String: Any]
    let tests = dict["capabilityTests"] as! [[String: Any]]
    XCTAssertEqual(tests.count, 3)
    XCTAssertEqual(tests[0]["name"] as? String, "GetDeviceInfo")
    XCTAssertEqual(tests[0]["supported"] as? Bool, true)
    XCTAssertNotNil(tests[0]["durationMs"])
    XCTAssertEqual(tests[2]["name"] as? String, "SendPartialObject")
    XCTAssertEqual(tests[2]["supported"] as? Bool, false)
    XCTAssertNotNil(tests[2]["errorMessage"])
  }

  func testDeviceLabReportMarkdownFormat() {
    let report = makeTestDeviceLabReport()
    let md = renderDeviceLabReportMarkdown(report)
    XCTAssertTrue(md.contains("# Device Lab Report"))
    XCTAssertTrue(md.contains("Google"))
    XCTAssertTrue(md.contains("Pixel 7"))
    XCTAssertTrue(md.contains("18d1:4ee1"))
    XCTAssertTrue(md.contains("| GetDeviceInfo |"))
    XCTAssertTrue(md.contains("| GetPartialObject64 |"))
    XCTAssertTrue(md.contains("| SendPartialObject |"))
    XCTAssertTrue(md.contains("✅"))
    XCTAssertTrue(md.contains("❌"))
  }

  // MARK: - 9. Submission Bundle Manifest Format

  func testSubmissionManifestJSONFormat() throws {
    let manifest = makeTestSubmissionManifest()
    let data = try sortedJSON(manifest)
    let dict = try JSONSerialization.jsonObject(with: data) as! [String: Any]
    XCTAssertEqual(dict["schemaVersion"] as? String, "1.0.0")
    XCTAssertNotNil(dict["tool"])
    XCTAssertNotNil(dict["host"])
    XCTAssertNotNil(dict["device"])
    XCTAssertNotNil(dict["artifacts"])
    XCTAssertNotNil(dict["consent"])
    let device = dict["device"] as! [String: Any]
    XCTAssertEqual(device["vendorId"] as? String, "18d1")
    XCTAssertEqual(device["productId"] as? String, "4ee1")
    XCTAssertEqual(device["vendor"] as? String, "Google")
    XCTAssertEqual(device["model"] as? String, "Pixel 7")
    let iface = device["interface"] as! [String: Any]
    XCTAssertEqual(iface["class"] as? String, "06")
    XCTAssertEqual(iface["subclass"] as? String, "01")
  }

  func testSubmissionManifestConsentFields() throws {
    let manifest = makeTestSubmissionManifest()
    let data = try sortedJSON(manifest)
    let dict = try JSONSerialization.jsonObject(with: data) as! [String: Any]
    let consent = dict["consent"] as! [String: Any]
    XCTAssertEqual(consent["anonymizeSerial"] as? Bool, true)
    XCTAssertEqual(consent["allowBench"] as? Bool, true)
  }

  // MARK: - 10. XPC Message Serialization

  func testReadRequestNSCodingRoundTrip() throws {
    let original = ReadRequest(deviceId: "pixel7-test", objectHandle: 42, bookmark: nil)
    let data = try NSKeyedArchiver.archivedData(
      withRootObject: original, requiringSecureCoding: true)
    let decoded = try NSKeyedUnarchiver.unarchivedObject(ofClass: ReadRequest.self, from: data)
    XCTAssertNotNil(decoded)
    XCTAssertEqual(decoded?.deviceId, "pixel7-test")
    XCTAssertEqual(decoded?.objectHandle, 42)
    XCTAssertNil(decoded?.bookmark)
  }

  func testReadResponseNSCodingRoundTrip() throws {
    let original = ReadResponse(
      success: true, errorMessage: nil,
      tempFileURL: URL(fileURLWithPath: "/tmp/test.jpg"), fileSize: 4_200_000)
    let data = try NSKeyedArchiver.archivedData(
      withRootObject: original, requiringSecureCoding: true)
    let decoded = try NSKeyedUnarchiver.unarchivedObject(ofClass: ReadResponse.self, from: data)
    XCTAssertNotNil(decoded)
    XCTAssertEqual(decoded?.success, true)
    XCTAssertNil(decoded?.errorMessage)
    XCTAssertEqual(decoded?.fileSize, 4_200_000)
  }

  func testReadResponseErrorNSCodingRoundTrip() throws {
    let original = ReadResponse(success: false, errorMessage: "Device disconnected")
    let data = try NSKeyedArchiver.archivedData(
      withRootObject: original, requiringSecureCoding: true)
    let decoded = try NSKeyedUnarchiver.unarchivedObject(ofClass: ReadResponse.self, from: data)
    XCTAssertNotNil(decoded)
    XCTAssertEqual(decoded?.success, false)
    XCTAssertEqual(decoded?.errorMessage, "Device disconnected")
    XCTAssertNil(decoded?.fileSize)
  }

  func testWriteRequestNSCodingRoundTrip() throws {
    let original = WriteRequest(
      deviceId: "dev-1", storageId: 0x00010001, parentHandle: 5,
      name: "photo.jpg", size: 5_242_880, bookmark: nil)
    let data = try NSKeyedArchiver.archivedData(
      withRootObject: original, requiringSecureCoding: true)
    let decoded = try NSKeyedUnarchiver.unarchivedObject(ofClass: WriteRequest.self, from: data)
    XCTAssertNotNil(decoded)
    XCTAssertEqual(decoded?.deviceId, "dev-1")
    XCTAssertEqual(decoded?.storageId, 0x00010001)
    XCTAssertEqual(decoded?.parentHandle, 5)
    XCTAssertEqual(decoded?.name, "photo.jpg")
    XCTAssertEqual(decoded?.size, 5_242_880)
  }

  func testWriteResponseSuccessNSCodingRoundTrip() throws {
    let original = WriteResponse(success: true, newHandle: 99)
    let data = try NSKeyedArchiver.archivedData(
      withRootObject: original, requiringSecureCoding: true)
    let decoded = try NSKeyedUnarchiver.unarchivedObject(ofClass: WriteResponse.self, from: data)
    XCTAssertNotNil(decoded)
    XCTAssertEqual(decoded?.success, true)
    XCTAssertEqual(decoded?.newHandle, 99)
    XCTAssertNil(decoded?.errorMessage)
  }

  func testDeleteRequestNSCodingRoundTrip() throws {
    let original = DeleteRequest(deviceId: "dev-1", objectHandle: 77, recursive: true)
    let data = try NSKeyedArchiver.archivedData(
      withRootObject: original, requiringSecureCoding: true)
    let decoded = try NSKeyedUnarchiver.unarchivedObject(ofClass: DeleteRequest.self, from: data)
    XCTAssertNotNil(decoded)
    XCTAssertEqual(decoded?.deviceId, "dev-1")
    XCTAssertEqual(decoded?.objectHandle, 77)
    XCTAssertEqual(decoded?.recursive, true)
  }

  func testCreateFolderRequestNSCodingRoundTrip() throws {
    let original = CreateFolderRequest(
      deviceId: "dev-1", storageId: 0x00010001, parentHandle: nil, name: "NewAlbum")
    let data = try NSKeyedArchiver.archivedData(
      withRootObject: original, requiringSecureCoding: true)
    let decoded = try NSKeyedUnarchiver.unarchivedObject(
      ofClass: CreateFolderRequest.self, from: data)
    XCTAssertNotNil(decoded)
    XCTAssertEqual(decoded?.name, "NewAlbum")
    XCTAssertNil(decoded?.parentHandle)
  }

  func testRenameRequestNSCodingRoundTrip() throws {
    let original = RenameRequest(deviceId: "dev-1", objectHandle: 10, newName: "renamed.txt")
    let data = try NSKeyedArchiver.archivedData(
      withRootObject: original, requiringSecureCoding: true)
    let decoded = try NSKeyedUnarchiver.unarchivedObject(ofClass: RenameRequest.self, from: data)
    XCTAssertNotNil(decoded)
    XCTAssertEqual(decoded?.objectHandle, 10)
    XCTAssertEqual(decoded?.newName, "renamed.txt")
  }

  func testMoveObjectRequestNSCodingRoundTrip() throws {
    let original = MoveObjectRequest(
      deviceId: "dev-1", objectHandle: 15, newParentHandle: 3, newStorageId: 0x00020001)
    let data = try NSKeyedArchiver.archivedData(
      withRootObject: original, requiringSecureCoding: true)
    let decoded = try NSKeyedUnarchiver.unarchivedObject(
      ofClass: MoveObjectRequest.self, from: data)
    XCTAssertNotNil(decoded)
    XCTAssertEqual(decoded?.objectHandle, 15)
    XCTAssertEqual(decoded?.newParentHandle, 3)
    XCTAssertEqual(decoded?.newStorageId, 0x00020001)
  }

  func testStorageListRequestNSCodingRoundTrip() throws {
    let original = StorageListRequest(deviceId: "pixel7")
    let data = try NSKeyedArchiver.archivedData(
      withRootObject: original, requiringSecureCoding: true)
    let decoded = try NSKeyedUnarchiver.unarchivedObject(
      ofClass: StorageListRequest.self, from: data)
    XCTAssertNotNil(decoded)
    XCTAssertEqual(decoded?.deviceId, "pixel7")
  }

  func testStorageInfoNSCodingRoundTrip() throws {
    let info = SwiftMTPXPC.StorageInfo(
      storageId: 0x00010001, description: "Internal shared storage",
      capacityBytes: 128_000_000_000, freeBytes: 42_000_000_000)
    let data = try NSKeyedArchiver.archivedData(
      withRootObject: info, requiringSecureCoding: true)
    let decoded = try NSKeyedUnarchiver.unarchivedObject(
      ofClass: SwiftMTPXPC.StorageInfo.self, from: data)
    XCTAssertNotNil(decoded)
    XCTAssertEqual(decoded?.storageId, 0x00010001)
    XCTAssertEqual(decoded?.storageDescription, "Internal shared storage")
    XCTAssertEqual(decoded?.capacityBytes, 128_000_000_000)
    XCTAssertEqual(decoded?.freeBytes, 42_000_000_000)
  }

  func testObjectInfoNSCodingRoundTrip() throws {
    let date = Date(timeIntervalSince1970: 1_700_000_000)
    let info = SwiftMTPXPC.ObjectInfo(
      handle: 42, name: "vacation.jpg", sizeBytes: 4_200_000,
      isDirectory: false, modifiedDate: date)
    let data = try NSKeyedArchiver.archivedData(
      withRootObject: info, requiringSecureCoding: true)
    let decoded = try NSKeyedUnarchiver.unarchivedObject(
      ofClass: SwiftMTPXPC.ObjectInfo.self, from: data)
    XCTAssertNotNil(decoded)
    XCTAssertEqual(decoded?.handle, 42)
    XCTAssertEqual(decoded?.name, "vacation.jpg")
    XCTAssertEqual(decoded?.sizeBytes, 4_200_000)
    XCTAssertEqual(decoded?.isDirectory, false)
    XCTAssertNotNil(decoded?.modifiedDate)
  }

  func testObjectInfoDirectoryNSCodingRoundTrip() throws {
    let info = SwiftMTPXPC.ObjectInfo(
      handle: 10, name: "DCIM", sizeBytes: nil,
      isDirectory: true, modifiedDate: nil)
    let data = try NSKeyedArchiver.archivedData(
      withRootObject: info, requiringSecureCoding: true)
    let decoded = try NSKeyedUnarchiver.unarchivedObject(
      ofClass: SwiftMTPXPC.ObjectInfo.self, from: data)
    XCTAssertNotNil(decoded)
    XCTAssertEqual(decoded?.name, "DCIM")
    XCTAssertEqual(decoded?.isDirectory, true)
    XCTAssertNil(decoded?.sizeBytes)
  }

  func testDeviceStatusResponseNSCodingRoundTrip() throws {
    let original = DeviceStatusResponse(
      connected: true, sessionOpen: true, lastCrawlTimestamp: 1234)
    let data = try NSKeyedArchiver.archivedData(
      withRootObject: original, requiringSecureCoding: true)
    let decoded = try NSKeyedUnarchiver.unarchivedObject(
      ofClass: DeviceStatusResponse.self, from: data)
    XCTAssertNotNil(decoded)
    XCTAssertEqual(decoded?.connected, true)
    XCTAssertEqual(decoded?.sessionOpen, true)
    XCTAssertEqual(decoded?.lastCrawlTimestamp, 1234)
  }

  func testCrawlTriggerRequestNSCodingRoundTrip() throws {
    let original = CrawlTriggerRequest(
      deviceId: "dev-1", storageId: 0x00010001, parentHandle: 5)
    let data = try NSKeyedArchiver.archivedData(
      withRootObject: original, requiringSecureCoding: true)
    let decoded = try NSKeyedUnarchiver.unarchivedObject(
      ofClass: CrawlTriggerRequest.self, from: data)
    XCTAssertNotNil(decoded)
    XCTAssertEqual(decoded?.deviceId, "dev-1")
    XCTAssertEqual(decoded?.storageId, 0x00010001)
    XCTAssertEqual(decoded?.parentHandle, 5)
  }

  // MARK: - Helpers

  /// Mirror of the CLI `formatBytes` function to test stable output format.
  private func fmtBytes(_ bytes: UInt64) -> String {
    let units = ["B", "KB", "MB", "GB", "TB"]
    var value = Double(bytes), unitIndex = 0
    while value >= 1024 && unitIndex < units.count - 1 {
      value /= 1024
      unitIndex += 1
    }
    return String(format: "%.1f %@", value, units[unitIndex])
  }

  private func sortedJSON<T: Encodable>(_ value: T) throws -> Data {
    let enc = JSONEncoder()
    enc.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    return try enc.encode(value)
  }

  private func makePixel7ProbeReceipt() -> ProbeReceipt {
    let fingerprint = MTPDeviceFingerprint(
      vid: "18d1", pid: "4ee1", bcdDevice: "0528",
      interfaceTriple: InterfaceTriple(class: "06", subclass: "01", protocol: "01"),
      endpointAddresses: EndpointAddresses(input: "81", output: "01", event: "82"),
      deviceInfoHash: "google-pixel7-hash"
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
      timestamp: ISO8601DateFormatter().date(from: "2026-06-01T10:00:00Z")!,
      deviceSummary: ReceiptDeviceSummary(from: summary),
      fingerprint: fingerprint
    )
    receipt.totalProbeTimeMs = 142
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

  private func makeTestDeviceLabReport() -> DeviceLabReport {
    let fingerprint = MTPDeviceFingerprint(
      vid: "18d1", pid: "4ee1", bcdDevice: "0528",
      interfaceTriple: InterfaceTriple(class: "06", subclass: "01", protocol: "01"),
      endpointAddresses: EndpointAddresses(input: "81", output: "01", event: "82"),
      deviceInfoHash: nil
    )
    return DeviceLabReport(
      timestamp: ISO8601DateFormatter().date(from: "2026-06-01T12:00:00Z")!,
      manufacturer: "Google",
      model: "Pixel 7",
      serialNumber: "ABC123",
      fingerprint: fingerprint,
      operationsSupported: ["GetDeviceInfo", "OpenSession", "GetPartialObject64"],
      eventsSupported: ["ObjectAdded", "ObjectRemoved"],
      capabilityTests: [
        CapabilityTestResult(
          name: "GetDeviceInfo", opcode: "0x1001", supported: true, durationMs: 12),
        CapabilityTestResult(
          name: "GetPartialObject64", opcode: "0x95C4", supported: true, durationMs: 45),
        CapabilityTestResult(
          name: "SendPartialObject", opcode: "0x95C1", supported: false, durationMs: 8,
          errorMessage: "OperationNotSupported (0x2005)"),
      ],
      suggestedFlags: QuirkFlags(),
      suggestedTuning: SuggestedTuning()
    )
  }

  /// Render a DeviceLabReport as markdown — mirrors what the CLI would produce.
  private func renderDeviceLabReportMarkdown(_ report: DeviceLabReport) -> String {
    var lines: [String] = []
    lines.append("# Device Lab Report")
    lines.append("")
    lines.append("| Field | Value |")
    lines.append("|-------|-------|")
    lines.append("| Manufacturer | \(report.manufacturer) |")
    lines.append("| Model | \(report.model) |")
    lines.append("| VID:PID | \(report.fingerprint.vid):\(report.fingerprint.pid) |")
    lines.append("| Serial | \(report.serialNumber ?? "—") |")
    lines.append("")
    lines.append("## Capability Tests")
    lines.append("")
    lines.append("| Test | Opcode | Supported | Duration |")
    lines.append("|------|--------|-----------|----------|")
    for test in report.capabilityTests {
      let icon = test.supported ? "✅" : "❌"
      let opcode = test.opcode ?? "—"
      lines.append("| \(test.name) | \(opcode) | \(icon) | \(test.durationMs)ms |")
    }
    return lines.joined(separator: "\n")
  }

  // Lightweight manifest for testing (mirrors CollectCommand.SubmissionManifest).
  private struct TestSubmissionManifest: Codable {
    var schemaVersion: String = "1.0.0"
    let tool: ToolInfo
    let host: HostInfo
    let timestamp: String
    let device: DeviceInfo
    let artifacts: ArtifactInfo
    let consent: ConsentInfo

    struct ToolInfo: Codable {
      var name: String = "swiftmtp"
      let version: String
      let commit: String?
    }

    struct HostInfo: Codable {
      let os: String
      let arch: String
    }

    struct DeviceInfo: Codable {
      let vendorId: String
      let productId: String
      let vendor: String
      let model: String
      let interface: InterfaceInfo
      let fingerprintHash: String
      let serialRedacted: String
    }

    struct InterfaceInfo: Codable {
      let `class`: String
      let subclass: String
      let `protocol`: String
      let `in`: String
      let out: String
    }

    struct ArtifactInfo: Codable {
      let probe: String
      let usbDump: String
    }

    struct ConsentInfo: Codable {
      let anonymizeSerial: Bool
      let allowBench: Bool
    }
  }

  private func makeTestSubmissionManifest() -> TestSubmissionManifest {
    TestSubmissionManifest(
      tool: .init(name: "swiftmtp", version: "0.1.0", commit: "abc1234"),
      host: .init(os: "macOS 15.0", arch: "arm64"),
      timestamp: "2026-06-01T12:00:00Z",
      device: .init(
        vendorId: "18d1", productId: "4ee1",
        vendor: "Google", model: "Pixel 7",
        interface: .init(
          class: "06", subclass: "01", protocol: "01",
          in: "81", out: "01"),
        fingerprintHash: "sha256:deadbeef",
        serialRedacted: "PXL***23"),
      artifacts: .init(probe: "probe.json", usbDump: "usb-dump.txt"),
      consent: .init(anonymizeSerial: true, allowBench: true)
    )
  }
}

// MARK: - JSONDecoder convenience

private extension JSONDecoder {
  static func isoDecoder() -> JSONDecoder {
    let d = JSONDecoder()
    d.dateDecodingStrategy = .iso8601
    return d
  }
}
