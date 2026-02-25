// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import SwiftMTPCore

// MARK: - Virtual Storage Configuration

/// Configuration for a virtual MTP storage device used in testing.
public struct VirtualStorageConfig: Sendable {
  public let id: MTPStorageID
  public let description: String
  public let capacityBytes: UInt64
  public let freeBytes: UInt64
  public let isReadOnly: Bool

  public init(
    id: MTPStorageID,
    description: String,
    capacityBytes: UInt64 = 64 * 1024 * 1024 * 1024,
    freeBytes: UInt64 = 32 * 1024 * 1024 * 1024,
    isReadOnly: Bool = false
  ) {
    self.id = id
    self.description = description
    self.capacityBytes = capacityBytes
    self.freeBytes = freeBytes
    self.isReadOnly = isReadOnly
  }

  /// Convert to an `MTPStorageInfo` for protocol responses.
  public func toStorageInfo() -> MTPStorageInfo {
    MTPStorageInfo(
      id: id,
      description: description,
      capacityBytes: capacityBytes,
      freeBytes: freeBytes,
      isReadOnly: isReadOnly
    )
  }
}

// MARK: - Virtual Object Configuration

/// Configuration for a virtual MTP object (file or folder) used in testing.
public struct VirtualObjectConfig: Sendable {
  public let handle: MTPObjectHandle
  public let storage: MTPStorageID
  public let parent: MTPObjectHandle?
  public let name: String
  public let sizeBytes: UInt64?
  public let formatCode: UInt16  // 0x3001 = folder, 0x3000 = undefined file
  public let data: Data?

  public init(
    handle: MTPObjectHandle,
    storage: MTPStorageID,
    parent: MTPObjectHandle? = nil,
    name: String,
    sizeBytes: UInt64? = nil,
    formatCode: UInt16 = 0x3000,
    data: Data? = nil
  ) {
    self.handle = handle
    self.storage = storage
    self.parent = parent
    self.name = name
    self.sizeBytes = sizeBytes ?? (data.map { UInt64($0.count) })
    self.formatCode = formatCode
    self.data = data
  }

  /// Whether this object represents a folder (association).
  public var isFolder: Bool { formatCode == 0x3001 }

  /// Convert to an `MTPObjectInfo` for protocol responses.
  public func toObjectInfo() -> MTPObjectInfo {
    MTPObjectInfo(
      handle: handle,
      storage: storage,
      parent: parent,
      name: name,
      sizeBytes: sizeBytes,
      modified: nil,
      formatCode: formatCode,
      properties: [:]
    )
  }
}

// MARK: - Virtual Device Configuration

/// Builder-style configuration for virtual MTP test devices.
///
/// Use the fluent API to compose device configurations:
/// ```swift
/// let config = VirtualDeviceConfig.pixel7
///     .withStorage(VirtualStorageConfig(id: MTPStorageID(raw: 2), description: "SD Card"))
///     .withLatency(.getObjectInfos, duration: .milliseconds(50))
/// ```
public struct VirtualDeviceConfig: Sendable {
  public let deviceId: MTPDeviceID
  public let summary: MTPDeviceSummary
  public let info: MTPDeviceInfo
  public var storages: [VirtualStorageConfig]
  public var objects: [VirtualObjectConfig]
  public var latencyPerOp: [LinkOperationType: Duration]

  public init(
    deviceId: MTPDeviceID,
    summary: MTPDeviceSummary,
    info: MTPDeviceInfo,
    storages: [VirtualStorageConfig] = [],
    objects: [VirtualObjectConfig] = [],
    latencyPerOp: [LinkOperationType: Duration] = [:]
  ) {
    self.deviceId = deviceId
    self.summary = summary
    self.info = info
    self.storages = storages
    self.objects = objects
    self.latencyPerOp = latencyPerOp
  }

  // MARK: - Fluent Builder Methods

  /// Returns a copy with an additional storage device.
  public func withStorage(_ storage: VirtualStorageConfig) -> VirtualDeviceConfig {
    var copy = self
    copy.storages.append(storage)
    return copy
  }

  /// Returns a copy with an additional object in the tree.
  public func withObject(_ object: VirtualObjectConfig) -> VirtualDeviceConfig {
    var copy = self
    copy.objects.append(object)
    return copy
  }

  /// Returns a copy with simulated latency for a specific operation type.
  public func withLatency(_ operation: LinkOperationType, duration: Duration) -> VirtualDeviceConfig
  {
    var copy = self
    copy.latencyPerOp[operation] = duration
    return copy
  }

  // MARK: - Preset Configurations

  /// A Pixel 7 device with internal storage and sample files.
  public static var pixel7: VirtualDeviceConfig {
    let deviceId = MTPDeviceID(raw: "18d1:4ee1@1:2")
    let summary = MTPDeviceSummary(
      id: deviceId,
      manufacturer: "Google",
      model: "Pixel 7",
      vendorID: 0x18d1,
      productID: 0x4ee1,
      bus: 1,
      address: 2
    )
    let info = MTPDeviceInfo(
      manufacturer: "Google",
      model: "Pixel 7",
      version: "1.0",
      serialNumber: "VIRTUAL001",
      operationsSupported: Set(
        [
          0x1001, 0x1002, 0x1003, 0x1004, 0x1005,
          0x1006, 0x1007, 0x1008, 0x1009, 0x100B,
          0x100C, 0x100D, 0x100E, 0x101B, 0x95C1, 0x95C4,
        ]
        .map { UInt16($0) }),
      eventsSupported: Set([0x4002, 0x4003, 0x400C].map { UInt16($0) })
    )
    let internalStorage = VirtualStorageConfig(
      id: MTPStorageID(raw: 0x0001_0001),
      description: "Internal shared storage",
      capacityBytes: 128 * 1024 * 1024 * 1024,
      freeBytes: 64 * 1024 * 1024 * 1024
    )
    let dcimFolder = VirtualObjectConfig(
      handle: 1,
      storage: internalStorage.id,
      parent: nil,
      name: "DCIM",
      formatCode: 0x3001
    )
    let cameraFolder = VirtualObjectConfig(
      handle: 2,
      storage: internalStorage.id,
      parent: 1,
      name: "Camera",
      formatCode: 0x3001
    )
    let samplePhoto = VirtualObjectConfig(
      handle: 3,
      storage: internalStorage.id,
      parent: 2,
      name: "IMG_20250101_120000.jpg",
      sizeBytes: 4_500_000,
      formatCode: 0x3801,
      data: Data(repeating: 0xFF, count: 4_500_000)
    )
    return VirtualDeviceConfig(
      deviceId: deviceId,
      summary: summary,
      info: info,
      storages: [internalStorage],
      objects: [dcimFolder, cameraFolder, samplePhoto]
    )
  }

  /// An empty device with a single empty storage.
  public static var emptyDevice: VirtualDeviceConfig {
    let deviceId = MTPDeviceID(raw: "0000:0000@0:0")
    let summary = MTPDeviceSummary(
      id: deviceId,
      manufacturer: "Virtual",
      model: "Empty Device",
      vendorID: 0x0000,
      productID: 0x0000,
      bus: 0,
      address: 0
    )
    let info = MTPDeviceInfo(
      manufacturer: "Virtual",
      model: "Empty Device",
      version: "1.0",
      serialNumber: "EMPTY001",
      operationsSupported: Set(
        [
          0x1001, 0x1002, 0x1003, 0x1004, 0x1005,
          0x1007, 0x1008, 0x1009, 0x100B, 0x100C, 0x100D,
        ]
        .map { UInt16($0) }),
      eventsSupported: Set([0x4002, 0x4003].map { UInt16($0) })
    )
    let storage = VirtualStorageConfig(
      id: MTPStorageID(raw: 0x0001_0001),
      description: "Internal storage"
    )
    return VirtualDeviceConfig(
      deviceId: deviceId,
      summary: summary,
      info: info,
      storages: [storage],
      objects: []
    )
  }
}
