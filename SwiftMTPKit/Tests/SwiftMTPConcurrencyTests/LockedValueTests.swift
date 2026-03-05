// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import XCTest
@testable import SwiftMTPConcurrency

final class LockedValueTests: XCTestCase {
  func testLockedValueMutationAndRead() {
    let value = LockedValue(3)
    value.withValue { $0 += 4 }
    XCTAssertEqual(value.read(), 7)
  }

  func testAtomicIntCounterGetAndAdd() {
    let counter = AtomicIntCounter(10)
    XCTAssertEqual(counter.getAndAdd(5), 10)
    XCTAssertEqual(counter.get(), 15)
  }

  func testAtomicUInt64CounterAdd() {
    let counter = AtomicUInt64Counter(2)
    XCTAssertEqual(counter.add(5), 7)
    XCTAssertEqual(counter.get(), 7)
  }
}
