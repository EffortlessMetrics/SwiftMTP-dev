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
        // PTP/MTP allows up to 255 characters. Length includes null terminator.
        let len = min(utf16Chars.count + 1, 255)
        data.append(UInt8(len))

        // Write UTF-16LE bytes
        for i in 0..<len-1 {
            let char = utf16Chars[i]
            data.append(contentsOf: [UInt8(char & 0xFF), UInt8(char >> 8)])
        }
        
        // Null terminator
        data.append(contentsOf: [0, 0])

        return data
    }
}

public struct PTPObjectInfoDataset {
    public static func encode(storageID: UInt32, parentHandle: UInt32, format: UInt16, size: UInt64, name: String) -> Data {
        var data = Data()
        
        func put32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { data.append(contentsOf: $0) } }
        func put16(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { data.append(contentsOf: $0) } }
        
        // PTP Spec: storageID can be 0 to use the "primary" or "default" storage
        put32(storageID)
        put16(format)
        put16(0) // ProtectionStatus
        put32(UInt32(min(size, UInt64(0xFFFFFFFF)))) // ObjectCompressedSize
        put16(0) // ThumbFormat
        put32(0) // ThumbCompressedSize
        put32(0) // ThumbPixWidth
        put32(0) // ThumbPixHeight
        put32(0) // ImagePixWidth
        put32(0) // ImagePixHeight
        put32(0) // ImageBitDepth
        put32(parentHandle)
        put16(0) // AssociationType
        put32(0) // AssociationDesc
        put32(0) // SequenceNumber
        data.append(PTPString.encode(name))
        data.append(PTPString.encode("")) // CaptureDate
        data.append(PTPString.encode("")) // ModificationDate
        data.append(PTPString.encode("")) // Keywords
        
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

// GetObjectPropList dataset parser
public struct PTPPropEntry {
    public let handle: UInt32
    public let propertyCode: UInt16
    public let dataType: UInt16
    public var value: Any?
}

public struct PTPPropList {
    public let entries: [PTPPropEntry]

    public static func parse(from data: Data) -> PTPPropList? {
        var offset = 0
        
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
        
        func read64() -> UInt64? {
            guard offset + 8 <= data.count else { return nil }
            var v: UInt64 = 0
            _ = withUnsafeMutableBytes(of: &v) { ptr in
                data.copyBytes(to: ptr, from: offset..<offset+8)
            }
            offset += 8
            return v.littleEndian
        }

        func readString() -> String? {
            return PTPString.parse(from: data, at: &offset)
        }

        guard let count = read32() else { return nil }
        var entries = [PTPPropEntry]()
        
        for _ in 0..<count {
            guard let handle = read32(),
                  let propCode = read16(),
                  let dataType = read16() else { break }
            
            var value: Any? = nil
            switch dataType {
            case 0x0002: // Int8
                value = Int8(bitPattern: data[offset]); offset += 1
            case 0x0001: // UInt8
                value = data[offset]; offset += 1
            case 0x0004: // Int16
                value = Int16(bitPattern: read16() ?? 0)
            case 0x0003: // UInt16
                value = read16()
            case 0x0006: // Int32
                value = Int32(bitPattern: read32() ?? 0)
            case 0x0005: // UInt32
                value = read32()
            case 0x0008: // Int64
                value = Int64(bitPattern: read64() ?? 0)
            case 0x0007: // UInt64
                value = read64()
            case 0xFFFF: // String
                value = readString()
            default:
                // Skip unknown types (this is simplified, should handle more types)
                break
            }
            
            entries.append(PTPPropEntry(handle: handle, propertyCode: propCode, dataType: dataType, value: value))
        }
        
        return PTPPropList(entries: entries)
    }
}
