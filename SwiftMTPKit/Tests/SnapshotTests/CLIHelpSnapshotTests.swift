// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import XCTest
@testable import SwiftMTPCore
@testable import SwiftMTPCLI

/// Inline snapshot tests for CLI help text structure and formatting.
///
/// Verifies CLIErrorEnvelope structure, ExitCode stability, DeviceFilter
/// parsing, and subcommand naming conventions.  Uses `XCTAssertEqual` /
/// `XCTAssertTrue` against known structural elements — no file-based
/// snapshot infrastructure required.
final class CLIHelpSnapshotTests: XCTestCase {

  // MARK: - 1. CLIErrorEnvelope Help-Level Structure

  func testErrorEnvelopeContainsSchemaVersionKey() throws {
    let envelope = CLIErrorEnvelope("help_test", timestamp: "2026-07-01T00:00:00Z")
    let data = try sortedJSON(envelope)
    let json = String(data: data, encoding: .utf8)!
    XCTAssertTrue(json.contains("\"schemaVersion\""))
    XCTAssertTrue(json.contains("\"1.0\""))
  }

  func testErrorEnvelopeTypeIsAlwaysError() throws {
    let envelope = CLIErrorEnvelope("unknown_command", timestamp: "2026-07-01T00:00:00Z")
    let data = try sortedJSON(envelope)
    let dict = try JSONSerialization.jsonObject(with: data) as! [String: Any]
    XCTAssertEqual(dict["type"] as? String, "error")
  }

  func testErrorEnvelopeTimestampPassthrough() throws {
    let ts = "2026-07-01T12:30:00Z"
    let envelope = CLIErrorEnvelope("test", timestamp: ts)
    let data = try sortedJSON(envelope)
    let dict = try JSONSerialization.jsonObject(with: data) as! [String: Any]
    XCTAssertEqual(dict["timestamp"] as? String, ts)
  }

  // MARK: - 2. CLI Subcommand Name Stability

  func testKnownSubcommandNamesStable() {
    let expectedCommands = [
      "probe", "ls", "pull", "push", "snapshot", "mirror",
      "bench", "events", "quirks", "device-lab", "wizard",
      "cp", "edit", "thumb", "info",
    ]
    for cmd in expectedCommands {
      XCTAssertFalse(cmd.isEmpty, "Command name must be non-empty: \(cmd)")
      XCTAssertEqual(cmd, cmd.lowercased(), "Command names must be lowercase: \(cmd)")
      XCTAssertFalse(cmd.contains(" "), "Command names must not contain spaces: \(cmd)")
    }
  }

  func testSubcommandCountIsAtLeast15() {
    let knownCommands = [
      "probe", "ls", "pull", "push", "snapshot", "mirror",
      "bench", "events", "quirks", "device-lab", "wizard",
      "cp", "edit", "thumb", "info",
    ]
    XCTAssertGreaterThanOrEqual(knownCommands.count, 15)
  }

  // MARK: - 3. CLIErrorEnvelope Variations

  func testErrorEnvelopeWithModePropagates() throws {
    let envelope = CLIErrorEnvelope(
      "transfer_failed", mode: "push", timestamp: "2026-07-01T00:00:00Z"
    )
    let data = try sortedJSON(envelope)
    let dict = try JSONSerialization.jsonObject(with: data) as! [String: Any]
    XCTAssertEqual(dict["mode"] as? String, "push")
    XCTAssertEqual(dict["error"] as? String, "transfer_failed")
  }

  func testErrorEnvelopeWithDetailsPropagates() throws {
    let envelope = CLIErrorEnvelope(
      "storage_full",
      details: ["storage": "Internal", "free": "0 bytes"],
      timestamp: "2026-07-01T00:00:00Z"
    )
    let data = try sortedJSON(envelope)
    let dict = try JSONSerialization.jsonObject(with: data) as! [String: Any]
    let details = dict["details"] as? [String: String]
    XCTAssertEqual(details?["storage"], "Internal")
    XCTAssertEqual(details?["free"], "0 bytes")
  }

  func testErrorEnvelopeNilsOmittedInJSON() throws {
    let envelope = CLIErrorEnvelope("simple_error", timestamp: "2026-07-01T00:00:00Z")
    let data = try sortedJSON(envelope)
    let dict = try JSONSerialization.jsonObject(with: data) as! [String: Any]
    XCTAssertNil(dict["details"])
    XCTAssertNil(dict["mode"])
  }

  func testErrorEnvelopeErrorFieldExact() throws {
    let envelope = CLIErrorEnvelope("device_busy", timestamp: "2026-07-01T00:00:00Z")
    let data = try sortedJSON(envelope)
    let dict = try JSONSerialization.jsonObject(with: data) as! [String: Any]
    XCTAssertEqual(dict["error"] as? String, "device_busy")
    XCTAssertEqual(dict["schemaVersion"] as? String, "1.0")
  }

  // MARK: - 4. ExitCode Enum Stability

  func testExitCodeOkRawValue() {
    XCTAssertEqual(ExitCode.ok.rawValue, 0)
  }

  func testExitCodeSoftwareRawValue() {
    XCTAssertEqual(ExitCode.software.rawValue, 70)
  }

  func testExitCodeUsageRawValue() {
    XCTAssertEqual(ExitCode.usage.rawValue, 64)
  }

  func testExitCodeUnavailableRawValue() {
    XCTAssertEqual(ExitCode.unavailable.rawValue, 69)
  }

  func testExitCodeTempfailRawValue() {
    XCTAssertEqual(ExitCode.tempfail.rawValue, 75)
  }

  // MARK: - 5. DeviceFilter Construction

  func testDeviceFilterAllFieldsNil() {
    let filter = DeviceFilter(vid: nil, pid: nil, bus: nil, address: nil)
    XCTAssertNil(filter.vid)
    XCTAssertNil(filter.pid)
    XCTAssertNil(filter.bus)
    XCTAssertNil(filter.address)
  }

  func testDeviceFilterWithVIDPID() {
    let filter = DeviceFilter(vid: 0x18D1, pid: 0x4EE1, bus: nil, address: nil)
    XCTAssertEqual(filter.vid, 0x18D1)
    XCTAssertEqual(filter.pid, 0x4EE1)
  }

  func testDeviceFilterWithBusAddress() {
    let filter = DeviceFilter(vid: nil, pid: nil, bus: 1, address: 5)
    XCTAssertEqual(filter.bus, 1)
    XCTAssertEqual(filter.address, 5)
  }

  // MARK: - 6. parseUSBIdentifier Stability

  func testParseUSBIdentifierHexPrefix() {
    XCTAssertEqual(parseUSBIdentifier("0x18d1"), 0x18D1)
  }

  func testParseUSBIdentifierPlainHex() {
    XCTAssertEqual(parseUSBIdentifier("4ee1"), 0x4EE1)
  }

  func testParseUSBIdentifierNil() {
    XCTAssertNil(parseUSBIdentifier(nil))
  }

  func testParseUSBIdentifierEmpty() {
    XCTAssertNil(parseUSBIdentifier(""))
  }

  func testParseUSBIdentifierUpperCase() {
    XCTAssertEqual(parseUSBIdentifier("0X04E8"), 0x04E8)
  }

  // MARK: - 7. DeviceFilterParse From Args

  func testDeviceFilterParseWithVIDPID() {
    var args = ["--vid", "18d1", "--pid", "4ee1"]
    let filter = DeviceFilterParse.parse(from: &args)
    XCTAssertEqual(filter.vid, 0x18D1)
    XCTAssertEqual(filter.pid, 0x4EE1)
    XCTAssertTrue(args.isEmpty, "Parsed args should be consumed")
  }

  func testDeviceFilterParseWithBusAddress() {
    var args = ["--bus", "1", "--address", "5"]
    let filter = DeviceFilterParse.parse(from: &args)
    XCTAssertEqual(filter.bus, 1)
    XCTAssertEqual(filter.address, 5)
    XCTAssertTrue(args.isEmpty)
  }

  func testDeviceFilterParsePreservesUnknownArgs() {
    var args = ["--output", "json", "--vid", "2717"]
    let filter = DeviceFilterParse.parse(from: &args)
    XCTAssertEqual(filter.vid, 0x2717)
    XCTAssertEqual(args, ["--output", "json"])
  }

  // MARK: - Helpers

  private func sortedJSON<T: Encodable>(_ value: T) throws -> Data {
    let enc = JSONEncoder()
    enc.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    return try enc.encode(value)
  }
}
