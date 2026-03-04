// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import OSLog

// MARK: - Recovery Event

/// Describes a single recovery attempt for observability.
public struct RecoveryEvent: Sendable, Codable {
  public let strategy: String
  public let attempt: Int
  public let maxAttempts: Int
  public let succeeded: Bool
  public let errorDescription: String?
  public let timeoutMs: Int?
  public let timestamp: Date

  public init(
    strategy: String, attempt: Int, maxAttempts: Int, succeeded: Bool,
    errorDescription: String? = nil, timeoutMs: Int? = nil, timestamp: Date = Date()
  ) {
    self.strategy = strategy
    self.attempt = attempt
    self.maxAttempts = maxAttempts
    self.succeeded = succeeded
    self.errorDescription = errorDescription
    self.timeoutMs = timeoutMs
    self.timestamp = timestamp
  }
}

// MARK: - Recovery Log

/// Thread-safe actor that tracks error recovery attempts and success/failure rates.
public actor RecoveryLog {
  public static let shared = RecoveryLog()

  private var events: [RecoveryEvent] = []
  private let maxEvents = 500
  private var successCount = 0
  private var failureCount = 0

  public init() {}

  /// Record a recovery attempt.
  public func record(_ event: RecoveryEvent) {
    events.append(event)
    if event.succeeded {
      successCount += 1
    } else {
      failureCount += 1
    }
    if events.count > maxEvents {
      events.removeFirst(events.count - maxEvents)
    }

    // Log via OSLog
    let logger = MTPLog.recovery
    if event.succeeded {
      logger.info(
        "Recovery succeeded: strategy=\(event.strategy, privacy: .public) attempt=\(event.attempt)/\(event.maxAttempts)"
      )
    } else {
      logger.warning(
        "Recovery failed: strategy=\(event.strategy, privacy: .public) attempt=\(event.attempt)/\(event.maxAttempts) error=\(event.errorDescription ?? "unknown", privacy: .public)"
      )
    }
  }

  /// Returns (successes, failures) counts.
  public func rates() -> (successes: Int, failures: Int) {
    (successCount, failureCount)
  }

  /// Returns the most recent `limit` events (oldest first).
  public func recent(limit: Int) -> [RecoveryEvent] {
    let start = max(0, events.count - limit)
    return Array(events[start...])
  }

  public func clear() {
    events.removeAll()
    successCount = 0
    failureCount = 0
  }
}
