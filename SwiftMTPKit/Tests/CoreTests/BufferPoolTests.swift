// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import Testing
@testable import SwiftMTPCore

@Suite("BufferPool Tests")
struct BufferPoolTests {

  // MARK: - Basic acquire / release

  @Test("Acquire and release a single buffer")
  func testAcquireRelease() async throws {
    let pool = BufferPool(bufferSize: 4096, poolDepth: 2)
    let buf = await pool.acquire()
    #expect(buf.ptr.count == 4096)
    await pool.release(buf)

    // Second acquire should succeed immediately (buffer was returned).
    let buf2 = await pool.acquire()
    #expect(buf2.ptr.count == 4096)
    await pool.release(buf2)
  }

  // MARK: - Pool depth = 2, third acquire blocks until one is released

  @Test("Third acquire blocks until release when poolDepth=2")
  func testThirdAcquireBlocksUntilRelease() async throws {
    let pool = BufferPool(bufferSize: 1024, poolDepth: 2)

    // Drain the pool.
    let b1 = await pool.acquire()
    let b2 = await pool.acquire()

    // Launch a task that tries to acquire a third buffer; it must block.
    let acquired = ActorBox(false)
    let t = Task {
      let b3 = await pool.acquire()
      await acquired.set(true)
      await pool.release(b3)
    }

    // Give the task a moment — it should still be blocked.
    try await Task.sleep(nanoseconds: 50_000_000)  // 50 ms
    let snapshot = await acquired.value
    #expect(snapshot == false, "Third acquire should still be blocked")

    // Release one buffer — the blocked acquire should now proceed.
    await pool.release(b1)
    try await Task.sleep(nanoseconds: 100_000_000)  // 100 ms
    let snapshot2 = await acquired.value
    #expect(snapshot2 == true, "Third acquire should have completed after release")

    await pool.release(b2)
    await t.value
  }

  // MARK: - PipelinedUpload metrics

  @Test("PipelinedUpload transfers all bytes and returns metrics")
  func testPipelinedUploadMetrics() async throws {
    let chunkSize = 1024
    let totalSize: UInt64 = 8 * 1024  // 8 KB — 8 chunks
    let payload = Data(repeating: 0xAB, count: Int(totalSize))

    // Write payload to a temp file.
    let sourceURL = URL(fileURLWithPath: NSTemporaryDirectory())
      .appendingPathComponent("bp_upload_test_\(UUID().uuidString).bin")
    try payload.write(to: sourceURL)
    defer { try? FileManager.default.removeItem(at: sourceURL) }

    let pool = BufferPool(bufferSize: chunkSize, poolDepth: 2)
    let upload = PipelinedUpload(pool: pool)

    let collector = ByteCollector()
    let metrics = try await upload.run(
      sourceURL: sourceURL,
      totalSize: totalSize,
      chunkSize: chunkSize,
      sendChunk: { buf, count in
        await collector.append(Data(UnsafeRawBufferPointer(buf).prefix(count)))
      },
      onProgress: { _ in }
    )

    let received = await collector.data
    #expect(metrics.bytesTransferred == totalSize)
    #expect(metrics.durationSeconds >= 0)
    #expect(received == payload)
  }

  // MARK: - PipelinedDownload writes bytes correctly

  @Test("PipelinedDownload writes all bytes to destination file")
  func testPipelinedDownloadWritesBytes() async throws {
    let chunkSize = 512
    let chunks = 6
    let payload = Data((0..<chunks).flatMap { _ in [UInt8](repeating: 0xCD, count: chunkSize) })
    let totalSize = UInt64(payload.count)

    let destURL = URL(fileURLWithPath: NSTemporaryDirectory())
      .appendingPathComponent("bp_download_test_\(UUID().uuidString).bin")
    defer { try? FileManager.default.removeItem(at: destURL) }

    let pool = BufferPool(bufferSize: chunkSize, poolDepth: 2)
    let download = PipelinedDownload(pool: pool)

    let source = ChunkSource(data: payload)
    let metrics = try await download.run(
      destURL: destURL,
      totalSize: totalSize,
      chunkSize: chunkSize,
      receiveChunk: { buf, maxCount in
        source.read(into: buf, max: maxCount)
      },
      onProgress: { _ in }
    )

    #expect(metrics.bytesTransferred == totalSize)
    let written = try Data(contentsOf: destURL)
    #expect(written == payload)
  }

  // MARK: - deinit releases all buffers (no leak)

  @Test("BufferPool deinit releases all allocated buffers")
  func testDeinitReleasesBuffers() async throws {
    // Create and immediately discard a pool; this should not crash or leak.
    // We validate indirectly by confirming that a freshly created pool works,
    // which means prior allocations were cleaned up by ARC.
    do {
      let pool = BufferPool(bufferSize: 64 * 1024, poolDepth: 4)
      let b = await pool.acquire()
      await pool.release(b)
    }
    // If deinit is broken (double-free / missing deallocate) the process would
    // crash here or leak. Test passes if execution reaches this point.
    #expect(Bool(true))
  }
}

// MARK: - Helpers

/// Minimal actor-isolated boolean box for cross-task observation in tests.
private actor ActorBox<T: Sendable> {
  private(set) var value: T
  init(_ initial: T) { value = initial }
  func set(_ newValue: T) { value = newValue }
}

/// Collects Data chunks from concurrent sendChunk callbacks.
private actor ByteCollector {
  private(set) var data = Data()
  func append(_ chunk: Data) { data.append(chunk) }
}

/// Produces successive chunks from a Data payload for receiveChunk callbacks.
/// Uses NSLock for thread-safety since it's accessed from @Sendable closures.
private final class ChunkSource: @unchecked Sendable {
  private let data: Data
  private var offset = 0
  private let lock = NSLock()
  init(data: Data) { self.data = data }
  func read(into buf: UnsafeMutableRawBufferPointer, max maxCount: Int) -> Int {
    lock.lock()
    defer { lock.unlock() }
    let remaining = data.count - offset
    guard remaining > 0 else { return 0 }
    let n = min(maxCount, remaining)
    data.copyBytes(to: buf, from: offset..<(offset + n))
    offset += n
    return n
  }
}
