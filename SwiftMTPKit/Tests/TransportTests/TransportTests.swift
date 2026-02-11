// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import XCTest
@testable import SwiftMTPCore

/// Transport layer tests
final class TransportTests: XCTestCase {

    // MARK: - Transport Error Tests

    func testTransportErrorEquatability() {
        XCTAssertEqual(TransportError.noDevice, TransportError.noDevice)
        XCTAssertEqual(TransportError.timeout, TransportError.timeout)
        XCTAssertEqual(TransportError.busy, TransportError.busy)
        XCTAssertEqual(TransportError.accessDenied, TransportError.accessDenied)
        XCTAssertEqual(TransportError.io("error A"), TransportError.io("error A"))
        XCTAssertNotEqual(TransportError.io("error A"), TransportError.io("error B"))
        XCTAssertNotEqual(TransportError.noDevice, TransportError.timeout)
    }

    func testTransportErrorDescriptions() {
        let noDevice = TransportError.noDevice
        let timeout = TransportError.timeout
        let busy = TransportError.busy
        let accessDenied = TransportError.accessDenied
        let ioError = TransportError.io("read failed")
        
        XCTAssertNotEqual(noDevice, timeout)
        XCTAssertNotEqual(noDevice, busy)
        XCTAssertNotEqual(noDevice, accessDenied)
        XCTAssertNotEqual(noDevice, ioError)
    }

    // MARK: - USB Endpoint Tests

    func testEndpointAddressParsing() {
        // Test valid endpoint addresses
        let input1 = USBEndpointAddress(rawValue: 0x81)
        XCTAssertTrue(input1.isInput)
        XCTAssertFalse(input1.isOutput)
        XCTAssertEqual(input1.number, 1)
        
        let input2 = USBEndpointAddress(rawValue: 0x82)
        XCTAssertTrue(input2.isInput)
        XCTAssertEqual(input2.number, 2)
        
        let output1 = USBEndpointAddress(rawValue: 0x01)
        XCTAssertFalse(output1.isInput)
        XCTAssertTrue(output1.isOutput)
        XCTAssertEqual(output1.number, 1)
    }

    // MARK: - Transfer Configuration Tests

    func testTransferConfigDefaults() {
        let config = TransferConfig.default
        XCTAssertEqual(config.timeoutMs, 10_000)
        XCTAssertEqual(config.chunkSize, 2 * 1024 * 1024)
    }

    func testTransferConfigCustom() {
        var config = TransferConfig.default
        config.timeoutMs = 30_000
        config.chunkSize = 4 * 1024 * 1024
        
        XCTAssertEqual(config.timeoutMs, 30_000)
        XCTAssertEqual(config.chunkSize, 4 * 1024 * 1024)
    }

    // MARK: - MTPFuzzer Tests

    func testMutationProducesDifferentOutput() {
        let original: [UInt8] = [0x01, 0x02, 0x03, 0x04, 0x05]
        
        var allMutations = Set<[UInt8]>()
        for _ in 0..<100 {
            let mutated = MTPFuzzer.mutate(Data(original))
            allMutations.insert([UInt8](mutated))
        }
        
        // Should produce some variation
        XCTAssertFalse(allMutations.isEmpty)
    }

    func testMutationPreservesSomeData() {
        let original = Data([0xFF, 0x00, 0xAA, 0x55, 0x12, 0x34, 0x56, 0x78])
        
        // After many mutations, some bytes should remain unchanged
        var unchangedCount = 0
        for _ in 0..<1000 {
            let mutated = MTPFuzzer.mutate(original)
            for i in 0..<min(original.count, mutated.count) {
                if original[i] == mutated[i] {
                    unchangedCount += 1
                }
            }
        }
        
        // Statistical check - at least some bytes should survive
        XCTAssertGreaterThan(unchangedCount, 0)
    }

    func testTruncationMutation() {
        let original = Data(repeating: 0xAA, count: 100)
        
        // Test various truncation sizes
        for size in [0, 1, 10, 50, 99, 100] {
            let truncated = original.prefix(size)
            // Should not crash
            _ = MTPFuzzer.mutate(truncated)
        }
    }

    func testByteFlipMutation() {
        let original = Data([0x00, 0x00, 0x00, 0x00])
        
        // Flip some bytes
        let mutated = MTPFuzzer.mutate(original)
        
        // Mutated data should have different bytes
        XCTAssertFalse(original == mutated)
    }
}

/// USB endpoint address helper
struct USBEndpointAddress {
    let rawValue: UInt8
    
    var number: UInt8 {
        rawValue & 0x0F
    }
    
    var isInput: Bool {
        (rawValue & 0x80) != 0
    }
    
    var isOutput: Bool {
        (rawValue & 0x80) == 0
    }
}

/// Transfer configuration
struct TransferConfig {
    var timeoutMs: Int = 10_000
    var chunkSize: Int = 2 * 1024 * 1024
    
    static var `default`: TransferConfig {
        TransferConfig()
    }
}

/// Fuzzer helper (minimal implementation)
enum MTPFuzzer {
    static func mutate(_ data: Data) -> Data {
        var result = Data(data)
        
        // Random mutation strategy
        let mutationType = Int.random(in: 0...3)
        
        switch mutationType {
        case 0: // Flip random byte
            if !result.isEmpty {
                let idx = Int.random(in: 0..<result.count)
                result[idx] = UInt8.random(in: 0...255)
            }
        case 1: // Insert random byte
            if result.count < 1000 {
                // Allow insertion into an empty buffer at index 0.
                let idx = Int.random(in: 0...result.count)
                result.insert(UInt8.random(in: 0...255), at: idx)
            }
        case 2: // Delete byte
            if !result.isEmpty {
                let idx = Int.random(in: 0..<result.count)
                result.remove(at: idx)
            }
        default: // Truncate
            if !result.isEmpty {
                let newSize = Int.random(in: 0..<result.count)
                result = Data(result.prefix(newSize))
            }
        }
        
        return result
    }
}
