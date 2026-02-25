// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import SwiftData

@Model
public final class MTPStorageEntity {
  @Attribute(.unique) public var compoundId: String  // "deviceId:storageId"
  public var deviceId: String
  public var storageId: Int
  public var storageDescription: String
  public var capacityBytes: Int64
  public var freeBytes: Int64
  public var isReadOnly: Bool
  public var lastIndexedAt: Date

  public var device: DeviceEntity?

  @Relationship(deleteRule: .cascade, inverse: \MTPObjectEntity.storage)
  public var objects: [MTPObjectEntity] = []

  public init(
    deviceId: String, storageId: Int, storageDescription: String, capacityBytes: Int64,
    freeBytes: Int64, isReadOnly: Bool, lastIndexedAt: Date = Date()
  ) {
    self.compoundId = "\(deviceId):\(storageId)"
    self.deviceId = deviceId
    self.storageId = storageId
    self.storageDescription = storageDescription
    self.capacityBytes = capacityBytes
    self.freeBytes = freeBytes
    self.isReadOnly = isReadOnly
    self.lastIndexedAt = lastIndexedAt
  }
}
