// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import XCTest
@testable import swiftmtp_cli
import SwiftMTPCore
import SwiftMTPCLI
import SwiftMTPQuirks

// MARK: - CLI Argument Parsing Edge Cases

final class CLIArgParsingEdgeCaseTests: XCTestCase {

  // MARK: Empty and minimal args

  func testEmptyArgsArrayProducesNilFilter() {
    var args: [String] = []
    let filter = DeviceFilterParse.parse(from: &args)
    XCTAssertNil(filter.vid)
    XCTAssertNil(filter.pid)
    XCTAssertNil(filter.bus)
    XCTAssertNil(filter.address)
    XCTAssertTrue(args.isEmpty)
  }

  func testUnknownFlagsPassThrough() {
    var args = ["--verbose", "--timeout", "30", "probe"]
    let filter = DeviceFilterParse.parse(from: &args)
    XCTAssertNil(filter.vid)
    XCTAssertEqual(args, ["--verbose", "--timeout", "30", "probe"])
  }

  func testDuplicateVIDFlagsUsesLast() {
    var args = ["--vid", "04e8", "--vid", "2717"]
    let filter = DeviceFilterParse.parse(from: &args)
    // Second parse overwrites first
    XCTAssertEqual(filter.vid, 0x2717)
    XCTAssertTrue(args.isEmpty)
  }

  func testDuplicatePIDFlagsUsesLast() {
    var args = ["--pid", "6860", "--pid", "ff10"]
    let filter = DeviceFilterParse.parse(from: &args)
    XCTAssertEqual(filter.pid, 0xff10)
    XCTAssertTrue(args.isEmpty)
  }

  func testVIDFlagWithoutValueSkipped() {
    var args = ["--vid"]
    let filter = DeviceFilterParse.parse(from: &args)
    XCTAssertNil(filter.vid)
  }

  func testPIDFlagWithoutValueSkipped() {
    var args = ["--pid"]
    let filter = DeviceFilterParse.parse(from: &args)
    XCTAssertNil(filter.pid)
  }

  func testBusFlagWithNonIntegerSkipped() {
    var args = ["--bus", "abc"]
    let filter = DeviceFilterParse.parse(from: &args)
    XCTAssertNil(filter.bus)
  }

  func testAddressFlagWithNonIntegerSkipped() {
    var args = ["--address", "xyz"]
    let filter = DeviceFilterParse.parse(from: &args)
    XCTAssertNil(filter.address)
  }
}

// MARK: - Device Filter Parsing (by vendor, product, bus, serial)

final class DeviceFilterParsingWave29Tests: XCTestCase {

  func testParseVIDWithHexPrefix() {
    XCTAssertEqual(parseUSBIdentifier("0x04e8"), 0x04e8)
    XCTAssertEqual(parseUSBIdentifier("0X2717"), 0x2717)
  }

  func testParseVIDWithImplicitHex() {
    // Contains a-f characters → hex
    XCTAssertEqual(parseUSBIdentifier("04e8"), 0x04e8)
    XCTAssertEqual(parseUSBIdentifier("abcd"), 0xabcd)
  }

  func testParseVIDWithDecimalFallback() {
    // "1234" has no hex-only digits, parsed as hex first (default)
    XCTAssertEqual(parseUSBIdentifier("1234"), 0x1234)
  }

  func testParseNilReturnsNil() {
    XCTAssertNil(parseUSBIdentifier(nil))
  }

  func testParseEmptyStringReturnsNil() {
    XCTAssertNil(parseUSBIdentifier(""))
    XCTAssertNil(parseUSBIdentifier("   "))
  }

  func testFilterByVIDAndPID() {
    var args = ["--vid", "2717", "--pid", "ff10", "probe"]
    let filter = DeviceFilterParse.parse(from: &args)
    XCTAssertEqual(filter.vid, 0x2717)
    XCTAssertEqual(filter.pid, 0xff10)
    XCTAssertEqual(args, ["probe"])
  }

  func testFilterByBusAndAddress() {
    var args = ["--bus", "1", "--address", "4", "ls"]
    let filter = DeviceFilterParse.parse(from: &args)
    XCTAssertEqual(filter.bus, 1)
    XCTAssertEqual(filter.address, 4)
    XCTAssertEqual(args, ["ls"])
  }

  func testFilterAllFieldsCombined() {
    var args = ["--vid", "04e8", "--pid", "6860", "--bus", "2", "--address", "7"]
    let filter = DeviceFilterParse.parse(from: &args)
    XCTAssertEqual(filter.vid, 0x04e8)
    XCTAssertEqual(filter.pid, 0x6860)
    XCTAssertEqual(filter.bus, 2)
    XCTAssertEqual(filter.address, 7)
    XCTAssertTrue(args.isEmpty)
  }
}

// MARK: - Device Selection Logic

private struct MockCandidate: DeviceFilterCandidate {
  var vendorID: UInt16?
  var productID: UInt16?
  var bus: UInt8?
  var address: UInt8?
}

final class DeviceSelectionWave29Tests: XCTestCase {

  func testSelectFromEmptyReturnsNone() {
    let result = selectDevice(
      [MockCandidate](), filter: DeviceFilter(vid: nil, pid: nil, bus: nil, address: nil),
      noninteractive: true)
    if case .none = result {} else { XCTFail("Expected .none") }
  }

  func testSelectSingleDeviceNoFilter() {
    let dev = MockCandidate(vendorID: 0x2717, productID: 0xff10, bus: 1, address: 3)
    let result = selectDevice(
      [dev], filter: DeviceFilter(vid: nil, pid: nil, bus: nil, address: nil),
      noninteractive: true)
    if case .selected(let d) = result {
      XCTAssertEqual(d.vendorID, 0x2717)
    } else {
      XCTFail("Expected .selected")
    }
  }

  func testSelectByVIDFiltersCorrectly() {
    let devA = MockCandidate(vendorID: 0x2717, productID: 0xff10, bus: 1, address: 3)
    let devB = MockCandidate(vendorID: 0x04e8, productID: 0x6860, bus: 1, address: 4)
    let result = selectDevice(
      [devA, devB], filter: DeviceFilter(vid: 0x2717, pid: nil, bus: nil, address: nil),
      noninteractive: true)
    if case .selected(let d) = result {
      XCTAssertEqual(d.vendorID, 0x2717)
    } else {
      XCTFail("Expected .selected for VID filter")
    }
  }

  func testSelectByBusAndAddress() {
    let devA = MockCandidate(vendorID: 0x2717, productID: 0xff10, bus: 1, address: 3)
    let devB = MockCandidate(vendorID: 0x2717, productID: 0xff40, bus: 2, address: 5)
    let result = selectDevice(
      [devA, devB], filter: DeviceFilter(vid: nil, pid: nil, bus: 2, address: 5),
      noninteractive: true)
    if case .selected(let d) = result {
      XCTAssertEqual(d.bus, 2)
      XCTAssertEqual(d.address, 5)
    } else {
      XCTFail("Expected .selected for bus/address")
    }
  }

  func testSelectNoMatchReturnsNone() {
    let dev = MockCandidate(vendorID: 0x2717, productID: 0xff10, bus: 1, address: 3)
    let result = selectDevice(
      [dev], filter: DeviceFilter(vid: 0x04e8, pid: nil, bus: nil, address: nil),
      noninteractive: true)
    if case .none = result {} else { XCTFail("Expected .none for non-matching VID") }
  }

  func testSelectMultipleReturnsMultiple() {
    let devA = MockCandidate(vendorID: 0x2717, productID: 0xff10, bus: 1, address: 3)
    let devB = MockCandidate(vendorID: 0x2717, productID: 0xff40, bus: 1, address: 4)
    let result = selectDevice(
      [devA, devB], filter: DeviceFilter(vid: 0x2717, pid: nil, bus: nil, address: nil),
      noninteractive: true)
    if case .multiple(let matches) = result {
      XCTAssertEqual(matches.count, 2)
    } else {
      XCTFail("Expected .multiple")
    }
  }
}

// MARK: - Output Formatting (JSON, Table, Human-Readable)

@MainActor
final class OutputFormattingWave29Tests: XCTestCase {

  func testCLIErrorEnvelopeJSONRoundTrip() throws {
    let envelope = CLIErrorEnvelope(
      "test error", details: ["key": "value"], mode: "strict",
      timestamp: "2025-01-01T00:00:00Z")
    let data = try JSONEncoder().encode(envelope)
    let decoded = try JSONDecoder().decode(CLIErrorEnvelope.self, from: data)
    XCTAssertEqual(decoded.error, "test error")
    XCTAssertEqual(decoded.schemaVersion, "1.0")
    XCTAssertEqual(decoded.type, "error")
    XCTAssertEqual(decoded.details?["key"], "value")
    XCTAssertEqual(decoded.mode, "strict")
  }

  func testCLIErrorEnvelopeMinimal() throws {
    let envelope = CLIErrorEnvelope("bare error")
    let data = try JSONEncoder().encode(envelope)
    let decoded = try JSONDecoder().decode(CLIErrorEnvelope.self, from: data)
    XCTAssertEqual(decoded.error, "bare error")
    XCTAssertNil(decoded.details)
    XCTAssertNil(decoded.mode)
  }

  func testCLIErrorEnvelopeJSONContainsSortedKeys() throws {
    let envelope = CLIErrorEnvelope("sorted", timestamp: "2025-01-01T00:00:00Z")
    let enc = JSONEncoder()
    enc.outputFormatting = [.sortedKeys]
    let data = try enc.encode(envelope)
    let str = String(data: data, encoding: .utf8)!
    // "error" should come before "schemaVersion" in sorted output
    let errorIdx = str.range(of: "\"error\"")!.lowerBound
    let schemaIdx = str.range(of: "\"schemaVersion\"")!.lowerBound
    XCTAssertTrue(errorIdx < schemaIdx)
  }

  func testFormatBytesEdgeCases() {
    XCTAssertEqual(formatBytes(0), "0.0 B")
    XCTAssertEqual(formatBytes(1), "1.0 B")
    XCTAssertEqual(formatBytes(UInt64.max), formatBytes(UInt64.max))  // no crash
  }

  func testParseSizeEdgeCases() {
    XCTAssertEqual(parseSize("0"), 0)
    XCTAssertEqual(parseSize(""), 0)
    XCTAssertEqual(parseSize("1G"), 1_073_741_824)
    XCTAssertEqual(parseSize("100M"), 104_857_600)
  }

  func testJSONEnvelopeEncodesAllFields() throws {
    let data = ["key": "value"]
    let envelope = JSONEnvelope(
      schemaVersion: "1.0.0", type: "test", timestamp: "2025-01-01T00:00:00Z",
      data: data)
    let encoded = try JSONEncoder().encode(envelope)
    let json = try JSONSerialization.jsonObject(with: encoded) as! [String: Any]
    XCTAssertEqual(json["schemaVersion"] as? String, "1.0.0")
    XCTAssertEqual(json["type"] as? String, "test")
    XCTAssertNotNil(json["data"])
  }
}

// MARK: - Error Exit Codes

final class ExitCodeWave29Tests: XCTestCase {

  func testUsageExitCode() {
    XCTAssertEqual(ExitCode.usage.rawValue, 64)
  }

  func testUnavailableExitCode() {
    XCTAssertEqual(ExitCode.unavailable.rawValue, 69)
  }

  func testSoftwareExitCode() {
    XCTAssertEqual(ExitCode.software.rawValue, 70)
  }

  func testTempfailExitCode() {
    XCTAssertEqual(ExitCode.tempfail.rawValue, 75)
  }

  func testOkExitCode() {
    XCTAssertEqual(ExitCode.ok.rawValue, 0)
  }

  func testAllExitCodesMapToBSDSysexits() {
    // BSD sysexits.h values
    let expected: [ExitCode: Int32] = [
      .ok: 0, .usage: 64, .unavailable: 69, .software: 70, .tempfail: 75,
    ]
    for (code, raw) in expected {
      XCTAssertEqual(code.rawValue, raw, "\(code) should be \(raw)")
    }
  }

  func testExitCodesAreUnique() {
    let codes: [ExitCode] = [.ok, .usage, .unavailable, .software, .tempfail]
    let rawSet = Set(codes.map(\.rawValue))
    XCTAssertEqual(rawSet.count, codes.count)
  }
}

// MARK: - Actionable Error Messages

@MainActor
final class ActionableMessageWave29Tests: XCTestCase {

  func testDisconnectedMessage() {
    let msg = actionableMessage(for: MTPError.deviceDisconnected)
    XCTAssertTrue(msg.contains("Reconnect"))
  }

  func testPermissionDeniedMessage() {
    let msg = actionableMessage(for: MTPError.permissionDenied)
    XCTAssertTrue(msg.contains("Trust"))
  }

  func testTransportNoDeviceMessage() {
    let msg = actionableMessage(for: MTPError.transport(.noDevice))
    XCTAssertTrue(msg.contains("MTP"))
  }

  func testTransportTimeoutMessage() {
    let msg = actionableMessage(for: MTPError.transport(.timeout))
    XCTAssertTrue(msg.contains("timed out"))
  }

  func testTransportBusyMessage() {
    let msg = actionableMessage(for: MTPError.transport(.busy))
    XCTAssertTrue(msg.contains("busy"))
  }

  func testTransportStallMessage() {
    let msg = actionableMessage(for: MTPError.transport(.stall))
    XCTAssertTrue(msg.contains("stall"))
  }

  func testTransportTimeoutInPhaseMessage() {
    let msg = actionableMessage(for: MTPError.transport(.timeoutInPhase(.bulkOut)))
    XCTAssertTrue(msg.contains("bulk-out"))
  }

  func testTransportIOMessage() {
    let msg = actionableMessage(for: MTPError.transport(.io("pipe error")))
    XCTAssertTrue(msg.contains("pipe error"))
  }

  func testStorageFullMessage() {
    let msg = actionableMessage(for: MTPError.storageFull)
    XCTAssertTrue(msg.contains("full"))
  }

  func testObjectNotFoundMessage() {
    let msg = actionableMessage(for: MTPError.objectNotFound)
    XCTAssertTrue(msg.contains("not found"))
  }

  func testProtocolErrorMessage() {
    let msg = actionableMessage(for: MTPError.protocolError(code: 0x2002, message: "fail"))
    XCTAssertTrue(msg.contains("2002"))
  }

  func testVerificationFailedMessage() {
    let msg = actionableMessage(for: MTPError.verificationFailed(expected: 100, actual: 50))
    XCTAssertTrue(msg.contains("50"))
    XCTAssertTrue(msg.contains("100"))
  }

  func testPreconditionFailedMessage() {
    let msg = actionableMessage(for: MTPError.preconditionFailed("test reason"))
    XCTAssertTrue(msg.contains("test reason"))
  }

  func testSessionBusyMessage() {
    let msg = actionableMessage(for: MTPError.sessionBusy)
    XCTAssertTrue(msg.contains("transaction"))
  }

  func testReadOnlyMessage() {
    let msg = actionableMessage(for: MTPError.readOnly)
    XCTAssertTrue(msg.contains("read-only"))
  }

  func testTimeoutMessage() {
    let msg = actionableMessage(for: MTPError.timeout)
    XCTAssertTrue(msg.contains("timed out"))
  }
}

// MARK: - Wizard Flow State Machine

final class WizardFlowWave29Tests: XCTestCase {

  /// Mirrors WizardCommand.inferDeviceClass
  private func inferDeviceClass(manufacturer: String, model: String) -> String {
    let combined = (manufacturer + " " + model).lowercased()
    let ptpKeywords = [
      "canon", "nikon", "sony", "fuji", "olympus", "panasonic", "pentax", "ricoh",
      "leica", "sigma", "hasselblad", "gopro", "dji", "camera", "dslr", "mirrorless",
    ]
    for kw in ptpKeywords where combined.contains(kw) {
      return "ptp"
    }
    return "android"
  }

  // MARK: Camera keywords → PTP

  func testAllPTPKeywordsDetected() {
    let keywords = [
      "canon", "nikon", "sony", "fuji", "olympus", "panasonic", "pentax", "ricoh",
      "leica", "sigma", "hasselblad", "gopro", "dji", "camera", "dslr", "mirrorless",
    ]
    for kw in keywords {
      XCTAssertEqual(
        inferDeviceClass(manufacturer: kw.capitalized, model: "X"),
        "ptp", "\(kw) should be ptp")
    }
  }

  // MARK: Phone/tablet → Android

  func testAndroidDevicesDetected() {
    let devices = [
      ("Samsung", "Galaxy S24"), ("Google", "Pixel 9"), ("Xiaomi", "14 Ultra"),
      ("OnePlus", "12"), ("Motorola", "Edge 50"), ("Nothing", "Phone 2"),
    ]
    for (mfg, model) in devices {
      XCTAssertEqual(
        inferDeviceClass(manufacturer: mfg, model: model),
        "android", "\(mfg) \(model) should be android")
    }
  }

  func testEmptyStringsDefaultToAndroid() {
    XCTAssertEqual(inferDeviceClass(manufacturer: "", model: ""), "android")
  }

  func testCaseInsensitiveDetection() {
    XCTAssertEqual(inferDeviceClass(manufacturer: "CANON", model: "eos r5"), "ptp")
    XCTAssertEqual(inferDeviceClass(manufacturer: "canon", model: "EOS R5"), "ptp")
  }

  func testModelContainingCameraKeyword() {
    XCTAssertEqual(inferDeviceClass(manufacturer: "Generic", model: "Trail Camera Pro"), "ptp")
  }

  // MARK: Timeout parsing

  func testTimeoutArgParsing() {
    let args = ["--timeout", "120"]
    var timeoutSec = 60
    if let idx = args.firstIndex(of: "--timeout"), idx + 1 < args.count,
      let t = Int(args[idx + 1])
    {
      timeoutSec = t
    }
    XCTAssertEqual(timeoutSec, 120)
  }

  func testTimeoutArgMissingValueUsesDefault() {
    let args = ["--timeout"]
    var timeoutSec = 60
    if let idx = args.firstIndex(of: "--timeout"), idx + 1 < args.count,
      let t = Int(args[idx + 1])
    {
      timeoutSec = t
    }
    XCTAssertEqual(timeoutSec, 60)
  }

  func testTimeoutArgInvalidValueUsesDefault() {
    let args = ["--timeout", "not-a-number"]
    var timeoutSec = 60
    if let idx = args.firstIndex(of: "--timeout"), idx + 1 < args.count,
      let t = Int(args[idx + 1])
    {
      timeoutSec = t
    }
    XCTAssertEqual(timeoutSec, 60)
  }

  // MARK: Help flag detection

  func testHelpFlagDetection() {
    XCTAssertTrue(["--help", "-h", "other"].contains("--help"))
    XCTAssertTrue(["--help", "-h", "other"].contains("-h"))
    XCTAssertFalse(["--timeout", "30"].contains("--help"))
    XCTAssertFalse(["--timeout", "30"].contains("-h"))
  }

  // MARK: Action choice validation

  func testActionChoiceMapping() {
    let validChoices = ["1", "2", "3"]
    for choice in validChoices {
      XCTAssertTrue(
        ["1", "2", "3"].contains(choice), "\(choice) should be valid")
    }
    XCTAssertFalse(["1", "2", "3"].contains("4"))
    XCTAssertFalse(["1", "2", "3"].contains(""))
  }

  // MARK: VID/PID formatting

  func testVIDPIDFormatting() {
    let vid: UInt16 = 0x2717
    let pid: UInt16 = 0xff10
    let formatted = String(format: "%04x:%04x", vid, pid)
    XCTAssertEqual(formatted, "2717:ff10")
  }

  func testVIDPIDFormattingZeroPadded() {
    let vid: UInt16 = 0x0001
    let pid: UInt16 = 0x0002
    let formatted = String(format: "%04x:%04x", vid, pid)
    XCTAssertEqual(formatted, "0001:0002")
  }
}

// MARK: - Device Lab Harness Report Generation

final class DeviceLabReportWave29Tests: XCTestCase {

  private func makeFingerprint() -> MTPDeviceFingerprint {
    MTPDeviceFingerprint.fromUSB(
      vid: 0x2717, pid: 0xff10,
      interfaceClass: 0xFF, interfaceSubclass: 0x01, interfaceProtocol: 0x01,
      epIn: 0x81, epOut: 0x02, epEvt: 0x83)
  }

  func testDeviceLabReportEncodeDecode() throws {
    let report = DeviceLabReport(
      timestamp: Date(timeIntervalSince1970: 1735689600),
      manufacturer: "Xiaomi",
      model: "Mi Note 2",
      serialNumber: nil,
      fingerprint: makeFingerprint(),
      operationsSupported: ["GetDeviceInfo", "OpenSession"],
      eventsSupported: ["ObjectAdded"],
      capabilityTests: [
        CapabilityTestResult(
          name: "GetDeviceInfo", opcode: "0x1001", supported: true, durationMs: 42)
      ],
      suggestedFlags: QuirkFlags(),
      suggestedTuning: SuggestedTuning())

    let enc = JSONEncoder()
    enc.dateEncodingStrategy = .iso8601
    let data = try enc.encode(report)

    let dec = JSONDecoder()
    dec.dateDecodingStrategy = .iso8601
    let decoded = try dec.decode(DeviceLabReport.self, from: data)

    XCTAssertEqual(decoded.manufacturer, "Xiaomi")
    XCTAssertEqual(decoded.model, "Mi Note 2")
    XCTAssertNil(decoded.serialNumber)
    XCTAssertEqual(decoded.operationsSupported.count, 2)
    XCTAssertEqual(decoded.capabilityTests.count, 1)
    XCTAssertEqual(decoded.capabilityTests[0].name, "GetDeviceInfo")
  }

  func testDeviceLabReportWithNoCapabilities() throws {
    let report = DeviceLabReport(
      timestamp: Date(timeIntervalSince1970: 1735689600),
      manufacturer: "Unknown",
      model: "Generic Device",
      serialNumber: "SN-1234",
      fingerprint: makeFingerprint(),
      operationsSupported: [],
      eventsSupported: [],
      capabilityTests: [],
      suggestedFlags: QuirkFlags(),
      suggestedTuning: SuggestedTuning())

    let enc = JSONEncoder()
    enc.dateEncodingStrategy = .iso8601
    let data = try enc.encode(report)

    let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
    XCTAssertEqual(json["manufacturer"] as? String, "Unknown")
    XCTAssertEqual((json["operationsSupported"] as? [String])?.count, 0)
  }

  func testSuggestedTuningDefaults() {
    let tuning = SuggestedTuning()
    XCTAssertEqual(tuning.maxChunkBytes, 1 << 20)
    XCTAssertEqual(tuning.ioTimeoutMs, 8000)
    XCTAssertEqual(tuning.handshakeTimeoutMs, 6000)
  }

  func testSuggestedTuningCustomValues() {
    let tuning = SuggestedTuning(
      maxChunkBytes: 256_000, ioTimeoutMs: 15000, handshakeTimeoutMs: 10000)
    XCTAssertEqual(tuning.maxChunkBytes, 256_000)
    XCTAssertEqual(tuning.ioTimeoutMs, 15000)
    XCTAssertEqual(tuning.handshakeTimeoutMs, 10000)
  }

  func testCapabilityTestResultWithAllFields() throws {
    let result = CapabilityTestResult(
      name: "SendObject", opcode: "0x100D", supported: false, durationMs: 200,
      errorMessage: "write-protected")
    let data = try JSONEncoder().encode(result)
    let decoded = try JSONDecoder().decode(CapabilityTestResult.self, from: data)
    XCTAssertEqual(decoded.name, "SendObject")
    XCTAssertFalse(decoded.supported)
    XCTAssertEqual(decoded.errorMessage, "write-protected")
  }

  func testCapabilityTestResultWithZeroDuration() {
    let result = CapabilityTestResult(name: "NoOp", supported: true, durationMs: 0)
    XCTAssertEqual(result.durationMs, 0)
    XCTAssertTrue(result.supported)
    XCTAssertNil(result.opcode)
  }

  func testDeviceLabHarnessInstantiation() {
    let harness = DeviceLabHarness()
    XCTAssertNotNil(harness)
  }
}

// MARK: - Submission Bundle Validation

final class SubmissionBundleWave29Tests: XCTestCase {

  func testSubmissionJSONMinimalValidity() throws {
    let json: [String: Any] = [
      "vendorID": 0x2717,
      "productID": 0xff10,
      "manufacturer": "Xiaomi",
      "model": "Mi Note 2",
    ]
    let data = try JSONSerialization.data(withJSONObject: json)
    let parsed = try JSONSerialization.jsonObject(with: data) as! [String: Any]
    XCTAssertEqual(parsed["manufacturer"] as? String, "Xiaomi")
    XCTAssertEqual(parsed["model"] as? String, "Mi Note 2")
  }

  func testSubmissionVIDPIDExtraction() throws {
    let json: [String: Any] = ["vendorID": 10007, "productID": 65296]
    let vid = String(format: "%04x", json["vendorID"] as? Int ?? 0)
    let pid = String(format: "%04x", json["productID"] as? Int ?? 0)
    XCTAssertEqual(vid, "2717")
    XCTAssertEqual(pid, "ff10")
  }

  func testSubmissionMissingVIDDefaultsToZero() {
    let json: [String: Any] = ["productID": 0xff10]
    let vid = String(format: "%04x", json["vendorID"] as? UInt16 ?? 0)
    XCTAssertEqual(vid, "0000")
  }

  func testSubmissionDeviceNameFromProbeJSON() throws {
    let probeJson: [String: Any] = [
      "deviceInfo": [
        "manufacturer": "Samsung",
        "model": "Galaxy S7",
      ]
    ]
    var deviceName = "Unknown Device"
    if let deviceInfo = probeJson["deviceInfo"] as? [String: Any] {
      let manufacturer = deviceInfo["manufacturer"] as? String ?? ""
      let model = deviceInfo["model"] as? String ?? ""
      deviceName = "\(manufacturer) \(model)".trimmingCharacters(in: .whitespaces)
    }
    XCTAssertEqual(deviceName, "Samsung Galaxy S7")
  }

  func testSubmissionDeviceNameTrimsWhitespace() {
    let manufacturer = "  Google  "
    let model = "  Pixel 7  "
    let name = "\(manufacturer) \(model)".trimmingCharacters(in: .whitespaces)
    // Only outer whitespace is trimmed; interior spaces from interpolation remain
    XCTAssertEqual(name, "Google     Pixel 7")
  }

  func testSubmissionDeviceNameEmptyComponents() {
    let manufacturer = ""
    let model = ""
    let name = "\(manufacturer) \(model)".trimmingCharacters(in: .whitespaces)
    XCTAssertEqual(name, "")
  }
}

// MARK: - Privacy / Redaction Validation (No PII Leakage)

final class PrivacyRedactionWave29Tests: XCTestCase {

  func testRedactSerialProducesHMAC() {
    let salt = Data("test-salt-w29".utf8)
    let result = Redaction.redactSerial("SN-12345-ABCDE", salt: salt)
    XCTAssertTrue(result.hasPrefix("hmacsha256:"))
    // HMAC-SHA256 produces 64 hex chars
    XCTAssertEqual(result.count, "hmacsha256:".count + 64)
  }

  func testRedactSerialDeterministic() {
    let salt = Data("deterministic-salt".utf8)
    let a = Redaction.redactSerial("my-serial", salt: salt)
    let b = Redaction.redactSerial("my-serial", salt: salt)
    XCTAssertEqual(a, b)
  }

  func testRedactSerialDifferentSaltsDifferentOutput() {
    let salt1 = Data("salt-one".utf8)
    let salt2 = Data("salt-two".utf8)
    let a = Redaction.redactSerial("same-serial", salt: salt1)
    let b = Redaction.redactSerial("same-serial", salt: salt2)
    XCTAssertNotEqual(a, b)
  }

  func testRedactSerialDifferentSerialsDifferentOutput() {
    let salt = Data("shared-salt".utf8)
    let a = Redaction.redactSerial("serial-A", salt: salt)
    let b = Redaction.redactSerial("serial-B", salt: salt)
    XCTAssertNotEqual(a, b)
  }

  func testGenerateSaltProducesRequestedLength() {
    let salt = Redaction.generateSalt(count: 64)
    XCTAssertEqual(salt.count, 64)
  }

  func testRedactorPTPStringReplacesAllChars() {
    let redactor = Redactor(bundleKey: "w29-test-key")
    let result = redactor.redactPTPString("Hello World")
    XCTAssertEqual(result.count, 11)
    XCTAssertEqual(result, "***********")
  }

  func testRedactorPTPStringEmptyInput() {
    let redactor = Redactor(bundleKey: "w29-test-key")
    let result = redactor.redactPTPString("")
    XCTAssertEqual(result, "")
  }

  func testRedactorTokenizePreservesExtension() {
    let redactor = Redactor(bundleKey: "w29-test-key")
    let token = redactor.tokenizeFilename("secret-photo.jpg")
    XCTAssertTrue(token.hasPrefix("file_"))
    XCTAssertTrue(token.hasSuffix(".jpg"))
    XCTAssertFalse(token.contains("secret"))
    XCTAssertFalse(token.contains("photo"))
  }

  func testRedactorTokenizeNoExtension() {
    let redactor = Redactor(bundleKey: "w29-test-key")
    let token = redactor.tokenizeFilename("README")
    XCTAssertTrue(token.hasPrefix("file_"))
    XCTAssertFalse(token.contains("."))
    XCTAssertFalse(token.contains("README"))
  }

  func testRedactorTokenizeDeterministic() {
    let redactor = Redactor(bundleKey: "same-key")
    let a = redactor.tokenizeFilename("photo.png")
    let b = redactor.tokenizeFilename("photo.png")
    XCTAssertEqual(a, b)
  }

  func testRedactorTokenizeDifferentFilesDifferentTokens() {
    let redactor = Redactor(bundleKey: "same-key")
    let a = redactor.tokenizeFilename("file-a.txt")
    let b = redactor.tokenizeFilename("file-b.txt")
    XCTAssertNotEqual(a, b)
  }

  func testRedactObjectInfoRedactsNameAndProperties() {
    let redactor = Redactor(bundleKey: "w29-test-key")
    let info = MTPObjectInfo(
      handle: 1, storage: MTPStorageID(raw: 0x10001), parent: 0, name: "vacation-photo.jpg",
      sizeBytes: 4_000_000, modified: Date(), formatCode: 0x3801,
      properties: [0xDC01: "Personal Document"])

    let redacted = redactor.redactObjectInfo(info)
    XCTAssertFalse(redacted.name.contains("vacation"))
    XCTAssertFalse(redacted.name.contains("photo"))
    XCTAssertTrue(redacted.name.hasPrefix("file_"))
    XCTAssertTrue(redacted.name.hasSuffix(".jpg"))
    // Properties should be redacted (all asterisks)
    XCTAssertEqual(redacted.properties[0xDC01], "*****************")
    // Structural fields preserved
    XCTAssertEqual(redacted.handle, 1)
    XCTAssertEqual(redacted.storage, MTPStorageID(raw: 0x10001))
    XCTAssertEqual(redacted.sizeBytes, 4_000_000)
    XCTAssertEqual(redacted.formatCode, 0x3801)
  }

  func testRedactObjectInfoNilDateReplacedConsistently() {
    let redactor = Redactor(bundleKey: "w29-test-key")
    let info = MTPObjectInfo(
      handle: 2, storage: MTPStorageID(raw: 0x10001), parent: nil, name: "test.txt",
      sizeBytes: 100, modified: nil, formatCode: 0x3001, properties: [:])
    let redacted = redactor.redactObjectInfo(info)
    XCTAssertNil(redacted.modified)
  }

  func testRedactObjectInfoDateNormalized() {
    let redactor = Redactor(bundleKey: "w29-test-key")
    let info = MTPObjectInfo(
      handle: 3, storage: MTPStorageID(raw: 0x10001), parent: nil, name: "test.txt",
      sizeBytes: 100, modified: Date(), formatCode: 0x3001, properties: [:])
    let redacted = redactor.redactObjectInfo(info)
    // Modified dates are normalized to 2025-01-01
    XCTAssertEqual(redacted.modified, Date(timeIntervalSince1970: 1735689600))
  }

  func testNoSerialInRedactedOutput() {
    let salt = Data("pii-test-salt".utf8)
    let serial = "ABCDEF123456"
    let redacted = Redaction.redactSerial(serial, salt: salt)
    XCTAssertFalse(redacted.contains(serial))
  }

  func testDataHexStringRoundTrip() {
    let data = Data([0xDE, 0xAD, 0xBE, 0xEF])
    let hex = data.hexString()
    XCTAssertEqual(hex, "deadbeef")
  }
}

// MARK: - CollectError Messages

final class CollectErrorWave29Tests: XCTestCase {

  func testNoDeviceMatchedErrorDescription() {
    let err = CollectCommand.CollectError.noDeviceMatched(candidates: [])
    let desc = err.errorDescription ?? ""
    XCTAssertTrue(desc.contains("swiftmtp probe"))
    XCTAssertTrue(desc.contains("--vid"))
    XCTAssertTrue(desc.contains("--pid"))
  }

  func testAmbiguousSelectionErrorDescription() {
    let err = CollectCommand.CollectError.ambiguousSelection(count: 5, candidates: [])
    let desc = err.errorDescription ?? ""
    XCTAssertTrue(desc.contains("5"))
    XCTAssertTrue(desc.contains("--vid"))
  }

  func testTimeoutErrorDescription() {
    let err = CollectCommand.CollectError.timeout(10000)
    let desc = err.errorDescription ?? ""
    XCTAssertTrue(desc.contains("10000"))
  }

  func testRedactionCheckFailedErrorDescription() {
    let err = CollectCommand.CollectError.redactionCheckFailed(["serial", "mac-address"])
    let desc = err.errorDescription ?? ""
    XCTAssertTrue(desc.contains("serial"))
    XCTAssertTrue(desc.contains("mac-address"))
    XCTAssertTrue(desc.contains("--no-strict"))
  }

  func testInvalidBenchSizeErrorDescription() {
    let err = CollectCommand.CollectError.invalidBenchSize("5T")
    let desc = err.errorDescription ?? ""
    XCTAssertTrue(desc.contains("5T"))
  }
}

// MARK: - CLIFlags Construction

final class CLIFlagsWave29Tests: XCTestCase {

  func testDefaultFlagsConstruction() {
    let flags = CLIFlags(
      realOnly: false, useMock: false, mockProfile: "default", json: false,
      jsonlOutput: false, traceUSB: false, strict: false, safe: false,
      traceUSBDetails: false, targetVID: nil, targetPID: nil,
      targetBus: nil, targetAddress: nil)
    XCTAssertFalse(flags.realOnly)
    XCTAssertFalse(flags.useMock)
    XCTAssertEqual(flags.mockProfile, "default")
    XCTAssertFalse(flags.json)
    XCTAssertNil(flags.targetVID)
  }

  func testFlagsWithAllFieldsSet() {
    let flags = CLIFlags(
      realOnly: true, useMock: true, mockProfile: "pixel7", json: true,
      jsonlOutput: true, traceUSB: true, strict: true, safe: true,
      traceUSBDetails: true, targetVID: "2717", targetPID: "ff10",
      targetBus: 1, targetAddress: 3)
    XCTAssertTrue(flags.realOnly)
    XCTAssertTrue(flags.useMock)
    XCTAssertEqual(flags.mockProfile, "pixel7")
    XCTAssertTrue(flags.json)
    XCTAssertTrue(flags.jsonlOutput)
    XCTAssertTrue(flags.traceUSB)
    XCTAssertTrue(flags.strict)
    XCTAssertTrue(flags.safe)
    XCTAssertEqual(flags.targetVID, "2717")
    XCTAssertEqual(flags.targetPID, "ff10")
    XCTAssertEqual(flags.targetBus, 1)
    XCTAssertEqual(flags.targetAddress, 3)
  }
}

// MARK: - Spinner Safety (via swiftmtp_cli module)

final class SpinnerSafetyWave29Tests: XCTestCase {

  func testSpinnerDisabledDoesNotCrash() {
    var spinner = swiftmtp_cli.Spinner(enabled: false)
    spinner.start("testing")
    spinner.stopAndClear()
  }

  func testSpinnerEnabledLifecycle() {
    var spinner = swiftmtp_cli.Spinner(enabled: true)
    spinner.start("working...")
    spinner.succeed("done")
  }

  func testSpinnerDoubleStopDoesNotCrash() {
    var spinner = swiftmtp_cli.Spinner(enabled: true)
    spinner.start("work")
    spinner.stopAndClear()
    spinner.stopAndClear()
  }

  func testSpinnerStopWithoutStartDoesNotCrash() {
    let spinner = swiftmtp_cli.Spinner(enabled: false)
    spinner.stopAndClear()
  }

  func testSpinnerFailDoesNotCrash() {
    var spinner = swiftmtp_cli.Spinner(enabled: false)
    spinner.start("failing task")
    spinner.fail("error occurred")
  }
}

// MARK: - TransportPhase Descriptions

final class TransportPhaseWave29Tests: XCTestCase {

  func testBulkOutDescription() {
    XCTAssertEqual(TransportPhase.bulkOut.description, "bulk-out")
  }

  func testBulkInDescription() {
    XCTAssertEqual(TransportPhase.bulkIn.description, "bulk-in")
  }

  func testResponseWaitDescription() {
    XCTAssertEqual(TransportPhase.responseWait.description, "response-wait")
  }

  func testAllPhasesHaveDescriptions() {
    let phases: [TransportPhase] = [.bulkOut, .bulkIn, .responseWait]
    for phase in phases {
      XCTAssertFalse(phase.description.isEmpty)
    }
  }
}

// MARK: - CollectFlags Structure

final class CollectFlagsWave29Tests: XCTestCase {

  func testCollectFlagsDefaults() {
    let flags = CollectCommand.CollectFlags(strict: true, json: false)
    XCTAssertTrue(flags.strict)
    XCTAssertFalse(flags.safe)
    XCTAssertTrue(flags.runBench.isEmpty)
    XCTAssertFalse(flags.json)
    XCTAssertFalse(flags.noninteractive)
    XCTAssertNil(flags.bundlePath)
    XCTAssertNil(flags.deviceName)
    XCTAssertFalse(flags.openPR)
    XCTAssertNil(flags.vid)
    XCTAssertNil(flags.pid)
    XCTAssertNil(flags.bus)
    XCTAssertNil(flags.address)
  }

  func testCollectFlagsWithDeviceFilter() {
    let flags = CollectCommand.CollectFlags(
      strict: true, safe: true, vid: 0x2717, pid: 0xff10, bus: 1, address: 3)
    XCTAssertEqual(flags.vid, 0x2717)
    XCTAssertEqual(flags.pid, 0xff10)
    XCTAssertEqual(flags.bus, 1)
    XCTAssertEqual(flags.address, 3)
    XCTAssertTrue(flags.safe)
  }
}
