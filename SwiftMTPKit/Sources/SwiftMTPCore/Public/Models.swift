// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
public struct MTPDeviceID: Hashable, Sendable {
    public let raw: String
    public init(raw: String) { self.raw = raw }
}
public struct MTPStorageID: Hashable, Sendable {
    public let raw: UInt32
    public init(raw: UInt32) { self.raw = raw }
}
public typealias MTPObjectHandle = UInt32
public struct MTPDeviceInfo: Sendable {
  public let manufacturer, model, version: String
  public let serialNumber: String?
  public let operationsSupported: Set<UInt16>
  public let eventsSupported: Set<UInt16>
  public init(manufacturer: String, model: String, version: String, serialNumber: String?, operationsSupported: Set<UInt16>, eventsSupported: Set<UInt16>) {
    self.manufacturer = manufacturer
    self.model = model
    self.version = version
    self.serialNumber = serialNumber
    self.operationsSupported = operationsSupported
    self.eventsSupported = eventsSupported
  }
}
public struct MTPStorageInfo: Sendable {
  public let id: MTPStorageID, description: String
  public let capacityBytes, freeBytes: UInt64
  public let isReadOnly: Bool
  public init(id: MTPStorageID, description: String, capacityBytes: UInt64, freeBytes: UInt64, isReadOnly: Bool) {
    self.id = id
    self.description = description
    self.capacityBytes = capacityBytes
    self.freeBytes = freeBytes
    self.isReadOnly = isReadOnly
  }
}
public struct MTPObjectInfo: Sendable {
  public let handle: MTPObjectHandle
  public let storage: MTPStorageID
  public let parent: MTPObjectHandle?
  public let name: String
  public let sizeBytes: UInt64?
  public let modified: Date?
  public let formatCode: UInt16
  public let properties: [UInt16: Sendable]
  public init(handle: MTPObjectHandle, storage: MTPStorageID, parent: MTPObjectHandle?, name: String, sizeBytes: UInt64?, modified: Date?, formatCode: UInt16, properties: [UInt16: Sendable]) {
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
