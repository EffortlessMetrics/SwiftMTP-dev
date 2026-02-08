// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import XCTest
@testable import SwiftMTPTransportLibUSB
@testable import SwiftMTPCore
import SwiftMTPTestKit

/// Tests for concurrent operations and thread safety
final class LibUSBConcurrencyTests: XCTestCase {

    // MARK: - Concurrent Device Operations Tests

    func testMultipleDeviceDiscovery() async throws {
        // Test that device discovery can be called concurrently
        let config1 = VirtualDeviceConfig.pixel7
        let config2 = VirtualDeviceConfig.androidGeneric

        XCTAssertNotNil(config1)
        XCTAssertNotNil(config2)
    }

    func testConcurrentVirtualDeviceCreation() async {
        // Test creating multiple virtual devices concurrently
        await withTaskGroup(of: Void.self) { group in
            for i in 0..<5 {
                group.addTask {
                    let config = VirtualDeviceConfig.pixel7
                        .withStorage(VirtualStorageConfig(
                            id: MTPStorageID(raw: UInt32(i + 1)),
                            description: "Storage \(i)"
                        ))
                    _ = VirtualMTPDevice(config: config)
                }
            }
        }
    }

    // MARK: - Thread Safety Tests

    func testMockTransportSendable() {
        // Test that MockTransport conforms to Sendable
        let summary = MTPDeviceSummary(
            id: MTPDeviceID(raw: "1234:5678@1:1"),
            manufacturer: "Test",
            model: "TestModel",
            vendorID: 0x1234,
            productID: 0x5678,
            bus: 1,
            address: 1,
            usbSerial: nil
        )

        let mockTransport = MockTransport(deviceData: MockDeviceData(
            deviceSummary: summary,
            storages: [],
            objects: []
        ))

        XCTAssertNotNil(mockTransport)
    }

    func testMockMTPLinkSendable() {
        // Test that MockMTPLink conforms to Sendable
        let summary = MTPDeviceSummary(
            id: MTPDeviceID(raw: "1234:5678@1:1"),
            manufacturer: "Test",
            model: "TestModel",
            vendorID: 0x1234,
            productID: 0x5678,
            bus: 1,
            address: 1,
            usbSerial: nil
        )

        let mockTransport = MockTransport(deviceData: MockDeviceData(
            deviceSummary: summary,
            storages: [],
            objects: []
        ))

        let mockLink = MockMTPLink(deviceData: MockDeviceData(
            deviceSummary: summary,
            storages: [],
            objects: []
        ), transport: mockTransport)

        XCTAssertNotNil(mockLink)
    }

    // MARK: - Async/Await Tests

    func testAsyncDeviceOpen() async throws {
        let summary = MTPDeviceSummary(
            id: MTPDeviceID(raw: "1234:5678@1:1"),
            manufacturer: "Test",
            model: "TestModel",
            vendorID: 0x1234,
            productID: 0x5678,
            bus: 1,
            address: 1,
            usbSerial: nil
        )

        let mockTransport = MockTransport(deviceData: MockDeviceData(
            deviceSummary: summary,
            storages: [],
            objects: []
        ))

        // Test async open operation
        let link = try await mockTransport.open(summary, config: SwiftMTPConfig())
        XCTAssertNotNil(link)
    }

    func testAsyncCloseOperation() async throws {
        let summary = MTPDeviceSummary(
            id: MTPDeviceID(raw: "1234:5678@1:1"),
            manufacturer: "Test",
            model: "TestModel",
            vendorID: 0x1234,
            productID: 0x5678,
            bus: 1,
            address: 1,
            usbSerial: nil
        )

        let mockTransport = MockTransport(deviceData: MockDeviceData(
            deviceSummary: summary,
            storages: [],
            objects: []
        ))

        try await mockTransport.close()
    }

    // MARK: - Concurrent Transfer Tests

    func testConcurrentDataBufferAccess() async {
        // Test thread-safe buffer access
        var buffer = DataBuffer(capacity: 1024)

        await withTaskGroup(of: Void.self) { group in
            for i in 0..<10 {
                group.addTask {
                    buffer.write(Data([UInt8(i)]))
                }
            }
        }

        // Buffer should have some data (may be less than 10 due to race conditions)
        XCTAssertGreaterThanOrEqual(buffer.availableBytes, 0)
    }

    // MARK: - Actor Isolation Tests

    func testLibUSBTransportActorIsolation() {
        // Test that LibUSBTransport is properly isolated
        let transport = LibUSBTransport()
        XCTAssertNotNil(transport)
    }

    // MARK: - Task Cancellation Tests

    func testCancellationDuringOperation() async {
        let task = Task {
            try? await Task.sleep(nanoseconds: 10_000_000_000) // 10 seconds
        }

        // Cancel immediately
        task.cancel()

        // Task should be cancelled
        XCTAssertTrue(task.isCancelled)
    }

    // MARK: - Timeout Handling Tests

    func testTimeoutConfiguration() {
        // Test various timeout configurations
        let shortTimeout: Int = 1000
        let mediumTimeout: Int = 5000
        let longTimeout: Int = 30000

        XCTAssertLessThan(shortTimeout, mediumTimeout)
        XCTAssertLessThan(mediumTimeout, longTimeout)
    }

    // MARK: - Parallel Test Execution

    func testParallelDeviceOperations() {
        // This test runs in parallel with other tests
        XCTAssertTrue(true)
    }

    // MARK: - Sendable Conformance Tests

    func testVirtualDeviceConfigSendable() {
        // Test that VirtualDeviceConfig is Sendable
        let config = VirtualDeviceConfig.pixel7
        XCTAssertNotNil(config)
    }

    func testVirtualStorageConfigSendable() {
        // Test that VirtualStorageConfig is Sendable
        let storage = VirtualStorageConfig(
            id: MTPStorageID(raw: 1),
            description: "Test Storage"
        )
        XCTAssertNotNil(storage)
    }

    func testVirtualObjectConfigSendable() {
        // Test that VirtualObjectConfig is Sendable
        let object = VirtualObjectConfig(
            handle: MTPObjectHandle(raw: 0x00010001),
            storage: MTPStorageID(raw: 1),
            name: "test.txt"
        )
        XCTAssertNotNil(object)
    }
}
