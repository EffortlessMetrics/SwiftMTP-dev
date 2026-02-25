// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import XCTest
@testable import SwiftMTPCore

final class MTPEventCoalescerTests: XCTestCase {

  func testFirstEventIsAlwaysForwarded() {
    let coalescer = MTPEventCoalescer(window: 0.05)
    XCTAssertTrue(coalescer.shouldForward(), "First event must always be forwarded")
  }

  func testSecondEventWithinWindowIsCoalesced() {
    let coalescer = MTPEventCoalescer(window: 0.05)
    XCTAssertTrue(coalescer.shouldForward())
    // Second call arrives immediately — well within the 50 ms window.
    XCTAssertFalse(coalescer.shouldForward(), "Event within window should be coalesced")
  }

  func testThirdEventAfterWindowExpiryIsForwarded() async throws {
    let coalescer = MTPEventCoalescer(window: 0.05)
    XCTAssertTrue(coalescer.shouldForward())
    // Wait for the window to expire.
    try await Task.sleep(nanoseconds: 60_000_000)  // 60 ms > 50 ms window
    XCTAssertTrue(coalescer.shouldForward(), "Event after window expiry must be forwarded")
  }

  func testEventExactlyAtWindowBoundaryIsForwarded() async throws {
    // Use a very short window so the sleep comfortably clears it.
    let coalescer = MTPEventCoalescer(window: 0.01)
    XCTAssertTrue(coalescer.shouldForward())
    // Sleep slightly beyond the window boundary.
    try await Task.sleep(nanoseconds: 15_000_000)  // 15 ms > 10 ms window
    XCTAssertTrue(coalescer.shouldForward(), "Event at/after window boundary must be forwarded")
  }
}
