// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation

/// Exponentially Weighted Moving Average for throughput measurement
/// Tracks bytes per second with configurable smoothing
public struct ThroughputEWMA: Sendable {
  private var rate: Double = 0  // bytes/sec
  private let alpha = 0.3
  private var sampleCount = 0

  public init() {}

  /// Update the throughput estimate with a new sample
  /// - Parameters:
  ///   - bytes: Number of bytes transferred
  ///   - dt: Time interval for the transfer
  /// - Returns: Current bytes per second rate (after update)
  @discardableResult
  public mutating func update(bytes: Int, dt: TimeInterval) -> Double {
    let inst = dt > 0 ? Double(bytes) / dt : 0
    if sampleCount == 0 {
      rate = inst
    } else {
      rate = alpha * inst + (1 - alpha) * rate
    }
    sampleCount += 1
    return rate
  }

  /// Current throughput in bytes per second
  public var bytesPerSecond: Double { rate }

  /// Current throughput in megabytes per second
  public var megabytesPerSecond: Double { rate / (1024 * 1024) }

  /// Reset the measurement (useful for new transfer sessions)
  public mutating func reset() {
    rate = 0
    sampleCount = 0
  }

  /// Number of samples used in the current estimate
  public var count: Int { sampleCount }
}

/// Ring buffer for storing recent throughput samples
/// Useful for calculating percentiles and detecting trends
public struct ThroughputRingBuffer: Sendable {
  private var samples: [Double] = []
  private let maxSamples: Int
  private var writeIndex = 0

  public init(maxSamples: Int = 100) {
    self.maxSamples = maxSamples
    samples.reserveCapacity(maxSamples)
  }

  public mutating func addSample(_ sample: Double) {
    if samples.count < maxSamples {
      samples.append(sample)
    } else {
      samples[writeIndex] = sample
      writeIndex = (writeIndex + 1) % maxSamples
    }
  }

  public var allSamples: [Double] { samples }

  public var count: Int { samples.count }

  public var p50: Double? {
    guard !samples.isEmpty else { return nil }
    let sorted = samples.sorted()
    return sorted[sorted.count / 2]
  }

  public var p95: Double? {
    guard !samples.isEmpty else { return nil }
    let sorted = samples.sorted()
    let index = Int(Double(sorted.count) * 0.95)
    return sorted[min(index, sorted.count - 1)]
  }

  public var average: Double? {
    guard !samples.isEmpty else { return nil }
    return samples.reduce(0, +) / Double(samples.count)
  }

  public mutating func reset() {
    samples.removeAll()
    writeIndex = 0
  }
}
