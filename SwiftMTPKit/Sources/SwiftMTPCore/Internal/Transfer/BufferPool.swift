// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation

/// A raw buffer that is safe to send across actor boundaries because its
/// ownership is explicitly managed by ``BufferPool``'s acquire/release protocol.
/// SAFETY: The pool guarantees exclusive access — at most one consumer holds a
/// given buffer at any point in time.
struct PooledBuffer: @unchecked Sendable {
  let ptr: UnsafeMutableRawBufferPointer

  /// A read-only view of the first `count` bytes.
  func readOnly(count: Int) -> UnsafeRawBufferPointer {
    UnsafeRawBufferPointer(UnsafeMutableRawBufferPointer(rebasing: ptr[..<count]))
  }

  /// A mutable view of the first `count` bytes.
  func mutable(count: Int) -> UnsafeMutableRawBufferPointer {
    UnsafeMutableRawBufferPointer(rebasing: ptr[..<count])
  }
}

/// A pool of reusable fixed-size buffers for transfer pipelining.
/// Thread-safe via actor isolation.
actor BufferPool {
  let bufferSize: Int
  let poolDepth: Int
  private var available: [PooledBuffer]
  private var waiters: [CheckedContinuation<PooledBuffer, Never>]
  /// All allocated buffers; stored nonisolated so deinit can deallocate them.
  /// Set once during init and never mutated, so nonisolated access is safe.
  nonisolated(unsafe) private let _allBuffers: [UnsafeMutableRawBufferPointer]

  init(bufferSize: Int = 256 * 1024, poolDepth: Int = 2) {
    let bufs = (0..<poolDepth)
      .map { _ in
        UnsafeMutableRawBufferPointer.allocate(byteCount: bufferSize, alignment: 16)
      }
    self.bufferSize = bufferSize
    self.poolDepth = poolDepth
    self._allBuffers = bufs
    self.available = bufs.map { PooledBuffer(ptr: $0) }
    self.waiters = []
  }

  /// Acquire a buffer (waits if all are in use).
  func acquire() async -> PooledBuffer {
    if let buf = available.popLast() {
      return buf
    }
    return await withCheckedContinuation { continuation in
      waiters.append(continuation)
    }
  }

  /// Return a buffer to the pool.
  func release(_ buf: PooledBuffer) {
    if let waiter = waiters.first {
      waiters.removeFirst()
      waiter.resume(returning: buf)
    } else {
      available.append(buf)
    }
  }

  deinit {
    for buf in _allBuffers {
      buf.deallocate()
    }
  }
}
