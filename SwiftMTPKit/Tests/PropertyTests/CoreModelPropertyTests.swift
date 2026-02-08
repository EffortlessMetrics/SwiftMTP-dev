// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import XCTest
import SwiftCheck
@testable import SwiftMTPCore

/// Property-based tests for SwiftMTPCore models
final class CoreModelPropertyTests: XCTestCase {

    // MARK: - PTPReader Property Tests

    func testPTPReaderU8Roundtrip() {
        property("PTPReader u8 reads what was written") <- forAll { (value: UInt8) in
            var data = Data(count: 1)
            data[0] = value
            
            var reader = PTPReader(data: data)
            let result = reader.u8()
            return result == value
        }
    }

    func testPTPReaderU16Roundtrip() {
        property("PTPReader u16 reads what was written") <- forAll { (value: UInt16) in
            var data = Data(count: 2)
            data[0] = UInt8(truncatingIfNeeded: value)
            data[1] = UInt8(truncatingIfNeeded: value >> 8)
            
            var reader = PTPReader(data: data)
            let result = reader.u16()
            return result == value
        }
    }

    func testPTPReaderU32Roundtrip() {
        property("PTPReader u32 reads what was written") <- forAll { (value: UInt32) in
            var data = Data(count: 4)
            data[0] = UInt8(truncatingIfNeeded: value)
            data[1] = UInt8(truncatingIfNeeded: value >> 8)
            data[2] = UInt8(truncatingIfNeeded: value >> 16)
            data[3] = UInt8(truncatingIfNeeded: value >> 24)
            
            var reader = PTPReader(data: data)
            let result = reader.u32()
            return result == value
        }
    }

    func testPTPReaderU64Roundtrip() {
        property("PTPReader u64 reads what was written") <- forAll { (value: UInt64) in
            var data = Data(count: 8)
            for i in 0..<8 {
                data[i] = UInt8(truncatingIfNeeded: value >> (i * 8))
            }
            
            var reader = PTPReader(data: data)
            let result = reader.u64()
            return result == value
        }
    }

    func testPTPReaderOffsetAdvances() {
        property("PTPReader offset advances correctly after reads") <- forAll { (v1: UInt8, v2: UInt16, v3: UInt32) in
            var data = Data(count: 1 + 2 + 4)
            data[0] = v1
            data[1] = UInt8(truncatingIfNeeded: v2)
            data[2] = UInt8(truncatingIfNeeded: v2 >> 8)
            data[3] = UInt8(truncatingIfNeeded: v3)
            data[4] = UInt8(truncatingIfNeeded: v3 >> 8)
            data[5] = UInt8(truncatingIfNeeded: v3 >> 16)
            data[6] = UInt8(truncatingIfNeeded: v3 >> 24)
            
            var reader = PTPReader(data: data)
            let _ = reader.u8()
            let _ = reader.u16()
            let _ = reader.u32()
            
            return reader.o == 7
        }
    }

    // MARK: - PTPString Property Tests

    func testPTPStringRoundtrip() {
        property("PTPString encode then parse equals original") <- forAll { (text: String) in
            // PTP strings are limited to 254 characters
            let truncated = String(text.prefix(254))
            
            let encoded = PTPString.encode(truncated)
            var offset = 0
            let decoded = PTPString.parse(from: encoded, at: &offset)
            
            return decoded == truncated
        }
    }

    func testPTPStringEmpty() {
        property("PTPString handles empty string") <- forAll { (_: Int) in
            let encoded = PTPString.encode("")
            var offset = 0
            let decoded = PTPString.parse(from: encoded, at: &offset)
            
            return decoded == ""
        }
    }

    func testPTPStringUnicode() {
        property("PTPString handles unicode characters") <- forAll { (text: String) in
            // Only test with reasonable length
            let truncated = String(text.prefix(50))
            
            let encoded = PTPString.encode(truncated)
            var offset = 0
            let decoded = PTPString.parse(from: encoded, at: &offset)
            
            return decoded == truncated
        }
    }

    // MARK: - PTPContainer Property Tests

    func testPTPContainerEncodeProducesCorrectLength() {
        property("PTPContainer encode produces correct length") <- forAll { (type: UInt16, code: UInt16, txid: UInt32, params: Array<UInt32>) in
            let paramArray = Array(params.prefix(10)) // Limit params
            let container = PTPContainer(
                length: 12 + UInt32(paramArray.count * 4),
                type: type,
                code: code,
                txid: txid,
                params: paramArray
            )
            
            let requiredSize = 12 + paramArray.count * 4
            var buffer = [UInt8](repeating: 0, count: requiredSize)
            let bytesWritten = container.encode(into: &buffer)
            
            return bytesWritten == requiredSize
        }
    }

    func testPTPContainerTypeValues() {
        property("PTPContainer type values encode correctly") <- forAll { (type: UInt16) in
            // Container type should be 1-4
            let container = PTPContainer(
                length: 12,
                type: type,
                code: 0x1001,
                txid: 1,
                params: []
            )
            
            let requiredSize = 12
            var buffer = [UInt8](repeating: 0, count: requiredSize)
            let bytesWritten = container.encode(into: &buffer)
            
            // Should always encode without crashing
            return bytesWritten == requiredSize
        }
    }

    // MARK: - PTPObjectInfoDataset Property Tests

    func testPTPObjectInfoDatasetEncode() {
        property("PTPObjectInfoDataset encode produces valid data") <- forAll { (storageID: UInt32, parentHandle: UInt32, format: UInt16, size: UInt64, name: String) in
            let data = PTPObjectInfoDataset.encode(
                storageID: storageID,
                parentHandle: parentHandle,
                format: format,
                size: size,
                name: String(name.prefix(254))
            )
            
            // Should produce non-empty data
            return data.count > 0
        }
    }
}
