// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation

/// Dynamically adjusts MTP transfer chunk sizes based on observed throughput.
///
/// The tuner starts at a conservative 512 KB and ramps up through predefined
/// tiers as sustained throughput increases.  On errors or throughput drops it
/// backs off to a smaller tier.  The maximum is capped at 8 MB.
///
/// Thread-safe: all mutable state is isolated inside an actor.
public actor AdaptiveChunkTuner {

  // MARK: - Tier table

  /// Throughput threshold (bytes/s) that must be sustained before the tuner
  /// promotes to the associated chunk size.
  public struct Tier: Sendable, Equatable {
    public let thresholdBytesPerSec: Double
    public let chunkSize: Int

    public init(thresholdBytesPerSec: Double, chunkSize: Int) {
      self.thresholdBytesPerSec = thresholdBytesPerSec
      self.chunkSize = chunkSize
    }
  }

  /// Default tier ladder (ascending).
  public static let defaultTiers: [Tier] = [
    Tier(thresholdBytesPerSec: 0, chunkSize: 512 * 1024),             // 512 KB (baseline)
    Tier(thresholdBytesPerSec: 10_000_000, chunkSize: 1024 * 1024),   // 1 MB @ >10 MB/s
    Tier(thresholdBytesPerSec: 20_000_000, chunkSize: 2 * 1024 * 1024), // 2 MB @ >20 MB/s
    Tier(thresholdBytesPerSec: 40_000_000, chunkSize: 4 * 1024 * 1024), // 4 MB @ >40 MB/s
  ]

  /// Absolute maximum chunk size regardless of throughput.
  public static let maxChunkSize = 8 * 1024 * 1024  // 8 MB

  /// Absolute minimum chunk size.
  public static let minChunkSize = 512 * 1024  // 512 KB

  // MARK: - State

  private let tiers: [Tier]
  private var currentTierIndex: Int = 0
  private var _currentChunkSize: Int
  private var sampleCount: Int = 0
  private var cumulativeBytesPerSec: Double = 0
  private var maxObservedThroughput: Double = 0
  private var errorCount: Int = 0
  private var adjustmentLog: [TuningAdjustment] = []

  /// A recorded tuning adjustment for telemetry.
  public struct TuningAdjustment: Sendable {
    public let timestamp: Date
    public let previousChunkSize: Int
    public let newChunkSize: Int
    public let throughputBytesPerSec: Double
    public let reason: Reason

    public enum Reason: String, Sendable {
      case promoted = "promoted"
      case demoted = "demoted"
      case errorBackoff = "error_backoff"
      case initial = "initial"
    }
  }

  /// Snapshot of the tuner's current state (for telemetry / persistence).
  public struct Snapshot: Sendable, Codable {
    public let currentChunkSize: Int
    public let maxObservedThroughput: Double
    public let averageThroughput: Double
    public let errorCount: Int
    public let sampleCount: Int
    public let tierIndex: Int
  }

  // MARK: - Init

  /// Creates a tuner starting at an optional previously-learned chunk size.
  public init(
    initialChunkSize: Int? = nil,
    tiers: [Tier] = AdaptiveChunkTuner.defaultTiers
  ) {
    precondition(!tiers.isEmpty, "At least one tier is required")
    self.tiers = tiers.sorted { $0.thresholdBytesPerSec < $1.thresholdBytesPerSec }

    let start = min(
      max(initialChunkSize ?? Self.minChunkSize, Self.minChunkSize),
      Self.maxChunkSize
    )
    self._currentChunkSize = start

    // Find matching tier for the initial chunk size.
    self.currentTierIndex = 0
    for (i, tier) in self.tiers.enumerated() {
      if tier.chunkSize <= start { self.currentTierIndex = i }
    }

    adjustmentLog.append(TuningAdjustment(
      timestamp: Date(), previousChunkSize: start, newChunkSize: start,
      throughputBytesPerSec: 0, reason: .initial))
  }

  // MARK: - Public API

  /// The chunk size that should be used for the next transfer.
  public var currentChunkSize: Int { _currentChunkSize }

  /// Record a completed chunk transfer and let the tuner adjust.
  ///
  /// - Parameters:
  ///   - bytes: Number of bytes transferred in this chunk.
  ///   - duration: Wall-clock seconds the chunk transfer took.
  /// - Returns: The (possibly updated) chunk size to use next.
  @discardableResult
  public func recordChunk(bytes: Int, duration: TimeInterval) -> Int {
    guard duration > 0 else { return _currentChunkSize }

    let throughput = Double(bytes) / duration
    sampleCount += 1
    cumulativeBytesPerSec += throughput
    maxObservedThroughput = max(maxObservedThroughput, throughput)

    let avgThroughput = cumulativeBytesPerSec / Double(sampleCount)

    // Determine best tier for average throughput.
    var bestTier = 0
    for (i, tier) in tiers.enumerated() {
      if avgThroughput >= tier.thresholdBytesPerSec { bestTier = i }
    }

    let previous = _currentChunkSize

    if bestTier > currentTierIndex {
      // Promote
      currentTierIndex = bestTier
      _currentChunkSize = min(tiers[bestTier].chunkSize, Self.maxChunkSize)
      adjustmentLog.append(TuningAdjustment(
        timestamp: Date(), previousChunkSize: previous, newChunkSize: _currentChunkSize,
        throughputBytesPerSec: avgThroughput, reason: .promoted))
    } else if bestTier < currentTierIndex && sampleCount > 3 {
      // Demote only after a few samples to avoid reacting to transient dips.
      currentTierIndex = bestTier
      _currentChunkSize = max(tiers[bestTier].chunkSize, Self.minChunkSize)
      adjustmentLog.append(TuningAdjustment(
        timestamp: Date(), previousChunkSize: previous, newChunkSize: _currentChunkSize,
        throughputBytesPerSec: avgThroughput, reason: .demoted))
    }

    return _currentChunkSize
  }

  /// Record an error; backs off chunk size by one tier.
  @discardableResult
  public func recordError() -> Int {
    errorCount += 1
    let previous = _currentChunkSize
    if currentTierIndex > 0 {
      currentTierIndex -= 1
      _currentChunkSize = max(tiers[currentTierIndex].chunkSize, Self.minChunkSize)
      adjustmentLog.append(TuningAdjustment(
        timestamp: Date(), previousChunkSize: previous, newChunkSize: _currentChunkSize,
        throughputBytesPerSec: averageThroughput, reason: .errorBackoff))
    }
    return _currentChunkSize
  }

  /// Current average throughput in bytes/s (0 if no samples).
  public var averageThroughput: Double {
    sampleCount > 0 ? cumulativeBytesPerSec / Double(sampleCount) : 0
  }

  /// A snapshot of the tuner state suitable for persistence or display.
  public var snapshot: Snapshot {
    Snapshot(
      currentChunkSize: _currentChunkSize,
      maxObservedThroughput: maxObservedThroughput,
      averageThroughput: averageThroughput,
      errorCount: errorCount,
      sampleCount: sampleCount,
      tierIndex: currentTierIndex
    )
  }

  /// All recorded adjustments for telemetry output.
  public var adjustments: [TuningAdjustment] { adjustmentLog }

  /// Reset the tuner to its initial state.
  public func reset() {
    currentTierIndex = 0
    _currentChunkSize = tiers[0].chunkSize
    sampleCount = 0
    cumulativeBytesPerSec = 0
    maxObservedThroughput = 0
    errorCount = 0
    adjustmentLog.removeAll()
  }
}
