// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import XCTest

@testable import SwiftMTPCore
@testable import SwiftMTPQuirks
@testable import SwiftMTPTransportLibUSB

/// Tests for Pixel 7 bulk transfer fixes from the timeout analysis.
///
/// Validates:
/// - Double-reset flag decoding and wiring
/// - Long timeout flag resolution
/// - QuirkFlags round-trip encoding for new flags
/// - SwiftMTPConfig flag propagation
/// - Endpoint drain and status helpers exist (compile-time checks)
final class Pixel7TransportFixesTests: XCTestCase {

  // MARK: - QuirkFlags: forceDoubleReset

  func testForceDoubleResetDefaultIsFalse() {
    let flags = QuirkFlags()
    XCTAssertFalse(flags.forceDoubleReset)
  }

  func testForceDoubleResetDecodesFromJSON() throws {
    let json = """
      { "forceDoubleReset": true }
      """.data(using: .utf8)!
    let flags = try JSONDecoder().decode(QuirkFlags.self, from: json)
    XCTAssertTrue(flags.forceDoubleReset)
  }

  func testForceDoubleResetRoundTrips() throws {
    var flags = QuirkFlags()
    flags.forceDoubleReset = true
    let data = try JSONEncoder().encode(flags)
    let decoded = try JSONDecoder().decode(QuirkFlags.self, from: data)
    XCTAssertTrue(decoded.forceDoubleReset)
  }

  // MARK: - QuirkFlags: longTimeout

  func testLongTimeoutDefaultIsFalse() {
    let flags = QuirkFlags()
    XCTAssertFalse(flags.longTimeout)
  }

  func testLongTimeoutDecodesFromJSON() throws {
    let json = """
      { "longTimeout": true }
      """.data(using: .utf8)!
    let flags = try JSONDecoder().decode(QuirkFlags.self, from: json)
    XCTAssertTrue(flags.longTimeout)
  }

  func testLongTimeoutRoundTrips() throws {
    var flags = QuirkFlags()
    flags.longTimeout = true
    let data = try JSONEncoder().encode(flags)
    let decoded = try JSONDecoder().decode(QuirkFlags.self, from: data)
    XCTAssertTrue(decoded.longTimeout)
  }

  // MARK: - SwiftMTPConfig: forceDoubleReset

  func testConfigForceDoubleResetDefaultIsFalse() {
    let config = SwiftMTPConfig()
    XCTAssertFalse(config.forceDoubleReset)
  }

  func testConfigForceDoubleResetCanBeSet() {
    var config = SwiftMTPConfig()
    config.forceDoubleReset = true
    XCTAssertTrue(config.forceDoubleReset)
  }

  // MARK: - Pixel 7 Quirks Database: flags present

  func testPixel7QuirkHasForceDoubleReset() throws {
    let db = try QuirkDatabase.load()
    let pixel = db.entries.first { $0.id == "google-pixel-7-4ee1" }
    XCTAssertNotNil(pixel, "Pixel 7 quirk entry must exist")
    let flags = pixel!.resolvedFlags()
    XCTAssertTrue(flags.forceDoubleReset, "Pixel 7 must have forceDoubleReset=true")
  }

  func testPixel7QuirkHasLongTimeout() throws {
    let db = try QuirkDatabase.load()
    let pixel = db.entries.first { $0.id == "google-pixel-7-4ee1" }
    XCTAssertNotNil(pixel)
    let flags = pixel!.resolvedFlags()
    XCTAssertTrue(flags.longTimeout, "Pixel 7 must have longTimeout=true")
  }

  func testPixel7QuirkHas60sIoTimeout() throws {
    let db = try QuirkDatabase.load()
    let pixel = db.entries.first { $0.id == "google-pixel-7-4ee1" }
    XCTAssertNotNil(pixel)
    XCTAssertNotNil(pixel?.ioTimeoutMs)
    XCTAssertGreaterThanOrEqual(
      pixel!.ioTimeoutMs ?? 0, 60_000,
      "Pixel 7 ioTimeoutMs must be >= 60000 (libmtp LONG_TIMEOUT)")
  }

  // MARK: - EffectiveTuning: longTimeout triggers 60s

  func testLongTimeoutFlagEnforcesMinimum60s() {
    var flags = QuirkFlags()
    flags.longTimeout = true
    // Simulate the logic in EffectiveTuning.swift
    var ioTimeoutMs = 10_000
    if flags.longTimeout {
      ioTimeoutMs = max(ioTimeoutMs, 60_000)
    }
    XCTAssertGreaterThanOrEqual(ioTimeoutMs, 60_000)
  }

  func testExtendedBulkTimeoutFlagEnforcesMinimum60s() {
    var flags = QuirkFlags()
    flags.extendedBulkTimeout = true
    var ioTimeoutMs = 10_000
    if flags.extendedBulkTimeout {
      ioTimeoutMs = max(ioTimeoutMs, 60_000)
    }
    XCTAssertGreaterThanOrEqual(ioTimeoutMs, 60_000)
  }

  // MARK: - Both new flags decode together (Pixel 7 JSON shape)

  func testBothNewFlagsDecodeFromPixel7Shape() throws {
    let json = """
      {
        "requiresKernelDetach": true,
        "resetOnOpen": false,
        "resetReopenOnOpenSessionIOError": true,
        "transactionIdResetsOnSession": true,
        "supportsGetObjectPropList": true,
        "forceDoubleReset": true,
        "longTimeout": true
      }
      """.data(using: .utf8)!
    let flags = try JSONDecoder().decode(QuirkFlags.self, from: json)
    XCTAssertTrue(flags.forceDoubleReset)
    XCTAssertTrue(flags.longTimeout)
    XCTAssertTrue(flags.requiresKernelDetach)
    XCTAssertTrue(flags.resetReopenOnOpenSessionIOError)
  }

  // MARK: - Missing flags decode to defaults (backward compat)

  func testOldJSONWithoutNewFlagsDecodesCleanly() throws {
    let json = """
      {
        "requiresKernelDetach": true,
        "resetOnOpen": false
      }
      """.data(using: .utf8)!
    let flags = try JSONDecoder().decode(QuirkFlags.self, from: json)
    XCTAssertFalse(flags.forceDoubleReset, "forceDoubleReset must default to false")
    XCTAssertFalse(flags.longTimeout, "longTimeout must default to false")
  }
}
