// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import Testing
import SwiftMTPCLI
@testable import SwiftMTPCore

// MARK: - ExitCode BSD Sysexits

@Suite("ExitCode BSD Values")
struct ExitCodeBSDValues {
  @Test("ExitCode.ok matches EX_OK (0)")
  func okValue() {
    #expect(ExitCode.ok.rawValue == 0)
  }

  @Test("ExitCode.usage matches EX_USAGE (64)")
  func usageValue() {
    #expect(ExitCode.usage.rawValue == 64)
  }

  @Test("ExitCode.unavailable matches EX_UNAVAILABLE (69)")
  func unavailableValue() {
    #expect(ExitCode.unavailable.rawValue == 69)
  }

  @Test("ExitCode.software matches EX_SOFTWARE (70)")
  func softwareValue() {
    #expect(ExitCode.software.rawValue == 70)
  }

  @Test("ExitCode.tempfail matches EX_TEMPFAIL (75)")
  func tempfailValue() {
    #expect(ExitCode.tempfail.rawValue == 75)
  }

  @Test("All exit codes have unique raw values")
  func uniqueValues() {
    let codes: [ExitCode] = [.ok, .usage, .unavailable, .software, .tempfail]
    let uniqueSet = Set(codes.map(\.rawValue))
    #expect(uniqueSet.count == codes.count)
  }
}

// MARK: - CLIErrorEnvelope JSON Tests

@Suite("CLIErrorEnvelope JSON")
struct CLIErrorEnvelopeJSON {
  @Test("Envelope schema version is 1.0")
  func schemaVersion() {
    let envelope = CLIErrorEnvelope("test")
    #expect(envelope.schemaVersion == "1.0")
  }

  @Test("Envelope type is always error")
  func typeField() {
    let envelope = CLIErrorEnvelope("any-error")
    #expect(envelope.type == "error")
  }

  @Test("Envelope timestamp is auto-populated")
  func autoTimestamp() {
    let envelope = CLIErrorEnvelope("ts-test")
    #expect(!envelope.timestamp.isEmpty)
  }

  @Test("Envelope with explicit timestamp preserves it")
  func explicitTimestamp() {
    let ts = "2026-01-01T00:00:00Z"
    let envelope = CLIErrorEnvelope("ts-test", timestamp: ts)
    #expect(envelope.timestamp == ts)
  }

  @Test("Envelope round-trip through JSON preserves fields")
  func jsonRoundTrip() throws {
    let original = CLIErrorEnvelope(
      "round-trip-error",
      details: ["fix": "retry"],
      mode: "safe",
      timestamp: "2026-06-15T12:00:00Z"
    )
    let data = try JSONEncoder().encode(original)
    let decoded = try JSONDecoder().decode(CLIErrorEnvelope.self, from: data)
    #expect(decoded.error == original.error)
    #expect(decoded.mode == original.mode)
    #expect(decoded.details == original.details)
    #expect(decoded.timestamp == original.timestamp)
    #expect(decoded.schemaVersion == "1.0")
    #expect(decoded.type == "error")
  }

  @Test("Envelope with nil optionals encodes cleanly")
  func nilOptionals() throws {
    let envelope = CLIErrorEnvelope("minimal")
    let data = try JSONEncoder().encode(envelope)
    let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
    // details and mode should not appear or be null
    #expect(json["error"] as? String == "minimal")
    #expect(json["schemaVersion"] as? String == "1.0")
  }

  @Test("Deterministic JSON output with fixed timestamp")
  func deterministicSnapshot() throws {
    let envelope = CLIErrorEnvelope(
      "snapshot-error",
      details: ["code": "E42"],
      mode: "unit",
      timestamp: "2026-01-01T00:00:00Z"
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.withoutEscapingSlashes, .sortedKeys]
    let data = try encoder.encode(envelope)
    let text = String(data: data, encoding: .utf8) ?? ""
    let expected =
      #"{"details":{"code":"E42"},"error":"snapshot-error","mode":"unit","schemaVersion":"1.0","timestamp":"2026-01-01T00:00:00Z","type":"error"}"#
    #expect(text == expected)
  }
}

// MARK: - DeviceFilter Tests

@Suite("DeviceFilter Construction")
struct DeviceFilterConstruction {
  @Test("Empty filter has all nil fields")
  func emptyFilter() {
    let f = DeviceFilter(vid: nil, pid: nil, bus: nil, address: nil)
    #expect(f.vid == nil)
    #expect(f.pid == nil)
    #expect(f.bus == nil)
    #expect(f.address == nil)
  }

  @Test("Full filter preserves all values")
  func fullFilter() {
    let f = DeviceFilter(vid: 0x2717, pid: 0xFF40, bus: 1, address: 4)
    #expect(f.vid == 0x2717)
    #expect(f.pid == 0xFF40)
    #expect(f.bus == 1)
    #expect(f.address == 4)
  }

  @Test("Partial filter (vid only)")
  func partialFilter() {
    let f = DeviceFilter(vid: 0x04e8, pid: nil, bus: nil, address: nil)
    #expect(f.vid == 0x04e8)
    #expect(f.pid == nil)
  }
}

// MARK: - parseUSBIdentifier Tests

@Suite("parseUSBIdentifier")
struct ParseUSBIdentifierSuite {
  @Test("nil input returns nil")
  func nilInput() { #expect(parseUSBIdentifier(nil) == nil) }

  @Test("empty string returns nil")
  func emptyString() { #expect(parseUSBIdentifier("") == nil) }

  @Test("whitespace-only returns nil")
  func whitespaceOnly() { #expect(parseUSBIdentifier("   ") == nil) }

  @Test("0x prefix hex parse")
  func hexPrefix() { #expect(parseUSBIdentifier("0x2717") == 0x2717) }

  @Test("0X uppercase prefix hex parse")
  func upperHexPrefix() { #expect(parseUSBIdentifier("0XABCD") == 0xABCD) }

  @Test("hex letters without prefix")
  func hexLetters() { #expect(parseUSBIdentifier("ff40") == 0xFF40) }

  @Test("pure digits as hex (USB convention)")
  func pureDigits() { #expect(parseUSBIdentifier("4660") == 0x4660) }

  @Test("whitespace is stripped")
  func whitespaceStripped() { #expect(parseUSBIdentifier(" 1234 ") == 0x1234) }

  @Test("invalid string returns nil")
  func invalid() { #expect(parseUSBIdentifier("not-a-number") == nil) }

  @Test("max UInt16 value")
  func maxValue() { #expect(parseUSBIdentifier("0xFFFF") == 0xFFFF) }

  @Test("zero value")
  func zeroValue() { #expect(parseUSBIdentifier("0x0000") == 0x0000) }
}

// MARK: - DeviceFilterParse Tests

@Suite("DeviceFilterParse")
struct DeviceFilterParseSuite {
  @Test("Parses --vid and removes from args")
  func parseVid() {
    var args = ["--vid", "2717", "remaining"]
    let f = DeviceFilterParse.parse(from: &args)
    #expect(f.vid == 0x2717)
    #expect(args == ["remaining"])
  }

  @Test("Parses --bus and --address")
  func parseBusAddress() {
    var args = ["--bus", "3", "--address", "12"]
    let f = DeviceFilterParse.parse(from: &args)
    #expect(f.bus == 3)
    #expect(f.address == 12)
    #expect(args.isEmpty)
  }

  @Test("Unknown flags remain untouched")
  func unknownFlags() {
    var args = ["--vid", "04e8", "--json", "--bus", "1"]
    let f = DeviceFilterParse.parse(from: &args)
    #expect(f.vid == 0x04e8)
    #expect(f.bus == 1)
    #expect(args == ["--json"])
  }

  @Test("Empty args returns empty filter")
  func emptyArgs() {
    var args: [String] = []
    let f = DeviceFilterParse.parse(from: &args)
    #expect(f.vid == nil)
    #expect(f.pid == nil)
    #expect(f.bus == nil)
    #expect(f.address == nil)
  }

  @Test("Parses all four filter options")
  func allFour() {
    var args = ["--vid", "04e8", "--pid", "6860", "--bus", "1", "--address", "4"]
    let f = DeviceFilterParse.parse(from: &args)
    #expect(f.vid == 0x04e8)
    #expect(f.pid == 0x6860)
    #expect(f.bus == 1)
    #expect(f.address == 4)
    #expect(args.isEmpty)
  }
}

// MARK: - selectDevice Tests

@Suite("selectDevice Logic")
struct SelectDeviceLogic {
  private func summary(
    _ id: String, vid: UInt16, pid: UInt16, bus: UInt8, addr: UInt8
  ) -> MTPDeviceSummary {
    MTPDeviceSummary(
      id: MTPDeviceID(raw: id),
      manufacturer: "T",
      model: "D",
      vendorID: vid,
      productID: pid,
      bus: bus,
      address: addr
    )
  }

  @Test("Empty list returns .none")
  func emptyList() {
    let r = selectDevice(
      [MTPDeviceSummary](),
      filter: DeviceFilter(vid: nil, pid: nil, bus: nil, address: nil),
      noninteractive: true
    )
    if case .none = r {} else { Issue.record("Expected .none") }
  }

  @Test("Single device with no filter returns .selected")
  func singleDeviceNoFilter() {
    let d = summary("x", vid: 0x1234, pid: 0x5678, bus: 1, addr: 1)
    let r = selectDevice([d], filter: DeviceFilter(vid: nil, pid: nil, bus: nil, address: nil), noninteractive: true)
    if case .selected(let s) = r {
      #expect(s.id.raw == "x")
    } else {
      Issue.record("Expected .selected")
    }
  }

  @Test("Multiple devices with no filter returns .multiple")
  func multipleNoFilter() {
    let devs = [
      summary("a", vid: 0x1111, pid: 0x2222, bus: 1, addr: 1),
      summary("b", vid: 0x3333, pid: 0x4444, bus: 2, addr: 2),
    ]
    let r = selectDevice(devs, filter: DeviceFilter(vid: nil, pid: nil, bus: nil, address: nil), noninteractive: true)
    if case .multiple(let m) = r { #expect(m.count == 2) }
    else { Issue.record("Expected .multiple") }
  }

  @Test("Filter by vid narrows to single device")
  func filterByVid() {
    let devs = [
      summary("a", vid: 0x1111, pid: 0x2222, bus: 1, addr: 1),
      summary("b", vid: 0x3333, pid: 0x4444, bus: 2, addr: 2),
    ]
    let r = selectDevice(devs, filter: DeviceFilter(vid: 0x3333, pid: nil, bus: nil, address: nil), noninteractive: true)
    if case .selected(let s) = r { #expect(s.id.raw == "b") }
    else { Issue.record("Expected .selected") }
  }

  @Test("Filter with no match returns .none")
  func noMatch() {
    let devs = [summary("a", vid: 0x1111, pid: 0x2222, bus: 1, addr: 1)]
    let r = selectDevice(devs, filter: DeviceFilter(vid: 0x9999, pid: nil, bus: nil, address: nil), noninteractive: true)
    if case .none = r {} else { Issue.record("Expected .none") }
  }

  @Test("Bus/address filter disambiguates same vid:pid")
  func busAddressDisambiguates() {
    let devs = [
      summary("a", vid: 0x04e8, pid: 0x6860, bus: 1, addr: 4),
      summary("b", vid: 0x04e8, pid: 0x6860, bus: 2, addr: 7),
    ]
    let r = selectDevice(devs, filter: DeviceFilter(vid: 0x04e8, pid: 0x6860, bus: 2, address: 7), noninteractive: true)
    if case .selected(let s) = r { #expect(s.id.raw == "b") }
    else { Issue.record("Expected .selected") }
  }
}

// MARK: - Spinner Tests

@Suite("Spinner Initialization")
struct SpinnerTests {
  @Test("Spinner can be created with enabled: false")
  func disabledSpinner() {
    let spinner = SwiftMTPCLI.Spinner(enabled: false)
    // Should not crash
    spinner.start("test")
    spinner.stopAndClear("done")
  }

  @Test("Spinner can be created with enabled: true")
  func enabledSpinner() {
    let spinner = SwiftMTPCLI.Spinner(enabled: true)
    spinner.start("loading")
    spinner.stopAndClear("complete")
  }
}

// MARK: - MTPDeviceSummary DeviceFilterCandidate Conformance

@Suite("MTPDeviceSummary Filtering")
struct MTPDeviceSummaryFiltering {
  @Test("MTPDeviceSummary conforms to DeviceFilterCandidate")
  func conformance() {
    let s = MTPDeviceSummary(
      id: MTPDeviceID(raw: "test"),
      manufacturer: "V",
      model: "M",
      vendorID: 0x1234,
      productID: 0x5678,
      bus: 3,
      address: 7
    )
    let candidate: any DeviceFilterCandidate = s
    #expect(candidate.vendorID == 0x1234)
    #expect(candidate.productID == 0x5678)
    #expect(candidate.bus == 3)
    #expect(candidate.address == 7)
  }

  @Test("MTPDeviceSummary fingerprint format")
  func fingerprintFormat() {
    let s = MTPDeviceSummary(
      id: MTPDeviceID(raw: "fp"),
      manufacturer: "V",
      model: "M",
      vendorID: 0x04e8,
      productID: 0x6860,
      bus: 1,
      address: 1
    )
    #expect(s.fingerprint == "04e8:6860")
  }

  @Test("MTPDeviceSummary fingerprint with nil IDs")
  func fingerprintNil() {
    let s = MTPDeviceSummary(
      id: MTPDeviceID(raw: "nil"),
      manufacturer: "V",
      model: "M",
      vendorID: nil,
      productID: nil,
      bus: nil,
      address: nil
    )
    #expect(s.fingerprint == "unknown")
  }
}
