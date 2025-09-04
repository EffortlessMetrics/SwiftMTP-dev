// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation

// MARK: - Thread-Safe Lock Implementation

/// Cross-platform lock for thread safety
final class _Lock: @unchecked Sendable {
    private let l = NSLock()
    func with<T>(_ body: () throws -> T) rethrows -> T {
        l.lock()
        defer { l.unlock() }
        return try body()
    }
}

// MARK: - Atomic Progress Tracker

/// Thread-safe progress counter for transfer operations
final class AtomicProgressTracker: @unchecked Sendable {
    private var _total: UInt64 = 0
    private let lock = _Lock()

    /// Add bytes to the total and return the new total
    @discardableResult
    func add(_ bytes: Int) -> UInt64 {
        lock.with {
            _total += UInt64(bytes)
            return _total
        }
    }

    /// Get the current total bytes
    var total: UInt64 {
        lock.with { _total }
    }
}

// MARK: - Sendable Wrappers

/// Sendable wrapper for ByteSink that serializes access
final class SendableSinkAdapter: @unchecked Sendable {
    private var sink: any ByteSink
    private let lock = _Lock()

    init(_ sink: any ByteSink) {
        self.sink = sink
    }

    /// Thread-safe write operation
    public func consume(_ buf: UnsafeRawBufferPointer) -> Int {
        lock.with {
            do {
                try sink.write(buf)
                return buf.count
            } catch {
                return 0 // Error occurred, return 0 bytes consumed
            }
        }
    }

    /// Thread-safe close operation
    public func close() throws {
        try lock.with { try sink.close() }
    }
}

/// Sendable wrapper for ByteSource that serializes access
final class SendableSourceAdapter: @unchecked Sendable {
    private var source: any ByteSource
    private let lock = _Lock()

    init(_ source: any ByteSource) {
        self.source = source
    }

    /// Thread-safe read operation
    public func produce(_ buf: UnsafeMutableRawBufferPointer) -> Int {
        lock.with {
            do {
                return try source.read(into: buf)
            } catch {
                return 0 // Error occurred, return 0 bytes produced
            }
        }
    }

    /// Thread-safe close operation
    public func close() throws {
        try lock.with { try source.close() }
    }

    /// File size access (thread-safe since it's read-only)
    public var fileSize: UInt64? {
        lock.with { source.fileSize }
    }
}
