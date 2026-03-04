// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import XCTest
@testable import SwiftMTPCore
import SwiftMTPQuirks

/// Inline snapshot tests for probe output formatting: ProbeReceipt structure,
/// InterfaceProbeResult fields, SessionProbeResult fields, PolicySummary
/// serialization, and JSON round-trip stability.
final class ProbeOutputSnapshotTests: XCTestCase {

  // MARK: - 1. ProbeReceipt JSON Structure

  func testProbeReceiptJSONContainsDeviceSummary() throws {
    let receipt = makeTestReceipt()
    let data = try sortedJSON(receipt)
    let dict = try jsonDict(from: data)
    let summary = dict["deviceSummary"] as? [String: Any]
    XCTAssertNotNil(summary)
    XCTAssertEqual(summary?["manufacturer"] as? String, "Google")
    XCTAssertEqual(summary?["model"] as? String, "Pixel 7")
  }

  func testProbeReceiptJSONContainsFingerprint() throws {
    let receipt = makeTestReceipt()
    let data = try sortedJSON(receipt)
    let dict = try jsonDict(from: data)
    let fp = dict["fingerprint"] as? [String: Any]
    XCTAssertNotNil(fp)
    XCTAssertEqual(fp?["vid"] as? String, "18d1")
    XCTAssertEqual(fp?["pid"] as? String, "4ee1")
  }

  func testProbeReceiptJSONContainsCapabilities() throws {
    let receipt = makeTestReceipt()
    let data = try sortedJSON(receipt)
    let dict = try jsonDict(from: data)
    let caps = dict["capabilities"] as? [String: Bool]
    XCTAssertNotNil(caps)
    XCTAssertEqual(caps?["supportsGetPartialObject64"], true)
    XCTAssertEqual(caps?["supportsEvents"], true)
  }

  func testProbeReceiptJSONContainsTotalProbeTime() throws {
    let receipt = makeTestReceipt()
    let data = try sortedJSON(receipt)
    let dict = try jsonDict(from: data)
    XCTAssertEqual(dict["totalProbeTimeMs"] as? Int, 142)
  }

  func testProbeReceiptJSONContainsFallbackResults() throws {
    let receipt = makeTestReceipt()
    let data = try sortedJSON(receipt)
    let dict = try jsonDict(from: data)
    let fallbacks = dict["fallbackResults"] as? [String: String]
    XCTAssertNotNil(fallbacks)
    XCTAssertEqual(fallbacks?["enumeration"], "propList5")
    XCTAssertEqual(fallbacks?["read"], "partial64")
  }

  // MARK: - 2. ProbeReceipt Codable Round-Trip

  func testProbeReceiptCodableRoundTrip() throws {
    let receipt = makeTestReceipt()
    let enc = JSONEncoder()
    enc.dateEncodingStrategy = .iso8601
    let data = try enc.encode(receipt)
    let dec = JSONDecoder()
    dec.dateDecodingStrategy = .iso8601
    let decoded = try dec.decode(ProbeReceipt.self, from: data)
    XCTAssertEqual(decoded.deviceSummary.manufacturer, "Google")
    XCTAssertEqual(decoded.deviceSummary.model, "Pixel 7")
    XCTAssertEqual(decoded.fingerprint.vid, "18d1")
    XCTAssertEqual(decoded.totalProbeTimeMs, 142)
    XCTAssertEqual(decoded.capabilities["supportsEvents"], true)
  }

  // MARK: - 3. InterfaceProbeResult Fields

  func testInterfaceProbeResultDefaults() {
    let result = InterfaceProbeResult()
    XCTAssertEqual(result.candidatesEvaluated, 0)
    XCTAssertNil(result.selectedInterface)
    XCTAssertNil(result.selectedScore)
    XCTAssertNil(result.selectedClass)
    XCTAssertFalse(result.deviceInfoCached)
    XCTAssertTrue(result.attempts.isEmpty)
    XCTAssertNil(result.selectionReason)
    XCTAssertTrue(result.skippedAlternatives.isEmpty)
  }

  func testInterfaceProbeResultPopulated() throws {
    var result = InterfaceProbeResult()
    result.candidatesEvaluated = 3
    result.selectedInterface = 0
    result.selectedScore = 12
    result.selectedClass = "06/01/01"
    result.deviceInfoCached = true
    result.selectionReason = "Highest PTP score"
    result.attempts = [
      InterfaceAttemptResult(interfaceNumber: 0, score: 12, succeeded: true, durationMs: 45),
      InterfaceAttemptResult(interfaceNumber: 1, score: 6, succeeded: false, durationMs: 30, error: "claim failed"),
    ]
    result.skippedAlternatives = [
      SkippedInterface(
        interfaceNumber: 2, interfaceClass: 0xFF, interfaceSubclass: 0x00,
        interfaceProtocol: 0x00, score: 0, reason: "vendor-specific"
      ),
    ]

    let data = try sortedJSON(result)
    let dict = try jsonDict(from: data)
    XCTAssertEqual(dict["candidatesEvaluated"] as? Int, 3)
    XCTAssertEqual(dict["selectedInterface"] as? Int, 0)
    XCTAssertEqual(dict["selectedScore"] as? Int, 12)
    XCTAssertEqual(dict["deviceInfoCached"] as? Bool, true)
    XCTAssertEqual(dict["selectionReason"] as? String, "Highest PTP score")
  }

  // MARK: - 4. SessionProbeResult Fields

  func testSessionProbeResultDefaults() {
    let result = SessionProbeResult()
    XCTAssertFalse(result.succeeded)
    XCTAssertFalse(result.requiredRetry)
    XCTAssertEqual(result.durationMs, 0)
    XCTAssertNil(result.error)
    XCTAssertNil(result.firstFailure)
    XCTAssertNil(result.recoveryAction)
    XCTAssertFalse(result.resetAttempted)
    XCTAssertNil(result.resetError)
  }

  func testSessionProbeResultSuccessPopulated() throws {
    var result = SessionProbeResult()
    result.succeeded = true
    result.durationMs = 89
    let data = try sortedJSON(result)
    let dict = try jsonDict(from: data)
    XCTAssertEqual(dict["succeeded"] as? Bool, true)
    XCTAssertEqual(dict["durationMs"] as? Int, 89)
  }

  func testSessionProbeResultWithRecovery() throws {
    var result = SessionProbeResult()
    result.succeeded = true
    result.requiredRetry = true
    result.durationMs = 210
    result.firstFailure = "SessionNotOpen (0x2003)"
    result.recoveryAction = "resetAndReopen"
    result.resetAttempted = true
    let data = try sortedJSON(result)
    let dict = try jsonDict(from: data)
    XCTAssertEqual(dict["requiredRetry"] as? Bool, true)
    XCTAssertEqual(dict["firstFailure"] as? String, "SessionNotOpen (0x2003)")
    XCTAssertEqual(dict["recoveryAction"] as? String, "resetAndReopen")
    XCTAssertEqual(dict["resetAttempted"] as? Bool, true)
  }

  // MARK: - 5. PolicySummary Serialization

  func testPolicySummaryFromResolvedPolicy() throws {
    let db = try QuirkDatabase.load()
    let fp = MTPDeviceFingerprint(
      vid: "2717", pid: "ff10", bcdDevice: nil,
      interfaceTriple: InterfaceTriple(class: "06", subclass: "01", protocol: "01"),
      endpointAddresses: EndpointAddresses(input: "81", output: "01", event: "82"),
      deviceInfoHash: nil
    )
    let policy = QuirkResolver.resolve(fingerprint: fp, database: db)
    let summary = PolicySummary(from: policy)

    XCTAssertGreaterThan(summary.maxChunkBytes, 0)
    XCTAssertGreaterThan(summary.ioTimeoutMs, 0)
    XCTAssertGreaterThan(summary.handshakeTimeoutMs, 0)
  }

  func testPolicySummaryCodableRoundTrip() throws {
    let db = try QuirkDatabase.load()
    let fp = MTPDeviceFingerprint(
      vid: "18d1", pid: "4ee1", bcdDevice: nil,
      interfaceTriple: InterfaceTriple(class: "06", subclass: "01", protocol: "01"),
      endpointAddresses: EndpointAddresses(input: "81", output: "01", event: "82"),
      deviceInfoHash: nil
    )
    let policy = QuirkResolver.resolve(fingerprint: fp, database: db)
    let summary = PolicySummary(from: policy)
    let data = try sortedJSON(summary)
    let decoded = try JSONDecoder().decode(PolicySummary.self, from: data)
    XCTAssertEqual(decoded.maxChunkBytes, summary.maxChunkBytes)
    XCTAssertEqual(decoded.ioTimeoutMs, summary.ioTimeoutMs)
    XCTAssertEqual(decoded.enumerationStrategy, summary.enumerationStrategy)
    XCTAssertEqual(decoded.readStrategy, summary.readStrategy)
    XCTAssertEqual(decoded.writeStrategy, summary.writeStrategy)
  }

  // MARK: - 6. Probe Receipt with All Sections Populated

  func testFullyPopulatedReceiptJSONFieldCount() throws {
    var receipt = makeTestReceipt()
    var iface = InterfaceProbeResult()
    iface.candidatesEvaluated = 2
    iface.selectedInterface = 0
    iface.selectedScore = 12
    receipt.interfaceProbe = iface

    var session = SessionProbeResult()
    session.succeeded = true
    session.durationMs = 95
    receipt.sessionEstablishment = session

    let db = try QuirkDatabase.load()
    let policy = QuirkResolver.resolve(fingerprint: receipt.fingerprint, database: db)
    receipt.resolvedPolicy = PolicySummary(from: policy)

    let enc = JSONEncoder()
    enc.dateEncodingStrategy = .iso8601
    enc.outputFormatting = [.sortedKeys]
    let data = try enc.encode(receipt)
    let dict = try JSONSerialization.jsonObject(with: data) as! [String: Any]

    // All top-level sections should be present
    XCTAssertNotNil(dict["deviceSummary"])
    XCTAssertNotNil(dict["fingerprint"])
    XCTAssertNotNil(dict["capabilities"])
    XCTAssertNotNil(dict["fallbackResults"])
    XCTAssertNotNil(dict["interfaceProbe"])
    XCTAssertNotNil(dict["sessionEstablishment"])
    XCTAssertNotNil(dict["resolvedPolicy"])
    XCTAssertNotNil(dict["totalProbeTimeMs"])
    XCTAssertNotNil(dict["timestamp"])
  }

  // MARK: - Helpers

  private func makeTestReceipt() -> ProbeReceipt {
    let fingerprint = MTPDeviceFingerprint(
      vid: "18d1", pid: "4ee1", bcdDevice: "0528",
      interfaceTriple: InterfaceTriple(class: "06", subclass: "01", protocol: "01"),
      endpointAddresses: EndpointAddresses(input: "81", output: "01", event: "82"),
      deviceInfoHash: "pixel7-probe-hash"
    )
    let summary = MTPDeviceSummary(
      id: MTPDeviceID(raw: "pixel7-probe"),
      manufacturer: "Google",
      model: "Pixel 7",
      vendorID: 0x18D1,
      productID: 0x4EE1,
      usbSerial: "PROBESERIAL"
    )
    var receipt = ProbeReceipt(
      timestamp: ISO8601DateFormatter().date(from: "2026-07-01T10:00:00Z")!,
      deviceSummary: ReceiptDeviceSummary(from: summary),
      fingerprint: fingerprint
    )
    receipt.totalProbeTimeMs = 142
    receipt.capabilities = [
      "supportsGetPartialObject64": true,
      "supportsEvents": true,
    ]
    receipt.fallbackResults = [
      "enumeration": "propList5",
      "read": "partial64",
    ]
    return receipt
  }

  private func sortedJSON<T: Encodable>(_ value: T) throws -> Data {
    let enc = JSONEncoder()
    enc.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    return try enc.encode(value)
  }

  private func jsonDict(from data: Data) throws -> [String: Any] {
    try JSONSerialization.jsonObject(with: data) as! [String: Any]
  }
}
