// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import XCTest

@testable import swiftmtp_cli
import SwiftMTPCore

// MARK: - Collect Command Enhanced Tests

final class CollectEnhancedTests: XCTestCase {

  // MARK: - Strict Validation Tests

  func testStrictValidationCatchesMissingVendorId() {
    let manifest = makeManifest(vendorId: "0x0000")
    let issues = CollectCommand.validateSubmissionManifest(manifest)
    XCTAssertTrue(issues.contains("missing or zero vendorId"))
  }

  func testStrictValidationCatchesMissingProductId() {
    let manifest = makeManifest(productId: "0x0000")
    let issues = CollectCommand.validateSubmissionManifest(manifest)
    XCTAssertTrue(issues.contains("missing or zero productId"))
  }

  func testStrictValidationCatchesMissingVendorName() {
    let manifest = makeManifest(vendor: "")
    let issues = CollectCommand.validateSubmissionManifest(manifest)
    XCTAssertTrue(issues.contains("missing vendor name"))
  }

  func testStrictValidationCatchesMissingModelName() {
    let manifest = makeManifest(model: "")
    let issues = CollectCommand.validateSubmissionManifest(manifest)
    XCTAssertTrue(issues.contains("missing model name"))
  }

  func testStrictValidationCatchesMissingSerial() {
    let manifest = makeManifest(serialRedacted: "")
    let issues = CollectCommand.validateSubmissionManifest(manifest)
    XCTAssertTrue(issues.contains("missing redacted serial"))
  }

  func testStrictValidationCatchesUnsetToolVersion() {
    let manifest = makeManifest(toolVersion: "0.0.0")
    let issues = CollectCommand.validateSubmissionManifest(manifest)
    XCTAssertTrue(issues.contains("tool version not set"))
  }

  func testStrictValidationCatchesMissingTimestamp() {
    let manifest = makeManifest(timestamp: "")
    let issues = CollectCommand.validateSubmissionManifest(manifest)
    XCTAssertTrue(issues.contains("missing timestamp"))
  }

  func testStrictValidationPassesForValidManifest() {
    let manifest = makeManifest()
    let issues = CollectCommand.validateSubmissionManifest(manifest)
    XCTAssertTrue(issues.isEmpty, "Expected no validation issues but got: \(issues)")
  }

  func testStrictValidationReportsMultipleIssues() {
    let manifest = makeManifest(vendorId: "0x0000", model: "", timestamp: "")
    let issues = CollectCommand.validateSubmissionManifest(manifest)
    XCTAssertTrue(issues.count >= 3, "Expected at least 3 issues but got \(issues.count)")
  }

  // MARK: - JSON Output Tests

  func testCollectionOutputEncodesToValidJSON() throws {
    let output = makeCollectionOutputJSON()
    let data = try JSONEncoder().encode(output)
    let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    XCTAssertNotNil(json)
    XCTAssertEqual(json?["schemaVersion"] as? String, "1.0.0")
    XCTAssertEqual(json?["redacted"] as? Bool, true)
    XCTAssertEqual(json?["validated"] as? Bool, true)
    XCTAssertEqual(json?["mode"] as? String, "strict")
  }

  func testCollectionOutputContainsDeviceInfo() throws {
    let output = makeCollectionOutputJSON()
    let data = try JSONEncoder().encode(output)
    let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    XCTAssertEqual(json?["deviceVID"] as? UInt16, 0x2717)
    XCTAssertEqual(json?["devicePID"] as? UInt16, 0xFF10)
  }

  // MARK: - Redact Flag Tests

  func testRedactFlagDefaultsToTrue() {
    let flags = CollectCommand.CollectFlags()
    XCTAssertTrue(flags.redact)
  }

  func testRedactFlagCanBeDisabled() {
    let flags = CollectCommand.CollectFlags(redact: false)
    XCTAssertFalse(flags.redact)
  }

  func testPrivacyRedactorStripsSerial() {
    let serial = "ABC123DEF456GHI789"
    let redacted = PrivacyRedactor.redactSerial(serial)
    // Redacted format: first 4 chars + "…" + 8-char hash
    XCTAssertTrue(redacted.hasPrefix("ABC1"))
    XCTAssertTrue(redacted.contains("…"))
    XCTAssertFalse(redacted.contains("DEF456GHI789"))
  }

  func testPrivacyRedactorRedactsSubmissionPaths() {
    let dict: [String: Any] = [
      "bundlePath": "/Users/alice/submissions/bundle-1",
      "vendorId": "0x2717",
    ]
    let redacted = PrivacyRedactor.redactSubmission(dict)
    let path = redacted["bundlePath"] as? String ?? ""
    XCTAssertFalse(path.contains("alice"), "Path should be redacted")
    XCTAssertTrue(path.contains("[redacted]"))
    // Safe keys should not be touched
    XCTAssertEqual(redacted["vendorId"] as? String, "0x2717")
  }

  func testPrivacyRedactorPreservesProtocolKeys() {
    let dict: [String: Any] = [
      "vendorId": "0x04e8",
      "productId": "0x6860",
      "formatCode": "0x3001",
      "interface": "MTP",
    ]
    let redacted = PrivacyRedactor.redactSubmission(dict)
    XCTAssertEqual(redacted["vendorId"] as? String, "0x04e8")
    XCTAssertEqual(redacted["productId"] as? String, "0x6860")
    XCTAssertEqual(redacted["formatCode"] as? String, "0x3001")
  }

  // MARK: - Noninteractive Flag Tests

  func testNoninteractiveFlagDefault() {
    let flags = CollectCommand.CollectFlags()
    XCTAssertFalse(flags.noninteractive)
  }

  func testNoninteractiveFlagCanBeEnabled() {
    let flags = CollectCommand.CollectFlags(noninteractive: true)
    XCTAssertTrue(flags.noninteractive)
  }

  // MARK: - Validation Error Tests

  func testValidationFailedErrorDescription() {
    let err = CollectCommand.CollectError.validationFailed([
      "missing vendor name", "missing model name",
    ])
    let desc = err.errorDescription ?? ""
    XCTAssertTrue(desc.contains("missing vendor name"))
    XCTAssertTrue(desc.contains("missing model name"))
    XCTAssertTrue(desc.contains("strict mode"))
  }

  // MARK: - Collection Summary Tests

  func testBuildCollectionSummaryContainsDeviceInfo() {
    let manifest = makeManifest()
    let summary = CollectCommand.buildCollectionSummary(
      bundleURL: URL(fileURLWithPath: "/tmp/test-bundle"),
      manifest: manifest,
      redacted: true
    )
    XCTAssertTrue(summary.contains("TestVendor"))
    XCTAssertTrue(summary.contains("TestModel"))
    XCTAssertTrue(summary.contains("0x2717"))
    XCTAssertTrue(summary.contains("applied"))
  }

  func testBuildCollectionSummaryShowsRedactionDisabled() {
    let manifest = makeManifest()
    let summary = CollectCommand.buildCollectionSummary(
      bundleURL: URL(fileURLWithPath: "/tmp/test-bundle"),
      manifest: manifest,
      redacted: false
    )
    XCTAssertTrue(summary.contains("disabled"))
  }

  // MARK: - Helpers

  private func makeManifest(
    vendorId: String = "0x2717",
    productId: String = "0xff10",
    vendor: String = "TestVendor",
    model: String = "TestModel",
    serialRedacted: String = "hmacsha256:abcdef1234567890",
    toolVersion: String = "1.0.0",
    timestamp: String = "2025-01-01T00:00:00Z"
  ) -> CollectCommand.SubmissionManifest {
    CollectCommand.SubmissionManifest(
      tool: .init(version: toolVersion, commit: "abc1234"),
      host: .init(os: "macOS 15.0", arch: "arm64"),
      timestamp: timestamp,
      user: .init(github: "testuser"),
      device: .init(
        vendorId: vendorId,
        productId: productId,
        bcdDevice: "0x0100",
        vendor: vendor,
        model: model,
        interface: .init(
          class: "0x06", subclass: "0x01", protocol: "0x01",
          in: "0x81", out: "0x01", evt: "0x82"
        ),
        fingerprintHash: "sha256:abc",
        serialRedacted: serialRedacted
      ),
      artifacts: .init(probe: "probe.json", usbDump: "usb-dump.txt", bench: nil, benchSummary: nil),
      consent: .init(anonymizeSerial: true, allowBench: false)
    )
  }

  private struct TestCollectionOutput: Codable {
    let schemaVersion: String
    let timestamp: String
    let bundlePath: String
    let deviceVID: UInt16
    let devicePID: UInt16
    let bus: Int
    let address: Int
    let mode: String
    let redacted: Bool
    let validated: Bool
  }

  private func makeCollectionOutputJSON() -> TestCollectionOutput {
    TestCollectionOutput(
      schemaVersion: "1.0.0",
      timestamp: "2025-01-01T00:00:00Z",
      bundlePath: "/tmp/test-bundle",
      deviceVID: 0x2717,
      devicePID: 0xFF10,
      bus: 1,
      address: 5,
      mode: "strict",
      redacted: true,
      validated: true
    )
  }
}
