// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import SwiftData

@Model
public final class ProfilingMetricEntity {
  public var operation: String
  public var count: Int
  public var minMs: Double
  public var maxMs: Double
  public var avgMs: Double
  public var p95Ms: Double
  public var throughputMBps: Double?

  public var run: ProfilingRunEntity?

  public init(
    operation: String, count: Int, minMs: Double, maxMs: Double, avgMs: Double, p95Ms: Double,
    throughputMBps: Double? = nil
  ) {
    self.operation = operation
    self.count = count
    self.minMs = minMs
    self.maxMs = maxMs
    self.avgMs = avgMs
    self.p95Ms = p95Ms
    self.throughputMBps = throughputMBps
  }
}
