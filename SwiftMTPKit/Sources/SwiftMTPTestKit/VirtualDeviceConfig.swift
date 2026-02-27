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

  /// A Samsung Galaxy Android phone in MTP mode (VID 0x04e8, PID 0x6860).
  /// GetObjectPropList is supported on this PID per libmtp.
  public static var samsungGalaxy: VirtualDeviceConfig {
    _androidPreset(
      rawId: "04e8:6860@1:3", vendor: "Samsung", model: "Galaxy Android",
      vendorID: 0x04e8, productID: 0x6860, serial: "VIRT-SAMSUNG-6860",
      includePropList: true)
  }

  /// A Samsung Galaxy in MTP+ADB mode (VID 0x04e8, PID 0x685c).
  /// GetObjectPropList is broken on this PID per libmtp.
  public static var samsungGalaxyMtpAdb: VirtualDeviceConfig {
    _androidPreset(
      rawId: "04e8:685c@1:4", vendor: "Samsung", model: "Galaxy Android (ADB)",
      vendorID: 0x04e8, productID: 0x685c, serial: "VIRT-SAMSUNG-685C",
      includePropList: false)
  }

  /// A Google Nexus/Pixel in MTP+ADB mode (VID 0x18d1, PID 0x4ee2).
  public static var googlePixelAdb: VirtualDeviceConfig {
    _androidPreset(
      rawId: "18d1:4ee2@1:5", vendor: "Google", model: "Nexus/Pixel (ADB)",
      vendorID: 0x18d1, productID: 0x4ee2, serial: "VIRT-PIXEL-4EE2",
      includePropList: false)
  }

  /// A Motorola Moto G/E/Z in standard MTP mode (VID 0x22b8, PID 0x2e82).
  /// GetObjectPropList is NOT broken on this PID per libmtp.
  public static var motorolaMotoG: VirtualDeviceConfig {
    _androidPreset(
      rawId: "22b8:2e82@1:6", vendor: "Motorola", model: "Moto G/E/Z",
      vendorID: 0x22b8, productID: 0x2e82, serial: "VIRT-MOTO-2E82",
      includePropList: true)
  }

  /// A Sony Xperia Z in MTP mode (VID 0x0fce, PID 0x0193). Standard MTP, no quirks.
  public static var sonyXperiaZ: VirtualDeviceConfig {
    _androidPreset(
      rawId: "0fce:0193@1:7", vendor: "Sony", model: "Xperia Z",
      vendorID: 0x0fce, productID: 0x0193, serial: "VIRT-XPERIA-0193",
      includePropList: true)
  }

  /// A Canon EOS R5 camera (VID 0x04a9, PID 0x32b4). PTP/MTP camera with GetObjectPropList.
  public static var canonEOSR5: VirtualDeviceConfig {
    _cameraPreset(
      rawId: "04a9:32b4@1:8", vendor: "Canon", model: "EOS R5",
      vendorID: 0x04a9, productID: 0x32b4, serial: "VIRT-CANON-R5")
  }

  /// A Nikon Z6/Z7 mirrorless camera (VID 0x04b0, PID 0x0441).
  public static var nikonZ6: VirtualDeviceConfig {
    _cameraPreset(
      rawId: "04b0:0441@1:9", vendor: "Nikon", model: "Z6/Z7",
      vendorID: 0x04b0, productID: 0x0441, serial: "VIRT-NIKON-Z6")
  }

  /// An OnePlus 9 (VID 0x2a70, PID 0x9011).
  public static var onePlus9: VirtualDeviceConfig {
    _androidPreset(
      rawId: "2a70:9011@1:10", vendor: "OnePlus", model: "OnePlus 9",
      vendorID: 0x2a70, productID: 0x9011, serial: "VIRT-ONEPLUS-9011",
      includePropList: true)
  }

  /// An LG Android phone in MTP mode (VID 0x1004, PID 0x633e).
  /// GetObjectPropList is broken on LG vendor-class MTP devices.
  public static var lgAndroid: VirtualDeviceConfig {
    _androidPreset(
      rawId: "1004:633e@1:11", vendor: "LG", model: "LG Android",
      vendorID: 0x1004, productID: 0x633e, serial: "VIRT-LG-633E",
      includePropList: false)
  }

  /// An LG Android phone (older) in MTP mode (VID 0x1004, PID 0x6300).
  public static var lgAndroidOlder: VirtualDeviceConfig {
    _androidPreset(
      rawId: "1004:6300@1:12", vendor: "LG", model: "LG Android (older)",
      vendorID: 0x1004, productID: 0x6300, serial: "VIRT-LG-6300",
      includePropList: false)
  }

  /// An HTC Android phone in MTP mode (VID 0x0bb4, PID 0x0f15).
  /// GetObjectPropList is broken on this HTC MTP device.
  public static var htcAndroid: VirtualDeviceConfig {
    _androidPreset(
      rawId: "0bb4:0f15@1:13", vendor: "HTC", model: "HTC Android",
      vendorID: 0x0bb4, productID: 0x0f15, serial: "VIRT-HTC-0F15",
      includePropList: false)
  }

  /// A Huawei Android phone in MTP mode (VID 0x12d1, PID 0x107e).
  /// GetObjectPropList is broken on this Huawei MTP device.
  public static var huaweiAndroid: VirtualDeviceConfig {
    _androidPreset(
      rawId: "12d1:107e@1:14", vendor: "Huawei", model: "Huawei Android",
      vendorID: 0x12d1, productID: 0x107e, serial: "VIRT-HUAWEI-107E",
      includePropList: false)
  }

  /// A Fujifilm X-series camera (VID 0x04cb, PID 0x0104). PTP class (0x06/0x01/0x01).
  public static var fujifilmX: VirtualDeviceConfig {
    _cameraPreset(
      rawId: "04cb:0104@1:15", vendor: "Fujifilm", model: "X-series",
      vendorID: 0x04cb, productID: 0x0104, serial: "VIRT-FUJI-0104")
  }

  /// A Nokia Android phone in MTP mode (VID 0x2e04, PID 0xc025).
  public static let nokiaAndroid: VirtualDeviceConfig = {
    _androidPreset(
      rawId: "2e04:c025@1:16", vendor: "Nokia", model: "Nokia 6",
      vendorID: 0x2e04, productID: 0xc025, serial: "VIRT-NOKIA-C025",
      includePropList: false)
  }()

  /// A ZTE Android phone in MTP mode (VID 0x19d2, PID 0x0306).
  public static let zteAndroid: VirtualDeviceConfig = {
    _androidPreset(
      rawId: "19d2:0306@1:17", vendor: "ZTE", model: "Blade 3",
      vendorID: 0x19d2, productID: 0x0306, serial: "VIRT-ZTE-0306",
      includePropList: false)
  }()

  /// An Amazon Kindle Fire in MTP mode (VID 0x1949, PID 0x0007).
  public static let amazonKindleFire: VirtualDeviceConfig = {
    _androidPreset(
      rawId: "1949:0007@1:18", vendor: "Amazon", model: "Kindle Fire",
      vendorID: 0x1949, productID: 0x0007, serial: "VIRT-AMZN-0007",
      includePropList: false)
  }()

  /// A Lenovo Android phone/tablet in MTP mode (VID 0x17ef, PID 0x740a).
  public static let lenovoAndroid: VirtualDeviceConfig = {
    _androidPreset(
      rawId: "17ef:740a@1:19", vendor: "Lenovo", model: "K1",
      vendorID: 0x17ef, productID: 0x740a, serial: "VIRT-LENOVO-740A",
      includePropList: false)
  }()

  /// A Nikon Z-series mirrorless camera (VID 0x04b0, PID 0x0443). PTP class, proplist supported.
  public static let nikonMirrorless: VirtualDeviceConfig = {
    _cameraPreset(
      rawId: "04b0:0443@1:20", vendor: "Nikon", model: "Z6",
      vendorID: 0x04b0, productID: 0x0443, serial: "VIRT-NIKON-Z6-0443")
  }()

  /// A Canon EOS R mirrorless camera (VID 0x04a9, PID 0x32da). PTP class, proplist supported.
  public static let canonEOSR: VirtualDeviceConfig = {
    _cameraPreset(
      rawId: "04a9:32da@1:21", vendor: "Canon", model: "EOS R",
      vendorID: 0x04a9, productID: 0x32da, serial: "VIRT-CANON-EOSR-32DA")
  }()

  /// A Sony Alpha a7 III camera (VID 0x054c, PID 0x0c03). PTP class, proplist supported.
  public static let sonyAlpha: VirtualDeviceConfig = {
    _cameraPreset(
      rawId: "054c:0c03@1:22", vendor: "Sony", model: "Alpha a7 III",
      vendorID: 0x054c, productID: 0x0c03, serial: "VIRT-SONY-ALPHA-0C03")
  }()

  /// A Leica SL (Typ 601) camera (VID 0x1a98, PID 0x2041). PTP class, proplist supported.
  public static let leica: VirtualDeviceConfig = {
    _cameraPreset(
      rawId: "1a98:2041@1:23", vendor: "Leica", model: "SL (Typ 601)",
      vendorID: 0x1a98, productID: 0x2041, serial: "VIRT-LEICA-SL-2041")
  }()

  /// A GoPro HERO10 Black action camera (VID 0x2672, PID 0x0056). PTP class, proplist supported.
  public static let goProHero: VirtualDeviceConfig = {
    _cameraPreset(
      rawId: "2672:0056@1:24", vendor: "GoPro", model: "HERO10 Black",
      vendorID: 0x2672, productID: 0x0056, serial: "VIRT-GOPRO-HERO10-0056")
  }()

  // MARK: - Private helpers

  private static func _androidPreset(
    rawId: String, vendor: String, model: String,
    vendorID: UInt16, productID: UInt16, serial: String,
    includePropList: Bool
  ) -> VirtualDeviceConfig {
    let deviceId = MTPDeviceID(raw: rawId)
    let summary = MTPDeviceSummary(
      id: deviceId, manufacturer: vendor, model: model,
      vendorID: vendorID, productID: productID, bus: 1, address: 0)
    var ops: [Int] = [
      0x1001, 0x1002, 0x1003, 0x1004, 0x1005,
      0x1006, 0x1007, 0x1008, 0x1009, 0x100B,
      0x100C, 0x100D, 0x101B, 0x95C1,
    ]
    if includePropList { ops.append(0x9805) }
    let info = MTPDeviceInfo(
      manufacturer: vendor, model: model, version: "1.0", serialNumber: serial,
      operationsSupported: Set(ops.map { UInt16($0) }),
      eventsSupported: Set([0x4002, 0x4003, 0x400C].map { UInt16($0) }))
    let storage = VirtualStorageConfig(
      id: MTPStorageID(raw: 0x0001_0001), description: "Internal storage",
      capacityBytes: 64 * 1024 * 1024 * 1024, freeBytes: 32 * 1024 * 1024 * 1024)
    let dcim = VirtualObjectConfig(
      handle: 1, storage: storage.id, parent: nil, name: "DCIM", formatCode: 0x3001)
    let photo = VirtualObjectConfig(
      handle: 2, storage: storage.id, parent: 1, name: "photo.jpg",
      sizeBytes: 3_000_000, formatCode: 0x3801, data: Data(count: 256))
    return VirtualDeviceConfig(
      deviceId: deviceId, summary: summary, info: info,
      storages: [storage], objects: [dcim, photo])
  }

  private static func _cameraPreset(
    rawId: String, vendor: String, model: String,
    vendorID: UInt16, productID: UInt16, serial: String
  ) -> VirtualDeviceConfig {
    let deviceId = MTPDeviceID(raw: rawId)
    let summary = MTPDeviceSummary(
      id: deviceId, manufacturer: vendor, model: model,
      vendorID: vendorID, productID: productID, bus: 1, address: 0)
    let info = MTPDeviceInfo(
      manufacturer: vendor, model: model, version: "1.0", serialNumber: serial,
      operationsSupported: Set(
        [
          0x1001, 0x1002, 0x1003, 0x1004, 0x1005,
          0x1007, 0x1008, 0x1009, 0x100B, 0x100C, 0x100D,
          0x100E, 0x101B,
        ]
        .map { UInt16($0) }),
      eventsSupported: Set([0x4002, 0x4003].map { UInt16($0) }))
    let storage = VirtualStorageConfig(
      id: MTPStorageID(raw: 0x0001_0001), description: "Memory Card",
      capacityBytes: 128 * 1024 * 1024 * 1024, freeBytes: 100 * 1024 * 1024 * 1024)
    let dcim = VirtualObjectConfig(
      handle: 1, storage: storage.id, parent: nil, name: "DCIM", formatCode: 0x3001)
    let raw = VirtualObjectConfig(
      handle: 2, storage: storage.id, parent: 1, name: "IMG_0001.CR3",
      sizeBytes: 25_000_000, formatCode: 0x3000, data: Data(count: 256))
    return VirtualDeviceConfig(
      deviceId: deviceId, summary: summary, info: info,
      storages: [storage], objects: [dcim, raw])
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
