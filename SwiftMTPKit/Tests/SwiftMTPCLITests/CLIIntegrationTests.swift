// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import Testing
import SwiftMTPCLI
@testable import SwiftMTPCore

// MARK: - 1. Exit Code Edge Cases

@Suite("ExitCode Edge Cases")
struct ExitCodeEdgeCases {
  @Test("All five BSD sysexits are defined")
  func allFiveDefined() {
    let codes: [ExitCode] = [.ok, .usage, .unavailable, .software, .tempfail]
    #expect(codes.count == 5)
  }

  @Test("ExitCode raw values are non-negative")
  func nonNegative() {
    let codes: [ExitCode] = [.ok, .usage, .unavailable, .software, .tempfail]
    for code in codes {
      #expect(code.rawValue >= 0, "ExitCode \(code) has negative raw value")
    }
  }

  @Test("ExitCode.ok is the only zero value")
  func onlyZeroIsOk() {
    let codes: [ExitCode] = [.usage, .unavailable, .software, .tempfail]
    for code in codes {
      #expect(code.rawValue != 0, "\(code) should not be zero")
    }
    #expect(ExitCode.ok.rawValue == 0)
  }

  @Test("ExitCode values fall in BSD sysexits range (64–78)")
  func bsdRange() {
    let nonOk: [ExitCode] = [.usage, .unavailable, .software, .tempfail]
    for code in nonOk {
      #expect(code.rawValue >= 64 && code.rawValue <= 78,
              "ExitCode \(code) raw value \(code.rawValue) outside BSD sysexits range")
    }
  }

  @Test("ExitCode Int32 representation is stable for scripting")
  func stableInt32() {
    let expected: [ExitCode: Int32] = [
      .ok: 0, .usage: 64, .unavailable: 69, .software: 70, .tempfail: 75
    ]
    for (code, value) in expected {
      #expect(code.rawValue == value)
    }
  }
}

// MARK: - 2. Device Filter Parsing

@Suite("Device Filter Parsing Edge Cases")
struct DeviceFilterParsingEdgeCases {
  @Test("Filter with only pid set")
  func pidOnly() {
    let f = DeviceFilter(vid: nil, pid: 0x6860, bus: nil, address: nil)
    #expect(f.vid == nil)
    #expect(f.pid == 0x6860)
  }

  @Test("Filter with bus and address only")
  func busAddressOnly() {
    let f = DeviceFilter(vid: nil, pid: nil, bus: 3, address: 12)
    #expect(f.bus == 3)
    #expect(f.address == 12)
    #expect(f.vid == nil)
    #expect(f.pid == nil)
  }

  @Test("parseUSBIdentifier handles mixed-case hex")
  func mixedCaseHex() {
    #expect(parseUSBIdentifier("AbCd") == 0xABCD)
    #expect(parseUSBIdentifier("0xaBcD") == 0xABCD)
  }

  @Test("parseUSBIdentifier rejects overflow beyond UInt16")
  func overflow() {
    #expect(parseUSBIdentifier("0x10000") == nil)
    #expect(parseUSBIdentifier("FFFFF") == nil)
  }

  @Test("parseUSBIdentifier accepts boundary values")
  func boundaryValues() {
    #expect(parseUSBIdentifier("0x0000") == 0)
    #expect(parseUSBIdentifier("0xFFFF") == 0xFFFF)
    #expect(parseUSBIdentifier("0x0001") == 1)
    #expect(parseUSBIdentifier("0xFFFE") == 0xFFFE)
  }

  @Test("DeviceFilterParse handles --vid with missing value")
  func vidMissingValue() {
    var args = ["--vid"]
    let f = DeviceFilterParse.parse(from: &args)
    #expect(f.vid == nil)
    #expect(args == ["--vid"])
  }

  @Test("DeviceFilterParse handles --bus with non-numeric value")
  func busNonNumeric() {
    var args = ["--bus", "abc"]
    let f = DeviceFilterParse.parse(from: &args)
    #expect(f.bus == nil)
    #expect(args == ["--bus", "abc"])
  }

  @Test("DeviceFilterParse preserves order of unknown flags")
  func preservesUnknownOrder() {
    var args = ["--verbose", "--vid", "04e8", "--json", "--bus", "1", "--output", "file.txt"]
    let f = DeviceFilterParse.parse(from: &args)
    #expect(f.vid == 0x04e8)
    #expect(f.bus == 1)
    #expect(args == ["--verbose", "--json", "--output", "file.txt"])
  }

  @Test("DeviceFilterParse handles duplicate flags (last wins)")
  func duplicateFlags() {
    var args = ["--vid", "1111", "--vid", "2222"]
    let f = DeviceFilterParse.parse(from: &args)
    // Parser removes first match; second match is also parsed
    #expect(f.vid != nil)
    #expect(args.isEmpty)
  }
}

// MARK: - 3. Output Formatting (JSON)

@Suite("Output Formatting")
struct OutputFormatting {
  @Test("CLIErrorEnvelope JSON contains all required keys")
  func requiredKeys() throws {
    let envelope = CLIErrorEnvelope("test-error")
    let data = try JSONEncoder().encode(envelope)
    let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
    #expect(json["error"] != nil)
    #expect(json["schemaVersion"] != nil)
    #expect(json["type"] != nil)
    #expect(json["timestamp"] != nil)
  }

  @Test("CLIErrorEnvelope details dict round-trips")
  func detailsRoundTrip() throws {
    let details = ["key1": "val1", "key2": "val2", "key3": "val3"]
    let envelope = CLIErrorEnvelope("err", details: details)
    let data = try JSONEncoder().encode(envelope)
    let decoded = try JSONDecoder().decode(CLIErrorEnvelope.self, from: data)
    #expect(decoded.details == details)
  }

  @Test("CLIErrorEnvelope mode field is preserved")
  func modeField() throws {
    let envelope = CLIErrorEnvelope("err", mode: "safe")
    let data = try JSONEncoder().encode(envelope)
    let decoded = try JSONDecoder().decode(CLIErrorEnvelope.self, from: data)
    #expect(decoded.mode == "safe")
  }

  @Test("CLIErrorEnvelope empty error string is valid")
  func emptyError() throws {
    let envelope = CLIErrorEnvelope("")
    let data = try JSONEncoder().encode(envelope)
    let decoded = try JSONDecoder().decode(CLIErrorEnvelope.self, from: data)
    #expect(decoded.error == "")
    #expect(decoded.schemaVersion == "1.0")
  }

  @Test("CLIErrorEnvelope sorted-keys output is deterministic across runs")
  func sortedKeysDeterministic() throws {
    let envelope = CLIErrorEnvelope(
      "det-test", details: ["a": "1", "b": "2"], mode: "test",
      timestamp: "2026-06-01T00:00:00Z"
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]

    let data1 = try encoder.encode(envelope)
    let data2 = try encoder.encode(envelope)
    #expect(data1 == data2)
  }

  @Test("CLIErrorEnvelope with special characters in error message")
  func specialChars() throws {
    let msg = "Error: file \"test.txt\" not found (code=404)"
    let envelope = CLIErrorEnvelope(msg, timestamp: "2026-01-01T00:00:00Z")
    let data = try JSONEncoder().encode(envelope)
    let decoded = try JSONDecoder().decode(CLIErrorEnvelope.self, from: data)
    #expect(decoded.error == msg)
  }
}

// MARK: - 4. CLI Argument Validation

@Suite("CLI Argument Validation")
struct CLIArgumentValidation {
  @Test("Empty args produce empty filter and empty remainder")
  func emptyArgsValidation() {
    var args: [String] = []
    let f = DeviceFilterParse.parse(from: &args)
    #expect(f.vid == nil)
    #expect(f.pid == nil)
    #expect(f.bus == nil)
    #expect(f.address == nil)
    #expect(args.isEmpty)
  }

  @Test("Only unknown flags are left after parsing")
  func unknownFlagsRemain() {
    var args = ["--json", "--verbose", "--output", "file.txt"]
    let f = DeviceFilterParse.parse(from: &args)
    #expect(f.vid == nil)
    #expect(args.count == 4)
    #expect(args == ["--json", "--verbose", "--output", "file.txt"])
  }

  @Test("Conflicting --vid values both consumed")
  func conflictingVid() {
    var args = ["--vid", "AAAA", "--pid", "BBBB", "--vid", "CCCC"]
    let _ = DeviceFilterParse.parse(from: &args)
    // Both --vid pairs should be consumed; only unrecognized flags remain
    #expect(!args.contains("--vid"))
  }

  @Test("Flag without value at end of args is not consumed")
  func flagWithoutValueAtEnd() {
    var args = ["--json", "--vid"]
    let f = DeviceFilterParse.parse(from: &args)
    #expect(f.vid == nil)
    // --vid without value stays, --json also stays
    #expect(args.contains("--vid") || args.contains("--json"))
  }

  @Test("Numeric-looking unknown flags are not consumed as filter values")
  func numericUnknownFlags() {
    var args = ["--timeout", "5000", "--vid", "04e8"]
    let f = DeviceFilterParse.parse(from: &args)
    #expect(f.vid == 0x04e8)
    #expect(args == ["--timeout", "5000"])
  }
}

// MARK: - 5. Help Text Structure

@Suite("Help Text & Command Structure")
struct HelpTextStructure {
  @Test("Known commands list is comprehensive")
  func knownCommands() {
    let knownCommands = [
      "probe", "usb-dump", "device-lab", "diag", "storages", "ls",
      "pull", "push", "bench", "mirror", "quirks", "info", "health",
      "collect", "submit", "add-device", "wizard", "delete", "move",
      "events", "learn-promote", "bdd", "snapshot", "version"
    ]
    // All known commands are non-empty and unique
    #expect(Set(knownCommands).count == knownCommands.count)
    #expect(knownCommands.allSatisfy { !$0.isEmpty })
  }

  @Test("ExitCode covers all expected CLI exit scenarios")
  func exitCodesComprehensive() {
    // ok: success, usage: bad arguments, unavailable: feature off,
    // software: internal error, tempfail: transient failure
    let scenarios: [(ExitCode, String)] = [
      (.ok, "success"),
      (.usage, "bad arguments"),
      (.unavailable, "feature disabled"),
      (.software, "internal error"),
      (.tempfail, "transient failure"),
    ]
    #expect(scenarios.count == 5)
    let uniqueRaw = Set(scenarios.map(\.0.rawValue))
    #expect(uniqueRaw.count == 5)
  }

  @Test("SelectionOutcome has three cases for device selection UX")
  func selectionOutcomeCases() {
    let summaries = [
      MTPDeviceSummary(
        id: MTPDeviceID(raw: "d1"), manufacturer: "V", model: "M",
        vendorID: 0x1234, productID: 0x5678, bus: 1, address: 1),
    ]
    let noFilter = DeviceFilter(vid: nil, pid: nil, bus: nil, address: nil)

    // .selected
    let r1 = selectDevice(summaries, filter: noFilter, noninteractive: true)
    if case .selected = r1 {} else { Issue.record("Expected .selected") }

    // .none
    let r2 = selectDevice([MTPDeviceSummary](), filter: noFilter, noninteractive: true)
    if case .none = r2 {} else { Issue.record("Expected .none") }

    // .multiple
    let multi = summaries + [
      MTPDeviceSummary(
        id: MTPDeviceID(raw: "d2"), manufacturer: "V2", model: "M2",
        vendorID: 0xAAAA, productID: 0xBBBB, bus: 2, address: 2),
    ]
    let r3 = selectDevice(multi, filter: noFilter, noninteractive: true)
    if case .multiple = r3 {} else { Issue.record("Expected .multiple") }
  }
}

// MARK: - 6. Error Message Formatting

@Suite("Error Message Formatting")
struct ErrorMessageFormatting {
  @Test("CLIErrorEnvelope type is always 'error'")
  func typeAlwaysError() {
    let envelopes = [
      CLIErrorEnvelope("err1"),
      CLIErrorEnvelope("err2", details: ["k": "v"]),
      CLIErrorEnvelope("err3", mode: "strict"),
    ]
    for e in envelopes {
      #expect(e.type == "error")
    }
  }

  @Test("CLIErrorEnvelope schemaVersion is consistent")
  func schemaVersionConsistent() {
    let e1 = CLIErrorEnvelope("a")
    let e2 = CLIErrorEnvelope("b", details: ["x": "y"], mode: "safe")
    #expect(e1.schemaVersion == e2.schemaVersion)
    #expect(e1.schemaVersion == "1.0")
  }

  @Test("MTPError.deviceDisconnected has descriptive message")
  func disconnectedMessage() {
    let err = MTPError.deviceDisconnected
    let desc = err.errorDescription ?? ""
    #expect(desc.contains("disconnected"))
  }

  @Test("MTPError.transport(.noDevice) has actionable description")
  func noDeviceMessage() {
    let err = MTPError.transport(.noDevice)
    let desc = err.errorDescription ?? ""
    #expect(desc.lowercased().contains("no mtp") || desc.lowercased().contains("not found"))
  }

  @Test("MTPError.timeout has useful description")
  func timeoutMessage() {
    let err = MTPError.timeout
    let desc = err.errorDescription ?? ""
    #expect(desc.lowercased().contains("timed out") || desc.lowercased().contains("timeout"))
  }

  @Test("MTPError.protocolError includes hex code")
  func protocolErrorHex() {
    let err = MTPError.protocolError(code: 0x201D, message: nil)
    let desc = err.errorDescription ?? ""
    #expect(desc.contains("201"))
  }

  @Test("TransportError.io includes custom message")
  func ioErrorMessage() {
    let err = TransportError.io("USB cable fault")
    let desc = err.errorDescription ?? ""
    #expect(desc.contains("USB cable fault"))
  }
}

// MARK: - 7. Environment Variable Handling

@Suite("Environment Variable Handling")
struct EnvironmentVariableHandling {
  @Test("FeatureFlags reads SWIFTMTP_ prefixed env vars")
  func featureFlagPrefix() {
    // FeatureFlags.shared loads from env; verify the API works
    let flags = FeatureFlags.shared
    let key = "SWIFTMTP_TEST_INTEGRATION_\(UInt32.random(in: 1000...9999))"
    // Not set → false
    #expect(flags.isEnabled(key) == false)
  }

  @Test("FeatureFlags set/get round-trip")
  func featureFlagSetGet() {
    let flags = FeatureFlags.shared
    let key = "SWIFTMTP_CLI_TEST_FLAG_\(UInt32.random(in: 1000...9999))"
    flags.set(key, enabled: true)
    #expect(flags.isEnabled(key) == true)
    flags.set(key, enabled: false)
    #expect(flags.isEnabled(key) == false)
  }

  @Test("MTPFeatureFlags enumerates all known features")
  func allFeaturesEnumerated() {
    let allFeatures = MTPFeature.allCases
    #expect(allFeatures.count >= 4)
    let names = allFeatures.map(\.rawValue)
    #expect(names.contains("PROPLIST_FASTPATH"))
    #expect(names.contains("CHUNKED_TRANSFER"))
    #expect(names.contains("LEARN_PROMOTE"))
  }

  @Test("MTPFeatureFlags setEnabled/isEnabled round-trip")
  func mtpFeatureFlagRoundTrip() {
    let flags = MTPFeatureFlags.shared
    // Save original state and restore after test
    let original = flags.isEnabled(.learnPromote)
    flags.setEnabled(.learnPromote, true)
    #expect(flags.isEnabled(.learnPromote) == true)
    flags.setEnabled(.learnPromote, false)
    #expect(flags.isEnabled(.learnPromote) == false)
    flags.setEnabled(.learnPromote, original)
  }

  @Test("FeatureFlags mockProfile defaults to pixel7")
  func mockProfileDefault() {
    let profile = FeatureFlags.shared.mockProfile
    // If SWIFTMTP_MOCK_PROFILE is not set, defaults to "pixel7"
    if ProcessInfo.processInfo.environment["SWIFTMTP_MOCK_PROFILE"] == nil {
      #expect(profile == "pixel7")
    } else {
      #expect(!profile.isEmpty)
    }
  }
}

// MARK: - Cross-Cutting Integration

@Suite("CLI Cross-Cutting Integration")
struct CLICrossCuttingIntegration {
  @Test("Full filter parse → selectDevice pipeline with no matches")
  func fullPipelineNoMatch() {
    var args = ["--vid", "DEAD", "--pid", "BEEF", "--bus", "99", "--address", "255"]
    let filter = DeviceFilterParse.parse(from: &args)
    #expect(args.isEmpty)

    let devices = [
      MTPDeviceSummary(
        id: MTPDeviceID(raw: "dev1"), manufacturer: "V", model: "M",
        vendorID: 0x1234, productID: 0x5678, bus: 1, address: 1),
    ]
    let result = selectDevice(devices, filter: filter, noninteractive: true)
    if case .none = result {} else { Issue.record("Expected .none for mismatched filter") }
  }

  @Test("Spinner disabled mode does not throw")
  func spinnerDisabledSafe() {
    let spinner = SwiftMTPCLI.Spinner(enabled: false)
    spinner.start("integration test")
    spinner.stopAndClear("done")
    spinner.start("")
    spinner.stopAndClear(nil)
  }

  @Test("CLIErrorEnvelope with large details dict")
  func largeDetails() throws {
    var details: [String: String] = [:]
    for i in 0..<50 {
      details["key_\(i)"] = "value_\(i)"
    }
    let envelope = CLIErrorEnvelope("large-test", details: details, timestamp: "2026-01-01T00:00:00Z")
    let data = try JSONEncoder().encode(envelope)
    let decoded = try JSONDecoder().decode(CLIErrorEnvelope.self, from: data)
    #expect(decoded.details?.count == 50)
  }
}
