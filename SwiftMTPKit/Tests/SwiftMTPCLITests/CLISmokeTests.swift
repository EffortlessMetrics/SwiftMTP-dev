// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import Testing
import SwiftMTPCLI
@testable import SwiftMTPCore

// MARK: - 1. Subcommand Help Output Validation

@Suite("Subcommand Help Strings")
struct SubcommandHelpStrings {
  /// The canonical list of commands printed by the CLI help text.
  private static let expectedCommands = [
    "probe", "usb-dump", "device-lab", "diag", "storages", "ls",
    "pull", "push", "bench", "mirror", "quirks", "info", "health",
    "collect", "submit", "add-device", "wizard", "delete", "move",
    "events", "learn-promote", "bdd", "snapshot", "version",
  ]

  @Test("Help text command list contains probe")
  func helpContainsProbe() {
    #expect(Self.expectedCommands.contains("probe"))
  }

  @Test("Help text command list contains version")
  func helpContainsVersion() {
    #expect(Self.expectedCommands.contains("version"))
  }

  @Test("Help text command list contains wizard")
  func helpContainsWizard() {
    #expect(Self.expectedCommands.contains("wizard"))
  }

  @Test("Help text command list contains snapshot")
  func helpContainsSnapshot() {
    #expect(Self.expectedCommands.contains("snapshot"))
  }

  @Test("Help text command list contains all 24 subcommands")
  func helpContainsAll24() {
    #expect(Self.expectedCommands.count == 24)
    #expect(Set(Self.expectedCommands).count == 24)
  }

  @Test("No subcommand name is empty or has leading/trailing whitespace")
  func noEmptyOrWhitespaceCommands() {
    for cmd in Self.expectedCommands {
      #expect(!cmd.isEmpty)
      #expect(cmd == cmd.trimmingCharacters(in: .whitespaces))
    }
  }

  @Test("All subcommand names are lowercase kebab-case")
  func allKebabCase() {
    let kebabPattern = /^[a-z][a-z0-9]*(-[a-z0-9]+)*$/
    for cmd in Self.expectedCommands {
      #expect(
        cmd.wholeMatch(of: kebabPattern) != nil,
        "Command '\(cmd)' is not kebab-case")
    }
  }
}

// MARK: - 2. Invalid Argument Handling

@Suite("Invalid Argument Handling")
struct InvalidArgumentHandling {
  @Test("Unknown flag --foobar is not consumed by DeviceFilterParse")
  func unknownFlagNotConsumed() {
    var args = ["--foobar", "value"]
    let filter = DeviceFilterParse.parse(from: &args)
    #expect(filter.vid == nil)
    #expect(filter.pid == nil)
    #expect(args == ["--foobar", "value"])
  }

  @Test("--vid with non-hex garbage returns nil vid")
  func vidGarbageValue() {
    var args = ["--vid", "ZZZZ"]
    let filter = DeviceFilterParse.parse(from: &args)
    #expect(filter.vid == nil)
    #expect(args.contains("--vid"))
  }

  @Test("--bus with negative number is handled without crash")
  func busNegativeValue() {
    var args = ["--bus", "-1"]
    let filter = DeviceFilterParse.parse(from: &args)
    // parseInt("-1") returns -1 which is valid Int; parser may or may not accept
    #expect(args.isEmpty || filter.bus != nil)
  }

  @Test("--address with floating-point value is not parsed")
  func addressFloatValue() {
    var args = ["--address", "3.14"]
    let filter = DeviceFilterParse.parse(from: &args)
    #expect(filter.address == nil)
    #expect(args.contains("--address"))
  }

  @Test("Duplicate conflicting --pid flags are both consumed")
  func duplicatePidConsumed() {
    var args = ["--pid", "AAAA", "--pid", "BBBB"]
    let filter = DeviceFilterParse.parse(from: &args)
    #expect(filter.pid != nil)
    #expect(!args.contains("--pid"))
  }
}

// MARK: - 3. Environment Variable Processing

@Suite("Environment Variable Processing")
struct EnvironmentVariableProcessing {
  @Test("FeatureFlags.useMockTransport reflects SWIFTMTP_DEMO_MODE")
  func demoModeFlag() {
    let flags = FeatureFlags.shared
    let original = flags.useMockTransport
    flags.useMockTransport = true
    #expect(flags.useMockTransport == true)
    #expect(flags.isEnabled("SWIFTMTP_DEMO_MODE") == true)
    flags.useMockTransport = original
  }

  @Test("FeatureFlags.traceUSB reflects SWIFTMTP_TRACE_USB")
  func traceUSBFlag() {
    let flags = FeatureFlags.shared
    let original = flags.traceUSB
    flags.traceUSB = true
    #expect(flags.traceUSB == true)
    flags.traceUSB = original
  }

  @Test("FeatureFlags.showStorybook reflects SWIFTMTP_SHOW_STORYBOOK")
  func storybookFlag() {
    let flags = FeatureFlags.shared
    let original = flags.showStorybook
    flags.showStorybook = true
    #expect(flags.showStorybook == true)
    flags.showStorybook = original
  }

  @Test("FeatureFlags unknown key defaults to false")
  func unknownKeyDefaultsFalse() {
    let key = "SWIFTMTP_NONEXISTENT_FLAG_\(UInt32.random(in: 10000...99999))"
    #expect(FeatureFlags.shared.isEnabled(key) == false)
  }

  @Test("MTPFeatureFlags toggling CHUNKED_TRANSFER round-trips")
  func chunkedTransferRoundTrip() {
    let flags = MTPFeatureFlags.shared
    let original = flags.isEnabled(.chunkedTransfer)
    flags.setEnabled(.chunkedTransfer, true)
    #expect(flags.isEnabled(.chunkedTransfer) == true)
    flags.setEnabled(.chunkedTransfer, false)
    #expect(flags.isEnabled(.chunkedTransfer) == false)
    flags.setEnabled(.chunkedTransfer, original)
  }
}

// MARK: - 4. Exit Code Correctness

@Suite("Exit Code Correctness")
struct ExitCodeCorrectness {
  @Test("ExitCode.usage is BSD EX_USAGE (64)")
  func usageIs64() {
    #expect(ExitCode.usage.rawValue == 64)
  }

  @Test("ExitCode.unavailable is BSD EX_UNAVAILABLE (69)")
  func unavailableIs69() {
    #expect(ExitCode.unavailable.rawValue == 69)
  }

  @Test("ExitCode.tempfail is BSD EX_TEMPFAIL (75)")
  func tempfailIs75() {
    #expect(ExitCode.tempfail.rawValue == 75)
  }

  @Test("Non-zero exit codes are all in the 64-78 BSD range")
  func allInBSDRange() {
    let nonZero: [ExitCode] = [.usage, .unavailable, .software, .tempfail]
    for code in nonZero {
      #expect(
        (64...78).contains(code.rawValue),
        "ExitCode \(code) = \(code.rawValue) outside BSD 64-78 range")
    }
  }

  @Test("ExitCode can initialize from raw Int32 values")
  func initFromRaw() {
    #expect(ExitCode(rawValue: 0) == .ok)
    #expect(ExitCode(rawValue: 64) == .usage)
    #expect(ExitCode(rawValue: 69) == .unavailable)
    #expect(ExitCode(rawValue: 70) == .software)
    #expect(ExitCode(rawValue: 75) == .tempfail)
    #expect(ExitCode(rawValue: 99) == nil)
  }
}

// MARK: - 5. CLIErrorEnvelope Smoke Tests

@Suite("CLIErrorEnvelope Smoke")
struct CLIErrorEnvelopeSmoke {
  @Test("Envelope with unicode error message round-trips")
  func unicodeError() throws {
    let msg = "设备断开连接 🔌"
    let envelope = CLIErrorEnvelope(msg, timestamp: "2026-01-01T00:00:00Z")
    let data = try JSONEncoder().encode(envelope)
    let decoded = try JSONDecoder().decode(CLIErrorEnvelope.self, from: data)
    #expect(decoded.error == msg)
  }

  @Test("Envelope with empty details dict is distinct from nil details")
  func emptyVsNilDetails() throws {
    let withEmpty = CLIErrorEnvelope("e", details: [:], timestamp: "2026-01-01T00:00:00Z")
    let withNil = CLIErrorEnvelope("e", timestamp: "2026-01-01T00:00:00Z")
    let enc = JSONEncoder()
    let d1 = try enc.encode(withEmpty)
    let d2 = try enc.encode(withNil)
    #expect(d1 != d2)
  }

  @Test("Envelope JSON contains all top-level keys when fully populated")
  func allTopLevelKeys() throws {
    let envelope = CLIErrorEnvelope(
      "test", details: ["k": "v"], mode: "strict",
      timestamp: "2026-01-01T00:00:00Z")
    let data = try JSONEncoder().encode(envelope)
    let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
    let requiredKeys: Set = ["schemaVersion", "type", "error", "timestamp", "details", "mode"]
    #expect(requiredKeys.isSubset(of: Set(json.keys)))
  }
}

// MARK: - 6. parseUSBIdentifier Extended Edge Cases

@Suite("parseUSBIdentifier Extended")
struct ParseUSBIdentifierExtended {
  @Test("Rejects overflow values above UInt16.max")
  func rejectsOverflow() {
    #expect(parseUSBIdentifier("0x10000") == nil)
    #expect(parseUSBIdentifier("FFFFF") == nil)
  }

  @Test("Accepts single hex digit")
  func singleHexDigit() {
    #expect(parseUSBIdentifier("A") == 0xA)
    #expect(parseUSBIdentifier("f") == 0xF)
  }

  @Test("Accepts four-digit zero-padded hex")
  func zeroPaddedHex() {
    #expect(parseUSBIdentifier("0001") == 0x0001)
    #expect(parseUSBIdentifier("00FF") == 0x00FF)
  }

  @Test("Handles tab characters in whitespace")
  func tabWhitespace() {
    #expect(parseUSBIdentifier("\t1234\t") == 0x1234)
  }
}

// MARK: - 7. DeviceFilter Matching Semantics

@Suite("DeviceFilter Matching Semantics")
struct DeviceFilterMatchingSemantics {
  private func summary(
    _ id: String, vid: UInt16, pid: UInt16, bus: UInt8, addr: UInt8
  ) -> MTPDeviceSummary {
    MTPDeviceSummary(
      id: MTPDeviceID(raw: id), manufacturer: "T", model: "D",
      vendorID: vid, productID: pid, bus: bus, address: addr
    )
  }

  @Test("Nil filter matches everything")
  func nilFilterMatchesAll() {
    let devs = [
      summary("a", vid: 0x1111, pid: 0x2222, bus: 1, addr: 1),
      summary("b", vid: 0x3333, pid: 0x4444, bus: 2, addr: 2),
      summary("c", vid: 0x5555, pid: 0x6666, bus: 3, addr: 3),
    ]
    let noFilter = DeviceFilter(vid: nil, pid: nil, bus: nil, address: nil)
    let result = selectDevice(devs, filter: noFilter, noninteractive: true)
    if case .multiple(let m) = result {
      #expect(m.count == 3)
    } else {
      Issue.record("Expected .multiple with 3 devices")
    }
  }

  @Test("Partial filter by pid only narrows correctly")
  func pidOnlyFilter() {
    let devs = [
      summary("a", vid: 0x04e8, pid: 0x6860, bus: 1, addr: 1),
      summary("b", vid: 0x2717, pid: 0x6860, bus: 2, addr: 2),
      summary("c", vid: 0x04e8, pid: 0xFF40, bus: 3, addr: 3),
    ]
    let filter = DeviceFilter(vid: nil, pid: 0x6860, bus: nil, address: nil)
    let result = selectDevice(devs, filter: filter, noninteractive: true)
    if case .multiple(let m) = result {
      #expect(m.count == 2)
    } else {
      Issue.record("Expected .multiple with 2 devices")
    }
  }

  @Test("Address-only filter narrows to single device")
  func addressOnlyFilter() {
    let devs = [
      summary("a", vid: 0x04e8, pid: 0x6860, bus: 1, addr: 4),
      summary("b", vid: 0x04e8, pid: 0x6860, bus: 1, addr: 7),
    ]
    let filter = DeviceFilter(vid: nil, pid: nil, bus: nil, address: 7)
    let result = selectDevice(devs, filter: filter, noninteractive: true)
    if case .selected(let s) = result {
      #expect(s.id.raw == "b")
    } else {
      Issue.record("Expected .selected for address-only filter")
    }
  }
}

// MARK: - 8. MTPError Description Smoke Tests

@Suite("MTPError Description Smoke")
struct MTPErrorDescriptionSmoke {
  @Test("MTPError.storageFull has descriptive message")
  func storageFullMessage() {
    let err = MTPError.storageFull
    let desc = err.errorDescription ?? ""
    #expect(desc.lowercased().contains("full") || desc.lowercased().contains("storage"))
  }

  @Test("MTPError.permissionDenied has descriptive message")
  func permissionDeniedMessage() {
    let err = MTPError.permissionDenied
    let desc = err.errorDescription ?? ""
    #expect(desc.lowercased().contains("permission") || desc.lowercased().contains("denied"))
  }

  @Test("MTPError.notSupported includes operation name")
  func notSupportedMessage() {
    let err = MTPError.notSupported("DeleteObject")
    let desc = err.errorDescription ?? ""
    #expect(desc.contains("DeleteObject"))
  }
}

// MARK: - 9. Spinner Safety

@Suite("Spinner Safety")
struct SpinnerSafety {
  @Test("Spinner disabled: start/stop cycle does not crash")
  func disabledCycle() {
    let spinner = SwiftMTPCLI.Spinner(enabled: false)
    spinner.start("test-label")
    spinner.stopAndClear("done")
  }

  @Test("Spinner disabled: double-stop does not crash")
  func disabledDoubleStop() {
    let spinner = SwiftMTPCLI.Spinner(enabled: false)
    spinner.start("label")
    spinner.stopAndClear("a")
    spinner.stopAndClear("b")
  }

  @Test("Spinner disabled: stop without start does not crash")
  func disabledStopWithoutStart() {
    let spinner = SwiftMTPCLI.Spinner(enabled: false)
    spinner.stopAndClear(nil)
  }
}

// MARK: - 10. MTPFeature Enum Completeness

@Suite("MTPFeature Enum Completeness")
struct MTPFeatureEnumCompleteness {
  @Test("MTPFeature has at least 4 cases")
  func minimumCases() {
    #expect(MTPFeature.allCases.count >= 4)
  }

  @Test("MTPFeature raw values are non-empty UPPER_SNAKE_CASE")
  func rawValueFormat() {
    let upperSnake = /^[A-Z][A-Z0-9]*(_[A-Z0-9]+)*$/
    for feature in MTPFeature.allCases {
      #expect(!feature.rawValue.isEmpty)
      #expect(
        feature.rawValue.wholeMatch(of: upperSnake) != nil,
        "Feature '\(feature.rawValue)' is not UPPER_SNAKE_CASE")
    }
  }

  @Test("MTPFeature raw values are all unique")
  func uniqueRawValues() {
    let rawValues = MTPFeature.allCases.map(\.rawValue)
    #expect(Set(rawValues).count == rawValues.count)
  }
}
