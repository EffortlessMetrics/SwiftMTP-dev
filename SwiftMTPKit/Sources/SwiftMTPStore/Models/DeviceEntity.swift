// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import SwiftData
import SwiftMTPCore

@Model
public final class DeviceEntity {
  @Attribute(.unique) public var id: String
  public var vendorId: Int?
  public var productId: Int?
  public var manufacturer: String?
  public var model: String?
  public var serialNumber: String?
  public var lastSeenAt: Date

  @Relationship(deleteRule: .cascade, inverse: \LearnedProfileEntity.device)
  public var profiles: [LearnedProfileEntity] = []

  @Relationship(deleteRule: .cascade, inverse: \ProfilingRunEntity.device)
  public var profilingRuns: [ProfilingRunEntity] = []

  @Relationship(deleteRule: .cascade, inverse: \SnapshotEntity.device)
  public var snapshots: [SnapshotEntity] = []

  public init(
    id: String, vendorId: Int? = nil, productId: Int? = nil, manufacturer: String? = nil,
    model: String? = nil, serialNumber: String? = nil, lastSeenAt: Date = Date()
  ) {
    self.id = id
    self.vendorId = vendorId
    self.productId = productId
    self.manufacturer = manufacturer
    self.model = model
    self.serialNumber = serialNumber
    self.lastSeenAt = lastSeenAt
  }
}
