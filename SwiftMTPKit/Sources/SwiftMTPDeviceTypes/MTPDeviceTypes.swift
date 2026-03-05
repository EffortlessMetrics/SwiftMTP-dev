// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import MTPEndianCodec

/// Unique identifier for an MTP device, typically derived from USB bus/address or serial number.
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
  /// - Parameters:
  ///   - id: Unique device identifier
  ///   - manufacturer: Device manufacturer name
  ///   - model: Device model name
  ///   - vendorID: USB Vendor ID
  ///   - productID: USB Product ID
  ///   - bus: USB Bus number
  ///   - address: USB Device address
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
/// Events that can be emitted by an MTP device during operation.
///
/// Covers all standard MTP 1.1 event codes (0x4001–0x400E).
/// These events notify about changes to the device's content or state
/// that may require UI updates or re-indexing.
public enum MTPEvent: Sendable {
  /// 0x4001 – The initiator cancelled the current transaction
  case cancelTransaction(transactionId: UInt32)
  /// 0x4002 – A new object was added to the device
  case objectAdded(MTPObjectHandle)
  /// 0x4003 – An object was removed from the device
  case objectRemoved(MTPObjectHandle)
  /// 0x4004 – A new storage (SD card, etc.) was added
  case storageAdded(MTPStorageID)
  /// 0x4005 – A storage was removed
  case storageRemoved(MTPStorageID)
  /// 0x4006 – A device property value changed
  case devicePropChanged(propertyCode: UInt16)
  /// 0x4007 – Object metadata was updated (name, date, etc.)
  case objectInfoChanged(MTPObjectHandle)
  /// 0x4008 – Device info changed (e.g. battery level property updated)
  case deviceInfoChanged
  /// 0x4009 – Device requests the host to initiate a data transfer
  case requestObjectTransfer(MTPObjectHandle)
  /// 0x400A – Storage is full
  case storeFull(MTPStorageID)
  /// 0x400B – Device has been reset
  case deviceReset
  /// 0x400C – Storage information changed (capacity, free space, etc.)
  case storageInfoChanged(MTPStorageID)
  /// 0x400D – A capture operation completed
  case captureComplete(transactionId: UInt32)
  /// 0x400E – Device has unreported status
  case unreportedStatus
  /// An unknown event code was received; carries the raw 16-bit code and parameters
  case unknown(code: UInt16, params: [UInt32])

  /// Human-readable description suitable for CLI output.
  public var eventDescription: String {
    switch self {
    case .cancelTransaction(let txId):
      return "CancelTransaction (txId: \(txId))"
    case .objectAdded(let handle):
      return "ObjectAdded (handle: 0x\(String(handle, radix: 16)))"
    case .objectRemoved(let handle):
      return "ObjectRemoved (handle: 0x\(String(handle, radix: 16)))"
    case .storageAdded(let sid):
      return "StoreAdded (storageId: 0x\(String(sid.raw, radix: 16)))"
    case .storageRemoved(let sid):
      return "StoreRemoved (storageId: 0x\(String(sid.raw, radix: 16)))"
    case .devicePropChanged(let prop):
      return "DevicePropChanged (property: 0x\(String(prop, radix: 16)))"
    case .objectInfoChanged(let handle):
      return "ObjectInfoChanged (handle: 0x\(String(handle, radix: 16)))"
    case .deviceInfoChanged:
      return "DeviceInfoChanged"
    case .requestObjectTransfer(let handle):
      return "RequestObjectTransfer (handle: 0x\(String(handle, radix: 16)))"
    case .storeFull(let sid):
      return "StoreFull (storageId: 0x\(String(sid.raw, radix: 16)))"
    case .deviceReset:
      return "DeviceReset"
    case .storageInfoChanged(let sid):
      return "StorageInfoChanged (storageId: 0x\(String(sid.raw, radix: 16)))"
    case .captureComplete(let txId):
      return "CaptureComplete (txId: \(txId))"
    case .unreportedStatus:
      return "UnreportedStatus"
    case .unknown(let code, let params):
      return "Unknown (code: 0x\(String(code, radix: 16)), params: \(params))"
    }
  }

  /// The MTP event code for this event.
  public var eventCode: UInt16 {
    switch self {
    case .cancelTransaction: return 0x4001
    case .objectAdded: return 0x4002
    case .objectRemoved: return 0x4003
    case .storageAdded: return 0x4004
    case .storageRemoved: return 0x4005
    case .devicePropChanged: return 0x4006
    case .objectInfoChanged: return 0x4007
    case .deviceInfoChanged: return 0x4008
    case .requestObjectTransfer: return 0x4009
    case .storeFull: return 0x400A
    case .deviceReset: return 0x400B
    case .storageInfoChanged: return 0x400C
    case .captureComplete: return 0x400D
    case .unreportedStatus: return 0x400E
    case .unknown(let code, _): return code
    }
  }

  /// Parse MTP event from raw PTP/MTP event container data.
  ///
  /// Returns `.unknown(code:params:)` for any unrecognised (but structurally valid) event
  /// rather than returning `nil`, so callers can log unknown events.
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
    case 0x4001:  // CancelTransaction
      return .cancelTransaction(transactionId: params.first ?? 0)
    case 0x4002:  // ObjectAdded
      guard let handle = params.first else { return nil }
      return .objectAdded(handle)
    case 0x4003:  // ObjectRemoved
      guard let handle = params.first else { return nil }
      return .objectRemoved(handle)
    case 0x4004:  // StoreAdded
      guard let raw = params.first else { return nil }
      return .storageAdded(MTPStorageID(raw: raw))
    case 0x4005:  // StoreRemoved
      guard let raw = params.first else { return nil }
      return .storageRemoved(MTPStorageID(raw: raw))
    case 0x4006:  // DevicePropChanged
      return .devicePropChanged(propertyCode: params.first.map { UInt16($0 & 0xFFFF) } ?? 0)
    case 0x4007:  // ObjectInfoChanged
      guard let handle = params.first else { return nil }
      return .objectInfoChanged(handle)
    case 0x4008:  // DeviceInfoChanged
      return .deviceInfoChanged
    case 0x4009:  // RequestObjectTransfer
      guard let handle = params.first else { return nil }
      return .requestObjectTransfer(handle)
    case 0x400A:  // StoreFull
      guard let raw = params.first else { return nil }
      return .storeFull(MTPStorageID(raw: raw))
    case 0x400B:  // DeviceReset
      return .deviceReset
    case 0x400C:  // StorageInfoChanged
      guard let raw = params.first else { return nil }
      return .storageInfoChanged(MTPStorageID(raw: raw))
    case 0x400D:  // CaptureComplete
      return .captureComplete(transactionId: params.first ?? 0)
    case 0x400E:  // UnreportedStatus
      return .unreportedStatus
    default:
      return .unknown(code: code, params: params)
    }
  }
}

/// Identifier for a storage unit on an MTP device (e.g., internal storage or SD card).
public struct MTPStorageID: Hashable, Sendable, Codable {
  public let raw: UInt32
  public init(raw: UInt32) { self.raw = raw }
}

/// Detailed information about an MTP device and its capabilities, obtained after opening a session.
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

/// Metadata about a single storage unit on an MTP device, including capacity and access mode.
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

public typealias MTPObjectHandle = UInt32

/// Metadata for an object (file or directory) stored on an MTP device.
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
