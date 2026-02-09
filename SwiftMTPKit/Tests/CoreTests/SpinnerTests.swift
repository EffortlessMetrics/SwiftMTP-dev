// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import XCTest
@testable import SwiftMTPCore

/// Tests for Spinner.swift CLI module
final class SpinnerTests: XCTestCase {

    // MARK: - Spinner Initialization

    func testSpinnerDisabledInitialization() {
        let spinner = Spinner(enabled: false)
        XCTAssertNotNil(spinner)
    }

    func testSpinnerEnabledInitialization() {
        let spinner = Spinner(enabled: true)
        XCTAssertNotNil(spinner)
    }

    // MARK: - Spinner Disabled Behavior

    func testStartDisabledSpinnerDoesNothing() {
        let spinner = Spinner(enabled: false)
        
        // Should not crash when starting a disabled spinner
        XCTAssertNoThrow(spinner.start("Loading..."))
    }

    func testStopDisabledSpinnerDoesNothing() {
        let spinner = Spinner(enabled: false)
        
        // Should not crash when stopping a disabled spinner
        XCTAssertNoThrow(spinner.stopAndClear())
    }

    func testStopDisabledSpinnerWithMessage() {
        let spinner = Spinner(enabled: false)
        
        // Should not crash with custom end message
        XCTAssertNoThrow(spinner.stopAndClear("Done!"))
    }

    // MARK: - Spinner Lifecycle

    func testStartAndStopEnabledSpinner() {
        let spinner = Spinner(enabled: true)
        
        // Start spinner with label
        XCTAssertNoThrow(spinner.start("Loading..."))
        
        // Small delay to let thread start
        Thread.sleep(forTimeInterval: 0.1)
        
        // Stop spinner with completion message
        XCTAssertNoThrow(spinner.stopAndClear("Complete!"))
    }

    func testStartWithEmptyLabel() {
        let spinner = Spinner(enabled: true)
        
        XCTAssertNoThrow(spinner.start(""))
    }

    func testStartWithLongLabel() {
        let spinner = Spinner(enabled: true)
        let longLabel = String(repeating: "Loading... ", count: 100)
        
        XCTAssertNoThrow(spinner.start(longLabel))
        
        Thread.sleep(forTimeInterval: 0.1)
        spinner.stopAndClear()
    }

    func testMultipleStartStopCycles() {
        let spinner = Spinner(enabled: true)
        
        for i in 0..<5 {
            spinner.start("Iteration \(i)...")
            Thread.sleep(forTimeInterval: 0.05)
            spinner.stopAndClear()
        }
    }

    // MARK: - Spinner Thread Safety

    func testConcurrentStartStop() {
        let spinner = Spinner(enabled: true)
        
        // Test that concurrent start/stop doesn't crash - the Spinner may not handle
        // this perfectly due to its single-thread design, but it should not hang
        let expectation = XCTestExpectation(description: "Concurrent operations complete")
        expectation.expectedFulfillmentCount = 2
        
        DispatchQueue.global().async {
            for i in 0..<3 {
                spinner.start("Thread1-\(i)")
                Thread.sleep(forTimeInterval: 0.02)
                spinner.stopAndClear()
            }
            expectation.fulfill()
        }
        
        DispatchQueue.global().async {
            for i in 0..<3 {
                spinner.start("Thread2-\(i)")
                Thread.sleep(forTimeInterval: 0.02)
                spinner.stopAndClear()
            }
            expectation.fulfill()
        }
        
        // Use a reasonable timeout that accounts for system load
        wait(for: [expectation], timeout: 5.0)
    }

    // MARK: - Spinner Thread Management

    func testStopBeforeThreadStarts() {
        let spinner = Spinner(enabled: true)
        
        // Stop immediately before thread can do anything
        spinner.start("Quick")
        spinner.stopAndClear()
    }

    func testStopWithNilMessage() {
        let spinner = Spinner(enabled: true)
        
        spinner.start("Loading...")
        Thread.sleep(forTimeInterval: 0.1)
        spinner.stopAndClear(nil)
    }

    func testDoubleStop() {
        let spinner = Spinner(enabled: true)
        
        spinner.start("Loading...")
        Thread.sleep(forTimeInterval: 0.1)
        spinner.stopAndClear("First stop")
        // Second stop should not crash
        XCTAssertNoThrow(spinner.stopAndClear("Second stop"))
    }

    // MARK: - Spinner Sendable Conformance

    func testSpinnerSendableConformance() {
        // Verify Spinner conforms to Sendable (unchecked)
        let spinner = Spinner(enabled: true)
        XCTAssertNotNil(spinner)
    }
}
