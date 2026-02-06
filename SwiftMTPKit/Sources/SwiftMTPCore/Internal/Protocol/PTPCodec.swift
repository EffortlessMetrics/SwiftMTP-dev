// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation

// PTP/MTP Unicode String format: count-prefixed UTF-16LE
public struct PTPString {
    public static func parse(from data: Data, at offset: inout Int) -> String? {
        guard offset + 1 <= data.count else { return nil }

        // Read string length (number of Unicode characters, not bytes)
        let length = Int(data[offset])
        offset += 1

        if length == 0 {
            return ""
        }

        // Each Unicode character is 2 bytes (UTF-16LE)
        let stringByteLength = length * 2
        guard offset + stringByteLength <= data.count else { return nil }

        let stringData = data[offset..<offset + stringByteLength]
        offset += stringByteLength

        // Convert UTF-16LE to String
        let utf16Data = stringData.withUnsafeBytes { ptr in
            ptr.bindMemory(to: UInt16.self)
        }

        var utf16Array = [UInt16]()
        for i in 0..<length {
            let char = UInt16(littleEndian: utf16Data[i])
            // Skip null terminator if present
            if char != 0 {
                utf16Array.append(char)
            }
        }

        return String(utf16CodeUnits: utf16Array, count: utf16Array.count)
    }

    public static func encode(_ string: String) -> Data {
        var data = Data()

        if string.isEmpty {
            data.append(0) // Empty string
            return data
        }

        // Convert string to UTF-16LE
        let utf16Chars = string.utf16.map { UInt16($0).littleEndian }

        // Write length (number of characters)
        data.append(UInt8(utf16Chars.count))

        // Write UTF-16LE bytes
        for char in utf16Chars {
            data.append(contentsOf: [UInt8(char & 0xFF), UInt8(char >> 8)])
        }

        return data
    }
}

// DeviceInfo dataset parser
public struct PTPDeviceInfo {
    public let standardVersion: UInt16
    public let vendorExtensionID: UInt32
    public let vendorExtensionVersion: UInt16
    public let vendorExtensionDesc: String
    public let functionalMode: UInt16
    public let operationsSupported: [UInt16]
    public let eventsSupported: [UInt16]
    public let devicePropertiesSupported: [UInt16]
    public let captureFormats: [UInt16]
    public let playbackFormats: [UInt16]
    public let manufacturer: String
    public let model: String
    public let deviceVersion: String
    public let serialNumber: String?

    public static func parse(from data: Data) -> PTPDeviceInfo? {
        var offset = 0

        // PTP/MTP DeviceInfo dataset starts immediately in the data phase payload.
        // It does NOT have a separate length prefix within the payload.
        guard data.count >= 8 else { return nil }
        offset = 0

        func read16() -> UInt16? {
            guard offset + 2 <= data.count else { return nil }
            var v: UInt16 = 0
            _ = withUnsafeMutableBytes(of: &v) { ptr in
                data.copyBytes(to: ptr, from: offset..<offset+2)
            }
            offset += 2
            return v.littleEndian
        }

        func read32() -> UInt32? {
            guard offset + 4 <= data.count else { return nil }
            var v: UInt32 = 0
            _ = withUnsafeMutableBytes(of: &v) { ptr in
                data.copyBytes(to: ptr, from: offset..<offset+4)
            }
            offset += 4
            return v.littleEndian
        }

        func readString() -> String? {
            return PTPString.parse(from: data, at: &offset)
        }

        func readArray16(count: Int) -> [UInt16]? {
            var array = [UInt16]()
            for _ in 0..<count {
                guard let value = read16() else { return nil }
                array.append(value)
            }
            return array
        }

        guard let standardVersion = read16(),
              let vendorExtensionID = read32(),
              let vendorExtensionVersion = read16(),
              let vendorExtensionDesc = readString(),
              let functionalMode = read16(),
              let operationsSupportedCount = read32(),
              let operationsSupported = readArray16(count: Int(operationsSupportedCount)),
              let eventsSupportedCount = read32(),
              let eventsSupported = readArray16(count: Int(eventsSupportedCount)),
              let devicePropertiesSupportedCount = read32(),
              let devicePropertiesSupported = readArray16(count: Int(devicePropertiesSupportedCount)),
              let captureFormatsCount = read32(),
              let captureFormats = readArray16(count: Int(captureFormatsCount)),
              let playbackFormatsCount = read32(),
              let playbackFormats = readArray16(count: Int(playbackFormatsCount)),
              let manufacturer = readString(),
              let model = readString(),
              let deviceVersion = readString(),
              let serialNumber = readString() else {
            return nil
        }

        return PTPDeviceInfo(
            standardVersion: standardVersion,
            vendorExtensionID: vendorExtensionID,
            vendorExtensionVersion: vendorExtensionVersion,
            vendorExtensionDesc: vendorExtensionDesc,
            functionalMode: functionalMode,
            operationsSupported: operationsSupported,
            eventsSupported: eventsSupported,
            devicePropertiesSupported: devicePropertiesSupported,
            captureFormats: captureFormats,
            playbackFormats: playbackFormats,
            manufacturer: manufacturer,
            model: model,
            deviceVersion: deviceVersion,
            serialNumber: serialNumber
        )
    }
}
