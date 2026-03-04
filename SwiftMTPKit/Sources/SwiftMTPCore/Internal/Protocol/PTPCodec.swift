// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import MTPEndianCodec

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
    let base = UnsafeMutableRawPointer(buf)
    var off = 0
    MTPEndianCodec.encode(length, into: base, at: off)
    off += 4
    MTPEndianCodec.encode(type, into: base, at: off)
    off += 2
    MTPEndianCodec.encode(code, into: base, at: off)
    off += 2
    MTPEndianCodec.encode(txid, into: base, at: off)
    off += 4
    for p in params {
      MTPEndianCodec.encode(p, into: base, at: off)
      off += 4
    }
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
  case getPartialObject64 = 0x95C1
  case sendPartialObject = 0x95C2
  case truncateObject = 0x95C3
  case beginEditObject = 0x95C4
  case endEditObject = 0x95C5
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
  /// Maximum safe device-supplied count for arrays and object lists.
  public static let maxSafeCount: UInt32 = 100_000

  /// Throws if `count` exceeds the maximum safe device-provided array or object count.
  public static func validateCount(_ count: UInt32) throws {
    guard count <= maxSafeCount else {
      throw MTPError.protocolError(code: 0x2006, message: "invalid dataset: count too large")
    }
  }

  public let data: Data
  public var o: Int = 0
  public init(data: Data) { self.data = data }

  public mutating func u8() -> UInt8? {
    guard o + 1 <= data.count else { return nil }
    defer { o += 1 }
    return data[o]
  }

  public mutating func u16() -> UInt16? {
    guard let v = MTPEndianCodec.decodeUInt16(from: data, at: o) else { return nil }
    defer { o += 2 }
    return v
  }

  public mutating func u32() -> UInt32? {
    guard let v = MTPEndianCodec.decodeUInt32(from: data, at: o) else { return nil }
    defer { o += 4 }
    return v
  }

  public mutating func u64() -> UInt64? {
    guard let v = MTPEndianCodec.decodeUInt64(from: data, at: o) else { return nil }
    defer { o += 8 }
    return v
  }

  public mutating func bytes(_ n: Int) -> Data? {
    guard o + n <= data.count else { return nil }
    defer { o += n }
    return data.subdata(in: o..<(o + n))
  }
  public mutating func string() -> String? { PTPString.parse(from: data, at: &o) }

  public mutating func value(dt: UInt16) -> PTPValue? {
    // 0xFFFF is the PTP Unicode String type — must be handled before the array-bit check
    // because 0xFFFF & 0x4000 ≠ 0 and would otherwise fall into the array branch.
    if dt == 0xFFFF {
      guard let s = string() else { return nil }
      return .string(s)
    }
    if (dt & 0x4000) != 0 {
      let base = dt & ~0x4000
      guard let count = u32() else { return nil }
      guard count <= PTPReader.maxSafeCount else { return nil }
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
      guard count <= PTPReader.maxSafeCount else { return nil }
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
    guard n <= PTPReader.maxSafeCount else { return nil }
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

  // MARK: - MTP 1.1 Standard Object Format Codes

  // Undefined / General
  public static let undefined: UInt16 = 0x3000
  public static let association: UInt16 = 0x3001
  public static let script: UInt16 = 0x3002
  public static let executable: UInt16 = 0x3003

  // Text
  public static let text: UInt16 = 0x3004
  public static let html: UInt16 = 0x3005
  public static let dpof: UInt16 = 0x3006
  public static let aiff: UInt16 = 0x3007
  public static let wav: UInt16 = 0x3008

  // Audio
  public static let mp3: UInt16 = 0x3009
  public static let avi: UInt16 = 0x300A
  public static let mpeg: UInt16 = 0x300B
  public static let asf: UInt16 = 0x300C
  public static let wma: UInt16 = 0xB901
  public static let aac: UInt16 = 0xB903
  public static let audible: UInt16 = 0xB904
  public static let flac: UInt16 = 0xB906
  public static let ogg: UInt16 = 0xB980

  // Image
  public static let undefinedImage: UInt16 = 0x3800
  public static let exifJPEG: UInt16 = 0x3801
  public static let tiffEP: UInt16 = 0x3802
  public static let bmp: UInt16 = 0x3804
  public static let gif: UInt16 = 0x3805
  public static let jfif: UInt16 = 0x3806
  public static let pict: UInt16 = 0x3807
  public static let png: UInt16 = 0x3808
  public static let tiff: UInt16 = 0x3809
  public static let jp2: UInt16 = 0x380B
  public static let heif: UInt16 = 0x380D

  // Video
  public static let undefinedVideo: UInt16 = 0xB800
  public static let wmv: UInt16 = 0xB801
  public static let mp4Container: UInt16 = 0xB802
  public static let mp2: UInt16 = 0xB803
  public static let threeGP: UInt16 = 0xB804
  public static let undefinedCollection: UInt16 = 0xB880
  public static let mkv: UInt16 = 0xB982

  // Document
  public static let undefinedDocument: UInt16 = 0xBA00
  public static let abstractMultimediaAlbum: UInt16 = 0xBA01
  public static let abstractAudioAlbum: UInt16 = 0xBA05
  public static let wplPlaylist: UInt16 = 0xBA10
  public static let m3uPlaylist: UInt16 = 0xBA11
  public static let xmlDocument: UInt16 = 0xBA82
  public static let msWordDocument: UInt16 = 0xBA83
  public static let msExcelSpreadsheet: UInt16 = 0xBA85
  public static let msPowerPointPresentation: UInt16 = 0xBA86

  // MARK: - Extension → Format mapping

  private static let extensionMap: [String: UInt16] = [
    // Image
    ".jpg": exifJPEG, ".jpeg": exifJPEG, ".jfif": jfif,
    ".png": png, ".gif": gif, ".bmp": bmp,
    ".tiff": tiff, ".tif": tiff, ".tiff-ep": tiffEP,
    ".heic": heif, ".heif": heif,
    ".jp2": jp2, ".pict": pict, ".pct": pict,
    // Audio
    ".mp3": mp3, ".wav": wav, ".aiff": aiff, ".aif": aiff,
    ".flac": flac, ".aac": aac, ".ogg": ogg, ".oga": ogg,
    ".wma": wma, ".aa": audible, ".aax": audible,
    // Video
    ".mp4": mp4Container, ".m4v": mp4Container, ".m4a": mp4Container,
    ".avi": avi, ".wmv": wmv, ".mkv": mkv,
    ".3gp": threeGP, ".3g2": threeGP,
    ".mov": mpeg, ".mpg": mpeg, ".mpeg": mpeg,
    ".mp2": mp2, ".asf": asf,
    // Text / Document
    ".txt": text, ".html": html, ".htm": html,
    ".xml": xmlDocument,
    ".doc": msWordDocument, ".docx": msWordDocument,
    ".xls": msExcelSpreadsheet, ".xlsx": msExcelSpreadsheet,
    ".ppt": msPowerPointPresentation, ".pptx": msPowerPointPresentation,
    ".m3u": m3uPlaylist, ".m3u8": m3uPlaylist,
    ".wpl": wplPlaylist,
    // Executable / Script
    ".sh": script, ".bat": script, ".exe": executable,
  ]

  /// Infer MTP object-format code from a filename extension.
  public static func forFilename(_ name: String) -> UInt16 {
    let lower = name.lowercased()
    if let dot = lower.lastIndex(of: ".") {
      let ext = String(lower[dot...])
      if let code = extensionMap[ext] { return code }
    }
    return undefined
  }

  // MARK: - Human-readable name

  private static let names: [UInt16: String] = [
    undefined: "Undefined", association: "Association", script: "Script",
    executable: "Executable", text: "Text", html: "HTML", dpof: "DPOF",
    aiff: "AIFF", wav: "WAV", mp3: "MP3", avi: "AVI", mpeg: "MPEG",
    asf: "ASF", wma: "WMA", aac: "AAC", audible: "Audible", flac: "FLAC",
    ogg: "OGG", undefinedImage: "UndefinedImage", exifJPEG: "EXIF/JPEG",
    tiffEP: "TIFF/EP", bmp: "BMP", gif: "GIF", jfif: "JFIF", pict: "PICT",
    png: "PNG", tiff: "TIFF", jp2: "JP2", heif: "HEIF",
    undefinedVideo: "UndefinedVideo", wmv: "WMV", mp4Container: "MP4",
    mp2: "MP2", threeGP: "3GP", undefinedCollection: "UndefinedCollection",
    mkv: "MKV", undefinedDocument: "UndefinedDocument",
    abstractMultimediaAlbum: "AbstractMultimediaAlbum",
    abstractAudioAlbum: "AbstractAudioAlbum",
    wplPlaylist: "WPLPlaylist", m3uPlaylist: "M3UPlaylist",
    xmlDocument: "XMLDocument", msWordDocument: "MSWordDocument",
    msExcelSpreadsheet: "MSExcelSpreadsheet",
    msPowerPointPresentation: "MSPowerPointPresentation",
  ]

  /// Human-readable name for a format code, e.g. `"EXIF/JPEG (0x3801)"`.
  public static func describe(_ code: UInt16) -> String {
    let n = names[code] ?? "Unknown"
    return "\(n) (0x\(String(format: "%04x", code)))"
  }

  // MARK: - MIME type

  private static let mimeTypes: [UInt16: String] = [
    text: "text/plain", html: "text/html", xmlDocument: "text/xml",
    exifJPEG: "image/jpeg", jfif: "image/jpeg", png: "image/png",
    gif: "image/gif", bmp: "image/bmp", tiff: "image/tiff",
    tiffEP: "image/tiff", jp2: "image/jp2", heif: "image/heif",
    pict: "image/x-pict",
    mp3: "audio/mpeg", wav: "audio/wav", aiff: "audio/aiff",
    flac: "audio/flac", aac: "audio/aac", ogg: "audio/ogg",
    wma: "audio/x-ms-wma", audible: "audio/vnd.audible.aax",
    mp4Container: "video/mp4", avi: "video/x-msvideo", wmv: "video/x-ms-wmv",
    mpeg: "video/mpeg", mkv: "video/x-matroska", threeGP: "video/3gpp",
    mp2: "video/mpeg", asf: "video/x-ms-asf",
    msWordDocument: "application/msword",
    msExcelSpreadsheet: "application/vnd.ms-excel",
    msPowerPointPresentation: "application/vnd.ms-powerpoint",
    executable: "application/octet-stream", script: "text/x-script",
    association: "inode/directory",
  ]

  /// MIME type for a format code, or `"application/octet-stream"` if unknown.
  public static func mimeType(for code: UInt16) -> String {
    mimeTypes[code] ?? "application/octet-stream"
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
    var w = MTPDataEncoder()
    w.append(storageID)
    w.append(format)
    w.append(UInt16(0))  // ProtectionStatus
    // ObjectCompressedSize
    w.append(objectCompressedSizeOverride ?? UInt32(min(size, UInt64(0xFFFF_FFFF))))
    w.append(UInt16(0))  // ThumbFormat
    w.append(UInt32(0))  // ThumbCompressedSize
    w.append(UInt32(0))  // ThumbPixWidth
    w.append(UInt32(0))  // ThumbPixHeight
    w.append(UInt32(0))  // ImagePixWidth
    w.append(UInt32(0))  // ImagePixHeight
    w.append(UInt32(0))  // ImageBitDepth
    w.append(objectInfoParentHandleOverride ?? parentHandle)
    w.append(associationType)
    w.append(associationDesc)
    w.append(UInt32(0))  // SequenceNumber
    w.append(PTPString.encode(name))
    if !omitOptionalStringFields {
      if useEmptyDates {
        w.append(PTPString.encode(""))  // CaptureDate
        w.append(PTPString.encode(""))  // ModificationDate
      } else {
        w.append(PTPString.encode("20250101T000000"))  // CaptureDate
        w.append(PTPString.encode("20250101T000000"))  // ModificationDate
      }
      w.append(PTPString.encode(""))  // Keywords
    }
    return w.encodedData
  }
}
