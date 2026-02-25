// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import SwiftData

@Model
public final class TransferEntity {
  @Attribute(.unique) public var id: String
  public var deviceId: String
  public var kind: String  // "read" | "write"
  public var handle: UInt32?
  public var parentHandle: UInt32?
  public var name: String
  public var totalBytes: UInt64?
  public var committedBytes: UInt64
  public var supportsPartial: Bool
  public var localTempURL: String
  public var finalURL: String?
  public var state: String  // "active" | "paused" | "failed" | "done"
  public var updatedAt: Date
  public var lastError: String?
  /// Measured throughput in MB/s, recorded on successful completion.
  public var throughputMBps: Double?
  /// Remote object handle assigned by the device after SendObjectInfo succeeds.
  public var remoteHandle: UInt32?
  /// SHA-256 hex digest of the source data, when available.
  public var contentHash: String?

  // ETag/Precondition info
  public var etagSize: UInt64?
  public var etagMtime: Date?

  public init(
    id: String,
    deviceId: String,
    kind: String,
    handle: UInt32? = nil,
    parentHandle: UInt32? = nil,
    name: String,
    totalBytes: UInt64? = nil,
    committedBytes: UInt64 = 0,
    supportsPartial: Bool = false,
    localTempURL: String,
    finalURL: String? = nil,
    state: String = "active",
    updatedAt: Date = Date()
  ) {
    self.id = id
    self.deviceId = deviceId
    self.kind = kind
    self.handle = handle
    self.parentHandle = parentHandle
    self.name = name
    self.totalBytes = totalBytes
    self.committedBytes = committedBytes
    self.supportsPartial = supportsPartial
    self.localTempURL = localTempURL
    self.finalURL = finalURL
    self.state = state
    self.updatedAt = updatedAt
  }
}
