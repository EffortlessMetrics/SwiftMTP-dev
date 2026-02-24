// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation

/// Possible outcomes when attempting to fetch storage IDs from an MTP device.
public enum StorageIDOutcome: Sendable {
  /// Successfully retrieved one or more storage IDs.
  case success([MTPStorageID])

  /// Device responded but reported zero storages (Samsung storage readiness issue).
  case zeroStorages

  /// Device responded but the response was not a valid storage ID response.
  case responseOnly

  /// Request timed out before receiving a response.
  case timeout

  /// Permanent error with specific PTP response code.
  case permanentError(UInt16)
}

/// Configuration for storage ID retry behavior.
public struct StorageIDRetryConfig: Sendable {
  /// Maximum number of retry attempts before escalating to reset.
  public let maxRetries: Int

  /// Backoff delays in milliseconds for each retry attempt.
  public let backoffMs: [UInt32]

  public init(maxRetries: Int = 5, backoffMs: [UInt32] = [250, 500, 1000, 2000, 3000]) {
    self.maxRetries = maxRetries
    self.backoffMs = backoffMs
  }
}

/// A single rung in a fallback ladder — a named strategy with an async closure.
public struct FallbackRung<T: Sendable>: Sendable {
  public let name: String
  public let execute: @Sendable () async throws -> T

  public init(name: String, execute: @escaping @Sendable () async throws -> T) {
    self.name = name
    self.execute = execute
  }
}

/// Records every attempt made during a fallback ladder execution.
public struct FallbackAttempt: Sendable {
  public let name: String
  public let succeeded: Bool
  public let error: String?
  public let durationMs: Int
}

/// The result of executing a fallback ladder.
public struct FallbackResult<T: Sendable>: Sendable {
  /// The value from the first rung that succeeded.
  public let value: T
  /// Which rung produced the result.
  public let winningRung: String
  /// All attempts (including failures).
  public let attempts: [FallbackAttempt]
}

/// Error thrown when all rungs of a fallback ladder have failed.
/// Carries the full attempt history for first-line diagnosis.
public struct FallbackAllFailedError: Error, Sendable, CustomStringConvertible {
  public let attempts: [FallbackAttempt]

  public var description: String {
    let summary =
      attempts.map { a in
        "  [\(a.name)] \(a.succeeded ? "✓" : "✗") \(a.durationMs)ms\(a.error.map { " — \($0)" } ?? "")"
      }
      .joined(separator: "\n")
    return "All fallback rungs failed:\n\(summary)"
  }

  public var localizedDescription: String { description }
}

/// Fallback ladder for storage ID retrieval with retry logic for storage readiness.
public enum FallbackLadder {

  /// Execute a list of rungs in order. Returns the first success.
  /// Throws `FallbackAllFailedError` with full attempt history if all rungs fail.
  public static func execute<T: Sendable>(
    _ rungs: [FallbackRung<T>]
  ) async throws -> FallbackResult<T> {
    var attempts: [FallbackAttempt] = []

    for rung in rungs {
      let start = DispatchTime.now()
      do {
        let value = try await rung.execute()
        let elapsed = Int(
          (DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000)
        attempts.append(
          FallbackAttempt(name: rung.name, succeeded: true, error: nil, durationMs: elapsed))
        return FallbackResult(value: value, winningRung: rung.name, attempts: attempts)
      } catch {
        let elapsed = Int(
          (DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000)
        attempts.append(
          FallbackAttempt(name: rung.name, succeeded: false, error: "\(error)", durationMs: elapsed)
        )
      }
    }

    throw FallbackAllFailedError(attempts: attempts)
  }

  // MARK: - Storage ID Fetching with Retry

  /// Fetches storage IDs with retry logic, treating zeroStorages as a retryable condition.
  /// This addresses Samsung devices that return empty storage lists until the MTP stack is ready.
  public static func fetchStorageIDsWithRetry(
    link: MTPLink,
    config: StorageIDRetryConfig = StorageIDRetryConfig()
  ) async throws -> [MTPStorageID] {
    var attempt = 0

    while true {
      let outcome = await fetchStorageIDsOnce(link: link)

      switch outcome {
      case .success(let ids) where !ids.isEmpty:
        return ids

      case .success(let ids) where ids.isEmpty:
        // This shouldn't happen since fetchStorageIDsOnce returns .zeroStorages for empty
        // But handle it anyway for exhaustiveness
        attempt += 1
        if attempt > config.maxRetries {
          return try await resetAndRetry(link: link, config: config)
        }
        let delay = config.backoffMs[min(attempt - 1, config.backoffMs.count - 1)]
        try await Task.sleep(nanoseconds: UInt64(delay) * 1_000_000)

      case .zeroStorages:
        // NEW: treat as retryable with backoff - Samsung storage readiness issue
        attempt += 1
        if attempt > config.maxRetries {
          // Escalate: session reset, then USB reset
          return try await resetAndRetry(link: link, config: config)
        }
        let delay = config.backoffMs[min(attempt - 1, config.backoffMs.count - 1)]
        try await Task.sleep(nanoseconds: UInt64(delay) * 1_000_000)

      case .responseOnly, .timeout:
        // existing retry logic
        attempt += 1
        if attempt > config.maxRetries {
          return try await resetAndRetry(link: link, config: config)
        }
        let delay = config.backoffMs[min(attempt - 1, config.backoffMs.count - 1)]
        try await Task.sleep(nanoseconds: UInt64(delay) * 1_000_000)

      case .permanentError(let code):
        throw MTPError.protocolError(code: code, message: "Storage enumeration failed")

      @unknown default:
        // Handle any future cases gracefully
        attempt += 1
        if attempt > config.maxRetries {
          return try await resetAndRetry(link: link, config: config)
        }
        let delay = config.backoffMs[min(attempt - 1, config.backoffMs.count - 1)]
        try await Task.sleep(nanoseconds: UInt64(delay) * 1_000_000)
      }
    }
  }

  /// Performs a single storage ID fetch operation.
  private static func fetchStorageIDsOnce(link: MTPLink) async -> StorageIDOutcome {
    do {
      let ids = try await link.getStorageIDs()
      if ids.isEmpty {
        return .zeroStorages
      }
      return .success(ids)
    } catch let error as MTPError {
      if case .protocolError(let code, _) = error {
        return .permanentError(code)
      }
      return .responseOnly
    } catch {
      return .responseOnly
    }
  }

  /// Resets the session and device, then retries storage ID fetch.
  private static func resetAndRetry(
    link: MTPLink,
    config: StorageIDRetryConfig
  ) async throws -> [MTPStorageID] {
    // Close existing session if any
    try? await link.closeSession()

    // Attempt device reset
    try? await link.resetDevice()

    // Reopen session
    try await link.openSession(id: 1)

    // Final attempt with longer backoff
    return try await link.getStorageIDs()
  }
}
