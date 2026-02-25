// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import XCTest
@testable import swiftmtp_cli

final class CollectPrivacyTests: XCTestCase {
  func testRedactionUsesStableHMACForSameSalt() throws {
    let salt = Data("fixture-salt-for-tests".utf8)
    let first = Redaction.redactSerial("ABCD-1234", salt: salt)
    let second = Redaction.redactSerial("ABCD-1234", salt: salt)
    let different = Redaction.redactSerial("EFGH-5678", salt: salt)

    XCTAssertEqual(first, second)
    XCTAssertNotEqual(first, different)
    XCTAssertTrue(first.hasPrefix("hmacsha256:"))
  }

  func testGenerateSaltLength() throws {
    let salt = Redaction.generateSalt(count: 48)
    XCTAssertEqual(salt.count, 48)
  }

  func testRedactionWithBinarySaltDoesNotCrash() throws {
    let salt = Redaction.generateSalt(count: 32)
    let value = Redaction.redactSerial("ABCD-1234", salt: salt)

    XCTAssertTrue(value.hasPrefix("hmacsha256:"))
    XCTAssertEqual(value.count, "hmacsha256:".count + 64)
  }

  func testRedactorTokenizeFilenamePreservesExtension() throws {
    let redactor = Redactor(bundleKey: "unit-test-key")
    let token = redactor.tokenizeFilename("private-report.txt")

    XCTAssertTrue(token.hasPrefix("file_"))
    XCTAssertTrue(token.hasSuffix(".txt"))
    XCTAssertNotEqual(token, "private-report.txt")
  }

  // MARK: - CollectError actionable messages (Sprint 2.1-B)

  func testCollectErrorNoDeviceMatchedContainsProbeHint() {
    let err = CollectCommand.CollectError.noDeviceMatched(candidates: [])
    XCTAssertTrue(err.errorDescription?.contains("swiftmtp probe") == true)
    XCTAssertTrue(err.errorDescription?.contains("--vid") == true)
  }

  func testCollectErrorAmbiguousSelectionContainsFilterHint() {
    let err = CollectCommand.CollectError.ambiguousSelection(count: 3, candidates: [])
    XCTAssertTrue(err.errorDescription?.contains("3") == true)
    XCTAssertTrue(err.errorDescription?.contains("--vid") == true)
  }

  func testCollectErrorRedactionCheckContainsRemediationHint() {
    let err = CollectCommand.CollectError.redactionCheckFailed(["serial", "ipv4"])
    let desc = err.errorDescription ?? ""
    XCTAssertTrue(desc.contains("serial"))
    XCTAssertTrue(desc.contains("swiftmtp redact"))
    XCTAssertTrue(desc.contains("--no-strict"))
  }

  func testCollectErrorInvalidBenchSizeContainsBounds() {
    let err = CollectCommand.CollectError.invalidBenchSize("0")
    let desc = err.errorDescription ?? ""
    XCTAssertTrue(desc.contains("0"))
    XCTAssertTrue(desc.contains("1 MB") || desc.contains("≥"))
  }

  func testCollectErrorTimeoutContainsHint() {
    let err = CollectCommand.CollectError.timeout(30000)
    let desc = err.errorDescription ?? ""
    XCTAssertTrue(desc.contains("30000"))
    XCTAssertTrue(desc.contains("--io-timeout") || desc.contains("retry"))
  }
}
