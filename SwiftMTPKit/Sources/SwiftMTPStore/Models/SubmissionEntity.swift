// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import SwiftData

@Model
public final class SubmissionEntity {
  @Attribute(.unique) public var id: String
  public var deviceId: String
  public var createdAt: Date
  public var path: String
  public var status: String

  public init(
    id: String, deviceId: String, createdAt: Date = Date(), path: String, status: String = "pending"
  ) {
    self.id = id
    self.deviceId = deviceId
    self.createdAt = createdAt
    self.path = path
    self.status = status
  }
}
