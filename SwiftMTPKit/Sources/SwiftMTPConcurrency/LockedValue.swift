// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation

/// A minimal lock-backed container for synchronizing access to mutable state.
public final class LockedValue<Value>: @unchecked Sendable {
  private var value: Value
  private let lock = NSLock()

  public init(_ value: Value) {
    self.value = value
  }

  @discardableResult
  public func withValue<T>(_ body: (inout Value) throws -> T) rethrows -> T {
    lock.lock()
    defer { lock.unlock() }
    return try body(&value)
  }

  public func read<T>(_ body: (Value) throws -> T) rethrows -> T {
    lock.lock()
    defer { lock.unlock() }
    return try body(value)
  }
}
