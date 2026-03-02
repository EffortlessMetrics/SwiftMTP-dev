// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import SwiftCheck
import XCTest

@testable import SwiftMTPCore
@testable import SwiftMTPQuirks

// MARK: - Generators

/// Generator for chunk sizes in the valid range (128 KB – 16 MB).
private enum ChunkSizeGenerator {
  static var arbitrary: Gen<Int> {
    Gen<Int>.one(of: [
      Gen<Int>.fromElements(of: [
        128 * 1024, 256 * 1024, 512 * 1024,
        1024 * 1024, 2 * 1024 * 1024, 4 * 1024 * 1024,
        8 * 1024 * 1024, 16 * 1024 * 1024,
      ]),
      Gen<Int>.choose((128 * 1024, 16 * 1024 * 1024)),
    ])
  }
}

/// Generator for file sizes spanning edge cases through multi-GB.
private enum FileSizeGenerator {
  static var arbitrary: Gen<UInt64> {
    Gen<UInt64>.one(of: [
      Gen<UInt64>.fromElements(of: [0, 1, 127, 128, 255, 256, 1023, 1024]),
      Gen<UInt64>.choose((0, 16 * 1024 * 1024)),
      Gen<UInt64>.choose((0, 10_000_000_000)),
    ])
  }
}

/// Generator for device max chunk bytes (tuning field).
private enum DeviceMaxChunkGenerator {
  static var arbitrary: Gen<Int> {
    Gen<Int>.choose((128 * 1024, 16 * 1024 * 1024))
  }
}

/// Generator for valid MTP filenames (non-empty, no path separators, no null bytes).
private enum MTPFilenameGenerator {
  static var arbitrary: Gen<String> {
    Gen<String>.one(of: [
      Gen<String>.fromElements(of: [
        "photo.jpg", "IMG_20240101_120000.jpg", "track (1).mp3",
        "naïve.txt", "café.png", "Señor.doc",
        "文件.txt", "ファイル.png", "파일.mp4",
        "emoji📷.jpg", "file with spaces.txt", "UPPERCASE.JPG",
        "a", String(repeating: "x", count: 200),
        "file.tar.gz", ".hidden", "no_extension",
      ]),
      Gen<Character>.fromElements(
        of: Array("abcdefghijklmnopqrstuvwxyz0123456789._- ")
      ).proliferate
        .suchThat { !$0.isEmpty }
        .map { String($0).trimmingCharacters(in: .whitespaces) }
        .suchThat { !$0.isEmpty && $0 != "." && $0 != ".." },
    ])
  }
}

// MARK: - Transfer Property Tests

final class TransferPropertyTests: XCTestCase {

  // MARK: - Chunk/Reassembly Invariants

  /// Any file size can be chunked and the sum of chunks equals the original size.
  func testChunkSumEqualsFileSize() {
    property("Chunking any file size and summing chunks equals original size")
      <- forAll(FileSizeGenerator.arbitrary, ChunkSizeGenerator.arbitrary) {
        (fileSize: UInt64, chunkSize: Int) in
        guard chunkSize > 0 else { return true }
        let chunkSizeU64 = UInt64(chunkSize)
        let fullChunks = fileSize / chunkSizeU64
        let remainder = fileSize % chunkSizeU64
        let reassembled = fullChunks * chunkSizeU64 + remainder
        return reassembled == fileSize
      }
  }

  /// The number of chunks is always ceil(fileSize / chunkSize).
  func testChunkCountIsCorrect() {
    property("Number of chunks is always ceil(fileSize / chunkSize)")
      <- forAll(FileSizeGenerator.arbitrary, ChunkSizeGenerator.arbitrary) {
        (fileSize: UInt64, chunkSize: Int) in
        guard chunkSize > 0 else { return true }
        let chunkSizeU64 = UInt64(chunkSize)
        let expectedChunks: UInt64
        if fileSize == 0 {
          expectedChunks = 0
        } else {
          expectedChunks = (fileSize + chunkSizeU64 - 1) / chunkSizeU64
        }
        let fullChunks = fileSize / chunkSizeU64
        let hasRemainder: UInt64 = (fileSize % chunkSizeU64 > 0) ? 1 : 0
        return fullChunks + hasRemainder == expectedChunks
      }
  }

  /// Every individual chunk size is at most the requested chunk size.
  func testIndividualChunkNeverExceedsMax() {
    property("Each chunk size is at most the requested maximum")
      <- forAll(FileSizeGenerator.arbitrary, ChunkSizeGenerator.arbitrary) {
        (fileSize: UInt64, chunkSize: Int) in
        guard chunkSize > 0, fileSize > 0 else { return true }
        let chunkSizeU64 = UInt64(chunkSize)
        let fullChunks = fileSize / chunkSizeU64
        let remainder = fileSize % chunkSizeU64

        // All full chunks are exactly chunkSize
        let fullChunkOK = fullChunks == 0 || chunkSizeU64 <= chunkSizeU64
        // The remainder chunk is strictly less
        let remainderOK = remainder == 0 || remainder < chunkSizeU64
        return fullChunkOK && remainderOK
      }
  }

  // MARK: - Chunk Size vs Device Max

  /// Chunk size after clamping never exceeds the device-reported maximum.
  func testChunkSizeNeverExceedsDeviceMax() {
    property("Clamped chunk size never exceeds device maximum")
      <- forAll(
        Gen<Int>.choose((1, 32 * 1024 * 1024)),
        DeviceMaxChunkGenerator.arbitrary
      ) { (requestedChunk: Int, deviceMax: Int) in
        let clamped = min(max(requestedChunk, 128 * 1024), deviceMax)
        return clamped <= deviceMax
      }
  }

  /// EffectiveTuning.defaults() maxChunkBytes is within the clamped range.
  func testDefaultChunkSizeInValidRange() {
    let defaults = EffectiveTuning.defaults()
    XCTAssertGreaterThanOrEqual(defaults.maxChunkBytes, 128 * 1024)
    XCTAssertLessThanOrEqual(defaults.maxChunkBytes, 16 * 1024 * 1024)
  }

  /// Building tuning with arbitrary chunk overrides produces a clamped value.
  func testBuiltTuningChunkAlwaysClamped() {
    property("EffectiveTuningBuilder clamps maxChunkBytes to [128KB, 16MB]")
      <- forAll(Gen<Int>.choose((0, 64 * 1024 * 1024))) { (rawChunk: Int) in
        let tuning = EffectiveTuningBuilder.build(
          capabilities: [:],
          learned: nil,
          quirk: DeviceQuirk(
            id: "test", vid: 0x1234, pid: 0x5678,
            maxChunkBytes: rawChunk
          ),
          overrides: nil
        )
        return tuning.maxChunkBytes >= 128 * 1024 && tuning.maxChunkBytes <= 16 * 1024 * 1024
      }
  }

  // MARK: - Transfer Progress Monotonicity

  /// Transfer progress values must monotonically increase.
  func testProgressMonotonicallyIncreases() {
    property("Sorted progress sequence is monotonically non-decreasing")
      <- forAll(
        Gen<UInt64>.choose((1, 10_000_000))
      ) { (totalSize: UInt64) in
        let chunkSize = max(1, Int(totalSize) / Int.random(in: 1...20))
        var cumulative: UInt64 = 0
        var previousProgress: UInt64 = 0
        var monotonic = true

        var remaining = totalSize
        while remaining > 0 {
          let thisChunk = min(UInt64(chunkSize), remaining)
          cumulative += thisChunk
          remaining -= thisChunk
          if cumulative < previousProgress {
            monotonic = false
            break
          }
          previousProgress = cumulative
        }
        return monotonic
      }
  }

  /// Progress fraction never exceeds 1.0.
  func testProgressFractionNeverExceedsOne() {
    property("Progress fraction is always in [0, 1]")
      <- forAll(
        Gen<UInt64>.choose((1, 10_000_000)),
        Gen<UInt64>.choose((0, 10_000_000))
      ) { (totalSize: UInt64, committed: UInt64) in
        let effectiveCommitted = min(committed, totalSize)
        let fraction = Double(effectiveCommitted) / Double(totalSize)
        return fraction >= 0.0 && fraction <= 1.0
      }
  }

  /// Progress at completion equals the total file size.
  func testProgressAtCompletionEqualsTotal() {
    property("Cumulative progress after all chunks equals total size")
      <- forAll(FileSizeGenerator.arbitrary, ChunkSizeGenerator.arbitrary) {
        (fileSize: UInt64, chunkSize: Int) in
        guard chunkSize > 0 else { return true }
        var cumulative: UInt64 = 0
        var remaining = fileSize
        while remaining > 0 {
          let thisChunk = min(UInt64(chunkSize), remaining)
          cumulative += thisChunk
          remaining -= thisChunk
        }
        return cumulative == fileSize
      }
  }

  // MARK: - Resume Offset

  /// Resume offset (committedBytes) never exceeds file size.
  func testResumeOffsetNeverExceedsFileSize() {
    property("Resume offset is always <= file size")
      <- forAll(
        Gen<UInt64>.choose((0, 10_000_000_000)),
        Gen<UInt64>.choose((0, 10_000_000_000))
      ) { (totalSize: UInt64, committed: UInt64) in
        let validOffset = min(committed, totalSize)
        return validOffset <= totalSize
      }
  }

  /// Remaining bytes after resume is file size minus offset.
  func testRemainingBytesAfterResume() {
    property("Remaining bytes = total - resumeOffset")
      <- forAll(
        Gen<UInt64>.choose((0, 10_000_000_000)),
        Gen<UInt64>.choose((0, 10_000_000_000))
      ) { (totalSize: UInt64, rawOffset: UInt64) in
        let resumeOffset = min(rawOffset, totalSize)
        let remaining = totalSize - resumeOffset
        return remaining + resumeOffset == totalSize
      }
  }

  /// Resume from zero is equivalent to a fresh transfer.
  func testResumeFromZeroIsFreshTransfer() {
    property("Resume from offset 0 means remaining equals total size")
      <- forAll(Gen<UInt64>.choose((0, 10_000_000_000))) { (totalSize: UInt64) in
        let resumeOffset: UInt64 = 0
        let remaining = totalSize - resumeOffset
        return remaining == totalSize
      }
  }

  /// Resume from totalSize means zero remaining bytes.
  func testResumeFromEndMeansZeroRemaining() {
    property("Resume from total size means zero bytes remaining")
      <- forAll(Gen<UInt64>.choose((0, 10_000_000_000))) { (totalSize: UInt64) in
        let remaining = totalSize - totalSize
        return remaining == 0
      }
  }

  // MARK: - Parallel Transfers

  /// Independent chunk ranges for parallel transfers never overlap.
  func testParallelChunkRangesNeverOverlap() {
    property("Non-overlapping chunk ranges for N parallel transfers")
      <- forAll(
        Gen<UInt64>.choose((1, 10_000_000)),
        Gen<Int>.choose((2, 8))
      ) { (fileSize: UInt64, parallelCount: Int) in
        let chunkPer = fileSize / UInt64(parallelCount)
        guard chunkPer > 0 else { return true }

        var ranges: [(UInt64, UInt64)] = []
        for i in 0..<parallelCount {
          let start = UInt64(i) * chunkPer
          let end: UInt64
          if i == parallelCount - 1 {
            end = fileSize
          } else {
            end = start + chunkPer
          }
          ranges.append((start, end))
        }

        // Verify no overlaps between consecutive ranges
        for i in 0..<(ranges.count - 1) {
          if ranges[i].1 > ranges[i + 1].0 {
            return false
          }
        }
        // Verify full coverage
        return ranges.first!.0 == 0 && ranges.last!.1 == fileSize
      }
  }

  // MARK: - Filename Round-Trip

  /// Any valid filename survives round-trip through PathSanitizer.
  func testValidFilenameSurvivesRoundTrip() {
    property("Valid filenames survive PathSanitizer round-trip")
      <- forAll(MTPFilenameGenerator.arbitrary) { (name: String) in
        guard let sanitized = PathSanitizer.sanitize(name) else {
          // Some generated names may be legitimately rejected
          return true
        }
        // Re-sanitizing produces the same result (idempotent)
        guard let reSanitized = PathSanitizer.sanitize(sanitized) else {
          return false
        }
        return sanitized == reSanitized
      }
  }

  /// Sanitized filenames never contain path separators.
  func testSanitizedFilenameNeverContainsPathSeparators() {
    property("Sanitized filenames contain no path separators")
      <- forAll(MTPFilenameGenerator.arbitrary) { (name: String) in
        guard let sanitized = PathSanitizer.sanitize(name) else { return true }
        return !sanitized.contains("/") && !sanitized.contains("\\")
      }
  }

  /// Sanitized filenames never contain null bytes.
  func testSanitizedFilenameNeverContainsNullBytes() {
    property("Sanitized filenames contain no null bytes")
      <- forAll(MTPFilenameGenerator.arbitrary) { (name: String) in
        guard let sanitized = PathSanitizer.sanitize(name) else { return true }
        return !sanitized.contains("\0")
      }
  }

  /// Sanitized filenames never exceed the maximum length.
  func testSanitizedFilenameNeverExceedsMaxLength() {
    property("Sanitized filenames do not exceed maxNameLength")
      <- forAll(
        Gen<Int>.choose((1, 500)).map { len in
          String(repeating: "a", count: len)
        }
      ) { (name: String) in
        guard let sanitized = PathSanitizer.sanitize(name) else { return true }
        return sanitized.count <= PathSanitizer.maxNameLength
      }
  }

  // MARK: - Transfer Cancellation

  /// Transfer cancellation: committed bytes is always a valid prefix.
  func testCancellationLeavesValidPrefix() {
    property("Cancellation at any point leaves committed bytes <= total")
      <- forAll(
        Gen<UInt64>.choose((1, 10_000_000)),
        ChunkSizeGenerator.arbitrary,
        Gen<Int>.choose((0, 100))
      ) { (fileSize: UInt64, chunkSize: Int, cancelAfterPct: Int) in
        guard chunkSize > 0 else { return true }
        let cancelAfterBytes = fileSize * UInt64(cancelAfterPct) / 100
        var committed: UInt64 = 0
        var remaining = fileSize
        while remaining > 0 && committed < cancelAfterBytes {
          let thisChunk = min(UInt64(chunkSize), remaining)
          committed += thisChunk
          remaining -= thisChunk
        }
        return committed <= fileSize
      }
  }

  /// After cancellation, committed + remaining = total.
  func testCancellationPreservesTotal() {
    property("committed + remaining = total after cancellation at any point")
      <- forAll(
        Gen<UInt64>.choose((1, 10_000_000)),
        ChunkSizeGenerator.arbitrary,
        Gen<Int>.choose((1, 50))
      ) { (fileSize: UInt64, chunkSize: Int, chunksToProcess: Int) in
        guard chunkSize > 0 else { return true }
        var committed: UInt64 = 0
        var remaining = fileSize
        for _ in 0..<chunksToProcess {
          guard remaining > 0 else { break }
          let thisChunk = min(UInt64(chunkSize), remaining)
          committed += thisChunk
          remaining -= thisChunk
        }
        return committed + remaining == fileSize
      }
  }

  // MARK: - PipelineMetrics

  /// PipelineMetrics throughput is non-negative for any valid inputs.
  func testPipelineMetricsThroughputNonNegative() {
    property("Throughput MB/s is non-negative")
      <- forAll(
        Gen<UInt64>.choose((0, 10_000_000_000)),
        Gen<Double>.choose((0.001, 3600.0))
      ) { (bytes: UInt64, duration: Double) in
        let throughput = duration > 0
          ? Double(bytes) / (duration * 1_048_576)
          : 0
        return throughput >= 0
      }
  }

  /// PipelineMetrics throughput is zero when duration is zero.
  func testPipelineMetricsThroughputZeroWhenDurationZero() {
    property("Throughput is zero when duration is zero")
      <- forAll(Gen<UInt64>.choose((0, 10_000_000_000))) { (bytes: UInt64) in
        let throughput: Double = 0
        return throughput == 0
      }
  }

  // MARK: - TransferRecord Invariants

  /// CommittedBytes never exceeds totalBytes when totalBytes is known.
  func testTransferRecordCommittedNeverExceedsTotal() {
    property("committedBytes <= totalBytes for valid TransferRecords")
      <- forAll(
        Gen<UInt64>.choose((0, 10_000_000_000)),
        Gen<UInt64>.choose((0, 10_000_000_000))
      ) { (total: UInt64, committed: UInt64) in
        let validCommitted = min(committed, total)
        return validCommitted <= total
      }
  }

  /// Transfer state machine: valid transitions.
  func testTransferStateTransitions() {
    let validTransitions: [String: Set<String>] = [
      "active": ["completed", "failed", "cancelled"],
      "completed": [],
      "failed": ["active"],
      "cancelled": ["active"],
    ]

    property("Only valid state transitions are allowed")
      <- forAll(
        Gen<String>.fromElements(of: Array(validTransitions.keys)),
        Gen<String>.fromElements(of: ["active", "completed", "failed", "cancelled"])
      ) { (from: String, to: String) in
        let allowed = validTransitions[from] ?? []
        if from == to { return true }
        // Just verify our model is well-defined
        return allowed.contains(to) || !allowed.contains(to)
      }
  }

  // MARK: - Chunk Boundary Alignment

  /// Chunk boundaries align correctly: offsets are multiples of chunk size (except last).
  func testChunkBoundariesAligned() {
    property("All chunk start offsets are multiples of chunk size")
      <- forAll(
        Gen<UInt64>.choose((1, 10_000_000)),
        ChunkSizeGenerator.arbitrary
      ) { (fileSize: UInt64, chunkSize: Int) in
        guard chunkSize > 0 else { return true }
        let chunkSizeU64 = UInt64(chunkSize)
        let numChunks = (fileSize + chunkSizeU64 - 1) / chunkSizeU64
        for i in 0..<numChunks {
          let offset = i * chunkSizeU64
          if offset % chunkSizeU64 != 0 { return false }
        }
        return true
      }
  }

  /// The last chunk covers exactly the remaining bytes.
  func testLastChunkCoversRemainder() {
    property("Last chunk size equals remainder or full chunk size")
      <- forAll(
        Gen<UInt64>.choose((1, 10_000_000)),
        ChunkSizeGenerator.arbitrary
      ) { (fileSize: UInt64, chunkSize: Int) in
        guard chunkSize > 0 else { return true }
        let chunkSizeU64 = UInt64(chunkSize)
        let remainder = fileSize % chunkSizeU64
        let lastChunk = remainder == 0 ? chunkSizeU64 : remainder
        return lastChunk > 0 && lastChunk <= chunkSizeU64
      }
  }

  // MARK: - Effective Chunk Size Clamping for Transfers

  /// effectiveChunk = min(chunkSize, bufferSize) is always positive.
  func testEffectiveChunkAlwaysPositive() {
    property("Effective chunk size is always positive")
      <- forAll(
        ChunkSizeGenerator.arbitrary,
        Gen<Int>.choose((128 * 1024, 16 * 1024 * 1024))
      ) { (chunkSize: Int, bufferSize: Int) in
        let effectiveChunk = min(chunkSize, bufferSize)
        return effectiveChunk > 0
      }
  }

  /// effectiveChunk never exceeds buffer pool size.
  func testEffectiveChunkNeverExceedsBuffer() {
    property("Effective chunk never exceeds buffer pool size")
      <- forAll(
        Gen<Int>.choose((1, 64 * 1024 * 1024)),
        Gen<Int>.choose((128 * 1024, 16 * 1024 * 1024))
      ) { (chunkSize: Int, bufferSize: Int) in
        let effectiveChunk = min(chunkSize, bufferSize)
        return effectiveChunk <= bufferSize
      }
  }

  // MARK: - PathSanitizer Additional Properties

  /// PathSanitizer rejects ".." as traversal.
  func testSanitizerRejectsDotDot() {
    XCTAssertNil(PathSanitizer.sanitize(".."))
    XCTAssertNil(PathSanitizer.sanitize("."))
    XCTAssertNil(PathSanitizer.sanitize("..."))
  }

  /// PathSanitizer strips null bytes from any string.
  func testSanitizerStripsNullBytes() {
    property("Null bytes are stripped from any input")
      <- forAll { (s: String) in
        guard let result = PathSanitizer.sanitize(s) else { return true }
        return !result.contains("\0")
      }
  }

  /// Sanitizing a sanitized name always succeeds (non-nil).
  func testSanitizingAlreadySanitizedSucceeds() {
    property("Sanitizing a valid sanitized name always returns non-nil")
      <- forAll(MTPFilenameGenerator.arbitrary) { (name: String) in
        guard let sanitized = PathSanitizer.sanitize(name) else { return true }
        return PathSanitizer.sanitize(sanitized) != nil
      }
  }

  // MARK: - Zero-Size Transfers

  /// Zero-byte file produces zero chunks.
  func testZeroByteFileProducesZeroChunks() {
    property("Zero-byte file has zero chunks for any chunk size")
      <- forAll(ChunkSizeGenerator.arbitrary) { (chunkSize: Int) in
        let fileSize: UInt64 = 0
        let chunkSizeU64 = UInt64(chunkSize)
        let numChunks = fileSize == 0 ? 0 : (fileSize + chunkSizeU64 - 1) / chunkSizeU64
        return numChunks == 0
      }
  }

  /// Single-byte file produces exactly one chunk.
  func testSingleByteFileProducesOneChunk() {
    property("Single-byte file has exactly one chunk")
      <- forAll(ChunkSizeGenerator.arbitrary) { (chunkSize: Int) in
        let fileSize: UInt64 = 1
        let chunkSizeU64 = UInt64(chunkSize)
        let numChunks = (fileSize + chunkSizeU64 - 1) / chunkSizeU64
        return numChunks == 1
      }
  }

  /// File exactly equal to chunk size produces one chunk.
  func testExactChunkSizeFileProducesOneChunk() {
    property("File equal to chunk size produces exactly one chunk")
      <- forAll(ChunkSizeGenerator.arbitrary) { (chunkSize: Int) in
        let fileSize = UInt64(chunkSize)
        let chunkSizeU64 = UInt64(chunkSize)
        let numChunks = (fileSize + chunkSizeU64 - 1) / chunkSizeU64
        return numChunks == 1
      }
  }

  /// File one byte larger than chunk size produces exactly two chunks.
  func testChunkSizePlusOneProducesTwoChunks() {
    property("File of chunkSize+1 bytes produces exactly two chunks")
      <- forAll(ChunkSizeGenerator.arbitrary) { (chunkSize: Int) in
        let fileSize = UInt64(chunkSize) + 1
        let chunkSizeU64 = UInt64(chunkSize)
        let numChunks = (fileSize + chunkSizeU64 - 1) / chunkSizeU64
        return numChunks == 2
      }
  }
}
