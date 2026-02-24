// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import MTPEndianCodec

// MARK: - Device Identifiers

/// Unique identifier for an MTP device instance.
public struct MTPDeviceID: Hashable, Sendable, Codable {
  public let raw: String
  public init(raw: String) { self.raw = raw }
}

/// Summary information about an MTP device discovered on the system.
///
/// This lightweight structure provides basic identification information
/// about a connected MTP device without requiring a full device connection.
public struct MTPDeviceSummary: Sendable {
  /// Unique identifier for the device
  public let id: MTPDeviceID
  /// Device manufacturer name
  public let manufacturer: String
  /// Device model name
  public let model: String
  /// USB Vendor ID
  public let vendorID: UInt16?
  /// USB Product ID
  public let productID: UInt16?
  /// USB Bus number
  public let bus: UInt8?
  /// USB Device address
  public let address: UInt8?
  /// USB serial number from iSerialNumber descriptor (most reliable identity signal)
  public let usbSerial: String?

  /// Device fingerprint for quirk matching
  public var fingerprint: String {
    guard let vid = vendorID, let pid = productID else { return "unknown" }
    return String(format: "%04x:%04x", vid, pid)
  }

  /// Creates a new device summary.
  public init(
    id: MTPDeviceID, manufacturer: String, model: String, vendorID: UInt16? = nil,
    productID: UInt16? = nil, bus: UInt8? = nil, address: UInt8? = nil, usbSerial: String? = nil
  ) {
    self.id = id
    self.manufacturer = manufacturer
    self.model = model
    self.vendorID = vendorID
    self.productID = productID
    self.bus = bus
    self.address = address
    self.usbSerial = usbSerial
  }
}

// MARK: - Storage Types

/// Identifier for a storage unit on an MTP device.
public struct MTPStorageID: Hashable, Sendable, Codable {
  public let raw: UInt32
  public init(raw: UInt32) { self.raw = raw }
}

/// Information about a storage unit on an MTP device.
public struct MTPStorageInfo: Sendable, Codable {
  public let id: MTPStorageID
  public let description: String
  public let capacityBytes: UInt64
  public let freeBytes: UInt64
  public let isReadOnly: Bool

  public init(
    id: MTPStorageID, description: String, capacityBytes: UInt64, freeBytes: UInt64,
    isReadOnly: Bool
  ) {
    self.id = id
    self.description = description
    self.capacityBytes = capacityBytes
    self.freeBytes = freeBytes
    self.isReadOnly = isReadOnly
  }
}

// MARK: - Object Types

/// Handle representing an object (file or folder) on an MTP device.
public typealias MTPObjectHandle = UInt32

/// Information about an object (file or folder) on an MTP device.
public struct MTPObjectInfo: Sendable, Codable {
  public let handle: MTPObjectHandle
  public let storage: MTPStorageID
  public let parent: MTPObjectHandle?
  public let name: String
  public let sizeBytes: UInt64?
  public let modified: Date?
  public let formatCode: UInt16
  public let properties: [UInt16: String]

  public init(
    handle: MTPObjectHandle, storage: MTPStorageID, parent: MTPObjectHandle?, name: String,
    sizeBytes: UInt64?, modified: Date?, formatCode: UInt16, properties: [UInt16: String]
  ) {
    self.handle = handle
    self.storage = storage
    self.parent = parent
    self.name = name
    self.sizeBytes = sizeBytes
    self.modified = modified
    self.formatCode = formatCode
    self.properties = properties
  }
}

// MARK: - Device Info

/// Detailed information about an MTP device and its capabilities.
public struct MTPDeviceInfo: Sendable, Codable {
  public let manufacturer: String
  public let model: String
  public let version: String
  public let serialNumber: String?
  public let operationsSupported: Set<UInt16>
  public let eventsSupported: Set<UInt16>

  public init(
    manufacturer: String, model: String, version: String, serialNumber: String?,
    operationsSupported: Set<UInt16>, eventsSupported: Set<UInt16>
  ) {
    self.manufacturer = manufacturer
    self.model = model
    self.version = version
    self.serialNumber = serialNumber
    self.operationsSupported = operationsSupported
    self.eventsSupported = eventsSupported
  }
}

// MARK: - Events

/// Events that can be emitted by an MTP device during operation.
public enum MTPEvent: Sendable {
  /// A new object was added to the device
  case objectAdded(MTPObjectHandle)
  /// An object was removed from the device
  case objectRemoved(MTPObjectHandle)
  /// Storage information changed (capacity, free space, etc.)
  case storageInfoChanged(MTPStorageID)

  /// Parse MTP event from raw PTP/MTP event container data
  public static func fromRaw(_ data: Data) -> MTPEvent? {
    guard data.count >= 12 else { return nil }
    // PTP/MTP Event container: [len(4) type(2)=4 code(2) txid(4) params...]
    guard let code: UInt16 = MTPEndianCodec.decodeUInt16(from: data, at: 6) else { return nil }
    let paramCount = (data.count - 12) / 4
    var params: [UInt32] = []
    params.reserveCapacity(paramCount)
    for index in 0..<paramCount {
      guard let value: UInt32 = MTPEndianCodec.decodeUInt32(from: data, at: 12 + index * 4) else {
        break
      }
      params.append(value)
    }

    switch code {
    case 0x4002:  // ObjectAdded
      guard let handle = params.first else { return nil }
      return .objectAdded(handle)
    case 0x4003:  // ObjectRemoved
      guard let handle = params.first else { return nil }
      return .objectRemoved(handle)
    case 0x400C:  // StorageInfoChanged
      guard let storageIdRaw = params.first else { return nil }
      return .storageInfoChanged(MTPStorageID(raw: storageIdRaw))
    default:
      return nil
    }
  }
}
