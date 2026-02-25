// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation

/// Metrics collected during a pipelined transfer.
struct PipelineMetrics: Sendable {
  let bytesTransferred: UInt64
  let durationSeconds: Double
  let throughputMBps: Double
  let retryCount: Int

  init(bytesTransferred: UInt64, durationSeconds: Double, retryCount: Int) {
    self.bytesTransferred = bytesTransferred
    self.durationSeconds = durationSeconds
    self.retryCount = retryCount
    self.throughputMBps =
      durationSeconds > 0
      ? Double(bytesTransferred) / (durationSeconds * 1_048_576)
      : 0
  }
}

/// 2-stage pipeline upload: reads from a file while sending the previous chunk.
struct PipelinedUpload: Sendable {
  let pool: BufferPool

  /// Run a pipelined upload from `sourceURL`.
  ///
  /// Concurrency: a child task fills the next buffer from disk while the parent
  /// task sends the current buffer to the device (via `sendChunk`).
  ///
  /// - Parameters:
  ///   - sourceURL: Local file to upload.
  ///   - totalSize: Expected number of bytes to transfer.
  ///   - chunkSize: Bytes per chunk (must be ≤ `pool.bufferSize`).
  ///   - sendChunk: Called with each filled buffer slice and its byte count.
  ///   - onProgress: Called after each chunk with cumulative bytes transferred.
  func run(
    sourceURL: URL,
    totalSize: UInt64,
    chunkSize: Int = 256 * 1024,
    sendChunk: @Sendable (UnsafeRawBufferPointer, Int) async throws -> Void,
    onProgress: @Sendable (UInt64) async -> Void
  ) async throws -> PipelineMetrics {
    let effectiveChunk = min(chunkSize, pool.bufferSize)
    let source = try FileSource(url: sourceURL)
    let start = Date()
    var totalSent: UInt64 = 0

    // Pre-fill the first read buffer.
    var readBuf = await pool.acquire()
    var readCount = try source.read(into: readBuf.mutable(count: effectiveChunk))

    while readCount > 0 {
      let sendBuf = readBuf
      let sendCount = readCount

      // Acquire the next buffer before launching the pipeline stages.
      readBuf = await pool.acquire()

      // Stage 1 (child task): fill readBuf from disk.
      // Stage 2 (parent):     send sendBuf to the device concurrently.
      let nextReadCount: Int
      let nextBuf = readBuf  // capture by value before passing to child task
      do {
        nextReadCount = try await withThrowingTaskGroup(of: Int.self) { group in
          group.addTask {
            try source.read(into: nextBuf.mutable(count: effectiveChunk))
          }
          try await sendChunk(sendBuf.readOnly(count: sendCount), sendCount)
          return try await group.next() ?? 0
        }
      } catch {
        await pool.release(sendBuf)
        await pool.release(readBuf)
        try source.close()
        throw error
      }

      totalSent += UInt64(sendCount)
      await pool.release(sendBuf)
      await onProgress(totalSent)
      readCount = nextReadCount
    }

    // Release the last (unfilled) buffer.
    await pool.release(readBuf)
    try source.close()

    let elapsed = Date().timeIntervalSince(start)
    return PipelineMetrics(bytesTransferred: totalSent, durationSeconds: elapsed, retryCount: 0)
  }
}

/// 2-stage pipeline download: receives a new chunk while writing the previous one.
struct PipelinedDownload: Sendable {
  let pool: BufferPool

  /// Run a pipelined download to `destURL`.
  ///
  /// Concurrency: a child task writes the previous chunk to disk while the parent
  /// task receives the next chunk from the device (via `receiveChunk`).
  ///
  /// - Parameters:
  ///   - destURL: Local file to write received data into.
  ///   - totalSize: Expected number of bytes to receive.
  ///   - chunkSize: Bytes per chunk (must be ≤ `pool.bufferSize`).
  ///   - receiveChunk: Called with a buffer to fill; must return the byte count filled.
  ///   - onProgress: Called after each chunk with cumulative bytes transferred.
  func run(
    destURL: URL,
    totalSize: UInt64,
    chunkSize: Int = 256 * 1024,
    receiveChunk: @Sendable (UnsafeMutableRawBufferPointer, Int) async throws -> Int,
    onProgress: @Sendable (UInt64) async -> Void
  ) async throws -> PipelineMetrics {
    let effectiveChunk = min(chunkSize, pool.bufferSize)
    let sink = try FileSink(url: destURL)
    let start = Date()
    var totalReceived: UInt64 = 0

    // Receive the first chunk.
    var recvBuf = await pool.acquire()
    var recvCount = try await receiveChunk(recvBuf.mutable(count: effectiveChunk), effectiveChunk)

    while recvCount > 0 {
      let writeBuf = recvBuf
      let writeCount = recvCount

      recvBuf = await pool.acquire()

      // Stage 1 (child task): write writeBuf to disk.
      // Stage 2 (parent):     receive the next chunk into recvBuf concurrently.
      let nextRecvCount: Int
      do {
        nextRecvCount = try await withThrowingTaskGroup(of: Int.self) { group in
          group.addTask {
            try sink.write(writeBuf.readOnly(count: writeCount))
            return 0
          }
          let n = try await receiveChunk(recvBuf.mutable(count: effectiveChunk), effectiveChunk)
          _ = try await group.next()  // wait for write to complete
          return n
        }
      } catch {
        await pool.release(writeBuf)
        await pool.release(recvBuf)
        try sink.close()
        throw error
      }

      totalReceived += UInt64(writeCount)
      await pool.release(writeBuf)
      await onProgress(totalReceived)
      recvCount = nextRecvCount
    }

    await pool.release(recvBuf)
    try sink.close()

    let elapsed = Date().timeIntervalSince(start)
    return PipelineMetrics(bytesTransferred: totalReceived, durationSeconds: elapsed, retryCount: 0)
  }
}
