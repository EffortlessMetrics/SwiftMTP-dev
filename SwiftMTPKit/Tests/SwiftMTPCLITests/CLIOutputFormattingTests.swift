// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import Testing
import SwiftMTPCLI
@testable import SwiftMTPCore

// MARK: - 1. CLIErrorEnvelope Output Formatting

@Suite("CLIErrorEnvelope Output Formatting")
struct CLIErrorEnvelopeOutputFormatting {
  @Test("JSON output contains schemaVersion 1.0")
  func jsonSchemaVersion() throws {
    let envelope = CLIErrorEnvelope("test")
    let data = try JSONEncoder().encode(envelope)
    let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
    #expect(json["schemaVersion"] as? String == "1.0")
  }

  @Test("JSON output type field is always 'error'")
  func jsonTypeField() throws {
    let envelope = CLIErrorEnvelope("any message")
    let data = try JSONEncoder().encode(envelope)
    let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
    #expect(json["type"] as? String == "error")
  }

  @Test("JSON timestamp is ISO 8601 format")
  func jsonTimestampFormat() {
    let envelope = CLIErrorEnvelope("ts-check")
    let formatter = ISO8601DateFormatter()
    let date = formatter.date(from: envelope.timestamp)
    #expect(date != nil, "Timestamp '\(envelope.timestamp)' is not ISO 8601")
  }

  @Test("JSON with sortedKeys produces alphabetical key order")
  func sortedKeysOrder() throws {
    let envelope = CLIErrorEnvelope("sorted", timestamp: "2026-01-01T00:00:00Z")
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let data = try encoder.encode(envelope)
    let text = String(data: data, encoding: .utf8) ?? ""
    let errorIdx = text.range(of: "\"error\"")!.lowerBound
    let schemaIdx = text.range(of: "\"schemaVersion\"")!.lowerBound
    let timestampIdx = text.range(of: "\"timestamp\"")!.lowerBound
    let typeIdx = text.range(of: "\"type\"")!.lowerBound
    #expect(errorIdx < schemaIdx)
    #expect(schemaIdx < timestampIdx)
    #expect(timestampIdx < typeIdx)
  }

  @Test("JSON with prettyPrinted contains newlines")
  func prettyPrintedOutput() throws {
    let envelope = CLIErrorEnvelope("pretty", timestamp: "2026-01-01T00:00:00Z")
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted]
    let data = try encoder.encode(envelope)
    let text = String(data: data, encoding: .utf8) ?? ""
    #expect(text.contains("\n"))
  }

  @Test("JSON compact output has no newlines")
  func compactOutput() throws {
    let envelope = CLIErrorEnvelope("compact", timestamp: "2026-01-01T00:00:00Z")
    let encoder = JSONEncoder()
    encoder.outputFormatting = []
    let data = try encoder.encode(envelope)
    let text = String(data: data, encoding: .utf8) ?? ""
    #expect(!text.contains("\n"))
  }

  @Test("Multiple envelopes produce valid ISO 8601 timestamps")
  func distinctTimestamps() throws {
    let e1 = CLIErrorEnvelope("first")
    let e2 = CLIErrorEnvelope("second")
    let f = ISO8601DateFormatter()
    #expect(f.date(from: e1.timestamp) != nil)
    #expect(f.date(from: e2.timestamp) != nil)
  }

  @Test("Envelope with very long error message encodes correctly")
  func longErrorMessage() throws {
    let longMsg = String(repeating: "x", count: 10_000)
    let envelope = CLIErrorEnvelope(longMsg, timestamp: "2026-01-01T00:00:00Z")
    let data = try JSONEncoder().encode(envelope)
    let decoded = try JSONDecoder().decode(CLIErrorEnvelope.self, from: data)
    #expect(decoded.error.count == 10_000)
  }

  @Test("Envelope with newlines in error message round-trips")
  func newlinesInError() throws {
    let msg = "line1\nline2\nline3"
    let envelope = CLIErrorEnvelope(msg, timestamp: "2026-01-01T00:00:00Z")
    let data = try JSONEncoder().encode(envelope)
    let decoded = try JSONDecoder().decode(CLIErrorEnvelope.self, from: data)
    #expect(decoded.error == msg)
  }

  @Test("Envelope with emoji in error message round-trips")
  func emojiInError() throws {
    let msg = "❌ Device disconnected 🔌 retry ♻️"
    let envelope = CLIErrorEnvelope(msg, timestamp: "2026-01-01T00:00:00Z")
    let data = try JSONEncoder().encode(envelope)
    let decoded = try JSONDecoder().decode(CLIErrorEnvelope.self, from: data)
    #expect(decoded.error == msg)
  }

  @Test("Envelope details with empty string values round-trips")
  func emptyStringValues() throws {
    let details = ["key": "", "another": ""]
    let envelope = CLIErrorEnvelope("err", details: details, timestamp: "2026-01-01T00:00:00Z")
    let data = try JSONEncoder().encode(envelope)
    let decoded = try JSONDecoder().decode(CLIErrorEnvelope.self, from: data)
    #expect(decoded.details?["key"] == "")
    #expect(decoded.details?["another"] == "")
  }
}

// MARK: - 2. MTP Error Description Formatting

@Suite("MTPError CLI Description Formatting")
struct MTPErrorCLIDescriptionFormatting {
  @Test("deviceDisconnected contains 'disconnected'")
  func deviceDisconnectedDesc() {
    let desc = MTPError.deviceDisconnected.errorDescription ?? ""
    #expect(desc.lowercased().contains("disconnected"))
  }

  @Test("permissionDenied contains 'denied' or 'permission'")
  func permissionDeniedDesc() {
    let desc = MTPError.permissionDenied.errorDescription ?? ""
    #expect(desc.lowercased().contains("denied") || desc.lowercased().contains("permission"))
  }

  @Test("storageFull contains 'full' or 'storage'")
  func storageFullDesc() {
    let desc = MTPError.storageFull.errorDescription ?? ""
    #expect(desc.lowercased().contains("full") || desc.lowercased().contains("storage"))
  }

  @Test("readOnly contains 'read-only' or 'read'")
  func readOnlyDesc() {
    let desc = MTPError.readOnly.errorDescription ?? ""
    #expect(desc.lowercased().contains("read"))
  }

  @Test("timeout contains 'timed out' or 'timeout'")
  func timeoutDesc() {
    let desc = MTPError.timeout.errorDescription ?? ""
    #expect(desc.lowercased().contains("timed out") || desc.lowercased().contains("timeout"))
  }

  @Test("busy contains 'busy'")
  func busyDesc() {
    let desc = MTPError.busy.errorDescription ?? ""
    #expect(desc.lowercased().contains("busy"))
  }

  @Test("sessionBusy contains 'transaction' or 'progress'")
  func sessionBusyDesc() {
    let desc = MTPError.sessionBusy.errorDescription ?? ""
    #expect(desc.lowercased().contains("transaction") || desc.lowercased().contains("progress"))
  }

  @Test("objectNotFound contains 'not found'")
  func objectNotFoundDesc() {
    let desc = MTPError.objectNotFound.errorDescription ?? ""
    #expect(desc.lowercased().contains("not found"))
  }

  @Test("objectWriteProtected contains 'write-protected' or 'protected'")
  func objectWriteProtectedDesc() {
    let desc = MTPError.objectWriteProtected.errorDescription ?? ""
    #expect(desc.lowercased().contains("protected"))
  }

  @Test("notSupported includes operation name in message")
  func notSupportedIncludesOp() {
    let desc = MTPError.notSupported("SendObjectInfo").errorDescription ?? ""
    #expect(desc.contains("SendObjectInfo"))
  }

  @Test("protocolError includes hex code")
  func protocolErrorHexCode() {
    let desc = MTPError.protocolError(code: 0x2001, message: nil).errorDescription ?? ""
    #expect(desc.contains("2001"))
  }

  @Test("protocolError includes custom message when provided")
  func protocolErrorWithMessage() {
    let desc =
      MTPError.protocolError(code: 0x201D, message: "InvalidParameter").errorDescription ?? ""
    #expect(desc.contains("InvalidParameter"))
  }

  @Test("verificationFailed includes both expected and actual sizes")
  func verificationFailedSizes() {
    let desc = MTPError.verificationFailed(expected: 1024, actual: 512).errorDescription ?? ""
    #expect(desc.contains("1024"))
    #expect(desc.contains("512"))
  }

  @Test("preconditionFailed includes reason")
  func preconditionFailedReason() {
    let desc = MTPError.preconditionFailed("session not open").errorDescription ?? ""
    #expect(desc.contains("session not open"))
  }
}

// MARK: - 3. TransportError Description Formatting

@Suite("TransportError CLI Description Formatting")
struct TransportErrorCLIDescriptionFormatting {
  @Test("noDevice mentions MTP or device")
  func noDeviceDesc() {
    let desc = TransportError.noDevice.errorDescription ?? ""
    #expect(desc.lowercased().contains("mtp") || desc.lowercased().contains("device"))
  }

  @Test("timeout mentions timeout")
  func timeoutDesc() {
    let desc = TransportError.timeout.errorDescription ?? ""
    #expect(desc.lowercased().contains("timed out") || desc.lowercased().contains("timeout"))
  }

  @Test("busy mentions busy")
  func busyDesc() {
    let desc = TransportError.busy.errorDescription ?? ""
    #expect(desc.lowercased().contains("busy"))
  }

  @Test("accessDenied mentions access or unavailable")
  func accessDeniedDesc() {
    let desc = TransportError.accessDenied.errorDescription ?? ""
    #expect(desc.lowercased().contains("access") || desc.lowercased().contains("unavailable"))
  }

  @Test("stall mentions stall or aborted")
  func stallDesc() {
    let desc = TransportError.stall.errorDescription ?? ""
    #expect(desc.lowercased().contains("stall") || desc.lowercased().contains("abort"))
  }

  @Test("io includes custom message")
  func ioDesc() {
    let desc = TransportError.io("USB cable fault detected").errorDescription ?? ""
    #expect(desc.contains("USB cable fault detected"))
  }

  @Test("timeoutInPhase includes phase name for bulkOut")
  func timeoutInPhaseBulkOut() {
    let desc = TransportError.timeoutInPhase(.bulkOut).errorDescription ?? ""
    #expect(desc.contains("bulk-out"))
  }

  @Test("timeoutInPhase includes phase name for bulkIn")
  func timeoutInPhaseBulkIn() {
    let desc = TransportError.timeoutInPhase(.bulkIn).errorDescription ?? ""
    #expect(desc.contains("bulk-in"))
  }

  @Test("timeoutInPhase includes phase name for responseWait")
  func timeoutInPhaseResponseWait() {
    let desc = TransportError.timeoutInPhase(.responseWait).errorDescription ?? ""
    #expect(desc.contains("response-wait"))
  }
}

// MARK: - 4. MTP Error via Transport Wrapper

@Suite("MTPError.transport Description Formatting")
struct MTPErrorTransportFormatting {
  @Test("transport(.noDevice) contains device info")
  func transportNoDevice() {
    let desc = MTPError.transport(.noDevice).errorDescription ?? ""
    #expect(desc.lowercased().contains("device") || desc.lowercased().contains("mtp"))
  }

  @Test("transport(.timeout) contains timeout info")
  func transportTimeout() {
    let desc = MTPError.transport(.timeout).errorDescription ?? ""
    #expect(desc.lowercased().contains("timed out") || desc.lowercased().contains("timeout"))
  }

  @Test("transport(.io) passes through message")
  func transportIO() {
    let desc = MTPError.transport(.io("custom I/O failure")).errorDescription ?? ""
    #expect(desc.contains("custom I/O failure"))
  }

  @Test("transport(.accessDenied) has recovery suggestion")
  func transportAccessDeniedRecovery() {
    let suggestion = MTPError.transport(.accessDenied).recoverySuggestion ?? ""
    #expect(!suggestion.isEmpty)
  }

  @Test("transport(.noDevice) has recovery suggestion")
  func transportNoDeviceRecovery() {
    let suggestion = MTPError.transport(.noDevice).recoverySuggestion ?? ""
    #expect(!suggestion.isEmpty)
  }
}

// MARK: - 5. MTPDeviceSummary Fingerprint Formatting

@Suite("MTPDeviceSummary Fingerprint Formatting")
struct MTPDeviceSummaryFingerprintFormatting {
  @Test("Fingerprint is lowercase hex with colon separator")
  func fingerprintFormat() {
    let s = MTPDeviceSummary(
      id: MTPDeviceID(raw: "t"), manufacturer: "V", model: "M",
      vendorID: 0x04E8, productID: 0x6860, bus: 1, address: 1
    )
    #expect(s.fingerprint == "04e8:6860")
  }

  @Test("Fingerprint zero-pads small values")
  func fingerprintZeroPad() {
    let s = MTPDeviceSummary(
      id: MTPDeviceID(raw: "t"), manufacturer: "V", model: "M",
      vendorID: 0x0001, productID: 0x0002, bus: 1, address: 1
    )
    #expect(s.fingerprint == "0001:0002")
  }

  @Test("Fingerprint for max UInt16 values")
  func fingerprintMaxValues() {
    let s = MTPDeviceSummary(
      id: MTPDeviceID(raw: "t"), manufacturer: "V", model: "M",
      vendorID: 0xFFFF, productID: 0xFFFF, bus: 1, address: 1
    )
    #expect(s.fingerprint == "ffff:ffff")
  }

  @Test("Fingerprint with nil IDs returns 'unknown'")
  func fingerprintNilIDs() {
    let s = MTPDeviceSummary(
      id: MTPDeviceID(raw: "t"), manufacturer: "V", model: "M"
    )
    #expect(s.fingerprint == "unknown")
  }

  @Test("Fingerprint with only VID nil returns 'unknown'")
  func fingerprintPartialNil() {
    let s = MTPDeviceSummary(
      id: MTPDeviceID(raw: "t"), manufacturer: "V", model: "M",
      vendorID: nil, productID: 0x1234
    )
    #expect(s.fingerprint == "unknown")
  }
}

// MARK: - 6. ExitCode Formatting

@Suite("ExitCode Display Values")
struct ExitCodeDisplayValues {
  @Test("ExitCode.ok displays as 0 for scripting")
  func okDisplayValue() {
    #expect(ExitCode.ok.rawValue == 0)
  }

  @Test("ExitCode raw values are distinct")
  func allDistinct() {
    let all: [ExitCode] = [.ok, .usage, .unavailable, .software, .tempfail]
    let rawSet = Set(all.map(\.rawValue))
    #expect(rawSet.count == all.count)
  }

  @Test("ExitCode.software is 70 (EX_SOFTWARE)")
  func softwareIs70() {
    #expect(ExitCode.software.rawValue == 70)
  }

  @Test("Non-zero codes are all >= 64 (BSD sysexits)")
  func nonZeroBSDRange() {
    let nonZero: [ExitCode] = [.usage, .unavailable, .software, .tempfail]
    for code in nonZero {
      #expect(code.rawValue >= 64)
    }
  }
}

// MARK: - 7. Spinner Output Safety

@Suite("Spinner Output Safety")
struct SpinnerOutputSafety {
  @Test("Disabled spinner start/stop does not crash")
  func disabledStartStop() {
    let spinner = SwiftMTPCLI.Spinner(enabled: false)
    spinner.start("loading...")
    spinner.stopAndClear("done")
  }

  @Test("Disabled spinner double-start does not crash")
  func disabledDoubleStart() {
    let spinner = SwiftMTPCLI.Spinner(enabled: false)
    spinner.start("first")
    spinner.start("second")
    spinner.stopAndClear("done")
  }

  @Test("Disabled spinner stop without start does not crash")
  func disabledStopOnly() {
    let spinner = SwiftMTPCLI.Spinner(enabled: false)
    spinner.stopAndClear("done")
  }

  @Test("Disabled spinner with nil end message does not crash")
  func disabledNilEnd() {
    let spinner = SwiftMTPCLI.Spinner(enabled: false)
    spinner.start("test")
    spinner.stopAndClear(nil)
  }

  @Test("Disabled spinner with empty label does not crash")
  func disabledEmptyLabel() {
    let spinner = SwiftMTPCLI.Spinner(enabled: false)
    spinner.start("")
    spinner.stopAndClear("")
  }

  @Test("Enabled spinner rapid start/stop cycle does not crash")
  func enabledRapidCycle() {
    let spinner = SwiftMTPCLI.Spinner(enabled: true)
    for i in 0..<10 {
      spinner.start("cycle-\(i)")
      spinner.stopAndClear("done-\(i)")
    }
  }
}

// MARK: - 8. CLIErrorEnvelope JSON Details Formatting

@Suite("CLIErrorEnvelope Details Formatting")
struct CLIErrorEnvelopeDetailsFormatting {
  @Test("Details with special characters in keys round-trip")
  func specialCharKeys() throws {
    let details = ["key.with.dots": "val", "key-with-dashes": "val2"]
    let envelope = CLIErrorEnvelope("err", details: details, timestamp: "2026-01-01T00:00:00Z")
    let data = try JSONEncoder().encode(envelope)
    let decoded = try JSONDecoder().decode(CLIErrorEnvelope.self, from: data)
    #expect(decoded.details?["key.with.dots"] == "val")
    #expect(decoded.details?["key-with-dashes"] == "val2")
  }

  @Test("Details with unicode values round-trip")
  func unicodeValues() throws {
    let details = ["msg": "デバイスが切断されました", "icon": "🔌"]
    let envelope = CLIErrorEnvelope("err", details: details, timestamp: "2026-01-01T00:00:00Z")
    let data = try JSONEncoder().encode(envelope)
    let decoded = try JSONDecoder().decode(CLIErrorEnvelope.self, from: data)
    #expect(decoded.details?["msg"] == "デバイスが切断されました")
    #expect(decoded.details?["icon"] == "🔌")
  }

  @Test("Mode field preserves arbitrary string values")
  func modeArbitraryValues() throws {
    for mode in ["strict", "safe", "normal", "debug", "custom-mode-123"] {
      let envelope = CLIErrorEnvelope("err", mode: mode, timestamp: "2026-01-01T00:00:00Z")
      let data = try JSONEncoder().encode(envelope)
      let decoded = try JSONDecoder().decode(CLIErrorEnvelope.self, from: data)
      #expect(decoded.mode == mode)
    }
  }

  @Test("Nil mode is omitted from JSON output")
  func nilModeOmitted() throws {
    let envelope = CLIErrorEnvelope("err", timestamp: "2026-01-01T00:00:00Z")
    let data = try JSONEncoder().encode(envelope)
    let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
    // mode key should be absent or null
    let modeValue = json["mode"]
    #expect(modeValue == nil || modeValue is NSNull)
  }

  @Test("Nil details is omitted from JSON output")
  func nilDetailsOmitted() throws {
    let envelope = CLIErrorEnvelope("err", timestamp: "2026-01-01T00:00:00Z")
    let data = try JSONEncoder().encode(envelope)
    let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
    let detailsValue = json["details"]
    #expect(detailsValue == nil || detailsValue is NSNull)
  }

  @Test("Details with 100 entries round-trips")
  func manyEntries() throws {
    var details: [String: String] = [:]
    for i in 0..<100 { details["k\(i)"] = "v\(i)" }
    let envelope = CLIErrorEnvelope("err", details: details, timestamp: "2026-01-01T00:00:00Z")
    let data = try JSONEncoder().encode(envelope)
    let decoded = try JSONDecoder().decode(CLIErrorEnvelope.self, from: data)
    #expect(decoded.details?.count == 100)
  }
}

// MARK: - 9. TransportPhase Description Formatting

@Suite("TransportPhase Description Formatting")
struct TransportPhaseDescriptionFormatting {
  @Test("bulkOut description is 'bulk-out'")
  func bulkOutDesc() {
    #expect(TransportPhase.bulkOut.description == "bulk-out")
  }

  @Test("bulkIn description is 'bulk-in'")
  func bulkInDesc() {
    #expect(TransportPhase.bulkIn.description == "bulk-in")
  }

  @Test("responseWait description is 'response-wait'")
  func responseWaitDesc() {
    #expect(TransportPhase.responseWait.description == "response-wait")
  }
}

// MARK: - 10. MTPError Equatable Conformance

@Suite("MTPError Equatable for CLI Output")
struct MTPErrorEquatable {
  @Test("Same error cases are equal")
  func sameEqual() {
    #expect(MTPError.timeout == MTPError.timeout)
    #expect(MTPError.busy == MTPError.busy)
    #expect(MTPError.storageFull == MTPError.storageFull)
    #expect(MTPError.deviceDisconnected == MTPError.deviceDisconnected)
  }

  @Test("Different error cases are not equal")
  func differentNotEqual() {
    #expect(MTPError.timeout != MTPError.busy)
    #expect(MTPError.storageFull != MTPError.readOnly)
  }

  @Test("protocolError with same code and message are equal")
  func protocolErrorEqual() {
    let a = MTPError.protocolError(code: 0x2001, message: "test")
    let b = MTPError.protocolError(code: 0x2001, message: "test")
    #expect(a == b)
  }

  @Test("protocolError with different codes are not equal")
  func protocolErrorDiffCode() {
    let a = MTPError.protocolError(code: 0x2001, message: nil)
    let b = MTPError.protocolError(code: 0x201D, message: nil)
    #expect(a != b)
  }

  @Test("notSupported with same message are equal")
  func notSupportedEqual() {
    #expect(MTPError.notSupported("Op") == MTPError.notSupported("Op"))
  }

  @Test("notSupported with different messages are not equal")
  func notSupportedDiff() {
    #expect(MTPError.notSupported("A") != MTPError.notSupported("B"))
  }
}
