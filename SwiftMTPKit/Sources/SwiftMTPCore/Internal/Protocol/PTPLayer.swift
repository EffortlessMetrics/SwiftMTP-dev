// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import MTPEndianCodec

// MARK: - MTP Object Property Codes

/// MTP object property codes (MTP 1.1 spec § 5.3).
public enum MTPObjectPropCode {

  // MARK: - Object Info Properties (0xDC01–0xDC0E)

  public static let storageID: UInt16 = 0xDC01
  public static let objectFormat: UInt16 = 0xDC02
  public static let protectionStatus: UInt16 = 0xDC03
  public static let objectSize: UInt16 = 0xDC04
  public static let associationType: UInt16 = 0xDC05
  public static let associationDesc: UInt16 = 0xDC06
  public static let objectFileName: UInt16 = 0xDC07
  public static let dateCreated: UInt16 = 0xDC08
  public static let dateModified: UInt16 = 0xDC09
  public static let keywords: UInt16 = 0xDC0A
  public static let parentObject: UInt16 = 0xDC0B
  public static let allowedFolderContents: UInt16 = 0xDC0C
  public static let hidden: UInt16 = 0xDC0D
  public static let systemObject: UInt16 = 0xDC0E

  // MARK: - Common Properties (0xDC41–0xDC51)

  public static let persistentUniqueObjectIdentifier: UInt16 = 0xDC41
  public static let syncID: UInt16 = 0xDC42
  public static let propertyBag: UInt16 = 0xDC43
  public static let name: UInt16 = 0xDC44
  public static let createdBy: UInt16 = 0xDC45
  public static let artist: UInt16 = 0xDC46
  public static let dateAuthored: UInt16 = 0xDC47
  public static let objectDescription: UInt16 = 0xDC48
  public static let urlReference: UInt16 = 0xDC49
  public static let languageLocale: UInt16 = 0xDC4A
  public static let copyrightInformation: UInt16 = 0xDC4B
  public static let source: UInt16 = 0xDC4C
  public static let originLocation: UInt16 = 0xDC4D
  public static let dateAdded: UInt16 = 0xDC4E
  public static let nonConsumable: UInt16 = 0xDC4F
  public static let corruptOrUnplayable: UInt16 = 0xDC50
  public static let producerSerialNumber: UInt16 = 0xDC51

  // MARK: - Music / Audio Metadata (0xDC89–0xDC9B)

  public static let duration: UInt16 = 0xDC89
  public static let rating: UInt16 = 0xDC8A
  public static let track: UInt16 = 0xDC8B
  public static let genre: UInt16 = 0xDC8C
  public static let useCount: UInt16 = 0xDC91
  public static let effectiveRating: UInt16 = 0xDC94
  public static let metaGenre: UInt16 = 0xDC96
  public static let albumName: UInt16 = 0xDC9A
  public static let albumArtist: UInt16 = 0xDC9B

  // MARK: - Representative Sample / Thumbnail (0xDCD5–0xDCDA)

  public static let representativeSampleFormat: UInt16 = 0xDCD5
  public static let representativeSampleSize: UInt16 = 0xDCD6
  public static let representativeSampleHeight: UInt16 = 0xDCD7
  public static let representativeSampleWidth: UInt16 = 0xDCD8
  public static let representativeSampleDuration: UInt16 = 0xDCD9
  public static let representativeSampleData: UInt16 = 0xDCDA

  // MARK: - Video Properties (0xDE00–0xDE04)

  public static let width: UInt16 = 0xDE00
  public static let height: UInt16 = 0xDE01
  public static let dpi: UInt16 = 0xDE02
  public static let fourCCCodec: UInt16 = 0xDE03
  public static let videoBitRate: UInt16 = 0xDE04

  // MARK: - Audio Properties (0xDE91–0xDE99)

  public static let sampleRate: UInt16 = 0xDE91
  public static let numberOfChannels: UInt16 = 0xDE92
  public static let audioBitDepth: UInt16 = 0xDE93
  public static let audioBitRate: UInt16 = 0xDE94
  public static let audioBlockAlignment: UInt16 = 0xDE95
  public static let audioDuration: UInt16 = 0xDE97
  public static let audioWAVECodec: UInt16 = 0xDE99

  // MARK: - Data Type Lookup

  /// Returns the MTP data type code for a given property code.
  /// Common types: 0x0002=UInt8, 0x0004=UInt16, 0x0006=UInt32, 0x0008=UInt64, 0x000A=UInt128, 0xFFFF=String.
  public static func dataType(for code: UInt16) -> UInt16 {
    switch code {
    // UInt16 properties
    case objectFormat, protectionStatus, associationType, hidden, systemObject,
         numberOfChannels, rating, track, effectiveRating, metaGenre,
         representativeSampleFormat:
      return 0x0004
    // UInt32 properties
    case storageID, associationDesc, parentObject, duration, useCount,
         representativeSampleSize, representativeSampleHeight,
         representativeSampleWidth, representativeSampleDuration,
         width, height, dpi, fourCCCodec, videoBitRate,
         sampleRate, audioBitDepth, audioBitRate, audioBlockAlignment,
         audioDuration, audioWAVECodec:
      return 0x0006
    // UInt64 properties
    case objectSize:
      return 0x0008
    // UInt128 properties
    case persistentUniqueObjectIdentifier:
      return 0x000A
    // String properties (including date-strings)
    case objectFileName, dateCreated, dateModified, keywords, syncID, name,
         createdBy, artist, dateAuthored, objectDescription, urlReference,
         languageLocale, copyrightInformation, source, originLocation,
         dateAdded, producerSerialNumber, genre, albumName, albumArtist:
      return 0xFFFF
    // UInt8 properties
    case nonConsumable, corruptOrUnplayable:
      return 0x0002
    // Array properties
    case allowedFolderContents, propertyBag:
      return 0x4004
    // Byte array (representative sample data)
    case representativeSampleData:
      return 0x4002
    default:
      return 0xFFFF  // default to string for unknown codes
    }
  }

  // MARK: - Display Name

  /// Returns a human-readable name for a property code.
  public static func displayName(for code: UInt16) -> String {
    switch code {
    case storageID: return "Storage ID"
    case objectFormat: return "Object Format"
    case protectionStatus: return "Protection Status"
    case objectSize: return "Object Size"
    case associationType: return "Association Type"
    case associationDesc: return "Association Description"
    case objectFileName: return "File Name"
    case dateCreated: return "Date Created"
    case dateModified: return "Date Modified"
    case keywords: return "Keywords"
    case parentObject: return "Parent Object"
    case allowedFolderContents: return "Allowed Folder Contents"
    case hidden: return "Hidden"
    case systemObject: return "System Object"
    case persistentUniqueObjectIdentifier: return "Persistent Unique Object ID"
    case syncID: return "Sync ID"
    case propertyBag: return "Property Bag"
    case name: return "Name"
    case createdBy: return "Created By"
    case artist: return "Artist"
    case dateAuthored: return "Date Authored"
    case objectDescription: return "Description"
    case urlReference: return "URL Reference"
    case languageLocale: return "Language Locale"
    case copyrightInformation: return "Copyright"
    case source: return "Source"
    case originLocation: return "Origin Location"
    case dateAdded: return "Date Added"
    case nonConsumable: return "Non-Consumable"
    case corruptOrUnplayable: return "Corrupt/Unplayable"
    case producerSerialNumber: return "Producer Serial Number"
    case duration: return "Duration"
    case rating: return "Rating"
    case track: return "Track"
    case genre: return "Genre"
    case useCount: return "Use Count"
    case effectiveRating: return "Effective Rating"
    case metaGenre: return "Meta Genre"
    case albumName: return "Album Name"
    case albumArtist: return "Album Artist"
    case representativeSampleFormat: return "Sample Format"
    case representativeSampleSize: return "Sample Size"
    case representativeSampleHeight: return "Sample Height"
    case representativeSampleWidth: return "Sample Width"
    case representativeSampleDuration: return "Sample Duration"
    case representativeSampleData: return "Sample Data"
    case width: return "Width"
    case height: return "Height"
    case dpi: return "DPI"
    case fourCCCodec: return "FourCC Codec"
    case videoBitRate: return "Video Bit Rate"
    case sampleRate: return "Sample Rate"
    case numberOfChannels: return "Channels"
    case audioBitDepth: return "Audio Bit Depth"
    case audioBitRate: return "Audio Bit Rate"
    case audioBlockAlignment: return "Audio Block Alignment"
    case audioDuration: return "Audio Duration"
    case audioWAVECodec: return "Audio WAVE Codec"
    default: return String(format: "Unknown (0x%04X)", code)
    }
  }
}

// MARK: - MTP Date String Helpers

/// Encode/decode MTP date strings (ISO 8601 compact format `YYYYMMDDTHHmmSS`).
public enum MTPDateString {
  // DateFormatter is not thread-safe: create a fresh instance per call.
  private static func makeFormatter() -> DateFormatter {
    let f = DateFormatter()
    f.dateFormat = "yyyyMMdd'T'HHmmss"
    f.timeZone = TimeZone(identifier: "UTC")
    f.locale = Locale(identifier: "en_US_POSIX")
    return f
  }

  public static func encode(_ date: Date) -> String {
    makeFormatter().string(from: date)
  }

  public static func decode(_ string: String) -> Date? {
    // Strip trailing timezone suffix (e.g. ".0Z", "+0000") before parsing
    let stripped = String(string.prefix(15))
    return makeFormatter().date(from: stripped)
  }
}

// MARK: - MTPPropListEntry

/// A single entry for batch property writes via SetObjectPropList (0x9806).
///
/// Each entry specifies the target object handle, the MTP property code,
/// the MTP data type, and the pre-encoded value bytes (little-endian per MTP spec).
public struct MTPPropListEntry: Sendable, Equatable {
  public let handle: MTPObjectHandle
  public let propCode: UInt16
  public let datatype: UInt16
  public let value: Data

  public init(handle: MTPObjectHandle, propCode: UInt16, datatype: UInt16, value: Data) {
    self.handle = handle
    self.propCode = propCode
    self.datatype = datatype
    self.value = value
  }

  /// Convenience: create an entry with the data type auto-resolved from `MTPObjectPropCode`.
  public init(handle: MTPObjectHandle, propCode: UInt16, value: Data) {
    self.handle = handle
    self.propCode = propCode
    self.datatype = MTPObjectPropCode.dataType(for: propCode)
    self.value = value
  }

  /// Convenience: create a string property entry.
  public static func string(
    handle: MTPObjectHandle, propCode: UInt16, value: String
  ) -> MTPPropListEntry {
    MTPPropListEntry(handle: handle, propCode: propCode, datatype: 0xFFFF, value: PTPString.encode(value))
  }

  /// Convenience: create a UInt32 property entry.
  public static func uint32(
    handle: MTPObjectHandle, propCode: UInt16, value: UInt32
  ) -> MTPPropListEntry {
    var enc = MTPDataEncoder()
    enc.append(value)
    return MTPPropListEntry(handle: handle, propCode: propCode, datatype: 0x0006, value: enc.encodedData)
  }

  /// Convenience: create a UInt16 property entry.
  public static func uint16(
    handle: MTPObjectHandle, propCode: UInt16, value: UInt16
  ) -> MTPPropListEntry {
    var enc = MTPDataEncoder()
    enc.append(value)
    return MTPPropListEntry(handle: handle, propCode: propCode, datatype: 0x0004, value: enc.encodedData)
  }

  /// Encode this entry into a data buffer (MTP wire format).
  func encode(into enc: inout MTPDataEncoder) {
    enc.append(handle)
    enc.append(propCode)
    enc.append(datatype)
    enc.append(value)
  }
}

// MARK: - PTPLayer

/// Pure PTP-standard operations that work on any PTP device (cameras, DAPs)
/// without requiring an MTP session. These can be called pre-session.
public enum PTPLayer {

  /// Send GetDeviceInfo (0x1001) — sessionless, works on any PTP device.
  public static func getDeviceInfo(on link: MTPLink) async throws -> MTPDeviceInfo {
    try await link.getDeviceInfo()
  }

  /// Open a PTP session with the given ID.
  public static func openSession(id: UInt32, on link: MTPLink) async throws {
    try await link.openSession(id: id)
  }

  /// Close the current PTP session.
  public static func closeSession(on link: MTPLink) async throws {
    try await link.closeSession()
  }

  /// Get list of storage IDs.
  public static func getStorageIDs(on link: MTPLink) async throws -> [MTPStorageID] {
    try await link.getStorageIDs()
  }

  /// Get storage info for a specific storage.
  public static func getStorageInfo(id: MTPStorageID, on link: MTPLink) async throws
    -> MTPStorageInfo
  {
    try await link.getStorageInfo(id: id)
  }

  /// Get object handles in a storage/parent.
  public static func getObjectHandles(
    storage: MTPStorageID, parent: MTPObjectHandle?,
    on link: MTPLink
  ) async throws -> [MTPObjectHandle] {
    try await link.getObjectHandles(storage: storage, parent: parent)
  }

  /// Check if a link's device supports a specific PTP/MTP operation code.
  public static func supportsOperation(_ opcode: UInt16, deviceInfo: MTPDeviceInfo) -> Bool {
    deviceInfo.operationsSupported.contains(opcode)
  }

  // MARK: - MTP Object Property Helpers

  /// Read the `DateModified` (0xDC09) property for an object and parse it.
  ///
  /// Returns `nil` if the property is not supported or the response is empty.
  public static func getObjectModificationDate(
    handle: MTPObjectHandle, on link: MTPLink
  ) async throws -> Date? {
    let data = try await link.getObjectPropValue(
      handle: handle, property: MTPObjectPropCode.dateModified)
    var offset = 0
    guard let s = PTPString.parse(from: data, at: &offset), !s.isEmpty else { return nil }
    return MTPDateString.decode(s)
  }

  /// Write the `DateModified` (0xDC09) property for an object.
  public static func setObjectModificationDate(
    handle: MTPObjectHandle, date: Date, on link: MTPLink
  ) async throws {
    let encoded = PTPString.encode(MTPDateString.encode(date))
    try await link.setObjectPropValue(
      handle: handle, property: MTPObjectPropCode.dateModified, value: encoded)
  }

  /// Read the `ObjectFileName` (0xDC07) property for an object.
  public static func getObjectFileName(
    handle: MTPObjectHandle, on link: MTPLink
  ) async throws -> String? {
    let data = try await link.getObjectPropValue(
      handle: handle, property: MTPObjectPropCode.objectFileName)
    var offset = 0
    return PTPString.parse(from: data, at: &offset)
  }

  /// GetObjectPropsSupported (0x9801): list all property codes supported for a given format.
  ///
  /// Returns an empty array if the device does not support this operation.
  public static func getObjectPropsSupported(
    format: UInt16, on link: MTPLink
  ) async throws -> [UInt16] {
    return try await link.getObjectPropsSupported(format: format)
  }

  /// Read the `ObjectSize` (0xDC04) property as a UInt64 via GetObjectPropValue.
  ///
  /// Use this to get the accurate 64-bit size of files > 4 GB, where
  /// `GetObjectInfo` reports `0xFFFFFFFF` as the compressed size.
  public static func getObjectSizeU64(
    handle: MTPObjectHandle, on link: MTPLink
  ) async throws -> UInt64? {
    let data = try await link.getObjectPropValue(
      handle: handle, property: MTPObjectPropCode.objectSize)
    var dec = MTPDataDecoder(data: data)
    return dec.readUInt64()
  }

  /// SetObjectPropList (0x9806): write multiple object properties in a single transaction.
  ///
  /// - Parameters:
  ///   - entries: Array of property entries to write.
  ///   - link: MTP link to execute on.
  /// - Returns: The number of entries successfully written (from device response param1).
  @discardableResult
  public static func setObjectPropList(
    entries: [MTPPropListEntry], on link: MTPLink
  ) async throws -> UInt32 {
    try await link.setObjectPropList(entries: entries)
  }
}
