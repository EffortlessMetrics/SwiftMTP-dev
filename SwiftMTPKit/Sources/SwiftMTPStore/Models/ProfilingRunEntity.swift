// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import SwiftData

@Model
public final class ProfilingRunEntity {
  public var timestamp: Date
  public var appVersion: String

  public var device: DeviceEntity?

  @Relationship(deleteRule: .cascade, inverse: \ProfilingMetricEntity.run)
  public var metrics: [ProfilingMetricEntity] = []

  public init(timestamp: Date = Date(), appVersion: String = "1.0.0") {
    self.timestamp = timestamp
    self.appVersion = appVersion
  }
}
