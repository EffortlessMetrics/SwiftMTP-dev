// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import XCTest
@testable import SwiftMTPCore

/// PTP packet encoding and decoding tests
final class PTPCodecTests: XCTestCase {

    // MARK: - Container Encoding

    func testCommandContainerEncoding() {
        let container = PTPContainer(
            type: PTPContainer.Kind.command.rawValue,
            code: PTPOp.getDeviceInfo.rawValue,
            txid: 0x00000001,
            params: []
        )

        var buffer = [UInt8](repeating: 0, count: 64)
        let bytesWritten = buffer.withUnsafeMutableBufferPointer { ptr in
            guard let base = ptr.baseAddress else { return 0 }
            return container.encode(into: base)
        }

        // Header: 4 bytes length + 2 bytes type + 2 bytes code + 4 bytes txid = 12
        XCTAssertEqual(bytesWritten, 12)

        // Verify little-endian encoding
        XCTAssertEqual(buffer[0], 0x0C) // length = 12 (little-endian)
        XCTAssertEqual(buffer[1], 0x00)
        XCTAssertEqual(buffer[4], 0x01) // type = command
        XCTAssertEqual(buffer[5], 0x00)
        XCTAssertEqual(buffer[6], 0x01) // code = GetDeviceInfo (0x1001)
        XCTAssertEqual(buffer[7], 0x10)
        XCTAssertEqual(buffer[8], 0x01) // txid
        XCTAssertEqual(buffer[9], 0x00)
        XCTAssertEqual(buffer[10], 0x00)
        XCTAssertEqual(buffer[11], 0x00)
    }

    func testCommandContainerWithParams() {
        let container = PTPContainer(
            length: 24,
            type: PTPContainer.Kind.command.rawValue,
            code: PTPOp.sendObject.rawValue,
            txid: 0x00000005,
            params: [0x00010001, 0xFFFFFFFF, 0x00000000]
        )

        var buffer = [UInt8](repeating: 0, count: 64)
        let bytesWritten = buffer.withUnsafeMutableBufferPointer { ptr in
            guard let base = ptr.baseAddress else { return 0 }
            return container.encode(into: base)
        }

        // 12 header + 3 * 4 params = 24
        XCTAssertEqual(bytesWritten, 24)

        // Verify length field
        XCTAssertEqual(buffer[0], 0x18) // 24 in little-endian
        XCTAssertEqual(buffer[1], 0x00)
    }

    func testResponseContainerEncoding() {
        let container = PTPContainer(
            length: 16,
            type: PTPContainer.Kind.response.rawValue,
            code: 0x2001, // OK response
            txid: 0x00000001,
            params: [0x00000000]
        )

        var buffer = [UInt8](repeating: 0, count: 64)
        let bytesWritten = buffer.withUnsafeMutableBufferPointer { ptr in
            guard let base = ptr.baseAddress else { return 0 }
            return container.encode(into: base)
        }

        XCTAssertEqual(bytesWritten, 16) // 12 + 4 for one param

        XCTAssertEqual(buffer[4], 0x03) // type = response
        XCTAssertEqual(buffer[6], 0x01) // code low byte
        XCTAssertEqual(buffer[7], 0x20) // code high byte (0x2001)
    }

    func testDataContainerEncoding() {
        let container = PTPContainer(
            type: PTPContainer.Kind.data.rawValue,
            code: 0x0000, // Not used for data
            txid: 0x00000001,
            params: []
        )

        var buffer = [UInt8](repeating: 0, count: 64)
        let bytesWritten = buffer.withUnsafeMutableBufferPointer { ptr in
            guard let base = ptr.baseAddress else { return 0 }
            return container.encode(into: base)
        }

        XCTAssertEqual(bytesWritten, 12)
        XCTAssertEqual(buffer[4], 0x02) // type = data
    }

    // MARK: - Container Initialization

    func testContainerDefaultLength() {
        let container = PTPContainer(
            type: 1,
            code: 0x1001,
            txid: 1
        )

        XCTAssertEqual(container.length, 12) // Default header-only length
    }

    func testContainerWithCustomLength() {
        let container = PTPContainer(
            length: 256,
            type: 1,
            code: 0x1001,
            txid: 1
        )

        XCTAssertEqual(container.length, 256)
    }

    func testContainerWithParams() {
        let params: [UInt32] = [1, 2, 3, 4, 5]
        let container = PTPContainer(
            type: 1,
            code: 0x1001,
            txid: 1,
            params: params
        )

        XCTAssertEqual(container.params.count, 5)
    }

    // MARK: - String Encoding/Decoding

    func testStringRoundTrip() {
        let original = "TestString123"
        let encoded = PTPString.encode(original)

        var offset = 0
        let decoded = PTPString.parse(from: encoded, at: &offset)

        XCTAssertEqual(decoded, original)
    }

    func testEmptyStringRoundTrip() {
        let original = ""
        let encoded = PTPString.encode(original)

        var offset = 0
        let decoded = PTPString.parse(from: encoded, at: &offset)

        XCTAssertEqual(decoded, "")
        XCTAssertEqual(offset, 1) // Only length byte read
    }

    func testSpecialCharactersString() {
        let original = "Test:Special-Characters_123"
        let encoded = PTPString.encode(original)

        var offset = 0
        let decoded = PTPString.parse(from: encoded, at: &offset)

        XCTAssertEqual(decoded, original)
    }

    func testStringWithSpaces() {
        let original = "Hello World Test"
        let encoded = PTPString.encode(original)

        var offset = 0
        let decoded = PTPString.parse(from: encoded, at: &offset)

        XCTAssertEqual(decoded, original)
    }

    // MARK: - PTPReader Value Parsing

    func testReadUint8() {
        var reader = PTPReader(data: Data([0xFF]))
        XCTAssertEqual(reader.u8(), 0xFF)
    }

    func testReadUint16() {
        var data = Data(count: 2)
        data[0] = 0x34
        data[1] = 0x12
        var reader = PTPReader(data: data)

        XCTAssertEqual(reader.u16(), 0x1234) // Little-endian
    }

    func testReadUint32() {
        var data = Data(count: 4)
        data[0] = 0x78
        data[1] = 0x56
        data[2] = 0x34
        data[3] = 0x12
        var reader = PTPReader(data: data)

        XCTAssertEqual(reader.u32(), 0x12345678) // Little-endian
    }

    func testReadUint64() {
        var data = Data(count: 8)
        data[0] = 0x78
        data[1] = 0x56
        data[2] = 0x34
        data[3] = 0x12
        data[4] = 0xEF
        data[5] = 0xCD
        data[6] = 0xAB
        data[7] = 0x89
        var reader = PTPReader(data: data)

        XCTAssertEqual(reader.u64(), 0x89ABCDEF12345678) // Little-endian
    }

    func testReadMultipleValues() {
        var data = Data(count: 10)
        data[0] = 0x01 // u8
        data[1] = 0x02
        data[2] = 0x03 // u16 (2 bytes)
        data[3] = 0x04
        data[4] = 0x05
        data[5] = 0x06
        data[6] = 0x07 // u32 (4 bytes)
        data[7] = 0x08
        data[8] = 0x09
        data[9] = 0x0A
        var reader = PTPReader(data: data)

        XCTAssertEqual(reader.u8(), 0x01)
        XCTAssertEqual(reader.u16(), 0x0302)
        XCTAssertEqual(reader.u32(), 0x07060504)
    }

    // MARK: - PTPReader Value Type Parsing

    func testReadInt8() {
        var reader = PTPReader(data: Data([0xFF]))
        if case .int8(let v) = reader.value(dt: 0x0001) {
            XCTAssertEqual(v, -1)
        } else {
            XCTFail("Expected int8 value")
        }
    }

    // MARK: - PTPReader Value Type Parsing

    func testReadValueTypeUint8() {
        var reader = PTPReader(data: Data([0xFF]))
        if case .uint8(let v) = reader.value(dt: 0x0002) {
            XCTAssertEqual(v, 0xFF)
        } else {
            XCTFail("Expected uint8 value")
        }
    }

    func testReadValueTypeUint16() {
        var data = Data(count: 2)
        data[0] = 0x34
        data[1] = 0x12
        var reader = PTPReader(data: data)
        if case .uint16(let v) = reader.value(dt: 0x0004) {
            XCTAssertEqual(v, 0x1234)
        } else {
            XCTFail("Expected uint16 value")
        }
    }

    func testReadValueTypeUint32() {
        var data = Data(count: 4)
        data[0] = 0x78
        data[1] = 0x56
        data[2] = 0x34
        data[3] = 0x12
        var reader = PTPReader(data: data)
        if case .uint32(let v) = reader.value(dt: 0x0006) {
            XCTAssertEqual(v, 0x12345678)
        } else {
            XCTFail("Expected uint32 value")
        }
    }

    func testReadString() {
        let encoded = PTPString.encode("Test")
        var reader = PTPReader(data: encoded)
        XCTAssertEqual(reader.string(), "Test")
    }

    func testReadArray() {
        // Array with 3 uint32 elements: 0x4000 | 0x0006 = 0x4006
        var data = Data(count: 4 + (3 * 4))
        data[0] = 0x03 // count
        data[1] = 0x00
        data[2] = 0x00
        data[3] = 0x00
        data[4] = 0x01 // first element
        data[5] = 0x00
        data[6] = 0x00
        data[7] = 0x00
        data[8] = 0x02 // second element
        data[9] = 0x00
        data[10] = 0x00
        data[11] = 0x00
        data[12] = 0x03 // third element
        data[13] = 0x00
        data[14] = 0x00
        data[15] = 0x00

        var reader = PTPReader(data: data)
        if case .array(let arr) = reader.value(dt: 0x4006) {
            XCTAssertEqual(arr.count, 3)
            if case .uint32(let v) = arr[0] { XCTAssertEqual(v, 1) }
            if case .uint32(let v) = arr[1] { XCTAssertEqual(v, 2) }
            if case .uint32(let v) = arr[2] { XCTAssertEqual(v, 3) }
        } else {
            XCTFail("Expected array value")
        }
    }

    // MARK: - PTPDeviceInfo Parsing

    func testParseMinimalDeviceInfo() {
        // Build minimal valid DeviceInfo dataset
        var data = Data()

        // StandardVersion (2)
        data.append(contentsOf: [0x01, 0x00])
        // VendorExtensionID (4)
        data.append(contentsOf: [0x00, 0x00, 0x00, 0x00])
        // VendorExtensionVersion (2)
        data.append(contentsOf: [0x01, 0x00])
        // VendorExtensionDesc (string)
        data.append(0x01) // length including null
        data.append(0x00) // null char
        data.append(0x00) // padding
        // FunctionalMode (2)
        data.append(contentsOf: [0x00, 0x00])

        // OperationsSupported (array of 1)
        data.append(contentsOf: [0x01, 0x00, 0x00, 0x00]) // count
        data.append(contentsOf: [0x01, 0x10]) // GetDeviceInfo

        // EventsSupported (array of 0)
        data.append(contentsOf: [0x00, 0x00, 0x00, 0x00])

        // DevicePropertiesSupported (array of 0)
        data.append(contentsOf: [0x00, 0x00, 0x00, 0x00])

        // CaptureFormats (array of 0)
        data.append(contentsOf: [0x00, 0x00, 0x00, 0x00])

        // PlaybackFormats (array of 0)
        data.append(contentsOf: [0x00, 0x00, 0x00, 0x00])

        // Manufacturer (string)
        data.append(0x01)
        data.append(0x00)
        data.append(0x00)

        // Model (string)
        data.append(0x01)
        data.append(0x00)
        data.append(0x00)

        // DeviceVersion (string)
        data.append(0x01)
        data.append(0x00)
        data.append(0x00)

        // SerialNumber (optional string)
        data.append(0x00)

        let deviceInfo = PTPDeviceInfo.parse(from: data)
        XCTAssertNotNil(deviceInfo)
        XCTAssertEqual(deviceInfo?.standardVersion, 1)
        XCTAssertEqual(deviceInfo?.operationsSupported, [0x1001])
    }

    // MARK: - Object Info Dataset Encoding

    func testObjectInfoDatasetBasic() {
        let data = PTPObjectInfoDataset.encode(
            storageID: 0x00010001,
            parentHandle: 0,
            format: 0x3001,
            size: 1024,
            name: "test.txt"
        )

        XCTAssertGreaterThan(data.count, 0)

        // Verify first fields
        var offset = 0
        let storageID = data.withUnsafeBytes { $0.load(fromByteOffset: offset, as: UInt32.self) }.littleEndian
        XCTAssertEqual(storageID, 0x00010001)
        offset += 4

        let format = data.withUnsafeBytes { $0.load(fromByteOffset: offset, as: UInt16.self) }.littleEndian
        XCTAssertEqual(format, 0x3001)
    }

    func testObjectInfoDatasetWithAssociation() {
        let data = PTPObjectInfoDataset.encode(
            storageID: 0x00010001,
            parentHandle: 0x00000001,
            format: 0x3001,
            size: 1024,
            name: "folder",
            associationType: 0x0001, // folder
            associationDesc: 0x00000001
        )

        XCTAssertGreaterThan(data.count, 0)

        // Verify parent handle field
        let parentOffset = 38
        XCTAssertEqual(data[parentOffset], 0x01)
        XCTAssertEqual(data[parentOffset + 1], 0x00)
        XCTAssertEqual(data[parentOffset + 2], 0x00)
        XCTAssertEqual(data[parentOffset + 3], 0x00)
    }

    // MARK: - Edge Cases

    func testStringParsingInvalidLength() {
        // Test parsing with invalid offset
        var offset = 100
        let result = PTPString.parse(from: Data([0x01, 0x02]), at: &offset)
        XCTAssertNil(result)
    }

    func testStringParsingInvalidFFLength() {
        // 0xFF is reserved/invalid for string length
        var offset = 0
        let data = Data([0xFF, 0x00, 0x00])
        let result = PTPString.parse(from: data, at: &offset)
        XCTAssertNil(result)
    }

    func testReadBeyondBounds() {
        var reader = PTPReader(data: Data([0x01]))
        XCTAssertNil(reader.u32()) // Needs 4 bytes
        XCTAssertNotNil(reader.u8())
        XCTAssertNil(reader.u8()) // Now at end
    }

    func testReadInvalidDataType() {
        var reader = PTPReader(data: Data([0x01, 0x02, 0x03, 0x04]))
        XCTAssertNil(reader.value(dt: 0x1234)) // Invalid type
    }
}
