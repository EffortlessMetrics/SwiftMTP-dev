// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import XCTest
@testable import SwiftMTPCore

/// Tests for Exit.swift CLI module
final class ExitTests: XCTestCase {

  // MARK: - ExitCode Enum Tests

  func testExitCodeValues() {
    // Verify all exit codes have expected values
    XCTAssertEqual(ExitCode.ok.rawValue, 0)
    XCTAssertEqual(ExitCode.usage.rawValue, 64)
    XCTAssertEqual(ExitCode.unavailable.rawValue, 69)
    XCTAssertEqual(ExitCode.software.rawValue, 70)
    XCTAssertEqual(ExitCode.tempfail.rawValue, 75)
  }

  func testExitCodeSendableConformance() {
    // Verify ExitCode conforms to Sendable
    let _: Sendable = ExitCode.ok
    let _: Sendable = ExitCode.software
    XCTAssertTrue(true)
  }

  func testExitCodeRawValueConsistency() {
    // Verify raw values are consistent with standard exit codes
    // EX_USAGE = 64
    XCTAssertEqual(ExitCode.usage.rawValue, 64)
    // EX_UNAVAILABLE = 69
    XCTAssertEqual(ExitCode.unavailable.rawValue, 69)
    // EX_SOFTWARE = 70
    XCTAssertEqual(ExitCode.software.rawValue, 70)
    // EX_TEMPFAIL = 75
    XCTAssertEqual(ExitCode.tempfail.rawValue, 75)
  }

  func testExitCodeEquality() {
    XCTAssertEqual(ExitCode.ok, ExitCode.ok)
    XCTAssertEqual(ExitCode.usage, ExitCode.usage)
    XCTAssertNotEqual(ExitCode.ok, ExitCode.usage)
    XCTAssertNotEqual(ExitCode.ok, ExitCode.software)
  }

  // MARK: - ExitCode Description Tests

  func testExitCodeDescription() {
    let okDescription = String(describing: ExitCode.ok)
    XCTAssertFalse(okDescription.isEmpty)

    let usageDescription = String(describing: ExitCode.usage)
    XCTAssertFalse(usageDescription.isEmpty)
  }

  // MARK: - ExitCode Common Use Cases

  func testExitCodeForSuccess() {
    // Success case
    let result: ExitCode = .ok
    XCTAssertEqual(result.rawValue, 0)
  }

  func testExitCodeForInvalidArgument() {
    // Invalid argument / usage error
    let result: ExitCode = .usage
    XCTAssertEqual(result.rawValue, 64)
  }

  func testExitCodeForUnavailableResource() {
    // Resource temporarily unavailable
    let result: ExitCode = .unavailable
    XCTAssertEqual(result.rawValue, 69)
  }

  func testExitCodeForInternalError() {
    // Internal software error
    let result: ExitCode = .software
    XCTAssertEqual(result.rawValue, 70)
  }

  func testExitCodeForTemporaryFailure() {
    // Temporary failure / retryable error
    let result: ExitCode = .tempfail
    XCTAssertEqual(result.rawValue, 75)
  }

  // MARK: - ExitCode Array/Collection Tests

  func testAllExitCodesEnumerable() {
    let allCodes: [ExitCode] = [.ok, .usage, .unavailable, .software, .tempfail]
    XCTAssertEqual(allCodes.count, 5)

    // Verify we can iterate
    var foundOk = false
    for code in allCodes {
      if case .ok = code {
        foundOk = true
      }
    }
    XCTAssertTrue(foundOk)
  }

  func testExitCodeHashable() {
    let set: Set<ExitCode> = [.ok, .usage, .ok]
    XCTAssertEqual(set.count, 2)

    let dict: [ExitCode: String] = [.ok: "success", .software: "error"]
    XCTAssertEqual(dict[.ok], "success")
    XCTAssertEqual(dict[.software], "error")
  }
}
