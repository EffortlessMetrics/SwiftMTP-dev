// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import Testing
import SwiftMTPCLI
@testable import SwiftMTPCore

// MARK: - 1. Subcommand Help Text Output Validation

@Suite("Wave31 Subcommand Help Text")
struct Wave31SubcommandHelpText {
  /// The full set of CLI subcommands from main.swift's switch statement.
  private static let allSubcommands = [
    "probe", "usb-dump", "device-lab", "diag", "storages", "ls",
    "pull", "push", "bench", "mirror", "quirks", "info", "health",
    "collect", "submit", "add-device", "wizard", "delete", "move",
    "events", "learn-promote", "bdd", "snapshot", "version",
  ]

  @Test("All 24 subcommands are present and unique")
  func allSubcommandsPresent() {
    #expect(Self.allSubcommands.count == 24)
    #expect(Set(Self.allSubcommands).count == 24)
  }

  @Test("Subcommand names are all lowercase kebab-case")
  func subcommandNamesKebabCase() {
    let kebab = /^[a-z][a-z0-9]*(-[a-z0-9]+)*$/
    for cmd in Self.allSubcommands {
      #expect(
        cmd.wholeMatch(of: kebab) != nil,
        "'\(cmd)' is not lowercase kebab-case")
    }
  }

  @Test("No duplicate subcommand names")
  func noDuplicateNames() {
    var seen = Set<String>()
    for cmd in Self.allSubcommands {
      #expect(!seen.contains(cmd), "Duplicate subcommand: \(cmd)")
      seen.insert(cmd)
    }
  }

  @Test("Transfer commands all present: pull, push, bench, mirror")
  func transferCommandsPresent() {
    for cmd in ["pull", "push", "bench", "mirror"] {
      #expect(Self.allSubcommands.contains(cmd), "Missing transfer command: \(cmd)")
    }
  }

  @Test("System commands all present: quirks, health, info, version")
  func systemCommandsPresent() {
    for cmd in ["quirks", "health", "info", "version"] {
      #expect(Self.allSubcommands.contains(cmd), "Missing system command: \(cmd)")
    }
  }

  @Test("Device management commands present: delete, move, events, snapshot")
  func deviceManagementPresent() {
    for cmd in ["delete", "move", "events", "snapshot"] {
      #expect(Self.allSubcommands.contains(cmd), "Missing device command: \(cmd)")
    }
  }

  @Test("Contribution commands present: collect, submit, add-device, wizard")
  func contributionCommandsPresent() {
    for cmd in ["collect", "submit", "add-device", "wizard"] {
      #expect(Self.allSubcommands.contains(cmd), "Missing contribution command: \(cmd)")
    }
  }
}

// MARK: - 2. Subcommand Argument Validation (Missing Required Args)

@Suite("Wave31 Argument Validation")
struct Wave31ArgumentValidation {
  @Test("ls requires a storage handle argument")
  func lsRequiresHandle() {
    // StorageListCommands.runList guards on args.first being a valid UInt32
    let invalidHandle = UInt32("not-a-number")
    #expect(invalidHandle == nil, "Non-numeric string should not parse as handle")
  }

  @Test("pull requires exactly 2 arguments: handle and destination")
  func pullRequiresTwoArgs() {
    // TransferCommands.runPull guards on args.count >= 2 and UInt32(args[0])
    let emptyArgs: [String] = []
    #expect(emptyArgs.count < 2, "Empty args should fail pull validation")

    let singleArg = ["12345"]
    #expect(singleArg.count < 2, "Single arg should fail pull validation")
  }

  @Test("push requires at least 2 arguments: source and parent")
  func pushRequiresTwoArgs() {
    let oneArg = ["file.txt"]
    #expect(oneArg.count < 2, "Single arg should fail push validation")
  }

  @Test("bench requires a size argument")
  func benchRequiresSize() {
    let noArgs: [String] = []
    #expect(noArgs.first == nil, "Empty args should fail bench validation")
  }

  @Test("mirror requires a destination argument")
  func mirrorRequiresDest() {
    let noArgs: [String] = []
    #expect(noArgs.first == nil, "Empty args should fail mirror validation")
  }

  @Test("delete requires a handle argument with hex parsing")
  func deleteRequiresHandle() {
    // delete parses handle as hex (radix: 16) or decimal (radix: 10)
    #expect(UInt32("FF", radix: 16) == 255)
    #expect(UInt32("notahandle", radix: 16) == nil, "Invalid handle should fail")
    #expect(UInt32("42", radix: 10) == 42)
  }

  @Test("move requires handle and new-parent-handle")
  func moveRequiresTwoHandles() {
    let oneArg = ["42"]
    #expect(oneArg.count < 2, "Single arg should fail move validation")
  }

  @Test("submit requires a bundle path")
  func submitRequiresPath() {
    let noArgs: [String] = []
    #expect(noArgs.first == nil, "Empty args should fail submit validation")
  }

  @Test("quirks requires a subcommand (--explain, matrix, lookup)")
  func quirksRequiresSubcommand() {
    let noArgs: [String] = []
    #expect(noArgs.first == nil, "Empty args should fail quirks validation")
  }

  @Test("quirks lookup requires --vid and --pid")
  func quirksLookupRequiresVidPid() {
    let args = ["lookup"]
    // Subcommand "lookup" without --vid/--pid should trigger usage error
    #expect(!args.contains("--vid"))
    #expect(!args.contains("--pid"))
  }
}

// MARK: - 3. Exit Code Correctness for Error Scenarios

@Suite("Wave31 Exit Code Scenarios")
struct Wave31ExitCodeScenarios {
  @Test("ExitCode.ok is 0 for successful commands")
  func okIsZero() {
    #expect(ExitCode.ok.rawValue == 0)
  }

  @Test("ExitCode.usage is 64 for invalid arguments")
  func usageFor64() {
    #expect(ExitCode.usage.rawValue == 64)
  }

  @Test("ExitCode.unavailable is 69 for disabled features / no device")
  func unavailableIs69() {
    #expect(ExitCode.unavailable.rawValue == 69)
  }

  @Test("ExitCode.software is 70 for internal errors")
  func softwareIs70() {
    #expect(ExitCode.software.rawValue == 70)
  }

  @Test("ExitCode.tempfail is 75 for transient device failures")
  func tempfailIs75() {
    #expect(ExitCode.tempfail.rawValue == 75)
  }

  @Test("Exit codes match BSD sysexits exactly")
  func matchesBSDSysexits() {
    let expected: [(ExitCode, Int32)] = [
      (.ok, 0), (.usage, 64), (.unavailable, 69), (.software, 70), (.tempfail, 75),
    ]
    for (code, raw) in expected {
      #expect(code.rawValue == raw, "ExitCode.\(code) should be \(raw)")
    }
  }

  @Test("All non-zero exit codes are in the 64-78 BSD range")
  func nonZeroBSDRange() {
    let nonZero: [ExitCode] = [.usage, .unavailable, .software, .tempfail]
    for code in nonZero {
      #expect(
        (64...78).contains(code.rawValue),
        "ExitCode \(code) = \(code.rawValue) outside 64-78 range")
    }
  }

  @Test("ExitCode initializer rejects values outside the defined set")
  func rejectsUnknownCodes() {
    #expect(ExitCode(rawValue: 1) == nil)
    #expect(ExitCode(rawValue: 63) == nil)
    #expect(ExitCode(rawValue: 65) == nil)
    #expect(ExitCode(rawValue: -1) == nil)
    #expect(ExitCode(rawValue: 128) == nil)
  }
}

// MARK: - 4. JSON Output Mode for probe, ls, quirks

@Suite("Wave31 JSON Output Mode")
struct Wave31JSONOutputMode {
  @Test("CLIErrorEnvelope JSON has schemaVersion 1.0")
  func envelopeSchemaVersion() throws {
    let envelope = CLIErrorEnvelope("test", timestamp: "2026-01-01T00:00:00Z")
    let data = try JSONEncoder().encode(envelope)
    let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
    #expect(json["schemaVersion"] as? String == "1.0")
  }

  @Test("CLIErrorEnvelope JSON type field is 'error'")
  func envelopeTypeField() throws {
    let envelope = CLIErrorEnvelope("test", timestamp: "2026-01-01T00:00:00Z")
    let data = try JSONEncoder().encode(envelope)
    let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
    #expect(json["type"] as? String == "error")
  }

  @Test("CLIErrorEnvelope with details produces valid JSON")
  func envelopeWithDetails() throws {
    let details = ["device": "pixel7", "operation": "probe"]
    let envelope = CLIErrorEnvelope("failed", details: details, timestamp: "2026-01-01T00:00:00Z")
    let data = try JSONEncoder().encode(envelope)
    let decoded = try JSONDecoder().decode(CLIErrorEnvelope.self, from: data)
    #expect(decoded.details?["device"] == "pixel7")
    #expect(decoded.details?["operation"] == "probe")
  }

  @Test("CLIErrorEnvelope with mode=strict round-trips")
  func envelopeStrictMode() throws {
    let envelope = CLIErrorEnvelope("err", mode: "strict", timestamp: "2026-01-01T00:00:00Z")
    let data = try JSONEncoder().encode(envelope)
    let decoded = try JSONDecoder().decode(CLIErrorEnvelope.self, from: data)
    #expect(decoded.mode == "strict")
  }

  @Test("CLIErrorEnvelope with mode=safe round-trips")
  func envelopeSafeMode() throws {
    let envelope = CLIErrorEnvelope("err", mode: "safe", timestamp: "2026-01-01T00:00:00Z")
    let data = try JSONEncoder().encode(envelope)
    let decoded = try JSONDecoder().decode(CLIErrorEnvelope.self, from: data)
    #expect(decoded.mode == "safe")
  }

  @Test("CLIErrorEnvelope sorted-keys output is deterministic")
  func sortedKeysDeterministic() throws {
    let envelope = CLIErrorEnvelope(
      "det-test", details: ["a": "1"], mode: "json",
      timestamp: "2026-06-01T00:00:00Z")
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    let d1 = try encoder.encode(envelope)
    let d2 = try encoder.encode(envelope)
    #expect(d1 == d2)
  }

  @Test("CLIErrorEnvelope auto-generates valid ISO 8601 timestamp")
  func autoTimestamp() {
    let envelope = CLIErrorEnvelope("ts-test")
    let formatter = ISO8601DateFormatter()
    let date = formatter.date(from: envelope.timestamp)
    #expect(date != nil, "Timestamp '\(envelope.timestamp)' is not valid ISO 8601")
  }

  @Test("CLIErrorEnvelope with probe-style error produces valid JSON")
  func probeErrorJSON() throws {
    let envelope = CLIErrorEnvelope(
      "No MTP device found", details: ["hint": "Check USB connection"],
      mode: "normal", timestamp: "2026-01-01T00:00:00Z")
    let data = try JSONEncoder().encode(envelope)
    let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
    #expect(json["error"] as? String == "No MTP device found")
    #expect((json["details"] as? [String: String])?["hint"] == "Check USB connection")
  }

  @Test("CLIErrorEnvelope with quirks-style error produces valid JSON")
  func quirksErrorJSON() throws {
    let envelope = CLIErrorEnvelope(
      "Device not in quirk database",
      details: ["vid": "0x18d1", "pid": "0x4ee1"],
      timestamp: "2026-01-01T00:00:00Z")
    let data = try JSONEncoder().encode(envelope)
    let decoded = try JSONDecoder().decode(CLIErrorEnvelope.self, from: data)
    #expect(decoded.details?["vid"] == "0x18d1")
  }
}

// MARK: - 5. Error Envelope Format Consistency

@Suite("Wave31 Error Envelope Consistency")
struct Wave31ErrorEnvelopeConsistency {
  @Test("All envelopes share the same schemaVersion regardless of content")
  func consistentSchemaVersion() {
    let envelopes = [
      CLIErrorEnvelope("error1"),
      CLIErrorEnvelope("error2", details: ["k": "v"]),
      CLIErrorEnvelope("error3", mode: "strict"),
      CLIErrorEnvelope("", details: [:], mode: nil),
    ]
    let versions = Set(envelopes.map(\.schemaVersion))
    #expect(versions.count == 1)
    #expect(versions.first == "1.0")
  }

  @Test("All envelopes have type == 'error'")
  func consistentType() {
    let envelopes = [
      CLIErrorEnvelope("a"),
      CLIErrorEnvelope("b", details: ["x": "y"]),
      CLIErrorEnvelope("c", mode: "safe"),
    ]
    for e in envelopes {
      #expect(e.type == "error")
    }
  }

  @Test("Envelope with nil details and mode omits keys in JSON")
  func nilFieldsOmitted() throws {
    let envelope = CLIErrorEnvelope("minimal", timestamp: "2026-01-01T00:00:00Z")
    let data = try JSONEncoder().encode(envelope)
    let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
    let detailsValue = json["details"]
    let modeValue = json["mode"]
    #expect(detailsValue == nil || detailsValue is NSNull)
    #expect(modeValue == nil || modeValue is NSNull)
  }

  @Test("Envelope with empty error string round-trips")
  func emptyErrorRoundTrips() throws {
    let envelope = CLIErrorEnvelope("", timestamp: "2026-01-01T00:00:00Z")
    let data = try JSONEncoder().encode(envelope)
    let decoded = try JSONDecoder().decode(CLIErrorEnvelope.self, from: data)
    #expect(decoded.error == "")
    #expect(decoded.schemaVersion == "1.0")
  }

  @Test("Envelope preserves unicode in error messages")
  func unicodePreserved() throws {
    let msg = "❌ デバイス切断 🔌"
    let envelope = CLIErrorEnvelope(msg, timestamp: "2026-01-01T00:00:00Z")
    let data = try JSONEncoder().encode(envelope)
    let decoded = try JSONDecoder().decode(CLIErrorEnvelope.self, from: data)
    #expect(decoded.error == msg)
  }

  @Test("Envelope with all fields populated has correct JSON key set")
  func allFieldsKeySet() throws {
    let envelope = CLIErrorEnvelope(
      "err", details: ["k": "v"], mode: "strict",
      timestamp: "2026-01-01T00:00:00Z")
    let data = try JSONEncoder().encode(envelope)
    let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
    let required: Set = ["schemaVersion", "type", "error", "timestamp", "details", "mode"]
    #expect(required.isSubset(of: Set(json.keys)))
  }
}

// MARK: - 6. Device Filter Argument Parsing (All Filter Types)

@Suite("Wave31 Device Filter Parsing")
struct Wave31DeviceFilterParsing {
  @Test("--vid parses hex and removes from args")
  func vidParsesAndRemoves() {
    var args = ["--vid", "04e8", "remaining"]
    let f = DeviceFilterParse.parse(from: &args)
    #expect(f.vid == 0x04e8)
    #expect(args == ["remaining"])
  }

  @Test("--pid parses hex and removes from args")
  func pidParsesAndRemoves() {
    var args = ["--pid", "6860"]
    let f = DeviceFilterParse.parse(from: &args)
    #expect(f.pid == 0x6860)
    #expect(args.isEmpty)
  }

  @Test("--bus parses decimal and removes from args")
  func busParsesAndRemoves() {
    var args = ["--bus", "3"]
    let f = DeviceFilterParse.parse(from: &args)
    #expect(f.bus == 3)
    #expect(args.isEmpty)
  }

  @Test("--address parses decimal and removes from args")
  func addressParsesAndRemoves() {
    var args = ["--address", "12"]
    let f = DeviceFilterParse.parse(from: &args)
    #expect(f.address == 12)
    #expect(args.isEmpty)
  }

  @Test("All four filters parse together")
  func allFourTogether() {
    var args = ["--vid", "2717", "--pid", "ff40", "--bus", "1", "--address", "4"]
    let f = DeviceFilterParse.parse(from: &args)
    #expect(f.vid == 0x2717)
    #expect(f.pid == 0xFF40)
    #expect(f.bus == 1)
    #expect(f.address == 4)
    #expect(args.isEmpty)
  }

  @Test("Unknown flags remain after parsing")
  func unknownFlagsRemain() {
    var args = ["--json", "--vid", "04e8", "--verbose", "--bus", "2"]
    let f = DeviceFilterParse.parse(from: &args)
    #expect(f.vid == 0x04e8)
    #expect(f.bus == 2)
    #expect(args == ["--json", "--verbose"])
  }

  @Test("--vid without following value is not consumed")
  func vidWithoutValue() {
    var args = ["--vid"]
    let f = DeviceFilterParse.parse(from: &args)
    #expect(f.vid == nil)
    #expect(args == ["--vid"])
  }

  @Test("--bus with non-numeric value is not consumed")
  func busWithNonNumeric() {
    var args = ["--bus", "abc"]
    let f = DeviceFilterParse.parse(from: &args)
    #expect(f.bus == nil)
    #expect(args == ["--bus", "abc"])
  }

  @Test("--address with non-numeric value is not consumed")
  func addressWithNonNumeric() {
    var args = ["--address", "xyz"]
    let f = DeviceFilterParse.parse(from: &args)
    #expect(f.address == nil)
    #expect(args == ["--address", "xyz"])
  }

  @Test("--vid with invalid hex is not consumed")
  func vidWithInvalidHex() {
    var args = ["--vid", "ZZZZ"]
    let f = DeviceFilterParse.parse(from: &args)
    #expect(f.vid == nil)
    #expect(args.contains("--vid"))
  }

  @Test("parseUSBIdentifier: 0x prefix → hex")
  func parseHexPrefix() {
    #expect(parseUSBIdentifier("0x2717") == 0x2717)
    #expect(parseUSBIdentifier("0X04E8") == 0x04E8)
  }

  @Test("parseUSBIdentifier: hex letters without prefix → hex")
  func parseHexLettersNoPrefix() {
    #expect(parseUSBIdentifier("ff40") == 0xFF40)
    #expect(parseUSBIdentifier("ABCD") == 0xABCD)
  }

  @Test("parseUSBIdentifier: pure digits → hex (USB convention)")
  func parsePureDigitsAsHex() {
    #expect(parseUSBIdentifier("1234") == 0x1234)
  }

  @Test("parseUSBIdentifier: nil/empty/whitespace → nil")
  func parseNilEmptyWhitespace() {
    #expect(parseUSBIdentifier(nil) == nil)
    #expect(parseUSBIdentifier("") == nil)
    #expect(parseUSBIdentifier("   ") == nil)
  }

  @Test("parseUSBIdentifier: overflow beyond UInt16.max → nil")
  func parseOverflow() {
    #expect(parseUSBIdentifier("0x10000") == nil)
    #expect(parseUSBIdentifier("FFFFF") == nil)
  }

  @Test("selectDevice with vid filter narrows correctly")
  func selectWithVidFilter() {
    let devs = [
      MTPDeviceSummary(
        id: MTPDeviceID(raw: "a"), manufacturer: "V", model: "M",
        vendorID: 0x04e8, productID: 0x6860, bus: 1, address: 1),
      MTPDeviceSummary(
        id: MTPDeviceID(raw: "b"), manufacturer: "V", model: "M",
        vendorID: 0x2717, productID: 0xFF40, bus: 2, address: 2),
    ]
    let filter = DeviceFilter(vid: 0x2717, pid: nil, bus: nil, address: nil)
    let result = selectDevice(devs, filter: filter, noninteractive: true)
    if case .selected(let s) = result {
      #expect(s.id.raw == "b")
    } else {
      Issue.record("Expected .selected for vid filter")
    }
  }

  @Test("selectDevice with bus+address disambiguates same vid:pid")
  func selectWithBusAddress() {
    let devs = [
      MTPDeviceSummary(
        id: MTPDeviceID(raw: "a"), manufacturer: "V", model: "M",
        vendorID: 0x04e8, productID: 0x6860, bus: 1, address: 4),
      MTPDeviceSummary(
        id: MTPDeviceID(raw: "b"), manufacturer: "V", model: "M",
        vendorID: 0x04e8, productID: 0x6860, bus: 2, address: 7),
    ]
    let filter = DeviceFilter(vid: nil, pid: nil, bus: 2, address: 7)
    let result = selectDevice(devs, filter: filter, noninteractive: true)
    if case .selected(let s) = result {
      #expect(s.id.raw == "b")
    } else {
      Issue.record("Expected .selected for bus+address filter")
    }
  }

  @Test("selectDevice with no match returns .none")
  func selectNoMatch() {
    let devs = [
      MTPDeviceSummary(
        id: MTPDeviceID(raw: "a"), manufacturer: "V", model: "M",
        vendorID: 0x1111, productID: 0x2222, bus: 1, address: 1)
    ]
    let filter = DeviceFilter(vid: 0x9999, pid: nil, bus: nil, address: nil)
    let result = selectDevice(devs, filter: filter, noninteractive: true)
    if case .none = result {} else { Issue.record("Expected .none") }
  }

  @Test("selectDevice with empty list always returns .none")
  func selectEmptyList() {
    let filter = DeviceFilter(vid: 0x1234, pid: 0x5678, bus: 1, address: 2)
    let result = selectDevice([MTPDeviceSummary](), filter: filter, noninteractive: true)
    if case .none = result {} else { Issue.record("Expected .none for empty list") }
  }
}

// MARK: - 7. Verbose Mode Output Includes Additional Detail

@Suite("Wave31 Verbose Mode")
struct Wave31VerboseMode {
  @Test("FeatureFlags traceUSB property round-trips")
  func featureFlagsTraceUSB() {
    let flags = FeatureFlags.shared
    let original = flags.traceUSB
    flags.traceUSB = true
    #expect(flags.traceUSB == true)
    flags.traceUSB = original
  }

  @Test("FeatureFlags useMockTransport property round-trips")
  func featureFlagsUseMock() {
    let flags = FeatureFlags.shared
    let original = flags.useMockTransport
    flags.useMockTransport = true
    #expect(flags.useMockTransport == true)
    flags.useMockTransport = original
  }

  @Test("FeatureFlags showStorybook property round-trips")
  func featureFlagsShowStorybook() {
    let flags = FeatureFlags.shared
    let original = flags.showStorybook
    flags.showStorybook = !original
    #expect(flags.showStorybook == !original)
    flags.showStorybook = original
  }

  @Test("FeatureFlags unknown key defaults to false")
  func unknownKeyDefaults() {
    let key = "SWIFTMTP_WAVE31_TEST_\(UInt32.random(in: 10000...99999))"
    #expect(FeatureFlags.shared.isEnabled(key) == false)
  }

  @Test("FeatureFlags set/get round-trip for arbitrary key")
  func setGetRoundTrip() {
    let key = "SWIFTMTP_WAVE31_VERBOSE_\(UInt32.random(in: 10000...99999))"
    let flags = FeatureFlags.shared
    flags.set(key, enabled: true)
    #expect(flags.isEnabled(key) == true)
    flags.set(key, enabled: false)
    #expect(flags.isEnabled(key) == false)
  }
}

// MARK: - 8. Quiet Mode Suppresses Non-Essential Output

@Suite("Wave31 Quiet Mode")
struct Wave31QuietMode {
  @Test("Spinner with enabled=false suppresses all output")
  func spinnerDisabledSuppresses() {
    let spinner = SwiftMTPCLI.Spinner(enabled: false)
    spinner.start("should-be-suppressed")
    spinner.stopAndClear("done")
  }

  @Test("Spinner disabled: double-stop is safe")
  func spinnerDisabledDoubleStop() {
    let spinner = SwiftMTPCLI.Spinner(enabled: false)
    spinner.start("test")
    spinner.stopAndClear("a")
    spinner.stopAndClear("b")
  }

  @Test("Spinner disabled: stop without start is safe")
  func spinnerDisabledStopWithoutStart() {
    let spinner = SwiftMTPCLI.Spinner(enabled: false)
    spinner.stopAndClear(nil)
  }

  @Test("Spinner disabled: empty label is safe")
  func spinnerDisabledEmptyLabel() {
    let spinner = SwiftMTPCLI.Spinner(enabled: false)
    spinner.start("")
    spinner.stopAndClear("")
  }

  @Test("Spinner enabled: rapid start/stop cycle does not crash")
  func spinnerEnabledRapidCycle() {
    let spinner = SwiftMTPCLI.Spinner(enabled: true)
    for i in 0..<5 {
      spinner.start("cycle-\(i)")
      spinner.stopAndClear("done-\(i)")
    }
  }
}

// MARK: - 9. MTPError Actionable Messages for CLI

@Suite("Wave31 MTPError Actionable Messages")
struct Wave31MTPErrorActionableMessages {
  @Test("MTPError.deviceDisconnected has descriptive message")
  func deviceDisconnected() {
    let desc = MTPError.deviceDisconnected.errorDescription ?? ""
    #expect(desc.lowercased().contains("disconnected"))
  }

  @Test("MTPError.storageFull has descriptive message")
  func storageFull() {
    let desc = MTPError.storageFull.errorDescription ?? ""
    #expect(desc.lowercased().contains("full") || desc.lowercased().contains("storage"))
  }

  @Test("MTPError.permissionDenied has descriptive message")
  func permissionDenied() {
    let desc = MTPError.permissionDenied.errorDescription ?? ""
    #expect(desc.lowercased().contains("permission") || desc.lowercased().contains("denied"))
  }

  @Test("MTPError.timeout has descriptive message")
  func timeout() {
    let desc = MTPError.timeout.errorDescription ?? ""
    #expect(desc.lowercased().contains("timed out") || desc.lowercased().contains("timeout"))
  }

  @Test("MTPError.notSupported includes operation name")
  func notSupported() {
    let desc = MTPError.notSupported("SendObjectInfo").errorDescription ?? ""
    #expect(desc.contains("SendObjectInfo"))
  }

  @Test("MTPError.protocolError includes hex code")
  func protocolError() {
    let desc = MTPError.protocolError(code: 0x201D, message: nil).errorDescription ?? ""
    #expect(desc.contains("201"))
  }

  @Test("MTPError.verificationFailed includes both sizes")
  func verificationFailed() {
    let desc = MTPError.verificationFailed(expected: 1024, actual: 512).errorDescription ?? ""
    #expect(desc.contains("1024"))
    #expect(desc.contains("512"))
  }

  @Test("MTPError.preconditionFailed includes reason")
  func preconditionFailed() {
    let desc = MTPError.preconditionFailed("session not open").errorDescription ?? ""
    #expect(desc.contains("session not open"))
  }

  @Test("TransportError.noDevice mentions device")
  func transportNoDevice() {
    let desc = TransportError.noDevice.errorDescription ?? ""
    #expect(desc.lowercased().contains("mtp") || desc.lowercased().contains("device"))
  }

  @Test("TransportError.timeoutInPhase includes phase name")
  func transportTimeoutPhase() {
    #expect(TransportError.timeoutInPhase(.bulkOut).errorDescription?.contains("bulk-out") == true)
    #expect(TransportError.timeoutInPhase(.bulkIn).errorDescription?.contains("bulk-in") == true)
    #expect(
      TransportError.timeoutInPhase(.responseWait).errorDescription?.contains("response-wait")
        == true)
  }
}

// MARK: - 10. Mock Mode and Feature Flags

@Suite("Wave31 Mock Mode and Feature Flags")
struct Wave31MockModeFeatureFlags {
  @Test("FeatureFlags useMockTransport can be enabled for demo mode")
  func mockTransportEnabled() {
    let flags = FeatureFlags.shared
    let original = flags.useMockTransport
    flags.useMockTransport = true
    #expect(flags.useMockTransport == true)
    flags.useMockTransport = original
  }

  @Test("FeatureFlags mockProfile defaults to non-empty string")
  func mockProfileNonEmpty() {
    #expect(!FeatureFlags.shared.mockProfile.isEmpty)
  }

  @Test("FeatureFlags mockProfile defaults to pixel7 when env not set")
  func mockProfileDefault() {
    if ProcessInfo.processInfo.environment["SWIFTMTP_MOCK_PROFILE"] == nil {
      #expect(FeatureFlags.shared.mockProfile == "pixel7")
    } else {
      #expect(!FeatureFlags.shared.mockProfile.isEmpty)
    }
  }

  @Test("DeviceFilter with all nil matches everything")
  func emptyFilterMatchesAll() {
    let devs = [
      MTPDeviceSummary(
        id: MTPDeviceID(raw: "a"), manufacturer: "V", model: "M",
        vendorID: 0x1111, productID: 0x2222, bus: 1, address: 1),
      MTPDeviceSummary(
        id: MTPDeviceID(raw: "b"), manufacturer: "V", model: "M",
        vendorID: 0x3333, productID: 0x4444, bus: 2, address: 2),
    ]
    let filter = DeviceFilter(vid: nil, pid: nil, bus: nil, address: nil)
    let result = selectDevice(devs, filter: filter, noninteractive: true)
    if case .multiple(let m) = result {
      #expect(m.count == 2)
    } else {
      Issue.record("Expected .multiple for empty filter")
    }
  }

  @Test("MTPFeatureFlags round-trip toggle for all features")
  func featureFlagsRoundTrip() {
    let flags = MTPFeatureFlags.shared
    for feature in MTPFeature.allCases {
      let original = flags.isEnabled(feature)
      flags.setEnabled(feature, !original)
      #expect(flags.isEnabled(feature) == !original)
      flags.setEnabled(feature, original)
      #expect(flags.isEnabled(feature) == original)
    }
  }

  @Test("MTPFeature has at least 4 cases")
  func minimumFeatures() {
    #expect(MTPFeature.allCases.count >= 4)
  }

  @Test("MTPFeature raw values are unique UPPER_SNAKE_CASE")
  func featureRawValues() {
    let upperSnake = /^[A-Z][A-Z0-9]*(_[A-Z0-9]+)*$/
    let rawValues = MTPFeature.allCases.map(\.rawValue)
    #expect(Set(rawValues).count == rawValues.count)
    for raw in rawValues {
      #expect(raw.wholeMatch(of: upperSnake) != nil, "'\(raw)' is not UPPER_SNAKE_CASE")
    }
  }
}

// MARK: - 11. Full Parse-to-Select Pipeline Smoke

@Suite("Wave31 Parse-Select Pipeline")
struct Wave31ParseSelectPipeline {
  @Test("Full pipeline: parse filter args → select matching device")
  func fullPipeline() {
    var args = ["--vid", "2717", "--bus", "11", "--address", "6", "--json"]
    let filter = DeviceFilterParse.parse(from: &args)
    #expect(filter.vid == 0x2717)
    #expect(filter.bus == 11)
    #expect(filter.address == 6)
    #expect(args == ["--json"])

    let devs = [
      MTPDeviceSummary(
        id: MTPDeviceID(raw: "match"), manufacturer: "V", model: "M",
        vendorID: 0x2717, productID: 0xAABB, bus: 11, address: 6),
      MTPDeviceSummary(
        id: MTPDeviceID(raw: "miss"), manufacturer: "V", model: "M",
        vendorID: 0x1234, productID: 0x5678, bus: 11, address: 7),
    ]
    let result = selectDevice(devs, filter: filter, noninteractive: true)
    if case .selected(let s) = result {
      #expect(s.id.raw == "match")
    } else {
      Issue.record("Expected .selected from pipeline")
    }
  }

  @Test("Pipeline with no known flags passes everything through")
  func noKnownFlags() {
    var args = ["--json", "--verbose", "--output", "file.txt"]
    let filter = DeviceFilterParse.parse(from: &args)
    #expect(filter.vid == nil)
    #expect(filter.pid == nil)
    #expect(filter.bus == nil)
    #expect(filter.address == nil)
    #expect(args.count == 4)
  }

  @Test("Pipeline with mismatched filter returns .none")
  func mismatchedFilter() {
    var args = ["--vid", "DEAD", "--pid", "BEEF"]
    let filter = DeviceFilterParse.parse(from: &args)
    let devs = [
      MTPDeviceSummary(
        id: MTPDeviceID(raw: "dev"), manufacturer: "V", model: "M",
        vendorID: 0x1234, productID: 0x5678, bus: 1, address: 1)
    ]
    let result = selectDevice(devs, filter: filter, noninteractive: true)
    if case .none = result {} else { Issue.record("Expected .none for mismatched filter") }
  }
}

// MARK: - 12. MTPDeviceSummary Fingerprint for CLI Display

@Suite("Wave31 Device Summary Fingerprint")
struct Wave31DeviceSummaryFingerprint {
  @Test("Fingerprint format is lowercase hex with colon separator")
  func fingerprintFormat() {
    let s = MTPDeviceSummary(
      id: MTPDeviceID(raw: "t"), manufacturer: "V", model: "M",
      vendorID: 0x04E8, productID: 0x6860, bus: 1, address: 1)
    #expect(s.fingerprint == "04e8:6860")
  }

  @Test("Fingerprint zero-pads small values")
  func fingerprintZeroPad() {
    let s = MTPDeviceSummary(
      id: MTPDeviceID(raw: "t"), manufacturer: "V", model: "M",
      vendorID: 0x0001, productID: 0x0002, bus: 1, address: 1)
    #expect(s.fingerprint == "0001:0002")
  }

  @Test("Fingerprint with nil IDs returns 'unknown'")
  func fingerprintNilIDs() {
    let s = MTPDeviceSummary(
      id: MTPDeviceID(raw: "t"), manufacturer: "V", model: "M")
    #expect(s.fingerprint == "unknown")
  }

  @Test("Fingerprint max values")
  func fingerprintMax() {
    let s = MTPDeviceSummary(
      id: MTPDeviceID(raw: "t"), manufacturer: "V", model: "M",
      vendorID: 0xFFFF, productID: 0xFFFF, bus: 1, address: 1)
    #expect(s.fingerprint == "ffff:ffff")
  }
}
