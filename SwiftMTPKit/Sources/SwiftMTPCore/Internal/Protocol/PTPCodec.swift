import Foundation

// PTP/MTP Unicode String format: count-prefixed UTF-16LE
struct PTPString {
    static func parse(from data: Data, at offset: inout Int) -> String? {
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

    static func encode(_ string: String) -> Data {
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
struct PTPDeviceInfo {
    let standardVersion: UInt16
    let vendorExtensionID: UInt32
    let vendorExtensionVersion: UInt16
    let vendorExtensionDesc: String
    let functionalMode: UInt16
    let operationsSupported: [UInt16]
    let eventsSupported: [UInt16]
    let devicePropertiesSupported: [UInt16]
    let captureFormats: [UInt16]
    let playbackFormats: [UInt16]
    let manufacturer: String
    let model: String
    let deviceVersion: String
    let serialNumber: String?

    static func parse(from data: Data) -> PTPDeviceInfo? {
        var offset = 0

        // Skip container header (12 bytes) and dataset length (4 bytes) to get to actual data
        guard data.count >= 16 else { return nil }
        offset = 16

        func read16() -> UInt16? {
            guard offset + 2 <= data.count else { return nil }
            let value = data[offset..<offset+2].withUnsafeBytes { $0.load(as: UInt16.self).littleEndian }
            offset += 2
            return value
        }

        func read32() -> UInt32? {
            guard offset + 4 <= data.count else { return nil }
            let value = data[offset..<offset+4].withUnsafeBytes { $0.load(as: UInt32.self).littleEndian }
            offset += 4
            return value
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
