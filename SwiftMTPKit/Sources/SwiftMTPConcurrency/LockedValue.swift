// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation

/// A minimal thread-safe container for mutable state shared across sendable contexts.
public final class LockedValue<Value>: @unchecked Sendable {
  private var value: Value
  private let lock = NSLock()

  public init(_ value: Value) {
    self.value = value
  }

  @discardableResult
  public func withLock<Result>(_ body: (inout Value) throws -> Result) rethrows -> Result {
    lock.lock()
    defer { lock.unlock() }
    return try body(&value)
  }

  public func read<Result>(_ body: (Value) throws -> Result) rethrows -> Result {
    lock.lock()
    defer { lock.unlock() }
    return try body(value)
  }
}
