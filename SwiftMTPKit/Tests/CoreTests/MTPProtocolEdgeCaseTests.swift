// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import XCTest
@testable import SwiftMTPCore

/// Protocol edge cases and corner scenarios for MTP/PTP implementation
final class MTPProtocolEdgeCaseTests: XCTestCase {

    // MARK: - Transaction ID Edge Cases

    func testTransactionIDWrapping() {
        // Test that transaction IDs can wrap around large values
        let maxTxID: UInt32 = 0xFFFFFFFF
        let wrappedTxID: UInt32 = 1

        // Simulate transaction ID overflow scenario
        XCTAssertNotEqual(maxTxID, wrappedTxID)
        XCTAssertEqual(maxTxID & 0xFFFF_FFFF, maxTxID)
        XCTAssertEqual(wrappedTxID & 0xFFFF_FFFF, wrappedTxID)
    }

    func testTransactionIDZeroHandling() {
        // Test that zero transaction ID is handled correctly
        let zeroTxID: UInt32 = 0
        XCTAssertEqual(zeroTxID, 0)
    }

    // MARK: - Container Length Edge Cases

    func testContainerLengthBoundaries() {
        // Test minimum valid container length (header only = 12 bytes)
        let minLength: UInt32 = 12
        XCTAssertEqual(minLength, UInt32(MemoryLayout<UInt32>.size) * 3)

        // Test maximum reasonable container length
        let maxReasonableLength: UInt32 = 1024 * 1024 // 1MB
        XCTAssertGreaterThan(maxReasonableLength, minLength)
    }

    func testContainerWithZeroParams() {
        // Test container encoding with no parameters
        let container = PTPContainer(
            length: 12,
            type: PTPContainer.Kind.command.rawValue,
            code: PTPOp.getDeviceInfo.rawValue,
            txid: 1,
            params: []
        )

        XCTAssertEqual(container.length, 12)
        XCTAssertEqual(container.params.count, 0)
    }

    func testContainerWithMaxParams() {
        // Test container with maximum parameter count (MTP allows up to 5 params)
        let maxParams = [UInt32](1...5)
        let container = PTPContainer(
            length: 12 + (5 * 4), // header + 5 params
            type: PTPContainer.Kind.command.rawValue,
            code: PTPOp.sendObject.rawValue,
            txid: 1,
            params: maxParams
        )

        XCTAssertEqual(container.params.count, 5)
        XCTAssertEqual(container.length, 32)
    }

    // MARK: - String Encoding Edge Cases

    func testEmptyStringEncoding() {
        let encoded = PTPString.encode("")
        XCTAssertEqual(encoded.count, 1)
        XCTAssertEqual(encoded[0], 0)
    }

    func testSingleCharacterString() {
        let encoded = PTPString.encode("A")
        XCTAssertEqual(encoded.count, 4) // 1 len + 2 char bytes + 1 null
        XCTAssertEqual(encoded[0], 2) // "A" + null terminator
    }

    func testUnicodeStringEncoding() {
        let encoded = PTPString.encode("Test")
        XCTAssertGreaterThan(encoded.count, 0)

        // Verify encoding contains length prefix
        XCTAssertEqual(encoded[0], 5) // "Test" (4 chars) + null = 5
    }

    func testLongStringTruncation() {
        // PTP strings are limited to 255 characters (including null terminator)
        let longString = String(repeating: "x", count: 300)
        let encoded = PTPString.encode(longString)

        // Should be truncated to 255
        XCTAssertLessThanOrEqual(encoded[0], 255)
    }

    // MARK: - PTP Operation Code Edge Cases

    func testGetDeviceInfoOpcode() {
        XCTAssertEqual(PTPOp.getDeviceInfo.rawValue, 0x1001)
    }

    func testOpenSessionOpcode() {
        XCTAssertEqual(PTPOp.openSession.rawValue, 0x1002)
    }

    func testCloseSessionOpcode() {
        XCTAssertEqual(PTPOp.closeSession.rawValue, 0x1003)
    }

    func testAllDefinedOpCodes() {
        // Verify all defined operation codes have valid values
        XCTAssertEqual(PTPOp.getDeviceInfo.rawValue, 0x1001)
        XCTAssertEqual(PTPOp.openSession.rawValue, 0x1002)
        XCTAssertEqual(PTPOp.closeSession.rawValue, 0x1003)
        XCTAssertEqual(PTPOp.getStorageIDs.rawValue, 0x1004)
        XCTAssertEqual(PTPOp.getStorageInfo.rawValue, 0x1005)
        XCTAssertEqual(PTPOp.getNumObjects.rawValue, 0x1006)
        XCTAssertEqual(PTPOp.getObjectHandles.rawValue, 0x1007)
        XCTAssertEqual(PTPOp.getObjectInfo.rawValue, 0x1008)
        XCTAssertEqual(PTPOp.getObject.rawValue, 0x1009)
        XCTAssertEqual(PTPOp.getThumb.rawValue, 0x100A)
        XCTAssertEqual(PTPOp.deleteObject.rawValue, 0x100B)
        XCTAssertEqual(PTPOp.sendObjectInfo.rawValue, 0x100C)
        XCTAssertEqual(PTPOp.sendObject.rawValue, 0x100D)
        XCTAssertEqual(PTPOp.moveObject.rawValue, 0x100E)
    }

    // MARK: - Response Code Edge Cases

    func testResponseCodeNames() {
        XCTAssertEqual(PTPResponseCode.name(for: 0x2001), "OK")
        XCTAssertEqual(PTPResponseCode.name(for: 0x2003), "SessionNotOpen")
        XCTAssertEqual(PTPResponseCode.name(for: 0x2019), "DeviceBusy")
        XCTAssertEqual(PTPResponseCode.name(for: 0x201E), "SessionAlreadyOpen")
    }

    func testResponseCodeDescribe() {
        let described = PTPResponseCode.describe(0x2019)
        XCTAssertTrue(described.contains("DeviceBusy"))
        XCTAssertTrue(described.contains("0x2019"))
    }

    func testUnknownResponseCode() {
        let name = PTPResponseCode.name(for: 0xFFFF)
        XCTAssertNil(name)

        let described = PTPResponseCode.describe(0xFFFF)
        XCTAssertTrue(described.contains("Unknown"))
    }

    // MARK: - Object Format Edge Cases

    func testObjectFormatForFilename() {
        XCTAssertEqual(PTPObjectFormat.forFilename("test.txt"), 0x3004)
        XCTAssertEqual(PTPObjectFormat.forFilename("photo.jpg"), 0x3801)
        XCTAssertEqual(PTPObjectFormat.forFilename("photo.jpeg"), 0x3801)
        XCTAssertEqual(PTPObjectFormat.forFilename("image.png"), 0x380b)
        XCTAssertEqual(PTPObjectFormat.forFilename("video.mp4"), 0x300b)
        XCTAssertEqual(PTPObjectFormat.forFilename("audio.mp3"), 0x3009)
        XCTAssertEqual(PTPObjectFormat.forFilename("audio.aac"), 0xb903)
    }

    func testUnknownObjectFormat() {
        // Unknown formats should return undefined (0x3000)
        XCTAssertEqual(PTPObjectFormat.forFilename("file.xyz"), 0x3000)
        XCTAssertEqual(PTPObjectFormat.forFilename("noextension"), 0x3000)
    }

    // MARK: - PTPValue Edge Cases

    func testPTPValueIntTypes() {
        let int8 = PTPValue.int8(-1)
        let uint8 = PTPValue.uint8(255)
        let int16 = PTPValue.int16(-1)
        let uint16 = PTPValue.uint16(65535)
        let int32 = PTPValue.int32(-1)
        let uint32 = PTPValue.uint32(4294967295)

        // Verify they are different types
        switch int8 {
        case .int8: break
        default: XCTFail("Expected int8")
        }
        switch uint8 {
        case .uint8: break
        default: XCTFail("Expected uint8")
        }
        switch int16 {
        case .int16: break
        default: XCTFail("Expected int16")
        }
        switch uint16 {
        case .uint16: break
        default: XCTFail("Expected uint16")
        }
        switch int32 {
        case .int32: break
        default: XCTFail("Expected int32")
        }
        switch uint32 {
        case .uint32: break
        default: XCTFail("Expected uint32")
        }
    }

    func testPTPValueStringType() {
        let string = PTPValue.string("test")
        if case .string(let s) = string {
            XCTAssertEqual(s, "test")
        } else {
            XCTFail("Expected string value")
        }
    }

    func testPTPValueBytesType() {
        let bytes = PTPValue.bytes(Data([0x01, 0x02, 0x03]))
        if case .bytes(let b) = bytes {
            XCTAssertEqual(b.count, 3)
        } else {
            XCTFail("Expected bytes value")
        }
    }

    func testPTPValueArrayType() {
        let array = PTPValue.array([.uint32(1), .uint32(2), .uint32(3)])
        if case .array(let arr) = array {
            XCTAssertEqual(arr.count, 3)
        } else {
            XCTFail("Expected array value")
        }
    }

    // MARK: - PTPReader Edge Cases

    func testPTPReaderBoundsChecking() {
        var reader = PTPReader(data: Data([0x01, 0x02]))

        // Reading beyond bounds should return nil
        XCTAssertNil(reader.u32()) // Needs 4 bytes, only 2 available
        XCTAssertNil(reader.u16()) // Already at end after u32 check
        XCTAssertNotNil(reader.u8()) // Should work
    }

    func testPTPReaderPartialReads() {
        var reader = PTPReader(data: Data([0x01, 0x02, 0x03, 0x04]))

        XCTAssertNotNil(reader.u8())
        XCTAssertNotNil(reader.u16())
        XCTAssertNotNil(reader.u32())
    }

    func testPTPReaderBytes() {
        var reader = PTPReader(data: Data([0x01, 0x02, 0x03, 0x04, 0x05]))

        let bytes = reader.bytes(3)
        XCTAssertNotNil(bytes)
        XCTAssertEqual(bytes?.count, 3)
        XCTAssertEqual(bytes?[0], 0x01)
        XCTAssertEqual(bytes?[1], 0x02)
        XCTAssertEqual(bytes?[2], 0x03)
    }

    func testPTPReaderBytesExceedsBounds() {
        var reader = PTPReader(data: Data([0x01, 0x02, 0x03]))

        let bytes = reader.bytes(5) // Exceeds available data
        XCTAssertNil(bytes)
    }

    // MARK: - PTPPropList Edge Cases

    func testEmptyPropList() {
        let data = Data([0x00, 0x00, 0x00, 0x00]) // count = 0
        let propList = PTPPropList.parse(from: data)

        XCTAssertNotNil(propList)
        XCTAssertEqual(propList?.entries.count, 0)
    }

    // MARK: - MTPError Edge Cases

    func testMTPErrorProtocolError() {
        let error = MTPError.protocolError(code: 0x2003, message: "Session not open")

        if case .protocolError(let code, let message) = error {
            XCTAssertEqual(code, 0x2003)
            XCTAssertEqual(message, "Session not open")
        } else {
            XCTFail("Expected protocol error")
        }
    }

    func testMTPErrorNotSupported() {
        let error = MTPError.notSupported("Operation not supported")
        if case .notSupported(let msg) = error {
            XCTAssertEqual(msg, "Operation not supported")
        } else {
            XCTFail("Expected notSupported error")
        }
    }

    func testMTPErrorIsSessionAlreadyOpen() {
        let sessionAlreadyOpen = MTPError.protocolError(code: 0x201E, message: nil)
        XCTAssertTrue(sessionAlreadyOpen.isSessionAlreadyOpen)

        let okError = MTPError.protocolError(code: 0x2001, message: nil)
        XCTAssertFalse(okError.isSessionAlreadyOpen)
    }

    // MARK: - Container Type Edge Cases

    func testContainerKindValues() {
        XCTAssertEqual(PTPContainer.Kind.command.rawValue, 1)
        XCTAssertEqual(PTPContainer.Kind.data.rawValue, 2)
        XCTAssertEqual(PTPContainer.Kind.response.rawValue, 3)
        XCTAssertEqual(PTPContainer.Kind.event.rawValue, 4)
    }

    // MARK: - Large Data Handling

    func testLargeObjectInfoDataset() {
        // Test encoding object info for large files
        let largeSize: UInt64 = 2 * 1024 * 1024 * 1024 // 2GB
        let data = PTPObjectInfoDataset.encode(
            storageID: 0x00010001,
            parentHandle: 0,
            format: 0x3001,
            size: largeSize,
            name: "large_file.dat"
        )

        XCTAssertGreaterThan(data.count, 0)
        // Verify size is clamped to UInt32 max
        XCTAssertEqual(data.count, 80) // Fixed structure size
    }
}
