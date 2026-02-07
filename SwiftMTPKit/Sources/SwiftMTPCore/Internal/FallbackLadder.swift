// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation

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

/// Generic fallback ladder: runs ranked strategies in order,
/// records each attempt, returns the first success.
public enum FallbackLadder {

  /// Execute a list of rungs in order. Returns the first success.
  /// Throws the last error if all rungs fail.
  public static func execute<T: Sendable>(
    _ rungs: [FallbackRung<T>]
  ) async throws -> FallbackResult<T> {
    var attempts: [FallbackAttempt] = []
    var lastError: Error?

    for rung in rungs {
      let start = DispatchTime.now()
      do {
        let value = try await rung.execute()
        let elapsed = Int((DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000)
        attempts.append(FallbackAttempt(name: rung.name, succeeded: true, error: nil, durationMs: elapsed))
        return FallbackResult(value: value, winningRung: rung.name, attempts: attempts)
      } catch {
        let elapsed = Int((DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000)
        attempts.append(FallbackAttempt(name: rung.name, succeeded: false, error: "\(error)", durationMs: elapsed))
        lastError = error
      }
    }

    throw lastError ?? MTPError.notSupported("all fallback rungs failed")
  }
}
