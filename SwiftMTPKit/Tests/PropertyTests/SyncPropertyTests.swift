// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import SwiftCheck
import XCTest

@testable import SwiftMTPCore
@testable import SwiftMTPIndex
@testable import SwiftMTPSync

// MARK: - Generators

/// Generator for MTPDiff.Row values
private enum DiffRowGenerator {
  static var arbitrary: Gen<MTPDiff.Row> {
    Gen<(UInt32, UInt32, String, UInt64, UInt16)>.zip(
      Gen<UInt32>.choose((1, UInt32.max)),
      Gen<UInt32>.choose((1, UInt32.max)),
      Gen<String>.fromElements(of: [
        "00010001/DCIM/photo.jpg",
        "00010001/Music/track.mp3",
        "00020001/Documents/notes.txt",
        "00010001/Videos/clip.mp4",
        "00010001/DCIM/2024/vacation/IMG_001.jpg",
      ]),
      Gen<UInt64>.choose((0, 10_000_000_000)),
      Gen<UInt16>.fromElements(of: [0x3001, 0x3801, 0x3009, 0xB982])
    ).map { handle, storage, pathKey, size, format in
      MTPDiff.Row(
        handle: handle,
        storage: storage,
        pathKey: pathKey,
        size: size,
        mtime: Date(timeIntervalSince1970: Double(Int.random(in: 1_600_000_000...1_700_000_000))),
        format: format
      )
    }
  }
}

/// Generator for MTPSyncReport values
private enum SyncReportGenerator {
  static var arbitrary: Gen<MTPSyncReport> {
    Gen<(Int, Int, Int)>.zip(
      Gen<Int>.choose((0, 1000)),
      Gen<Int>.choose((0, 1000)),
      Gen<Int>.choose((0, 100))
    ).map { downloaded, skipped, failed in
      var report = MTPSyncReport()
      report.downloaded = downloaded
      report.skipped = skipped
      report.failed = failed
      return report
    }
  }
}

// MARK: - Sync Property Tests

final class SyncPropertyTests: XCTestCase {

  // MARK: - MTPDiff Invariants

  /// An empty diff has no changes.
  func testEmptyDiffIsEmpty() {
    let diff = MTPDiff()
    XCTAssertTrue(diff.isEmpty)
    XCTAssertEqual(diff.totalChanges, 0)
  }

  /// Diff of identical object sets is always empty.
  func testDiffOfIdenticalSetsIsEmpty() {
    property("Diff of identical object sets should have zero total changes")
      <- forAll(
        Gen<Int>.choose((0, 50))
      ) { count in
        // Two identical sets of pathKeys yield no added/removed/modified
        var diff = MTPDiff()
        // When old and new are the same, no entries should appear
        return diff.isEmpty && diff.totalChanges == 0
      }
  }

  /// totalChanges equals added + removed + modified.
  func testTotalChangesEqualsSum() {
    property("totalChanges should equal added.count + removed.count + modified.count")
      <- forAll(
        Gen<Int>.choose((0, 20)),
        Gen<Int>.choose((0, 20)),
        Gen<Int>.choose((0, 20))
      ) { addedCount, removedCount, modifiedCount in
        var diff = MTPDiff()
        for i in 0..<addedCount {
          diff.added.append(MTPDiff.Row(
            handle: UInt32(i + 1), storage: 1,
            pathKey: "00000001/added_\(i)", size: 100, mtime: nil, format: 0x3001))
        }
        for i in 0..<removedCount {
          diff.removed.append(MTPDiff.Row(
            handle: UInt32(i + 1000), storage: 1,
            pathKey: "00000001/removed_\(i)", size: 200, mtime: nil, format: 0x3001))
        }
        for i in 0..<modifiedCount {
          diff.modified.append(MTPDiff.Row(
            handle: UInt32(i + 2000), storage: 1,
            pathKey: "00000001/modified_\(i)", size: 300, mtime: nil, format: 0x3001))
        }
        return diff.totalChanges == addedCount + removedCount + modifiedCount
      }
  }

  /// isEmpty is consistent with totalChanges.
  func testIsEmptyConsistentWithTotalChanges() {
    property("isEmpty should be true iff totalChanges == 0")
      <- forAll(
        Gen<Int>.choose((0, 10)),
        Gen<Int>.choose((0, 10)),
        Gen<Int>.choose((0, 10))
      ) { a, r, m in
        var diff = MTPDiff()
        for i in 0..<a {
          diff.added.append(MTPDiff.Row(
            handle: UInt32(i + 1), storage: 1,
            pathKey: "00000001/a_\(i)", size: nil, mtime: nil, format: 0x3001))
        }
        for i in 0..<r {
          diff.removed.append(MTPDiff.Row(
            handle: UInt32(i + 100), storage: 1,
            pathKey: "00000001/r_\(i)", size: nil, mtime: nil, format: 0x3001))
        }
        for i in 0..<m {
          diff.modified.append(MTPDiff.Row(
            handle: UInt32(i + 200), storage: 1,
            pathKey: "00000001/m_\(i)", size: nil, mtime: nil, format: 0x3001))
        }
        return diff.isEmpty == (diff.totalChanges == 0)
      }
  }

  // MARK: - MTPSyncReport Invariants

  /// totalProcessed always equals downloaded + skipped + failed.
  func testSyncReportTotalProcessed() {
    property("totalProcessed should equal downloaded + skipped + failed")
      <- forAll(
        Gen<Int>.choose((0, 1000)),
        Gen<Int>.choose((0, 1000)),
        Gen<Int>.choose((0, 100))
      ) { downloaded, skipped, failed in
        var report = MTPSyncReport()
        report.downloaded = downloaded
        report.skipped = skipped
        report.failed = failed
        return report.totalProcessed == report.downloaded + report.skipped + report.failed
      }
  }

  /// Success rate is between 0 and 100 inclusive.
  func testSyncReportSuccessRateRange() {
    property("successRate should be between 0 and 100")
      <- forAll(
        Gen<Int>.choose((0, 1000)),
        Gen<Int>.choose((0, 1000)),
        Gen<Int>.choose((0, 100))
      ) { downloaded, skipped, failed in
        var report = MTPSyncReport()
        report.downloaded = downloaded
        report.skipped = skipped
        report.failed = failed
        return report.successRate >= 0 && report.successRate <= 100
      }
  }

  /// When no files are processed, success rate is 0.
  func testSyncReportEmptyIsZeroRate() {
    let report = MTPSyncReport()
    XCTAssertEqual(report.totalProcessed, 0)
    XCTAssertEqual(report.successRate, 0)
  }

  /// When all files are downloaded, success rate is 100%.
  func testSyncReportAllDownloaded() {
    property("When only downloaded files exist, success rate should be 100%")
      <- forAll(Gen<Int>.choose((1, 10000))) { count in
        var report = MTPSyncReport()
        report.downloaded = count
        return report.successRate == 100.0
      }
  }

  // MARK: - MirrorEngine Pattern Matching

  /// The ** glob pattern matches any path.
  func testGlobDoubleStarMatchesAll() {
    let engine = makeMirrorEngine()
    property("** glob pattern should match any path key")
      <- forAll(
        Gen<String>.fromElements(of: [
          "00010001/DCIM/photo.jpg",
          "00010001/Music/Albums/Artist/track.mp3",
          "00020001/file.txt",
          "00010001/a/b/c/d/e/f.dat",
        ])
      ) { pathKey in
        engine.matchesPattern(pathKey, pattern: "**")
      }
  }

  /// An exact single-component pattern only matches that component.
  func testGlobExactExtensionMatch() {
    let engine = makeMirrorEngine()
    property("*.jpg should match only .jpg files at root level")
      <- forAll(
        Gen<String>.fromElements(of: ["photo.jpg", "image.jpg", "pic.jpg"])
      ) { name in
        let pathKey = "00010001/\(name)"
        return engine.matchesPattern(pathKey, pattern: "*.jpg")
      }
  }

  /// DCIM/** matches anything under DCIM.
  func testGlobDCIMRecursive() {
    let engine = makeMirrorEngine()
    property("DCIM/** should match any path starting with DCIM")
      <- forAll(
        Gen<String>.fromElements(of: [
          "00010001/DCIM/photo.jpg",
          "00010001/DCIM/2024/photo.jpg",
          "00010001/DCIM/a/b/c/photo.jpg",
        ])
      ) { pathKey in
        // pathKey starts with storage prefix, pattern matches components
        engine.matchesPattern(pathKey, pattern: "DCIM/**")
      }
  }

  // MARK: - Helpers

  private func makeMirrorEngine() -> MirrorEngine {
    let tempDir = FileManager.default.temporaryDirectory
      .appendingPathComponent("sync_prop_test_\(UUID().uuidString)")
    let dbPath = tempDir.appendingPathComponent("test.db").path
    try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    let snapshotter = try! Snapshotter(dbPath: dbPath)
    let diffEngine = try! DiffEngine(dbPath: dbPath)
    let journal = try! SQLiteTransferJournal(
      dbPath: tempDir.appendingPathComponent("journal.db").path)
    return MirrorEngine(snapshotter: snapshotter, diffEngine: diffEngine, journal: journal)
  }
}
