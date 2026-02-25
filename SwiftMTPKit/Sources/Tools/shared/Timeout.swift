// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation

enum StepTimeout: Error { case timedOut(String) }

@discardableResult
func withTimeout<T>(
  seconds: TimeInterval,
  stepName: String,
  _ op: @escaping @Sendable () async throws -> T
) async throws -> T {
  try await withThrowingTaskGroup(of: T.self) { g in
    g.addTask { try await op() }
    g.addTask {
      try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
      throw StepTimeout.timedOut(stepName)
    }
    let v = try await g.next()!
    g.cancelAll()
    return v
  }
}
