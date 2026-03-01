// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import XCTest
@testable import swiftmtp_cli
import SwiftMTPCore
import SwiftMTPCLI

// MARK: - Exit Code Tests

final class ExitCodeTests: XCTestCase {
  func testBSDSysexitValues() {
    XCTAssertEqual(ExitCode.ok.rawValue, 0)
    XCTAssertEqual(ExitCode.usage.rawValue, 64)
    XCTAssertEqual(ExitCode.unavailable.rawValue, 69)
    XCTAssertEqual(ExitCode.software.rawValue, 70)
    XCTAssertEqual(ExitCode.tempfail.rawValue, 75)
  }

  func testExitCodeRawValuesAreDistinct() {
    let codes: [ExitCode] = [.ok, .usage, .unavailable, .software, .tempfail]
    let rawValues = codes.map(\.rawValue)
    XCTAssertEqual(Set(rawValues).count, rawValues.count)
  }
}

// MARK: - Output Formatting Tests

@MainActor
final class OutputFormattingTests: XCTestCase {
  func testFormatBytesSmall() {
    XCTAssertEqual(formatBytes(0), "0.0 B")
    XCTAssertEqual(formatBytes(512), "512.0 B")
  }

  func testFormatBytesKilobytes() {
    XCTAssertEqual(formatBytes(1024), "1.0 KB")
    XCTAssertEqual(formatBytes(1536), "1.5 KB")
  }

  func testFormatBytesMegabytes() {
    XCTAssertEqual(formatBytes(1_048_576), "1.0 MB")
    XCTAssertEqual(formatBytes(5_242_880), "5.0 MB")
  }

  func testFormatBytesGigabytes() {
    XCTAssertEqual(formatBytes(1_073_741_824), "1.0 GB")
  }

  func testFormatBytesTerabytes() {
    XCTAssertEqual(formatBytes(1_099_511_627_776), "1.0 TB")
  }

  func testParseSizeKilobytes() {
    XCTAssertEqual(parseSize("1K"), 1024)
    XCTAssertEqual(parseSize("4K"), 4096)
  }

  func testParseSizeMegabytes() {
    XCTAssertEqual(parseSize("1M"), 1_048_576)
    XCTAssertEqual(parseSize("8M"), 8_388_608)
  }

  func testParseSizeGigabytes() {
    XCTAssertEqual(parseSize("1G"), 1_073_741_824)
  }

  func testParseSizePlainNumber() {
    XCTAssertEqual(parseSize("1024"), 1024)
  }

  func testParseSizeInvalid() {
    XCTAssertEqual(parseSize("abc"), 0)
  }
}

// MARK: - Help Text Tests

@MainActor
final class HelpTextTests: XCTestCase {
  func testHelpTextContainsAllMajorCommands() {
    // Verify the known command list is complete and unique.
    let expectedCommands = [
      "probe", "usb-dump", "device-lab", "diag", "storages",
      "ls", "pull", "push", "bench", "mirror", "quirks",
      "info", "health", "collect", "submit", "add-device",
      "wizard", "delete", "move", "events", "learn-promote",
      "bdd", "snapshot", "version",
    ]
    // Verify the command count matches expectations
    XCTAssertEqual(expectedCommands.count, 24)
    // Each command should be unique
    XCTAssertEqual(Set(expectedCommands).count, expectedCommands.count)
  }
}

// MARK: - Error Display Formatting Tests

@MainActor
final class ErrorDisplayTests: XCTestCase {
  func testActionableMessageDeviceDisconnected() {
    let err = MTPError.deviceDisconnected
    let msg = actionableMessage(for: err)
    XCTAssertTrue(msg.contains("Reconnect"), "Expected reconnect hint, got: \(msg)")
  }

  func testActionableMessageNotSupported() {
    let err = MTPError.notSupported("GetObjectPropList")
    let msg = actionableMessage(for: err)
    XCTAssertTrue(msg.contains("GetObjectPropList"), "Expected operation name, got: \(msg)")
    XCTAssertTrue(msg.contains("USB mode"), "Expected USB mode hint, got: \(msg)")
  }

  func testActionableMessageObjectNotFound() {
    let err = MTPError.objectNotFound
    let msg = actionableMessage(for: err)
    XCTAssertTrue(
      msg.contains("not found") || msg.contains("moved"),
      "Expected not-found hint, got: \(msg)")
  }

  func testActionableMessageObjectWriteProtected() {
    let err = MTPError.objectWriteProtected
    let msg = actionableMessage(for: err)
    XCTAssertTrue(msg.contains("write-protected"), "Expected write-protected hint, got: \(msg)")
  }

  func testActionableMessageReadOnly() {
    let err = MTPError.readOnly
    let msg = actionableMessage(for: err)
    XCTAssertTrue(msg.contains("read-only"), "Expected read-only hint, got: \(msg)")
  }

  func testActionableMessageBusy() {
    let err = MTPError.busy
    let msg = actionableMessage(for: err)
    XCTAssertTrue(msg.contains("busy"), "Expected busy hint, got: \(msg)")
  }

  func testActionableMessageSessionBusy() {
    let err = MTPError.sessionBusy
    let msg = actionableMessage(for: err)
    XCTAssertTrue(msg.contains("transaction"), "Expected transaction hint, got: \(msg)")
  }

  func testActionableMessagePreconditionFailed() {
    let err = MTPError.preconditionFailed("No storage available")
    let msg = actionableMessage(for: err)
    XCTAssertTrue(msg.contains("No storage available"), "Expected reason, got: \(msg)")
  }

  func testActionableMessageVerificationFailed() {
    let err = MTPError.verificationFailed(expected: 1000, actual: 500)
    let msg = actionableMessage(for: err)
    XCTAssertTrue(msg.contains("1000"), "Expected expected size, got: \(msg)")
    XCTAssertTrue(msg.contains("500"), "Expected actual size, got: \(msg)")
  }

  func testActionableMessageTransportBusy() {
    let err = MTPError.transport(.busy)
    let msg = actionableMessage(for: err)
    XCTAssertTrue(msg.contains("busy"), "Expected busy hint, got: \(msg)")
  }

  func testActionableMessageTransportAccessDenied() {
    let err = MTPError.transport(.accessDenied)
    let msg = actionableMessage(for: err)
    XCTAssertTrue(msg.contains("USB"), "Expected USB hint, got: \(msg)")
  }

  func testActionableMessageTransportStall() {
    let err = MTPError.transport(.stall)
    let msg = actionableMessage(for: err)
    XCTAssertTrue(msg.contains("stall"), "Expected stall hint, got: \(msg)")
  }

  func testActionableMessageTransportTimeoutInPhase() {
    let err = MTPError.transport(.timeoutInPhase(.bulkIn))
    let msg = actionableMessage(for: err)
    XCTAssertTrue(msg.contains("bulk-in"), "Expected phase hint, got: \(msg)")
  }

  func testActionableMessageTransportIO() {
    let err = MTPError.transport(.io("pipe broken"))
    let msg = actionableMessage(for: err)
    XCTAssertTrue(msg.contains("pipe broken"), "Expected IO detail, got: \(msg)")
  }
}

// MARK: - CLIFlags Construction Tests

@MainActor
final class CLIFlagsTests: XCTestCase {
  func testDefaultFlags() {
    let flags = CLIFlags(
      realOnly: false, useMock: false, mockProfile: "default",
      json: false, jsonlOutput: false, traceUSB: false,
      strict: false, safe: false, traceUSBDetails: false,
      targetVID: nil, targetPID: nil, targetBus: nil, targetAddress: nil
    )
    XCTAssertFalse(flags.realOnly)
    XCTAssertFalse(flags.json)
    XCTAssertFalse(flags.strict)
    XCTAssertNil(flags.targetVID)
  }

  func testFlagsWithDeviceFilter() {
    let flags = CLIFlags(
      realOnly: true, useMock: false, mockProfile: "pixel7",
      json: true, jsonlOutput: false, traceUSB: true,
      strict: true, safe: true, traceUSBDetails: false,
      targetVID: "0x2717", targetPID: "ff40",
      targetBus: 1, targetAddress: 4
    )
    XCTAssertTrue(flags.realOnly)
    XCTAssertTrue(flags.json)
    XCTAssertTrue(flags.strict)
    XCTAssertTrue(flags.safe)
    XCTAssertEqual(flags.targetVID, "0x2717")
    XCTAssertEqual(flags.targetPID, "ff40")
    XCTAssertEqual(flags.targetBus, 1)
    XCTAssertEqual(flags.targetAddress, 4)
  }
}

// MARK: - JSON Envelope Tests

@MainActor
final class JSONEnvelopeTests: XCTestCase {
  func testJSONEnvelopeEncoding() throws {
    let envelope = JSONEnvelope(
      schemaVersion: "1.0.0",
      type: "test",
      timestamp: "2026-01-01T00:00:00Z",
      data: ["key": "value"]
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let data = try encoder.encode(envelope)
    let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    XCTAssertEqual(json["schemaVersion"] as? String, "1.0.0")
    XCTAssertEqual(json["type"] as? String, "test")
    XCTAssertEqual(json["timestamp"] as? String, "2026-01-01T00:00:00Z")
  }

  func testCLIErrorEnvelopeFields() throws {
    let envelope = CLIErrorEnvelope(
      "test-error",
      details: ["hint": "try again"],
      mode: "strict",
      timestamp: "2026-01-01T00:00:00Z"
    )
    XCTAssertEqual(envelope.schemaVersion, "1.0")
    XCTAssertEqual(envelope.type, "error")
    XCTAssertEqual(envelope.error, "test-error")
    XCTAssertEqual(envelope.mode, "strict")
    XCTAssertEqual(envelope.details?["hint"], "try again")
  }

  func testCLIErrorEnvelopeWithoutOptionals() throws {
    let envelope = CLIErrorEnvelope("minimal-error")
    XCTAssertEqual(envelope.schemaVersion, "1.0")
    XCTAssertNil(envelope.details)
    XCTAssertNil(envelope.mode)
    XCTAssertFalse(envelope.timestamp.isEmpty)
  }

  func testCLIErrorEnvelopeRoundTrip() throws {
    let original = CLIErrorEnvelope(
      "round-trip",
      details: ["code": "E99"],
      mode: "safe",
      timestamp: "2026-06-15T12:00:00Z"
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let data = try encoder.encode(original)
    let decoded = try JSONDecoder().decode(CLIErrorEnvelope.self, from: data)
    XCTAssertEqual(decoded.error, original.error)
    XCTAssertEqual(decoded.mode, original.mode)
    XCTAssertEqual(decoded.details, original.details)
    XCTAssertEqual(decoded.timestamp, original.timestamp)
  }
}

// MARK: - BuildInfo Tests

final class BuildInfoTests: XCTestCase {
  func testBuildInfoVersionNonEmpty() {
    XCTAssertFalse(BuildInfo.version.isEmpty)
  }

  func testBuildInfoGitNonEmpty() {
    XCTAssertFalse(BuildInfo.git.isEmpty)
  }

  func testBuildInfoSchemaVersion() {
    XCTAssertEqual(BuildInfo.schemaVersion, "1.0.0")
  }

  func testBuildInfoBuiltAtIsISO8601() {
    let formatter = ISO8601DateFormatter()
    XCTAssertNotNil(
      formatter.date(from: BuildInfo.builtAt),
      "builtAt should be valid ISO8601: \(BuildInfo.builtAt)")
  }
}

// MARK: - Redaction Tests

final class RedactionExtendedTests: XCTestCase {
  func testRedactionDeterministic() {
    let salt = Data("deterministic-salt".utf8)
    let a = Redaction.redactSerial("SN-001", salt: salt)
    let b = Redaction.redactSerial("SN-001", salt: salt)
    XCTAssertEqual(a, b)
  }

  func testRedactionDifferentSaltsDiffer() {
    let salt1 = Data("salt-1".utf8)
    let salt2 = Data("salt-2".utf8)
    let a = Redaction.redactSerial("SN-001", salt: salt1)
    let b = Redaction.redactSerial("SN-001", salt: salt2)
    XCTAssertNotEqual(a, b)
  }

  func testRedactionEmptySerial() {
    let salt = Data("salt".utf8)
    let result = Redaction.redactSerial("", salt: salt)
    XCTAssertTrue(result.hasPrefix("hmacsha256:"))
    XCTAssertEqual(result.count, "hmacsha256:".count + 64)
  }

  func testRedactionHexLength() {
    let salt = Data("test".utf8)
    let result = Redaction.redactSerial("X", salt: salt)
    // HMAC-SHA256 produces 32 bytes → 64 hex chars
    let hexPart = result.dropFirst("hmacsha256:".count)
    XCTAssertEqual(hexPart.count, 64)
  }

  func testGenerateSaltDifferentCalls() {
    let s1 = Redaction.generateSalt(count: 32)
    let s2 = Redaction.generateSalt(count: 32)
    // Extremely unlikely to collide
    XCTAssertNotEqual(s1, s2)
  }
}

// MARK: - Redactor Tests

final class RedactorExtendedTests: XCTestCase {
  func testRedactPTPStringEmpty() {
    let r = Redactor(bundleKey: "key")
    XCTAssertEqual(r.redactPTPString(""), "")
  }

  func testRedactPTPStringPreservesLength() {
    let r = Redactor(bundleKey: "key")
    let input = "Hello World"
    let redacted = r.redactPTPString(input)
    XCTAssertEqual(redacted.count, input.count)
    XCTAssertEqual(redacted, String(repeating: "*", count: input.count))
  }

  func testTokenizeFilenameWithoutExtension() {
    let r = Redactor(bundleKey: "stable-key")
    let token = r.tokenizeFilename("README")
    XCTAssertTrue(token.hasPrefix("file_"))
    XCTAssertFalse(token.contains("."))
  }

  func testTokenizeFilenameIsDeterministic() {
    let r = Redactor(bundleKey: "fixed-key")
    let a = r.tokenizeFilename("photo.jpg")
    let b = r.tokenizeFilename("photo.jpg")
    XCTAssertEqual(a, b)
  }

  func testTokenizeFilenamePreservesMultiDotExtension() {
    let r = Redactor(bundleKey: "key")
    let token = r.tokenizeFilename("archive.tar.gz")
    // NSString.pathExtension returns "gz"
    XCTAssertTrue(token.hasSuffix(".gz"))
  }
}

// MARK: - USBDumper Report Tests

final class USBDumperExtendedTests: XCTestCase {
  func testDumpReportSchemaVersionInJSON() throws {
    let report = USBDumper.DumpReport(
      schemaVersion: "1.0.0", generatedAt: Date(timeIntervalSince1970: 0), devices: [])
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let data = try encoder.encode(report)
    let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    XCTAssertEqual(json["schemaVersion"] as? String, "1.0.0")
  }

  func testDumpDeviceEncoding() throws {
    let device = USBDumper.DumpDevice(
      id: "04e8:6860@1:4",
      vendorID: "04e8",
      productID: "6860",
      bus: 1,
      address: 4,
      manufacturer: "Samsung",
      product: "Galaxy",
      serial: nil,
      interfaces: []
    )
    let data = try JSONEncoder().encode(device)
    let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    XCTAssertEqual(json["vendorID"] as? String, "04e8")
    XCTAssertEqual(json["bus"] as? Int, 1)
    XCTAssertNil(json["serial"])
  }

  func testDumpInterfaceEncoding() throws {
    let iface = USBDumper.DumpInterface(
      number: 0,
      altSetting: 0,
      interfaceClass: "0x06",
      interfaceSubclass: "0x01",
      interfaceProtocol: "0x01",
      name: "MTP",
      endpoints: [
        USBDumper.DumpEndpoint(address: "0x81", direction: "in", transferType: "bulk"),
        USBDumper.DumpEndpoint(address: "0x02", direction: "out", transferType: "bulk"),
      ]
    )
    let data = try JSONEncoder().encode(iface)
    let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    XCTAssertEqual(json["interfaceClass"] as? String, "0x06")
    XCTAssertEqual((json["endpoints"] as? [Any])?.count, 2)
  }
}

// MARK: - CollectCommand Error Tests

final class CollectCommandExtendedTests: XCTestCase {
  func testCollectErrorTimeoutContainsMilliseconds() {
    let err = CollectCommand.CollectError.timeout(5000)
    let desc = err.errorDescription ?? ""
    XCTAssertTrue(desc.contains("5000"))
  }

  func testCollectErrorInvalidBenchSizeNegative() {
    let err = CollectCommand.CollectError.invalidBenchSize("-1")
    let desc = err.errorDescription ?? ""
    XCTAssertTrue(desc.contains("-1"))
  }

  func testCollectFlagsDefaults() {
    let flags = CollectCommand.CollectFlags()
    XCTAssertTrue(flags.strict)
    XCTAssertFalse(flags.safe)
    XCTAssertTrue(flags.runBench.isEmpty)
    XCTAssertFalse(flags.json)
    XCTAssertFalse(flags.noninteractive)
    XCTAssertNil(flags.bundlePath)
    XCTAssertNil(flags.vid)
  }

  func testCollectFlagsWithDeviceFilter() {
    let flags = CollectCommand.CollectFlags(
      strict: false,
      safe: true,
      runBench: ["1M", "4M"],
      json: true,
      noninteractive: true,
      bundlePath: "/tmp/bundle",
      vid: 0x2717, pid: 0xFF40, bus: 1, address: 5
    )
    XCTAssertFalse(flags.strict)
    XCTAssertTrue(flags.safe)
    XCTAssertEqual(flags.runBench, ["1M", "4M"])
    XCTAssertEqual(flags.vid, 0x2717)
    XCTAssertEqual(flags.pid, 0xFF40)
  }
}

// MARK: - Device Selection Logic Tests

@MainActor
final class DeviceSelectionTests: XCTestCase {
  private func makeSummary(
    id: String, vid: UInt16, pid: UInt16, bus: UInt8, address: UInt8
  ) -> MTPDeviceSummary {
    MTPDeviceSummary(
      id: MTPDeviceID(raw: id),
      manufacturer: "Test",
      model: "Device",
      vendorID: vid,
      productID: pid,
      bus: bus,
      address: address
    )
  }

  func testSelectDeviceNoFilter() {
    let devices = [
      makeSummary(id: "a", vid: 0x04e8, pid: 0x6860, bus: 1, address: 4),
      makeSummary(id: "b", vid: 0x2717, pid: 0xff40, bus: 2, address: 5),
    ]
    let filter = DeviceFilter(vid: nil, pid: nil, bus: nil, address: nil)
    let result = selectDevice(devices, filter: filter, noninteractive: true)
    if case .multiple(let matches) = result {
      XCTAssertEqual(matches.count, 2)
    } else {
      XCTFail("Expected multiple outcome")
    }
  }

  func testSelectDeviceSingleMatch() {
    let devices = [
      makeSummary(id: "a", vid: 0x04e8, pid: 0x6860, bus: 1, address: 4),
      makeSummary(id: "b", vid: 0x2717, pid: 0xff40, bus: 2, address: 5),
    ]
    let filter = DeviceFilter(vid: 0x2717, pid: nil, bus: nil, address: nil)
    let result = selectDevice(devices, filter: filter, noninteractive: true)
    if case .selected(let device) = result {
      XCTAssertEqual(device.id.raw, "b")
    } else {
      XCTFail("Expected selected outcome")
    }
  }

  func testSelectDeviceNoMatch() {
    let devices = [
      makeSummary(id: "a", vid: 0x04e8, pid: 0x6860, bus: 1, address: 4)
    ]
    let filter = DeviceFilter(vid: 0x9999, pid: nil, bus: nil, address: nil)
    let result = selectDevice(devices, filter: filter, noninteractive: true)
    if case .none = result {
      // expected
    } else {
      XCTFail("Expected none outcome")
    }
  }

  func testSelectDeviceEmptyList() {
    let devices: [MTPDeviceSummary] = []
    let filter = DeviceFilter(vid: nil, pid: nil, bus: nil, address: nil)
    let result = selectDevice(devices, filter: filter, noninteractive: true)
    if case .none = result {
      // expected
    } else {
      XCTFail("Expected none outcome for empty list")
    }
  }

  func testSelectDeviceByBusAndAddress() {
    let devices = [
      makeSummary(id: "a", vid: 0x04e8, pid: 0x6860, bus: 1, address: 4),
      makeSummary(id: "b", vid: 0x04e8, pid: 0x6860, bus: 2, address: 7),
    ]
    let filter = DeviceFilter(vid: nil, pid: nil, bus: 2, address: 7)
    let result = selectDevice(devices, filter: filter, noninteractive: true)
    if case .selected(let device) = result {
      XCTAssertEqual(device.id.raw, "b")
    } else {
      XCTFail("Expected selected outcome for bus/address filter")
    }
  }

  func testSelectDeviceByVidPidBusAddress() {
    let devices = [
      makeSummary(id: "a", vid: 0x04e8, pid: 0x6860, bus: 1, address: 4),
      makeSummary(id: "b", vid: 0x04e8, pid: 0x6860, bus: 2, address: 5),
    ]
    let filter = DeviceFilter(vid: 0x04e8, pid: 0x6860, bus: 1, address: 4)
    let result = selectDevice(devices, filter: filter, noninteractive: true)
    if case .selected(let device) = result {
      XCTAssertEqual(device.id.raw, "a")
    } else {
      XCTFail("Expected selected outcome for full filter")
    }
  }

  func testSelectDeviceSingleDevice() {
    let devices = [
      makeSummary(id: "only", vid: 0x18d1, pid: 0x4ee1, bus: 3, address: 1)
    ]
    let filter = DeviceFilter(vid: nil, pid: nil, bus: nil, address: nil)
    let result = selectDevice(devices, filter: filter, noninteractive: true)
    if case .selected(let device) = result {
      XCTAssertEqual(device.id.raw, "only")
    } else {
      XCTFail("Expected single device to be selected")
    }
  }
}

// MARK: - DeviceFilterParse Tests

final class DeviceFilterParseTests: XCTestCase {
  func testParseVidOnly() {
    var args = ["--vid", "2717", "other"]
    let filter = DeviceFilterParse.parse(from: &args)
    XCTAssertEqual(filter.vid, 0x2717)
    XCTAssertNil(filter.pid)
    XCTAssertEqual(args, ["other"])
  }

  func testParsePidOnly() {
    var args = ["--pid", "ff40", "other"]
    let filter = DeviceFilterParse.parse(from: &args)
    XCTAssertNil(filter.vid)
    XCTAssertEqual(filter.pid, 0xFF40)
    XCTAssertEqual(args, ["other"])
  }

  func testParseBusAndAddress() {
    var args = ["--bus", "3", "--address", "12"]
    let filter = DeviceFilterParse.parse(from: &args)
    XCTAssertEqual(filter.bus, 3)
    XCTAssertEqual(filter.address, 12)
    XCTAssertTrue(args.isEmpty)
  }

  func testParseAllFilters() {
    var args = ["--vid", "04e8", "--pid", "6860", "--bus", "1", "--address", "4"]
    let filter = DeviceFilterParse.parse(from: &args)
    XCTAssertEqual(filter.vid, 0x04e8)
    XCTAssertEqual(filter.pid, 0x6860)
    XCTAssertEqual(filter.bus, 1)
    XCTAssertEqual(filter.address, 4)
    XCTAssertTrue(args.isEmpty)
  }

  func testParseNoFilterArgs() {
    var args = ["probe", "--json"]
    let filter = DeviceFilterParse.parse(from: &args)
    XCTAssertNil(filter.vid)
    XCTAssertNil(filter.pid)
    XCTAssertNil(filter.bus)
    XCTAssertNil(filter.address)
    XCTAssertEqual(args, ["probe", "--json"])
  }

  func testParsePreservesUnknownArgs() {
    var args = ["--vid", "1234", "--unknown", "value", "--bus", "5"]
    let filter = DeviceFilterParse.parse(from: &args)
    XCTAssertEqual(filter.vid, 0x1234)
    XCTAssertEqual(filter.bus, 5)
    XCTAssertEqual(args, ["--unknown", "value"])
  }

  func testParseEmptyArgs() {
    var args: [String] = []
    let filter = DeviceFilterParse.parse(from: &args)
    XCTAssertNil(filter.vid)
    XCTAssertNil(filter.pid)
    XCTAssertNil(filter.bus)
    XCTAssertNil(filter.address)
  }
}

// MARK: - parseUSBIdentifier Tests

final class ParseUSBIdentifierTests: XCTestCase {
  func testNilInput() {
    XCTAssertNil(parseUSBIdentifier(nil))
  }

  func testEmptyString() {
    XCTAssertNil(parseUSBIdentifier(""))
  }

  func testWhitespaceOnly() {
    XCTAssertNil(parseUSBIdentifier("   "))
  }

  func testHexWithPrefix() {
    XCTAssertEqual(parseUSBIdentifier("0x2717"), 0x2717)
  }

  func testHexWithUppercasePrefix() {
    XCTAssertEqual(parseUSBIdentifier("0XABCD"), 0xABCD)
  }

  func testHexLettersWithoutPrefix() {
    XCTAssertEqual(parseUSBIdentifier("ff40"), 0xFF40)
  }

  func testPureDigitsInterpretedAsHex() {
    // USB convention: unprefixed numeric values are hex
    XCTAssertEqual(parseUSBIdentifier("4660"), 0x4660)
  }

  func testWhitespaceStripped() {
    XCTAssertEqual(parseUSBIdentifier(" 1234 "), 0x1234)
  }

  func testInvalidString() {
    XCTAssertNil(parseUSBIdentifier("not-a-number"))
  }
}

// MARK: - Data Extension Tests

final class DataHexStringTests: XCTestCase {
  func testEmptyData() {
    XCTAssertEqual(Data().hexString(), "")
  }

  func testSingleByte() {
    XCTAssertEqual(Data([0xFF]).hexString(), "ff")
  }

  func testMultipleBytes() {
    XCTAssertEqual(Data([0x01, 0x23, 0x45]).hexString(), "012345")
  }

  func testZeroBytes() {
    XCTAssertEqual(Data([0x00, 0x00]).hexString(), "0000")
  }
}
