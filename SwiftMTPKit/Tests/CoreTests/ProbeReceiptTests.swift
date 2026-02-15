// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import XCTest
@testable import SwiftMTPCore
@testable import SwiftMTPQuirks

/// Tests for ProbeReceipt and related diagnostic types
final class ProbeReceiptTests: XCTestCase {

  // MARK: - ProbeReceipt Basic Tests

  func testProbeReceiptInitialization() {
    let summary = MTPDeviceSummary(
      id: MTPDeviceID(raw: "test-device-123"),
      manufacturer: "TestCo",
      model: "MTP Device",
      vendorID: 0x1234,
      productID: 0x5678,
      bus: 1,
      address: 2
    )

    let fingerprint = MTPDeviceFingerprint.fromUSB(
      vid: 0x1234,
      pid: 0x5678,
      interfaceClass: 6,
      interfaceSubclass: 1,
      interfaceProtocol: 1,
      epIn: 0x81,
      epOut: 0x01
    )

    let receipt = ProbeReceipt(
      deviceSummary: ReceiptDeviceSummary(from: summary),
      fingerprint: fingerprint
    )

    XCTAssertNotNil(receipt)
    XCTAssertEqual(receipt.deviceSummary.manufacturer, "TestCo")
    XCTAssertEqual(receipt.deviceSummary.vendorID, "0x1234")
    XCTAssertEqual(receipt.deviceSummary.productID, "0x5678")
  }

  func testProbeReceiptDefaultValues() {
    let summary = MTPDeviceSummary(
      id: MTPDeviceID(raw: "test-device-123"),
      manufacturer: "TestCo",
      model: "MTP Device",
      vendorID: 0x1234,
      productID: 0x5678,
      bus: 1,
      address: 2
    )

    let fingerprint = MTPDeviceFingerprint.fromUSB(
      vid: 0x1234,
      pid: 0x5678,
      interfaceClass: 6,
      interfaceSubclass: 1,
      interfaceProtocol: 1,
      epIn: 0x81,
      epOut: 0x01
    )

    let receipt = ProbeReceipt(
      deviceSummary: ReceiptDeviceSummary(from: summary),
      fingerprint: fingerprint
    )

    XCTAssertEqual(receipt.capabilities, [:])
    XCTAssertEqual(receipt.fallbackResults, [:])
    XCTAssertEqual(receipt.totalProbeTimeMs, 0)
    XCTAssertNil(receipt.interfaceProbe)
    XCTAssertNil(receipt.sessionEstablishment)
    XCTAssertNil(receipt.resolvedPolicy)
  }

  func testProbeReceiptMutableProperties() {
    let summary = MTPDeviceSummary(
      id: MTPDeviceID(raw: "test-device-123"),
      manufacturer: "TestCo",
      model: "MTP Device",
      vendorID: 0x1234,
      productID: 0x5678,
      bus: 1,
      address: 2
    )

    let fingerprint = MTPDeviceFingerprint.fromUSB(
      vid: 0x1234,
      pid: 0x5678,
      interfaceClass: 6,
      interfaceSubclass: 1,
      interfaceProtocol: 1,
      epIn: 0x81,
      epOut: 0x01
    )

    var receipt = ProbeReceipt(
      deviceSummary: ReceiptDeviceSummary(from: summary),
      fingerprint: fingerprint
    )

    receipt.capabilities = ["partialRead": true, "partialWrite": false]
    receipt.fallbackResults = ["read": "partial64"]
    receipt.totalProbeTimeMs = 150

    XCTAssertEqual(receipt.capabilities["partialRead"], true)
    XCTAssertEqual(receipt.capabilities["partialWrite"], false)
    XCTAssertEqual(receipt.fallbackResults["read"], "partial64")
    XCTAssertEqual(receipt.totalProbeTimeMs, 150)
  }

  // MARK: - ReceiptDeviceSummary Tests

  func testReceiptDeviceSummaryFromSummary() {
    let summary = MTPDeviceSummary(
      id: MTPDeviceID(raw: "test-device-abc"),
      manufacturer: "Samsung",
      model: "Galaxy S21",
      vendorID: 0x04E8,
      productID: 0x685C,
      bus: 1,
      address: 3
    )

    let receiptSummary = ReceiptDeviceSummary(from: summary)

    XCTAssertEqual(receiptSummary.id, "test-device-abc")
    XCTAssertEqual(receiptSummary.manufacturer, "Samsung")
    XCTAssertEqual(receiptSummary.model, "Galaxy S21")
    XCTAssertEqual(receiptSummary.vendorID?.lowercased(), "0x04e8".lowercased())
    XCTAssertEqual(receiptSummary.productID?.lowercased(), "0x685c".lowercased())
  }

  func testReceiptDeviceSummaryWithNilVendorProduct() {
    let summary = MTPDeviceSummary(
      id: MTPDeviceID(raw: "test-device-xyz"),
      manufacturer: "Generic",
      model: "MTP Device",
      vendorID: nil,
      productID: nil,
      bus: 1,
      address: 4
    )

    let receiptSummary = ReceiptDeviceSummary(from: summary)

    XCTAssertNil(receiptSummary.vendorID)
    XCTAssertNil(receiptSummary.productID)
  }

  // MARK: - InterfaceProbeResult Tests

  func testInterfaceProbeResultDefaultValues() {
    let result = InterfaceProbeResult()
    XCTAssertEqual(result.candidatesEvaluated, 0)
    XCTAssertNil(result.selectedInterface)
    XCTAssertNil(result.selectedScore)
    XCTAssertFalse(result.deviceInfoCached)
    XCTAssertTrue(result.attempts.isEmpty)
  }

  func testInterfaceProbeResultMutableProperties() {
    var result = InterfaceProbeResult()
    result.candidatesEvaluated = 5
    result.selectedInterface = 2
    result.selectedScore = 100
    result.deviceInfoCached = true

    XCTAssertEqual(result.candidatesEvaluated, 5)
    XCTAssertEqual(result.selectedInterface, 2)
    XCTAssertEqual(result.selectedScore, 100)
    XCTAssertTrue(result.deviceInfoCached)
  }

  // MARK: - InterfaceAttemptResult Tests

  func testInterfaceAttemptResultSuccess() {
    let attempt = InterfaceAttemptResult(
      interfaceNumber: 0,
      score: 100,
      succeeded: true,
      durationMs: 50
    )

    XCTAssertEqual(attempt.interfaceNumber, 0)
    XCTAssertEqual(attempt.score, 100)
    XCTAssertTrue(attempt.succeeded)
    XCTAssertEqual(attempt.durationMs, 50)
    XCTAssertNil(attempt.error)
  }

  func testInterfaceAttemptResultFailure() {
    let attempt = InterfaceAttemptResult(
      interfaceNumber: 1,
      score: 50,
      succeeded: false,
      durationMs: 10,
      error: "Timeout"
    )

    XCTAssertEqual(attempt.interfaceNumber, 1)
    XCTAssertEqual(attempt.score, 50)
    XCTAssertFalse(attempt.succeeded)
    XCTAssertEqual(attempt.durationMs, 10)
    XCTAssertEqual(attempt.error, "Timeout")
  }

  // MARK: - SessionProbeResult Tests

  func testSessionProbeResultDefaultValues() {
    let result = SessionProbeResult()
    XCTAssertFalse(result.succeeded)
    XCTAssertFalse(result.requiredRetry)
    XCTAssertEqual(result.durationMs, 0)
    XCTAssertNil(result.error)
  }

  func testSessionProbeResultSuccess() {
    var result = SessionProbeResult()
    result.succeeded = true
    result.requiredRetry = false
    result.durationMs = 100

    XCTAssertTrue(result.succeeded)
    XCTAssertFalse(result.requiredRetry)
    XCTAssertEqual(result.durationMs, 100)
  }

  func testSessionProbeResultWithRetry() {
    var result = SessionProbeResult()
    result.succeeded = true
    result.requiredRetry = true
    result.durationMs = 250
    result.error = "SessionAlreadyOpen"

    XCTAssertTrue(result.succeeded)
    XCTAssertTrue(result.requiredRetry)
    XCTAssertEqual(result.durationMs, 250)
    XCTAssertEqual(result.error, "SessionAlreadyOpen")
  }

  // MARK: - PolicySummary Tests

  func testPolicySummaryFromPolicy() {
    var fallbacks = FallbackSelections()
    fallbacks.enumeration = .propList5
    fallbacks.read = .partial64
    fallbacks.write = .partial

    let flags = QuirkFlags()
    let tuning = EffectiveTuning(
      maxChunkBytes: 4 * 1024 * 1024,
      ioTimeoutMs: 15_000,
      handshakeTimeoutMs: 8_000,
      inactivityTimeoutMs: 10_000,
      overallDeadlineMs: 60_000,
      stabilizeMs: 500,
      postClaimStabilizeMs: 100,
      postProbeStabilizeMs: 0,
      resetOnOpen: true,
      disableEventPump: false,
      operations: [:],
      hooks: []
    )

    let policy = DevicePolicy(
      tuning: tuning,
      flags: flags,
      fallbacks: fallbacks
    )

    let summary = PolicySummary(from: policy)

    XCTAssertEqual(summary.enumerationStrategy, "propList5")
    XCTAssertEqual(summary.readStrategy, "partial64")
    XCTAssertEqual(summary.writeStrategy, "partial")
    XCTAssertEqual(summary.resetOnOpen, flags.resetOnOpen)
    XCTAssertEqual(summary.disableEventPump, flags.disableEventPump)
    XCTAssertEqual(summary.maxChunkBytes, tuning.maxChunkBytes)
    XCTAssertEqual(summary.ioTimeoutMs, tuning.ioTimeoutMs)
  }

  // MARK: - ProbeReceipt Codable Tests

  func testProbeReceiptCodable() throws {
    let summary = MTPDeviceSummary(
      id: MTPDeviceID(raw: "test-device-123"),
      manufacturer: "TestCo",
      model: "MTP Device",
      vendorID: 0x1234,
      productID: 0x5678,
      bus: 1,
      address: 2
    )

    let fingerprint = MTPDeviceFingerprint.fromUSB(
      vid: 0x1234,
      pid: 0x5678,
      interfaceClass: 6,
      interfaceSubclass: 1,
      interfaceProtocol: 1,
      epIn: 0x81,
      epOut: 0x01
    )

    var receipt = ProbeReceipt(
      deviceSummary: ReceiptDeviceSummary(from: summary),
      fingerprint: fingerprint
    )
    receipt.capabilities = ["test": true]
    receipt.totalProbeTimeMs = 100

    let encoder = JSONEncoder()
    let decoder = JSONDecoder()

    let data = try encoder.encode(receipt)
    let decoded = try decoder.decode(ProbeReceipt.self, from: data)

    XCTAssertEqual(receipt.deviceSummary.id, decoded.deviceSummary.id)
    XCTAssertEqual(receipt.capabilities, decoded.capabilities)
    XCTAssertEqual(receipt.totalProbeTimeMs, decoded.totalProbeTimeMs)
  }
}
