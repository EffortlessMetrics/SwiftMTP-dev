// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation

/// Cross-thread lock primitive with scoped execution.
public final class Lock: @unchecked Sendable {
  private let lock = NSLock()

  public init() {}

  @discardableResult
  public func withLock<T>(_ body: () throws -> T) rethrows -> T {
    lock.lock()
    defer { lock.unlock() }
    return try body()
  }
}

/// Thread-safe mutable value wrapper.
public final class LockedValue<Value>: @unchecked Sendable {
  private var value: Value
  private let lock = Lock()

  public init(_ value: Value) {
    self.value = value
  }

  @discardableResult
  public func withValue<T>(_ body: (inout Value) throws -> T) rethrows -> T {
    try lock.withLock {
      try body(&value)
    }
  }

  public func read() -> Value {
    lock.withLock { value }
  }
}

/// Atomically incrementing Int counter.
public final class AtomicIntCounter: @unchecked Sendable {
  private let value: LockedValue<Int>

  public init(_ initialValue: Int = 0) {
    self.value = LockedValue(initialValue)
  }

  @discardableResult
  public func getAndAdd(_ amount: Int) -> Int {
    value.withValue {
      let previous = $0
      $0 += amount
      return previous
    }
  }

  public func get() -> Int {
    value.read()
  }
}

/// Atomically incrementing UInt64 counter.
public final class AtomicUInt64Counter: @unchecked Sendable {
  private let value: LockedValue<UInt64>

  public init(_ initialValue: UInt64 = 0) {
    self.value = LockedValue(initialValue)
  }

  @discardableResult
  public func add(_ amount: Int) -> UInt64 {
    value.withValue {
      $0 += UInt64(amount)
      return $0
    }
  }

  public func get() -> UInt64 {
    value.read()
  }
}
