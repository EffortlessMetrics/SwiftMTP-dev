// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation

// Sendable closure type aliases for MTP data transfer
public typealias MTPDataIn = @Sendable (UnsafeRawBufferPointer) -> Int
public typealias MTPDataOut = @Sendable (UnsafeMutableRawBufferPointer) -> Int

public struct PTPContainer: Sendable {
  public enum Kind: UInt16, Sendable { case command = 1, data = 2, response = 3, event = 4 }
  public var length: UInt32 = 12
  public var type: UInt16
  public var code: UInt16
  public var txid: UInt32
  public var params: [UInt32] = []

  public init(length: UInt32 = 12, type: UInt16, code: UInt16, txid: UInt32, params: [UInt32] = [])
  {
    self.length = length
    self.type = type
    self.code = code
    self.txid = txid
    self.params = params
  }

  public func encode(into buf: UnsafeMutablePointer<UInt8>) -> Int {
    var off = 0
    func put32(_ v: UInt32) {
      withUnsafeBytes(of: v.littleEndian) { m in
        m.copyBytes(to: UnsafeMutableRawBufferPointer(start: buf + off, count: 4))
        off += 4
      }
    }
    func put16(_ v: UInt16) {
      withUnsafeBytes(of: v.littleEndian) { m in
        m.copyBytes(to: UnsafeMutableRawBufferPointer(start: buf + off, count: 2))
        off += 2
      }
    }
    put32(length)
    put16(type)
    put16(code)
    put32(txid)
    for p in params { put32(p) }
    return off
  }
}

public enum PTPOp: UInt16 {
  case getDeviceInfo = 0x1001
  case openSession = 0x1002
  case closeSession = 0x1003
  case getStorageIDs = 0x1004
  case getStorageInfo = 0x1005
  case getNumObjects = 0x1006
  case getObjectHandles = 0x1007
  case getObjectInfo = 0x1008
  case getObject = 0x1009
  case getThumb = 0x100A
  case deleteObject = 0x100B
  case sendObjectInfo = 0x100C
  case sendObject = 0x100D
  case moveObject = 0x100E
  case getDevicePropDesc = 0x1014
  case getDevicePropValue = 0x1015
  case setDevicePropValue = 0x1016
  case resetDevicePropValue = 0x1017
  case getPartialObject = 0x101B
  case getPartialObject64 = 0x95C4
  case sendPartialObject = 0x95C1
}

// PTP/MTP Unicode String format: count-prefixed UTF-16LE
public struct PTPString {
  public static func parse(from data: Data, at offset: inout Int) -> String? {
    guard offset < data.count else { return nil }
    let charCount = Int(data[offset])
    offset += 1
    if charCount == 0 { return "" }
    if charCount == 0xFF { return nil }

    let byteCount = charCount * 2
    guard offset + byteCount <= data.count else { return nil }

    var utf16Chars = [UInt16]()
    utf16Chars.reserveCapacity(charCount)

    for _ in 0..<charCount {
      let low = UInt16(data[offset])
      let high = UInt16(data[offset + 1])
      let char = low | (high << 8)
      if char != 0 {
        utf16Chars.append(char)
      }
      offset += 2
    }

    return String(utf16CodeUnits: utf16Chars, count: utf16Chars.count)
  }

  public static func encode(_ string: String) -> Data {
    var data = Data()
    if string.isEmpty {
      data.append(0)
      return data
    }
    let utf16Chars = string.utf16.map { UInt16($0).littleEndian }
    let len = min(utf16Chars.count + 1, 255)
    data.append(UInt8(len))
    for i in 0..<len - 1 {
      let char = utf16Chars[i]
      data.append(contentsOf: [UInt8(char & 0xFF), UInt8(char >> 8)])
    }
    data.append(contentsOf: [0, 0])
    return data
  }
}

public enum PTPValue: Sendable {
  case int8(Int8), uint8(UInt8)
  case int16(Int16), uint16(UInt16)
  case int32(Int32), uint32(UInt32)
  case int64(Int64), uint64(UInt64)
  case int128(Data), uint128(Data)
  case string(String)
  case bytes(Data)
  case array([PTPValue])
}

public struct PTPReader {
  public let data: Data
  public var o: Int = 0
  public init(data: Data) { self.data = data }

  public mutating func u8() -> UInt8? {
    guard o + 1 <= data.count else { return nil }
    defer { o += 1 }
    return data[o]
  }

  public mutating func u16() -> UInt16? {
    guard o + 2 <= data.count else { return nil }
    var v: UInt16 = 0
    _ = withUnsafeMutableBytes(of: &v) { data.copyBytes(to: $0, from: o..<(o + 2)) }
    defer { o += 2 }
    return v.littleEndian
  }

  public mutating func u32() -> UInt32? {
    guard o + 4 <= data.count else { return nil }
    var v: UInt32 = 0
    _ = withUnsafeMutableBytes(of: &v) { data.copyBytes(to: $0, from: o..<(o + 4)) }
    defer { o += 4 }
    return v.littleEndian
  }

  public mutating func u64() -> UInt64? {
    guard o + 8 <= data.count else { return nil }
    var v: UInt64 = 0
    _ = withUnsafeMutableBytes(of: &v) { data.copyBytes(to: $0, from: o..<(o + 8)) }
    defer { o += 8 }
    return v.littleEndian
  }

  public mutating func bytes(_ n: Int) -> Data? {
    guard o + n <= data.count else { return nil }
    defer { o += n }
    return data.subdata(in: o..<(o + n))
  }
  public mutating func string() -> String? { PTPString.parse(from: data, at: &o) }

  public mutating func value(dt: UInt16) -> PTPValue? {
    if (dt & 0x4000) != 0 {
      let base = dt & ~0x4000
      guard let count = u32() else { return nil }
      var out: [PTPValue] = []
      out.reserveCapacity(Int(count))
      for _ in 0..<count {
        guard let v = value(dt: base) else { return nil }
        out.append(v)
      }
      return .array(out)
    }
    switch dt {
    case 0x0001:
      guard let b = u8() else { return nil }
      return .int8(Int8(bitPattern: b))
    case 0x0002:
      guard let b = u8() else { return nil }
      return .uint8(b)
    case 0x0003:
      guard let v = u16() else { return nil }
      return .int16(Int16(bitPattern: v))
    case 0x0004:
      guard let v = u16() else { return nil }
      return .uint16(v)
    case 0x0005:
      guard let v = u32() else { return nil }
      return .int32(Int32(bitPattern: v))
    case 0x0006:
      guard let v = u32() else { return nil }
      return .uint32(v)
    case 0x0007:
      guard let v = u64() else { return nil }
      return .int64(Int64(bitPattern: v))
    case 0x0008:
      guard let v = u64() else { return nil }
      return .uint64(v)
    case 0x0009:
      guard let d = bytes(16) else { return nil }
      return .int128(d)
    case 0x000A:
      guard let d = bytes(16) else { return nil }
      return .uint128(d)
    case 0xFFFF:
      guard let s = string() else { return nil }
      return .string(s)
    default: return nil
    }
  }
}

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
    var r = PTPReader(data: data)
    func readArray16() -> [UInt16]? {
      guard let count = r.u32() else { return nil }
      var array = [UInt16]()
      for _ in 0..<count {
        guard let value = r.u16() else { return nil }
        array.append(value)
      }
      return array
    }
    guard let standardVersion = r.u16(), let vendorExtensionID = r.u32(),
      let vendorExtensionVersion = r.u16(),
      let vendorExtensionDesc = r.string(), let functionalMode = r.u16(),
      let operationsSupported = readArray16(),
      let eventsSupported = readArray16(), let devicePropertiesSupported = readArray16(),
      let captureFormats = readArray16(), let playbackFormats = readArray16(),
      let manufacturer = r.string(), let model = r.string(), let deviceVersion = r.string(),
      let serialNumber = r.string()
    else { return nil }
    return PTPDeviceInfo(
      standardVersion: standardVersion, vendorExtensionID: vendorExtensionID,
      vendorExtensionVersion: vendorExtensionVersion, vendorExtensionDesc: vendorExtensionDesc,
      functionalMode: functionalMode, operationsSupported: operationsSupported,
      eventsSupported: eventsSupported, devicePropertiesSupported: devicePropertiesSupported,
      captureFormats: captureFormats, playbackFormats: playbackFormats, manufacturer: manufacturer,
      model: model, deviceVersion: deviceVersion, serialNumber: serialNumber)
  }
}

public struct PTPPropEntry: Sendable {
  public let handle: UInt32
  public let propertyCode: UInt16
  public let dataType: UInt16
  public let value: PTPValue?
}

public struct PTPPropList: Sendable {
  public let entries: [PTPPropEntry]
  public static func parse(from data: Data) -> PTPPropList? {
    var r = PTPReader(data: data)
    guard let n = r.u32() else { return nil }
    var out: [PTPPropEntry] = []
    out.reserveCapacity(Int(n))
    for _ in 0..<n {
      guard let h = r.u32(), let pc = r.u16(), let dt = r.u16(), let v = r.value(dt: dt)
      else { return nil }
      out.append(.init(handle: h, propertyCode: pc, dataType: dt, value: v))
    }
    return .init(entries: out)
  }
}

// MARK: - PTP Response Code Lookup

public enum PTPResponseCode {
  private static let names: [UInt16: String] = [
    0x2001: "OK",
    0x2002: "GeneralError",
    0x2003: "SessionNotOpen",
    0x2004: "InvalidTransactionID",
    0x2005: "OperationNotSupported",
    0x2006: "ParameterNotSupported",
    0x2007: "IncompleteTransfer",
    0x2008: "InvalidStorageID",
    0x2009: "InvalidObjectHandle",
    0x200A: "DevicePropNotSupported",
    0x200B: "InvalidObjectFormatCode",
    0x200C: "StoreFull",
    0x200D: "ObjectWriteProtected",
    0x200E: "StoreReadOnly",
    0x200F: "AccessDenied",
    0x2010: "NoThumbnailPresent",
    0x2011: "SelfTestFailed",
    0x2012: "PartialDeletion",
    0x2013: "StoreNotAvailable",
    0x2014: "SpecificationByFormatUnsupported",
    0x2015: "NoValidObjectInfo",
    0x2016: "InvalidCodeFormat",
    0x2017: "UnknownVendorCode",
    0x2018: "CaptureAlreadyTerminated",
    0x2019: "DeviceBusy",
    0x201A: "InvalidParentObject",
    0x201B: "InvalidDevicePropFormat",
    0x201C: "InvalidDevicePropValue",
    0x201D: "InvalidParameter",
    0x201E: "SessionAlreadyOpen",
    0x201F: "TransactionCancelled",
    0x2020: "SpecificationOfDestinationUnsupported",
  ]

  /// Return the standard PTP name for a response code, or nil if unknown.
  public static func name(for code: UInt16) -> String? {
    names[code]
  }

  /// Human-readable description: `"InvalidParameter (0x201d)"` or `"Unknown (0x201d)"`.
  public static func describe(_ code: UInt16) -> String {
    let n = names[code] ?? "Unknown"
    return "\(n) (0x\(String(format: "%04x", code)))"
  }
}

public enum PTPObjectFormat {
  public static func forFilename(_ name: String) -> UInt16 {
    let lower = name.lowercased()
    if lower.hasSuffix(".txt") { return 0x3004 }  // Text
    if lower.hasSuffix(".jpg") || lower.hasSuffix(".jpeg") { return 0x3801 }  // EXIF/JPEG
    if lower.hasSuffix(".png") { return 0x380b }  // PNG
    if lower.hasSuffix(".mp4") { return 0x300b }  // MP4
    if lower.hasSuffix(".mp3") { return 0x3009 }  // MP3
    if lower.hasSuffix(".aac") { return 0xb903 }  // AAC
    return 0x3000  // Undefined
  }
}

public struct PTPObjectInfoDataset {
  public static func encode(
    storageID: UInt32, parentHandle: UInt32, format: UInt16, size: UInt64, name: String,
    associationType: UInt16 = 0, associationDesc: UInt32 = 0,
    useEmptyDates: Bool = false,
    objectCompressedSizeOverride: UInt32? = nil,
    omitOptionalStringFields: Bool = false,
    objectInfoParentHandleOverride: UInt32? = nil
  ) -> Data {
    var data = Data()
    func put32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { data.append(contentsOf: $0) } }
    func put16(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { data.append(contentsOf: $0) } }
    func putPTPString(_ s: String) {
      if s.isEmpty {
        data.append(0)
        return
      }
      let utf16 = Array(s.utf16)
      let charCount = UInt8(min(255, utf16.count + 1))
      data.append(charCount)
      for cu in utf16.prefix(Int(charCount) - 1) {
        put16(UInt16(cu))
      }
      put16(0)  // Null terminator
    }

    put32(storageID)
    put16(format)
    put16(0)  // ProtectionStatus
    put32(objectCompressedSizeOverride ?? UInt32(min(size, UInt64(0xFFFFFFFF))))  // ObjectCompressedSize
    put16(0)  // ThumbFormat
    put32(0)  // ThumbCompressedSize
    put32(0)  // ThumbPixWidth
    put32(0)  // ThumbPixHeight
    put32(0)  // ImagePixWidth
    put32(0)  // ImagePixHeight
    put32(0)  // ImageBitDepth
    put32(objectInfoParentHandleOverride ?? parentHandle)
    put16(associationType)
    put32(associationDesc)
    put32(0)  // SequenceNumber
    putPTPString(name)
    if !omitOptionalStringFields {
      if useEmptyDates {
        putPTPString("")  // CaptureDate (empty)
        putPTPString("")  // ModificationDate (empty)
      } else {
        putPTPString("20250101T000000")  // CaptureDate
        putPTPString("20250101T000000")  // ModificationDate
      }
      putPTPString("")  // Keywords
    }

    return data
  }
}
