// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import XCTest
@testable import swiftmtp_cli
import SwiftMTPCore
import SwiftMTPQuirks

// MARK: - DeviceLabHarness Unit Tests

final class DeviceLabHarnessInitTests: XCTestCase {
  func testHarnessCanBeCreated() {
    let harness = DeviceLabHarness()
    XCTAssertNotNil(harness)
  }
}

// MARK: - CapabilityTestResult Tests

final class CapabilityTestResultTests: XCTestCase {
  func testCapabilityTestResultBasicInit() {
    let result = CapabilityTestResult(
      name: "GetDeviceInfo", opcode: "0x1001", supported: true, durationMs: 42)
    XCTAssertEqual(result.name, "GetDeviceInfo")
    XCTAssertEqual(result.opcode, "0x1001")
    XCTAssertTrue(result.supported)
    XCTAssertEqual(result.durationMs, 42)
    XCTAssertNil(result.errorMessage)
  }

  func testCapabilityTestResultWithError() {
    let result = CapabilityTestResult(
      name: "GetStorageIDs", opcode: "0x1004", supported: false, durationMs: 100,
      errorMessage: "timeout")
    XCTAssertFalse(result.supported)
    XCTAssertEqual(result.errorMessage, "timeout")
  }

  func testCapabilityTestResultWithoutOpcode() {
    let result = CapabilityTestResult(
      name: "CustomTest", supported: true, durationMs: 5)
    XCTAssertNil(result.opcode)
    XCTAssertTrue(result.supported)
  }

  func testCapabilityTestResultEncodeDecode() throws {
    let original = CapabilityTestResult(
      name: "GetObjectHandles", opcode: "0x1007", supported: true, durationMs: 55,
      errorMessage: nil)
    let data = try JSONEncoder().encode(original)
    let decoded = try JSONDecoder().decode(CapabilityTestResult.self, from: data)
    XCTAssertEqual(decoded.name, original.name)
    XCTAssertEqual(decoded.opcode, original.opcode)
    XCTAssertEqual(decoded.supported, original.supported)
    XCTAssertEqual(decoded.durationMs, original.durationMs)
    XCTAssertEqual(decoded.errorMessage, original.errorMessage)
  }

  func testCapabilityTestResultWithZeroDuration() {
    let result = CapabilityTestResult(
      name: "InstantOp", opcode: "0x9999", supported: true, durationMs: 0)
    XCTAssertEqual(result.durationMs, 0)
  }
}

// MARK: - SuggestedTuning Tests

final class SuggestedTuningTests: XCTestCase {
  func testDefaultTuningValues() {
    let tuning = SuggestedTuning()
    XCTAssertEqual(tuning.maxChunkBytes, 1 << 20)
    XCTAssertEqual(tuning.ioTimeoutMs, 8000)
    XCTAssertEqual(tuning.handshakeTimeoutMs, 6000)
  }

  func testCustomTuningValues() {
    let tuning = SuggestedTuning(
      maxChunkBytes: 512_000, ioTimeoutMs: 3000, handshakeTimeoutMs: 2000)
    XCTAssertEqual(tuning.maxChunkBytes, 512_000)
    XCTAssertEqual(tuning.ioTimeoutMs, 3000)
    XCTAssertEqual(tuning.handshakeTimeoutMs, 2000)
  }

  func testSuggestedTuningEncodeDecode() throws {
    let original = SuggestedTuning(
      maxChunkBytes: 2_097_152, ioTimeoutMs: 10000, handshakeTimeoutMs: 5000)
    let data = try JSONEncoder().encode(original)
    let decoded = try JSONDecoder().decode(SuggestedTuning.self, from: data)
    XCTAssertEqual(decoded.maxChunkBytes, original.maxChunkBytes)
    XCTAssertEqual(decoded.ioTimeoutMs, original.ioTimeoutMs)
    XCTAssertEqual(decoded.handshakeTimeoutMs, original.handshakeTimeoutMs)
  }
}

// MARK: - DeviceLabReport Tests

final class DeviceLabReportTests: XCTestCase {
  private func makeFingerprint() -> MTPDeviceFingerprint {
    MTPDeviceFingerprint.fromUSB(
      vid: 0x18D1, pid: 0x4EE1,
      interfaceClass: 0x06, interfaceSubclass: 0x01, interfaceProtocol: 0x01,
      epIn: 0x81, epOut: 0x01)
  }

  func testDeviceLabReportInit() {
    let report = DeviceLabReport(
      manufacturer: "Google",
      model: "Pixel 7",
      serialNumber: "SN-001",
      fingerprint: makeFingerprint(),
      operationsSupported: ["0x1001", "0x1002"],
      eventsSupported: ["0x4001"],
      capabilityTests: [],
      suggestedFlags: QuirkFlags(),
      suggestedTuning: SuggestedTuning())
    XCTAssertEqual(report.manufacturer, "Google")
    XCTAssertEqual(report.model, "Pixel 7")
    XCTAssertEqual(report.serialNumber, "SN-001")
    XCTAssertEqual(report.operationsSupported.count, 2)
    XCTAssertEqual(report.eventsSupported.count, 1)
  }

  func testDeviceLabReportWithNilSerial() {
    let report = DeviceLabReport(
      manufacturer: "Samsung",
      model: "Galaxy S7",
      serialNumber: nil,
      fingerprint: makeFingerprint(),
      operationsSupported: [],
      eventsSupported: [],
      capabilityTests: [],
      suggestedFlags: QuirkFlags(),
      suggestedTuning: SuggestedTuning())
    XCTAssertNil(report.serialNumber)
  }

  func testDeviceLabReportEncodeDecode() throws {
    let original = DeviceLabReport(
      timestamp: Date(timeIntervalSince1970: 1_000_000),
      manufacturer: "OnePlus",
      model: "3T",
      serialNumber: nil,
      fingerprint: makeFingerprint(),
      operationsSupported: ["0x1001"],
      eventsSupported: [],
      capabilityTests: [
        CapabilityTestResult(
          name: "GetDeviceInfo", opcode: "0x1001", supported: true, durationMs: 10)
      ],
      suggestedFlags: QuirkFlags(),
      suggestedTuning: SuggestedTuning())
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let data = try encoder.encode(original)
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let decoded = try decoder.decode(DeviceLabReport.self, from: data)
    XCTAssertEqual(decoded.manufacturer, "OnePlus")
    XCTAssertEqual(decoded.model, "3T")
    XCTAssertEqual(decoded.capabilityTests.count, 1)
    XCTAssertEqual(decoded.capabilityTests.first?.name, "GetDeviceInfo")
  }

  func testDeviceLabReportWithCapabilityTests() {
    let tests = [
      CapabilityTestResult(
        name: "GetDeviceInfo", opcode: "0x1001", supported: true, durationMs: 10),
      CapabilityTestResult(
        name: "GetStorageIDs", opcode: "0x1004", supported: true, durationMs: 20),
      CapabilityTestResult(
        name: "GetObjectHandles", opcode: "0x1007", supported: false, durationMs: 5000,
        errorMessage: "timeout"),
    ]
    let report = DeviceLabReport(
      manufacturer: "Test",
      model: "Device",
      serialNumber: nil,
      fingerprint: makeFingerprint(),
      operationsSupported: [],
      eventsSupported: [],
      capabilityTests: tests,
      suggestedFlags: QuirkFlags(),
      suggestedTuning: SuggestedTuning())
    XCTAssertEqual(report.capabilityTests.count, 3)
    XCTAssertTrue(report.capabilityTests[0].supported)
    XCTAssertFalse(report.capabilityTests[2].supported)
    XCTAssertEqual(report.capabilityTests[2].errorMessage, "timeout")
  }
}

// MARK: - VirtualDeviceProfile Tests

final class VirtualDeviceProfileTests: XCTestCase {
  func testPixel7Profile() {
    let p = VirtualDeviceProfiles.pixel7
    XCTAssertEqual(p.name, "pixel7")
    XCTAssertEqual(p.vendorID, 0x18D1)
    XCTAssertEqual(p.productID, 0x4EE1)
    XCTAssertEqual(p.manufacturer, "Google")
    XCTAssertEqual(p.model, "Pixel 7")
    XCTAssertFalse(p.supportedOperations.isEmpty)
    XCTAssertFalse(p.supportedEvents.isEmpty)
    XCTAssertEqual(p.storageInfo.count, 1)
  }

  func testOnePlus3TProfile() {
    let p = VirtualDeviceProfiles.onePlus3T
    XCTAssertEqual(p.name, "oneplus3t")
    XCTAssertEqual(p.vendorID, 0x2A70)
    XCTAssertEqual(p.manufacturer, "OnePlus")
    XCTAssertEqual(p.storageInfo.count, 2)
    XCTAssertFalse(p.quirks.supportsPartialRead64)
    XCTAssertTrue(p.quirks.supportsPartialRead32)
  }

  func testMiNote2Profile() {
    let p = VirtualDeviceProfiles.miNote2
    XCTAssertEqual(p.name, "mi-note2")
    XCTAssertEqual(p.vendorID, 0x2717)
    XCTAssertEqual(p.productID, 0xFF10)
    XCTAssertEqual(p.manufacturer, "Xiaomi")
    XCTAssertTrue(p.quirks.disableEventPump)
    XCTAssertFalse(p.quirks.supportsPartialRead64)
    XCTAssertFalse(p.quirks.supportsPartialRead32)
  }

  func testVirtualStorageInfoInit() {
    let storage = VirtualDeviceProfile.VirtualStorageInfo(
      storageID: 0x00010001,
      capacity: 128_000_000_000,
      freeSpace: 64_000_000_000,
      fileSystemType: "FAT32",
      accessCapability: 0x0003)
    XCTAssertEqual(storage.storageID, 0x00010001)
    XCTAssertEqual(storage.capacity, 128_000_000_000)
    XCTAssertEqual(storage.freeSpace, 64_000_000_000)
    XCTAssertEqual(storage.fileSystemType, "FAT32")
    XCTAssertEqual(storage.accessCapability, 0x0003)
  }

  func testProfileStorageFreeSpaceLessThanCapacity() {
    for profile in [
      VirtualDeviceProfiles.pixel7, VirtualDeviceProfiles.onePlus3T, VirtualDeviceProfiles.miNote2,
    ] {
      for storage in profile.storageInfo {
        XCTAssertLessThanOrEqual(
          storage.freeSpace, storage.capacity,
          "\(profile.name): freeSpace exceeds capacity for storage \(storage.storageID)")
      }
    }
  }

  func testAllProfilesHaveAtLeastOneStorage() {
    let profiles = [
      VirtualDeviceProfiles.pixel7, VirtualDeviceProfiles.onePlus3T, VirtualDeviceProfiles.miNote2,
    ]
    for profile in profiles {
      XCTAssertFalse(
        profile.storageInfo.isEmpty,
        "\(profile.name) should have at least one storage")
    }
  }

  func testAllProfilesHaveUniqueVIDPID() {
    let profiles = [
      VirtualDeviceProfiles.pixel7, VirtualDeviceProfiles.onePlus3T, VirtualDeviceProfiles.miNote2,
    ]
    var seen = Set<String>()
    for profile in profiles {
      let key = String(format: "%04x:%04x", profile.vendorID, profile.productID)
      XCTAssertTrue(seen.insert(key).inserted, "Duplicate VID:PID \(key) in virtual profiles")
    }
  }
}

// MARK: - MockUSBTransport Tests

final class MockUSBTransportTests: XCTestCase {
  func testTransportInitiallyDisconnected() async {
    let transport = MockUSBTransport()
    let connected = await transport.isConnected
    XCTAssertFalse(connected)
  }

  func testTransportConnectAndDisconnect() async throws {
    let transport = MockUSBTransport()
    try await transport.connect(vid: 0x18D1, pid: 0x4EE1)
    var connected = await transport.isConnected
    XCTAssertTrue(connected)

    await transport.disconnect()
    connected = await transport.isConnected
    XCTAssertFalse(connected)
  }

  func testTransportDefaultEndpoints() async {
    let transport = MockUSBTransport()
    let epIn = await transport.endpointIn
    let epOut = await transport.endpointOut
    XCTAssertEqual(epIn, 0x81)
    XCTAssertEqual(epOut, 0x01)
  }

  func testTransportWriteWhenDisconnectedThrows() async {
    let transport = MockUSBTransport()
    do {
      _ = try await transport.write(Data([0x01, 0x02]), timeout: 1000)
      XCTFail("Expected error for write when disconnected")
    } catch {
      XCTAssertEqual(error as? USBTransportError, .notConnected)
    }
  }

  func testTransportReadWhenDisconnectedThrows() async {
    let transport = MockUSBTransport()
    var buffer = Data(count: 64)
    do {
      _ = try await transport.read(into: &buffer, timeout: 1000)
      XCTFail("Expected error for read when disconnected")
    } catch {
      XCTAssertEqual(error as? USBTransportError, .notConnected)
    }
  }

  func testTransportReadEmptyQueueThrows() async throws {
    let transport = MockUSBTransport()
    try await transport.connect(vid: 0x18D1, pid: 0x4EE1)
    var buffer = Data(count: 64)
    do {
      _ = try await transport.read(into: &buffer, timeout: 1000)
      XCTFail("Expected noData error")
    } catch {
      XCTAssertEqual(error as? USBTransportError, .noData)
    }
  }

  func testTransportErrorInjectionStall() async throws {
    let transport = MockUSBTransport()
    try await transport.connect(vid: 0x18D1, pid: 0x4EE1)
    await transport.setErrorInjection(.stallNextRequest)
    do {
      _ = try await transport.write(Data([0x01]), timeout: 1000)
      XCTFail("Expected stall error")
    } catch {
      XCTAssertEqual(error as? USBTransportError, .stall)
    }
  }

  func testTransportErrorInjectionTimeout() async throws {
    let transport = MockUSBTransport()
    try await transport.connect(vid: 0x18D1, pid: 0x4EE1)
    await transport.setErrorInjection(.timeoutNextRequest)
    do {
      _ = try await transport.write(Data([0x01]), timeout: 1000)
      XCTFail("Expected timeout error")
    } catch {
      XCTAssertEqual(error as? USBTransportError, .timeout)
    }
  }

  func testTransportErrorInjectionCorrupt() async throws {
    let transport = MockUSBTransport()
    try await transport.connect(vid: 0x18D1, pid: 0x4EE1)
    await transport.setErrorInjection(.corruptNextPacket)
    do {
      _ = try await transport.write(Data([0x01]), timeout: 1000)
      XCTFail("Expected CRC error")
    } catch {
      XCTAssertEqual(error as? USBTransportError, .crcMismatch)
    }
  }

  func testTransportRequestLogTracksWrites() async throws {
    let transport = MockUSBTransport()
    try await transport.connect(vid: 0x18D1, pid: 0x4EE1)
    _ = try await transport.write(Data([0xAA, 0xBB]), timeout: 1000)
    let log = await transport.getRequestLog()
    XCTAssertEqual(log.count, 1)
    XCTAssertEqual(log.first?.direction, .outRequest)
    XCTAssertEqual(log.first?.data, Data([0xAA, 0xBB]))
  }

  func testTransportClearRequests() async throws {
    let transport = MockUSBTransport()
    try await transport.connect(vid: 0x18D1, pid: 0x4EE1)
    _ = try await transport.write(Data([0x01]), timeout: 1000)
    await transport.clearRequests()
    let log = await transport.getRequestLog()
    XCTAssertTrue(log.isEmpty)
  }
}

// MARK: - TrafficRecorder Tests

final class TrafficRecorderTests: XCTestCase {
  /// Build a TrafficEntry via JSON decoding (memberwise init is internal).
  private func makeEntry(
    direction: String = "REQ", opcode: UInt16? = nil,
    payloadBytes: Int = 4, responseTimeMs: Int = 5
  ) throws -> TrafficRecorder.TrafficEntry {
    let opcodeJSON: String = opcode.map { "\($0)" } ?? "null"
    let payloadBase64 = Data(count: payloadBytes).base64EncodedString()
    let json = """
      {"timestamp":"2025-01-01T00:00:00Z","direction":"\(direction)",
       "opcode":\(opcodeJSON),"payload":"\(payloadBase64)",
       "responseTimeMs":\(responseTimeMs)}
      """
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    decoder.dataDecodingStrategy = .base64
    return try decoder.decode(TrafficRecorder.TrafficEntry.self, from: Data(json.utf8))
  }

  func testRecorderStartsEmpty() async {
    let recorder = TrafficRecorder()
    let recordings = await recorder.getRecordings()
    XCTAssertTrue(recordings.isEmpty)
  }

  func testRecorderSessionLifecycle() async throws {
    let recorder = TrafficRecorder()
    await recorder.startSession(profile: "pixel7")
    await recorder.record(entry: try makeEntry(direction: "REQ", opcode: 0x1001))
    await recorder.record(
      entry: try makeEntry(direction: "RSP", opcode: 0x1001, responseTimeMs: 10))
    let session = await recorder.endSession()
    XCTAssertNotNil(session)
    XCTAssertEqual(session?.deviceProfile, "pixel7")
    XCTAssertEqual(session?.entries.count, 2)
  }

  func testRecorderSessionSummary() async throws {
    let recorder = TrafficRecorder()
    await recorder.startSession(profile: "test")
    await recorder.record(
      entry: try makeEntry(direction: "REQ", opcode: 0x1001, payloadBytes: 100, responseTimeMs: 10))
    await recorder.record(
      entry: try makeEntry(direction: "RSP", payloadBytes: 200, responseTimeMs: 20))
    let session = await recorder.endSession()
    XCTAssertEqual(session?.summary.totalRequests, 1)
    XCTAssertEqual(session?.summary.totalBytes, 300)
    XCTAssertEqual(session?.summary.averageResponseTimeMs, 20.0)
  }

  func testRecorderEndSessionWithoutStartReturnsNil() async {
    let recorder = TrafficRecorder()
    let session = await recorder.endSession()
    XCTAssertNil(session)
  }

  func testRecorderMultipleSessions() async {
    let recorder = TrafficRecorder()
    await recorder.startSession(profile: "session1")
    _ = await recorder.endSession()
    await recorder.startSession(profile: "session2")
    _ = await recorder.endSession()
    let recordings = await recorder.getRecordings()
    XCTAssertEqual(recordings.count, 2)
    XCTAssertEqual(recordings[0].deviceProfile, "session1")
    XCTAssertEqual(recordings[1].deviceProfile, "session2")
  }
}

// MARK: - ClassifyFailureClass Extended Tests

@MainActor
final class ClassifyFailureClassExtendedTests: XCTestCase {
  func testClassifyEnumerationFailure() {
    let result = DeviceLabCommand.classifyFailureClassForState(
      openSucceeded: false,
      deviceInfoSucceeded: false,
      storagesSucceeded: false,
      storageCount: 0,
      rootListingSucceeded: false,
      hasTransferErrors: false,
      combinedErrorText: "no mtp interface found")
    XCTAssertEqual(result, "class1-enumeration")
  }

  func testClassifyClaimFailure() {
    let result = DeviceLabCommand.classifyFailureClassForState(
      openSucceeded: false,
      deviceInfoSucceeded: false,
      storagesSucceeded: false,
      storageCount: 0,
      rootListingSucceeded: false,
      hasTransferErrors: false,
      combinedErrorText: "access denied by system policy")
    XCTAssertEqual(result, "class2-claim")
  }

  func testClassifyClaimBusyFailure() {
    let result = DeviceLabCommand.classifyFailureClassForState(
      openSucceeded: false,
      deviceInfoSucceeded: false,
      storagesSucceeded: false,
      storageCount: 0,
      rootListingSucceeded: false,
      hasTransferErrors: false,
      combinedErrorText: "claim failed on interface 0")
    XCTAssertEqual(result, "class2-claim")
  }

  func testClassifyHandshakeFailureOpenFailed() {
    let result = DeviceLabCommand.classifyFailureClassForState(
      openSucceeded: false,
      deviceInfoSucceeded: false,
      storagesSucceeded: false,
      storageCount: 0,
      rootListingSucceeded: false,
      hasTransferErrors: false,
      combinedErrorText: "unknown error during open")
    XCTAssertEqual(result, "class3-handshake")
  }

  func testClassifyHandshakeFailureDeviceInfoFailed() {
    let result = DeviceLabCommand.classifyFailureClassForState(
      openSucceeded: true,
      deviceInfoSucceeded: false,
      storagesSucceeded: true,
      storageCount: 1,
      rootListingSucceeded: true,
      hasTransferErrors: false,
      combinedErrorText: "")
    XCTAssertEqual(result, "class3-handshake")
  }

  func testClassifyTransferFailure() {
    let result = DeviceLabCommand.classifyFailureClassForState(
      openSucceeded: true,
      deviceInfoSucceeded: true,
      storagesSucceeded: true,
      storageCount: 1,
      rootListingSucceeded: true,
      hasTransferErrors: true,
      combinedErrorText: "read failed at offset 1024")
    XCTAssertEqual(result, "class4-transfer")
  }

  func testClassifyNoFailureReturnsNil() {
    let result = DeviceLabCommand.classifyFailureClassForState(
      openSucceeded: true,
      deviceInfoSucceeded: true,
      storagesSucceeded: true,
      storageCount: 2,
      rootListingSucceeded: true,
      hasTransferErrors: false,
      combinedErrorText: "")
    XCTAssertNil(result)
  }

  func testClassifyNoDeviceEnumeration() {
    let result = DeviceLabCommand.classifyFailureClassForState(
      openSucceeded: false,
      deviceInfoSucceeded: false,
      storagesSucceeded: false,
      storageCount: 0,
      rootListingSucceeded: false,
      hasTransferErrors: false,
      combinedErrorText: "no device available")
    XCTAssertEqual(result, "class1-enumeration")
  }

  func testClassifyStorageGatedNoRootListing() {
    let result = DeviceLabCommand.classifyFailureClassForState(
      openSucceeded: true,
      deviceInfoSucceeded: true,
      storagesSucceeded: true,
      storageCount: 0,
      rootListingSucceeded: false,
      hasTransferErrors: false,
      combinedErrorText: "")
    XCTAssertEqual(result, "storage_gated")
  }
}

// MARK: - LooksLikeTimeoutFailure Tests

@MainActor
final class LooksLikeTimeoutFailureTests: XCTestCase {
  func testTimeoutStringDetected() {
    XCTAssertTrue(DeviceLabCommand.looksLikeTimeoutFailure("operation timeout"))
  }

  func testTimedOutStringDetected() {
    XCTAssertTrue(DeviceLabCommand.looksLikeTimeoutFailure("request timed out"))
  }

  func testNonTimeoutNotDetected() {
    XCTAssertFalse(DeviceLabCommand.looksLikeTimeoutFailure("permission denied"))
  }

  func testNilMessageReturnsFalse() {
    XCTAssertFalse(DeviceLabCommand.looksLikeTimeoutFailure(nil))
  }

  func testEmptyMessageReturnsFalse() {
    XCTAssertFalse(DeviceLabCommand.looksLikeTimeoutFailure(""))
  }

  func testCaseInsensitiveTimeout() {
    XCTAssertTrue(DeviceLabCommand.looksLikeTimeoutFailure("TIMEOUT error"))
  }
}

// MARK: - LooksLikeRetryableWriteFailure Extended Tests

@MainActor
final class LooksLikeRetryableWriteFailureExtendedTests: XCTestCase {
  func testNilMessageReturnsFalse() {
    XCTAssertFalse(DeviceLabCommand.looksLikeRetryableWriteFailure(nil))
  }

  func testEmptyMessageReturnsFalse() {
    XCTAssertFalse(DeviceLabCommand.looksLikeRetryableWriteFailure(""))
  }

  func testInvalidParameterDetected() {
    XCTAssertTrue(DeviceLabCommand.looksLikeRetryableWriteFailure("InvalidParameter in write"))
  }

  func testInvalidStorageIDDetected() {
    XCTAssertTrue(DeviceLabCommand.looksLikeRetryableWriteFailure("InvalidStorageID"))
  }

  func testObjectNotFoundDetected() {
    XCTAssertTrue(DeviceLabCommand.looksLikeRetryableWriteFailure("ObjectNotFound during lookup"))
  }

  func testTemporaryFailureDetected() {
    XCTAssertTrue(DeviceLabCommand.looksLikeRetryableWriteFailure("temporary failure"))
  }

  func testIOErrorDetected() {
    XCTAssertTrue(DeviceLabCommand.looksLikeRetryableWriteFailure("io(pipe broken)"))
  }

  func testNonRetryableFailure() {
    XCTAssertFalse(DeviceLabCommand.looksLikeRetryableWriteFailure("permission denied"))
  }
}

// MARK: - USBTransportError Tests

final class USBTransportErrorTests: XCTestCase {
  func testErrorEquality() {
    XCTAssertEqual(USBTransportError.notConnected, USBTransportError.notConnected)
    XCTAssertEqual(USBTransportError.timeout, USBTransportError.timeout)
    XCTAssertEqual(USBTransportError.stall, USBTransportError.stall)
    XCTAssertEqual(USBTransportError.crcMismatch, USBTransportError.crcMismatch)
    XCTAssertEqual(USBTransportError.noData, USBTransportError.noData)
  }

  func testErrorInequality() {
    XCTAssertNotEqual(USBTransportError.notConnected, USBTransportError.timeout)
    XCTAssertNotEqual(USBTransportError.stall, USBTransportError.babble)
  }

  func testAllCases() {
    let cases: [USBTransportError] = [
      .notConnected, .noData, .timeout, .stall,
      .crcMismatch, .babble, .deviceDisconnected,
    ]
    XCTAssertEqual(cases.count, 7)
    XCTAssertEqual(Set(cases).count, 7)
  }
}

// MARK: - MTPDeviceFingerprint Tests

final class MTPDeviceFingerprintTests: XCTestCase {
  func testFromUSBCreatesCorrectFingerprint() {
    let fp = MTPDeviceFingerprint.fromUSB(
      vid: 0x18D1, pid: 0x4EE1,
      interfaceClass: 0x06, interfaceSubclass: 0x01, interfaceProtocol: 0x01,
      epIn: 0x81, epOut: 0x01)
    XCTAssertEqual(fp.vid, "18d1")
    XCTAssertEqual(fp.pid, "4ee1")
    XCTAssertEqual(fp.interfaceTriple.class, "06")
    XCTAssertEqual(fp.interfaceTriple.subclass, "01")
    XCTAssertEqual(fp.interfaceTriple.protocol, "01")
    XCTAssertEqual(fp.endpointAddresses.input, "81")
    XCTAssertEqual(fp.endpointAddresses.output, "01")
    XCTAssertNil(fp.endpointAddresses.event)
    XCTAssertNil(fp.bcdDevice)
  }

  func testFromUSBWithBcdDevice() {
    let fp = MTPDeviceFingerprint.fromUSB(
      vid: 0x04E8, pid: 0x6860,
      bcdDevice: 0x0400,
      interfaceClass: 0x06, interfaceSubclass: 0x01, interfaceProtocol: 0x01,
      epIn: 0x81, epOut: 0x02)
    XCTAssertEqual(fp.bcdDevice, "0400")
  }

  func testFromUSBWithEventEndpoint() {
    let fp = MTPDeviceFingerprint.fromUSB(
      vid: 0x04A9, pid: 0x3139,
      interfaceClass: 0x06, interfaceSubclass: 0x01, interfaceProtocol: 0x01,
      epIn: 0x81, epOut: 0x02, epEvt: 0x83)
    XCTAssertEqual(fp.endpointAddresses.event, "83")
  }

  func testFingerprintEncodeDecode() throws {
    let original = MTPDeviceFingerprint.fromUSB(
      vid: 0x2717, pid: 0xFF10,
      interfaceClass: 0x06, interfaceSubclass: 0x01, interfaceProtocol: 0x01,
      epIn: 0x81, epOut: 0x01)
    let data = try JSONEncoder().encode(original)
    let decoded = try JSONDecoder().decode(MTPDeviceFingerprint.self, from: data)
    XCTAssertEqual(decoded.vid, original.vid)
    XCTAssertEqual(decoded.pid, original.pid)
    XCTAssertEqual(decoded, original)
  }

  func testFingerprintHashStringNotEmpty() {
    let fp = MTPDeviceFingerprint.fromUSB(
      vid: 0x18D1, pid: 0x4EE1,
      interfaceClass: 0x06, interfaceSubclass: 0x01, interfaceProtocol: 0x01,
      epIn: 0x81, epOut: 0x01)
    XCTAssertFalse(fp.hashString.isEmpty)
  }
}
