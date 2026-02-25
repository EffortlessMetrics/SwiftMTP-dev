// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import XCTest
@testable import SwiftMTPCore
@testable import SwiftMTPQuirks

/// Tests for FallbackSelections and related strategy types
final class FallbackSelectionTests: XCTestCase {

  // MARK: - FallbackSelections Basic Tests

  func testFallbackSelectionsDefaultValues() {
    let fallbacks = FallbackSelections()
    XCTAssertEqual(fallbacks.enumeration, .unknown)
    XCTAssertEqual(fallbacks.read, .unknown)
    XCTAssertEqual(fallbacks.write, .unknown)
  }

  func testFallbackSelectionsInitialization() {
    let fallbacks = FallbackSelections()
    XCTAssertNotNil(fallbacks)
  }

  func testFallbackSelectionsEquality() {
    let fallbacks1 = FallbackSelections()
    let fallbacks2 = FallbackSelections()
    XCTAssertEqual(fallbacks1, fallbacks2)
  }

  func testFallbackSelectionsInequality() {
    var fallbacks1 = FallbackSelections()
    var fallbacks2 = FallbackSelections()

    fallbacks1.enumeration = .propList5
    fallbacks2.enumeration = .handlesThenInfo

    XCTAssertNotEqual(fallbacks1, fallbacks2)
  }

  // MARK: - EnumerationStrategy Tests

  func testEnumerationStrategyPropList5() {
    let strategy = FallbackSelections.EnumerationStrategy.propList5
    XCTAssertEqual(strategy.rawValue, "propList5")
  }

  func testEnumerationStrategyPropList3() {
    let strategy = FallbackSelections.EnumerationStrategy.propList3
    XCTAssertEqual(strategy.rawValue, "propList3")
  }

  func testEnumerationStrategyHandlesThenInfo() {
    let strategy = FallbackSelections.EnumerationStrategy.handlesThenInfo
    XCTAssertEqual(strategy.rawValue, "handlesThenInfo")
  }

  func testEnumerationStrategyUnknown() {
    let strategy = FallbackSelections.EnumerationStrategy.unknown
    XCTAssertEqual(strategy.rawValue, "unknown")
  }

  // MARK: - ReadStrategy Tests

  func testReadStrategyPartial64() {
    let strategy = FallbackSelections.ReadStrategy.partial64
    XCTAssertEqual(strategy.rawValue, "partial64")
  }

  func testReadStrategyPartial32() {
    let strategy = FallbackSelections.ReadStrategy.partial32
    XCTAssertEqual(strategy.rawValue, "partial32")
  }

  func testReadStrategyWholeObject() {
    let strategy = FallbackSelections.ReadStrategy.wholeObject
    XCTAssertEqual(strategy.rawValue, "wholeObject")
  }

  func testReadStrategyUnknown() {
    let strategy = FallbackSelections.ReadStrategy.unknown
    XCTAssertEqual(strategy.rawValue, "unknown")
  }

  // MARK: - WriteStrategy Tests

  func testWriteStrategyPartial() {
    let strategy = FallbackSelections.WriteStrategy.partial
    XCTAssertEqual(strategy.rawValue, "partial")
  }

  func testWriteStrategyWholeObject() {
    let strategy = FallbackSelections.WriteStrategy.wholeObject
    XCTAssertEqual(strategy.rawValue, "wholeObject")
  }

  func testWriteStrategyUnknown() {
    let strategy = FallbackSelections.WriteStrategy.unknown
    XCTAssertEqual(strategy.rawValue, "unknown")
  }

  // MARK: - FallbackSelections Mutation Tests

  func testFallbackSelectionsSetEnumeration() {
    var fallbacks = FallbackSelections()
    fallbacks.enumeration = .handlesThenInfo
    XCTAssertEqual(fallbacks.enumeration, .handlesThenInfo)
  }

  func testFallbackSelectionsSetRead() {
    var fallbacks = FallbackSelections()
    fallbacks.read = .partial64
    XCTAssertEqual(fallbacks.read, .partial64)
  }

  func testFallbackSelectionsSetWrite() {
    var fallbacks = FallbackSelections()
    fallbacks.write = .partial
    XCTAssertEqual(fallbacks.write, .partial)
  }

  func testFallbackSelectionsFullConfiguration() {
    var fallbacks = FallbackSelections()
    fallbacks.enumeration = .propList5
    fallbacks.read = .partial64
    fallbacks.write = .partial

    XCTAssertEqual(fallbacks.enumeration, .propList5)
    XCTAssertEqual(fallbacks.read, .partial64)
    XCTAssertEqual(fallbacks.write, .partial)
  }

  func testFallbackSelectionsCodable() {
    let fallbacks = FallbackSelections()
    let encoder = JSONEncoder()
    let decoder = JSONDecoder()

    do {
      let data = try encoder.encode(fallbacks)
      let decoded = try decoder.decode(FallbackSelections.self, from: data)
      XCTAssertEqual(fallbacks, decoded)
    } catch {
      XCTFail("Codable should work: \(error)")
    }
  }

  // MARK: - Strategy Combinations Tests

  func testStrategyCombinationPropList5WithPartialRead() {
    var fallbacks = FallbackSelections()
    fallbacks.enumeration = .propList5
    fallbacks.read = .partial64
    fallbacks.write = .wholeObject

    XCTAssertEqual(fallbacks.enumeration, .propList5)
    XCTAssertEqual(fallbacks.read, .partial64)
    XCTAssertEqual(fallbacks.write, .wholeObject)
  }

  func testStrategyCombinationHandlesThenInfoWithWholeObject() {
    var fallbacks = FallbackSelections()
    fallbacks.enumeration = .handlesThenInfo
    fallbacks.read = .wholeObject
    fallbacks.write = .partial

    XCTAssertEqual(fallbacks.enumeration, .handlesThenInfo)
    XCTAssertEqual(fallbacks.read, .wholeObject)
    XCTAssertEqual(fallbacks.write, .partial)
  }
}
