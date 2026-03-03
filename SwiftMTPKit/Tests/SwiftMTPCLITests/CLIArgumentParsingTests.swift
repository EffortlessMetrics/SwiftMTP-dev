// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import Testing
import SwiftMTPCLI
@testable import SwiftMTPCore

// MARK: - 1. parseUSBIdentifier Argument Parsing

@Suite("parseUSBIdentifier Argument Parsing")
struct ParseUSBIdentifierArgumentParsing {
  @Test("Nil input returns nil")
  func nilReturnsNil() {
    #expect(parseUSBIdentifier(nil) == nil)
  }

  @Test("Empty string returns nil")
  func emptyReturnsNil() {
    #expect(parseUSBIdentifier("") == nil)
  }

  @Test("Whitespace-only returns nil")
  func whitespaceReturnsNil() {
    #expect(parseUSBIdentifier("   ") == nil)
    #expect(parseUSBIdentifier("\t") == nil)
    #expect(parseUSBIdentifier("\n") == nil)
  }

  @Test("0x prefix parses as hex")
  func hexPrefix() {
    #expect(parseUSBIdentifier("0x2717") == 0x2717)
    #expect(parseUSBIdentifier("0x04e8") == 0x04E8)
  }

  @Test("0X uppercase prefix parses as hex")
  func hexUpperPrefix() {
    #expect(parseUSBIdentifier("0XABCD") == 0xABCD)
  }

  @Test("Hex letters without prefix parse as hex")
  func hexLettersNoPrefix() {
    #expect(parseUSBIdentifier("ff40") == 0xFF40)
    #expect(parseUSBIdentifier("ABCD") == 0xABCD)
    #expect(parseUSBIdentifier("abcd") == 0xABCD)
  }

  @Test("Pure digits parse as hex (USB convention)")
  func pureDigitsAsHex() {
    #expect(parseUSBIdentifier("1234") == 0x1234)
    #expect(parseUSBIdentifier("4660") == 0x4660)
  }

  @Test("Leading/trailing whitespace is stripped")
  func whitespaceStripped() {
    #expect(parseUSBIdentifier(" 1234 ") == 0x1234)
    #expect(parseUSBIdentifier("\t04e8\t") == 0x04E8)
  }

  @Test("Non-hex strings return nil")
  func nonHexReturnsNil() {
    #expect(parseUSBIdentifier("not-a-number") == nil)
    #expect(parseUSBIdentifier("xyz") == nil)
    #expect(parseUSBIdentifier("0x") == nil)
  }

  @Test("Boundary values: 0x0000 and 0xFFFF")
  func boundaryValues() {
    #expect(parseUSBIdentifier("0x0000") == 0x0000)
    #expect(parseUSBIdentifier("0xFFFF") == 0xFFFF)
  }

  @Test("Overflow beyond UInt16.max returns nil")
  func overflowReturnsNil() {
    #expect(parseUSBIdentifier("0x10000") == nil)
    #expect(parseUSBIdentifier("FFFFF") == nil)
  }

  @Test("Single hex digit parses correctly")
  func singleDigit() {
    #expect(parseUSBIdentifier("A") == 0xA)
    #expect(parseUSBIdentifier("f") == 0xF)
    #expect(parseUSBIdentifier("0") == 0x0)
  }

  @Test("Mixed case hex parses correctly")
  func mixedCase() {
    #expect(parseUSBIdentifier("AbCd") == 0xABCD)
    #expect(parseUSBIdentifier("0xaBcD") == 0xABCD)
  }
}

// MARK: - 2. DeviceFilterParse Argument Parsing

@Suite("DeviceFilterParse Argument Parsing")
struct DeviceFilterParseArgumentParsing {
  @Test("Empty args produce empty filter")
  func emptyArgs() {
    var args: [String] = []
    let f = DeviceFilterParse.parse(from: &args)
    #expect(f.vid == nil)
    #expect(f.pid == nil)
    #expect(f.bus == nil)
    #expect(f.address == nil)
    #expect(args.isEmpty)
  }

  @Test("--vid parses and removes from args")
  func vidParsesAndRemoves() {
    var args = ["--vid", "04e8", "remaining"]
    let f = DeviceFilterParse.parse(from: &args)
    #expect(f.vid == 0x04e8)
    #expect(args == ["remaining"])
  }

  @Test("--pid parses and removes from args")
  func pidParsesAndRemoves() {
    var args = ["--pid", "6860"]
    let f = DeviceFilterParse.parse(from: &args)
    #expect(f.pid == 0x6860)
    #expect(args.isEmpty)
  }

  @Test("--bus parses decimal and removes from args")
  func busParsesDecimal() {
    var args = ["--bus", "3"]
    let f = DeviceFilterParse.parse(from: &args)
    #expect(f.bus == 3)
    #expect(args.isEmpty)
  }

  @Test("--address parses decimal and removes from args")
  func addressParsesDecimal() {
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

  @Test("Unknown flags remain in args")
  func unknownFlagsRemain() {
    var args = ["--json", "--vid", "04e8", "--verbose"]
    let f = DeviceFilterParse.parse(from: &args)
    #expect(f.vid == 0x04e8)
    #expect(args == ["--json", "--verbose"])
  }

  @Test("--vid without value is not consumed")
  func vidWithoutValue() {
    var args = ["--vid"]
    let f = DeviceFilterParse.parse(from: &args)
    #expect(f.vid == nil)
    #expect(args == ["--vid"])
  }

  @Test("--bus with non-numeric value is not consumed")
  func busNonNumeric() {
    var args = ["--bus", "abc"]
    let f = DeviceFilterParse.parse(from: &args)
    #expect(f.bus == nil)
    #expect(args == ["--bus", "abc"])
  }

  @Test("--address with non-numeric value is not consumed")
  func addressNonNumeric() {
    var args = ["--address", "xyz"]
    let f = DeviceFilterParse.parse(from: &args)
    #expect(f.address == nil)
    #expect(args == ["--address", "xyz"])
  }

  @Test("Interleaved known and unknown flags preserve order")
  func interleavedFlags() {
    var args = ["--verbose", "--vid", "04e8", "--json", "--bus", "2", "--output", "file.txt"]
    let f = DeviceFilterParse.parse(from: &args)
    #expect(f.vid == 0x04e8)
    #expect(f.bus == 2)
    #expect(args == ["--verbose", "--json", "--output", "file.txt"])
  }

  @Test("Duplicate --vid flags are both consumed")
  func duplicateVidConsumed() {
    var args = ["--vid", "1111", "--vid", "2222"]
    let _ = DeviceFilterParse.parse(from: &args)
    #expect(!args.contains("--vid"))
  }

  @Test("Duplicate --pid flags are both consumed")
  func duplicatePidConsumed() {
    var args = ["--pid", "AAAA", "--pid", "BBBB"]
    let f = DeviceFilterParse.parse(from: &args)
    #expect(f.pid != nil)
    #expect(!args.contains("--pid"))
  }

  @Test("--vid with invalid hex leaves args unchanged")
  func vidInvalidHex() {
    var args = ["--vid", "ZZZZ"]
    let f = DeviceFilterParse.parse(from: &args)
    #expect(f.vid == nil)
    #expect(args.contains("--vid"))
  }
}

// MARK: - 3. DeviceFilter Construction

@Suite("DeviceFilter Construction")
struct DeviceFilterArgumentConstruction {
  @Test("Filter with all nil fields")
  func allNil() {
    let f = DeviceFilter(vid: nil, pid: nil, bus: nil, address: nil)
    #expect(f.vid == nil && f.pid == nil && f.bus == nil && f.address == nil)
  }

  @Test("Filter with all fields set")
  func allSet() {
    let f = DeviceFilter(vid: 0x2717, pid: 0xFF40, bus: 1, address: 4)
    #expect(f.vid == 0x2717)
    #expect(f.pid == 0xFF40)
    #expect(f.bus == 1)
    #expect(f.address == 4)
  }

  @Test("Filter with vid only")
  func vidOnly() {
    let f = DeviceFilter(vid: 0x04E8, pid: nil, bus: nil, address: nil)
    #expect(f.vid == 0x04E8)
    #expect(f.pid == nil)
  }

  @Test("Filter with bus and address only")
  func busAndAddress() {
    let f = DeviceFilter(vid: nil, pid: nil, bus: 3, address: 12)
    #expect(f.bus == 3)
    #expect(f.address == 12)
  }

  @Test("Filter boundary: vid=0, pid=0, bus=0, address=0")
  func zeroValues() {
    let f = DeviceFilter(vid: 0, pid: 0, bus: 0, address: 0)
    #expect(f.vid == 0)
    #expect(f.pid == 0)
    #expect(f.bus == 0)
    #expect(f.address == 0)
  }

  @Test("Filter boundary: max UInt16 vid/pid")
  func maxValues() {
    let f = DeviceFilter(vid: 0xFFFF, pid: 0xFFFF, bus: 255, address: 255)
    #expect(f.vid == 0xFFFF)
    #expect(f.pid == 0xFFFF)
  }
}

// MARK: - 4. selectDevice Argument Handling

@Suite("selectDevice with Various Filters")
struct SelectDeviceArgumentHandling {
  private func summary(
    _ id: String, vid: UInt16, pid: UInt16, bus: UInt8, addr: UInt8
  ) -> MTPDeviceSummary {
    MTPDeviceSummary(
      id: MTPDeviceID(raw: id), manufacturer: "T", model: "D",
      vendorID: vid, productID: pid, bus: bus, address: addr
    )
  }

  @Test("Empty device list returns .none regardless of filter")
  func emptyListAlwaysNone() {
    let filters: [DeviceFilter] = [
      DeviceFilter(vid: nil, pid: nil, bus: nil, address: nil),
      DeviceFilter(vid: 0x1234, pid: nil, bus: nil, address: nil),
      DeviceFilter(vid: 0x1234, pid: 0x5678, bus: 1, address: 2),
    ]
    for filter in filters {
      let result = selectDevice([MTPDeviceSummary](), filter: filter, noninteractive: true)
      if case .none = result {} else { Issue.record("Expected .none") }
    }
  }

  @Test("Single device with matching filter returns .selected")
  func singleDeviceMatching() {
    let dev = summary("x", vid: 0x04e8, pid: 0x6860, bus: 1, addr: 4)
    let filter = DeviceFilter(vid: 0x04e8, pid: nil, bus: nil, address: nil)
    let result = selectDevice([dev], filter: filter, noninteractive: true)
    if case .selected(let s) = result {
      #expect(s.id.raw == "x")
    } else {
      Issue.record("Expected .selected")
    }
  }

  @Test("Single device with non-matching filter returns .none")
  func singleDeviceNonMatching() {
    let dev = summary("x", vid: 0x04e8, pid: 0x6860, bus: 1, addr: 4)
    let filter = DeviceFilter(vid: 0x9999, pid: nil, bus: nil, address: nil)
    let result = selectDevice([dev], filter: filter, noninteractive: true)
    if case .none = result {} else { Issue.record("Expected .none") }
  }

  @Test("Multiple devices with no filter returns .multiple")
  func multipleNoFilter() {
    let devs = [
      summary("a", vid: 0x1111, pid: 0x2222, bus: 1, addr: 1),
      summary("b", vid: 0x3333, pid: 0x4444, bus: 2, addr: 2),
    ]
    let filter = DeviceFilter(vid: nil, pid: nil, bus: nil, address: nil)
    let result = selectDevice(devs, filter: filter, noninteractive: true)
    if case .multiple(let m) = result {
      #expect(m.count == 2)
    } else {
      Issue.record("Expected .multiple")
    }
  }

  @Test("VID filter narrows from multiple to single")
  func vidNarrowsToSingle() {
    let devs = [
      summary("a", vid: 0x04e8, pid: 0x6860, bus: 1, addr: 1),
      summary("b", vid: 0x2717, pid: 0xFF40, bus: 2, addr: 2),
    ]
    let filter = DeviceFilter(vid: 0x2717, pid: nil, bus: nil, address: nil)
    let result = selectDevice(devs, filter: filter, noninteractive: true)
    if case .selected(let s) = result {
      #expect(s.id.raw == "b")
    } else {
      Issue.record("Expected .selected")
    }
  }

  @Test("Bus+address disambiguates same vid:pid")
  func busAddressDisambiguates() {
    let devs = [
      summary("a", vid: 0x04e8, pid: 0x6860, bus: 1, addr: 4),
      summary("b", vid: 0x04e8, pid: 0x6860, bus: 2, addr: 7),
    ]
    let filter = DeviceFilter(vid: nil, pid: nil, bus: 2, address: 7)
    let result = selectDevice(devs, filter: filter, noninteractive: true)
    if case .selected(let s) = result {
      #expect(s.id.raw == "b")
    } else {
      Issue.record("Expected .selected for bus+address filter")
    }
  }

  @Test("Full filter (vid+pid+bus+addr) selects exact device")
  func fullFilterExact() {
    let devs = [
      summary("a", vid: 0x04e8, pid: 0x6860, bus: 1, addr: 4),
      summary("b", vid: 0x04e8, pid: 0x6860, bus: 1, addr: 5),
      summary("c", vid: 0x2717, pid: 0xFF40, bus: 2, addr: 6),
    ]
    let filter = DeviceFilter(vid: 0x04e8, pid: 0x6860, bus: 1, address: 5)
    let result = selectDevice(devs, filter: filter, noninteractive: true)
    if case .selected(let s) = result {
      #expect(s.id.raw == "b")
    } else {
      Issue.record("Expected .selected for full filter")
    }
  }

  @Test("PID-only filter returns multiple when multiple match")
  func pidOnlyMultipleMatch() {
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
      Issue.record("Expected .multiple")
    }
  }
}

// MARK: - 5. Full Parse-to-Select Pipeline

@Suite("Full Parse-to-Select Pipeline")
struct FullParseToSelectPipeline {
  private func summary(
    _ id: String, vid: UInt16, pid: UInt16, bus: UInt8, addr: UInt8
  ) -> MTPDeviceSummary {
    MTPDeviceSummary(
      id: MTPDeviceID(raw: id), manufacturer: "T", model: "D",
      vendorID: vid, productID: pid, bus: bus, address: addr
    )
  }

  @Test("Parse args then select device end-to-end")
  func parseAndSelect() {
    var args = ["--vid", "2717", "--bus", "11", "--address", "6", "--other", "token"]
    let filter = DeviceFilterParse.parse(from: &args)
    #expect(filter.vid == 0x2717)
    #expect(filter.bus == 11)
    #expect(filter.address == 6)
    #expect(args == ["--other", "token"])

    let devs = [
      summary("match", vid: 0x2717, pid: 0xAABB, bus: 11, addr: 6),
      summary("miss", vid: 0x1234, pid: 0x5678, bus: 11, addr: 7),
    ]
    let result = selectDevice(devs, filter: filter, noninteractive: true)
    if case .selected(let s) = result {
      #expect(s.id.raw == "match")
    } else {
      Issue.record("Expected .selected")
    }
  }

  @Test("Parse with no known flags passes through all args")
  func noKnownFlagsPassthrough() {
    var args = ["--json", "--verbose", "--output", "file.txt"]
    let filter = DeviceFilterParse.parse(from: &args)
    #expect(filter.vid == nil)
    #expect(filter.pid == nil)
    #expect(args.count == 4)
  }

  @Test("Parse with invalid values and select with default filter")
  func invalidValuesDefaultFilter() {
    var args = ["--vid", "ZZZZ", "--bus", "abc"]
    let filter = DeviceFilterParse.parse(from: &args)
    // Invalid values are not consumed
    let devs = [summary("a", vid: 0x1111, pid: 0x2222, bus: 1, addr: 1)]
    let result = selectDevice(devs, filter: filter, noninteractive: true)
    if case .selected = result {
    } else if case .none = result {
    } else {
      Issue.record("Expected .selected or .none")
    }
  }
}

// MARK: - 6. MTPFeature Enum Argument Validation

@Suite("MTPFeature Enum Validation")
struct MTPFeatureEnumValidation {
  @Test("All MTPFeature cases have UPPER_SNAKE_CASE raw values")
  func upperSnakeCase() {
    let pattern = /^[A-Z][A-Z0-9]*(_[A-Z0-9]+)*$/
    for feature in MTPFeature.allCases {
      #expect(
        feature.rawValue.wholeMatch(of: pattern) != nil,
        "'\(feature.rawValue)' is not UPPER_SNAKE_CASE")
    }
  }

  @Test("All MTPFeature raw values are unique")
  func uniqueRawValues() {
    let raw = MTPFeature.allCases.map(\.rawValue)
    #expect(Set(raw).count == raw.count)
  }

  @Test("MTPFeature has at least 5 cases")
  func minimumCases() {
    #expect(MTPFeature.allCases.count >= 5)
  }

  @Test("Known features exist: PROPLIST_FASTPATH, CHUNKED_TRANSFER, LEARN_PROMOTE")
  func knownFeatures() {
    let rawValues = MTPFeature.allCases.map(\.rawValue)
    #expect(rawValues.contains("PROPLIST_FASTPATH"))
    #expect(rawValues.contains("CHUNKED_TRANSFER"))
    #expect(rawValues.contains("LEARN_PROMOTE"))
  }

  @Test("MTPFeatureFlags toggle round-trip for all features")
  func toggleRoundTrip() {
    let flags = MTPFeatureFlags.shared
    for feature in MTPFeature.allCases {
      let original = flags.isEnabled(feature)
      flags.setEnabled(feature, !original)
      #expect(flags.isEnabled(feature) == !original)
      flags.setEnabled(feature, original)
      #expect(flags.isEnabled(feature) == original)
    }
  }
}

// MARK: - 7. FeatureFlags Argument Handling

@Suite("FeatureFlags CLI Argument Handling")
struct FeatureFlagsCLIArgumentHandling {
  @Test("Unknown SWIFTMTP_ key defaults to false")
  func unknownKeyFalse() {
    let key = "SWIFTMTP_UNKNOWN_\(UInt32.random(in: 10000...99999))"
    #expect(FeatureFlags.shared.isEnabled(key) == false)
  }

  @Test("Set and get round-trip for FeatureFlags")
  func setGetRoundTrip() {
    let key = "SWIFTMTP_TEST_\(UInt32.random(in: 10000...99999))"
    let flags = FeatureFlags.shared
    flags.set(key, enabled: true)
    #expect(flags.isEnabled(key) == true)
    flags.set(key, enabled: false)
    #expect(flags.isEnabled(key) == false)
  }

  @Test("useMockTransport property round-trips")
  func useMockTransportRoundTrip() {
    let flags = FeatureFlags.shared
    let original = flags.useMockTransport
    flags.useMockTransport = !original
    #expect(flags.useMockTransport == !original)
    flags.useMockTransport = original
  }

  @Test("traceUSB property round-trips")
  func traceUSBRoundTrip() {
    let flags = FeatureFlags.shared
    let original = flags.traceUSB
    flags.traceUSB = !original
    #expect(flags.traceUSB == !original)
    flags.traceUSB = original
  }

  @Test("showStorybook property round-trips")
  func showStorybookRoundTrip() {
    let flags = FeatureFlags.shared
    let original = flags.showStorybook
    flags.showStorybook = !original
    #expect(flags.showStorybook == !original)
    flags.showStorybook = original
  }

  @Test("mockProfile returns non-empty string")
  func mockProfileNonEmpty() {
    #expect(!FeatureFlags.shared.mockProfile.isEmpty)
  }
}

// MARK: - 8. ExitCode Argument Validation

@Suite("ExitCode Argument Validation")
struct ExitCodeArgumentValidation {
  @Test("ExitCode initializes from valid raw values")
  func validRawInit() {
    #expect(ExitCode(rawValue: 0) == .ok)
    #expect(ExitCode(rawValue: 64) == .usage)
    #expect(ExitCode(rawValue: 69) == .unavailable)
    #expect(ExitCode(rawValue: 70) == .software)
    #expect(ExitCode(rawValue: 75) == .tempfail)
  }

  @Test("ExitCode returns nil for invalid raw values")
  func invalidRawInit() {
    #expect(ExitCode(rawValue: 1) == nil)
    #expect(ExitCode(rawValue: 63) == nil)
    #expect(ExitCode(rawValue: 99) == nil)
    #expect(ExitCode(rawValue: -1) == nil)
  }

  @Test("ExitCode.ok is the only zero-valued code")
  func onlyZeroIsOk() {
    let nonZero: [ExitCode] = [.usage, .unavailable, .software, .tempfail]
    for code in nonZero {
      #expect(code.rawValue != 0)
    }
    #expect(ExitCode.ok.rawValue == 0)
  }
}

// MARK: - 9. MTPError isSessionAlreadyOpen

@Suite("MTPError isSessionAlreadyOpen Flag")
struct MTPErrorSessionAlreadyOpen {
  @Test("protocolError 0x201E is sessionAlreadyOpen")
  func codeMatches() {
    let err = MTPError.protocolError(code: 0x201E, message: nil)
    #expect(err.isSessionAlreadyOpen == true)
  }

  @Test("protocolError with different code is not sessionAlreadyOpen")
  func codeMismatch() {
    let err = MTPError.protocolError(code: 0x2001, message: nil)
    #expect(err.isSessionAlreadyOpen == false)
  }

  @Test("Non-protocolError cases are not sessionAlreadyOpen")
  func nonProtocolError() {
    #expect(MTPError.timeout.isSessionAlreadyOpen == false)
    #expect(MTPError.busy.isSessionAlreadyOpen == false)
    #expect(MTPError.deviceDisconnected.isSessionAlreadyOpen == false)
  }
}

// MARK: - 10. MTPError.internalError Factory

@Suite("MTPError.internalError Factory")
struct MTPErrorInternalErrorFactory {
  @Test("internalError maps to notSupported")
  func mapsToNotSupported() {
    let err = MTPError.internalError("test message")
    #expect(err == MTPError.notSupported("test message"))
  }

  @Test("internalError preserves message")
  func preservesMessage() {
    let msg = "Something went wrong internally"
    let err = MTPError.internalError(msg)
    if case .notSupported(let m) = err {
      #expect(m == msg)
    } else {
      Issue.record("Expected .notSupported")
    }
  }
}
