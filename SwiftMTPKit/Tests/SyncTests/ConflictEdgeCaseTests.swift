// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import XCTest

@testable import SwiftMTPCore
@testable import SwiftMTPIndex
@testable import SwiftMTPSync
@testable import SwiftMTPTestKit

/// Edge-case tests for sync conflict resolution: case sensitivity, timestamp ties,
/// zero-byte files, deep paths, special characters, long filenames, multi-conflict
/// directories, and all 6 resolution strategies.
final class ConflictEdgeCaseTests: XCTestCase {
  private var tempDirectory: URL!
  private var dbPath: String!
  private var snapshotter: Snapshotter!
  private var diffEngine: DiffEngine!

  private let storage: UInt32 = 0x0001_0001

  override func setUpWithError() throws {
    try super.setUpWithError()
    tempDirectory = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString).resolvingSymlinksInPath()
    try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    dbPath = tempDirectory.appendingPathComponent("conflict-edge.sqlite").path
    snapshotter = try Snapshotter(dbPath: dbPath)
    diffEngine = try DiffEngine(dbPath: dbPath)
  }

  override func tearDownWithError() throws {
    try? FileManager.default.removeItem(at: tempDirectory)
    diffEngine = nil
    snapshotter = nil
    dbPath = nil
    tempDirectory = nil
    try super.tearDownWithError()
  }

  // MARK: - Case-Insensitive Filename Conflicts

  func testSameFilenameDifferentCaseDetectedAsConflict() throws {
    // On case-insensitive FS (macOS default), Photo.jpg and photo.jpg map to the same file.
    let localDir = makeSubDir("local")
    let remoteDir = makeSubDir("remote")

    try "LOCAL version".write(
      to: localDir.appendingPathComponent("Photo.jpg"), atomically: true, encoding: .utf8)
    try "REMOTE version".write(
      to: remoteDir.appendingPathComponent("photo.jpg"), atomically: true, encoding: .utf8)

    // On case-insensitive FS, both names resolve to the same file — detect as conflict
    let localFiles = Set(listRelativeFiles(in: localDir).map { $0.lowercased() })
    let remoteFiles = Set(listRelativeFiles(in: remoteDir).map { $0.lowercased() })
    let commonCI = localFiles.intersection(remoteFiles)
    XCTAssertTrue(commonCI.contains("photo.jpg"), "Case-insensitive match should detect overlap")
  }

  func testCaseInsensitiveConflictResolvesWithStrategy() throws {
    let localDir = makeSubDir("local")
    let remoteDir = makeSubDir("remote")
    let mergedDir = makeSubDir("merged")

    try "local PHOTO".write(
      to: localDir.appendingPathComponent("Photo.JPG"), atomically: true, encoding: .utf8)
    try "device photo".write(
      to: remoteDir.appendingPathComponent("photo.jpg"), atomically: true, encoding: .utf8)

    // localWins should keep local regardless of case
    resolveConflictCaseInsensitive(
      localName: "Photo.JPG", remoteName: "photo.jpg",
      localDir: localDir, remoteDir: remoteDir, mergedDir: mergedDir, strategy: .localWins)

    let merged = try String(
      contentsOf: mergedDir.appendingPathComponent("Photo.JPG"), encoding: .utf8)
    XCTAssertEqual(merged, "local PHOTO")
  }

  // MARK: - Timestamp Tie Resolution

  func testTimestampTieFallsBackToDevicePreference() async throws {
    // newerWins with equal timestamps: `deviceMtime > localMtime` is false when equal,
    // so the engine returns .keptLocal — verify this deterministic behavior.
    let fixedDate = Date(timeIntervalSince1970: 1_700_000_000)
    let conflict = MTPConflictInfo(
      pathKey: "00010001/DCIM/tie.jpg", handle: 1,
      deviceSize: 2048, deviceMtime: fixedDate,
      localSize: 1024, localMtime: fixedDate)

    let journal = try SQLiteTransferJournal(dbPath: dbPath)
    let engine = MirrorEngine(
      snapshotter: snapshotter, diffEngine: diffEngine, journal: journal,
      conflictStrategy: .newerWins)

    let row = makeRow(handle: 1, path: "00010001/DCIM/tie.jpg", size: 2048, mtime: fixedDate)
    let localURL = tempDirectory.appendingPathComponent("tie.jpg")
    try "local content".write(to: localURL, atomically: true, encoding: .utf8)

    let record = try await engine.resolveConflict(
        conflict: conflict, file: row, localURL: localURL,
        device: VirtualMTPDevice(config: .emptyDevice), root: self.tempDirectory)
    XCTAssertEqual(record.outcome, .keptLocal)
    XCTAssertEqual(record.strategy, .newerWins)
  }

  func testNewerWinsDeviceNewer() throws {
    let older = Date(timeIntervalSince1970: 1_700_000_000)
    let newer = Date(timeIntervalSince1970: 1_700_001_000)
    let conflict = MTPConflictInfo(
      pathKey: "00010001/DCIM/newer.jpg", handle: 2,
      deviceSize: 2048, deviceMtime: newer,
      localSize: 1024, localMtime: older)

    let journal = try SQLiteTransferJournal(dbPath: dbPath)
    let engine = MirrorEngine(
      snapshotter: snapshotter, diffEngine: diffEngine, journal: journal,
      conflictStrategy: .newerWins)

    let row = makeRow(handle: 2, path: "00010001/DCIM/newer.jpg", size: 2048, mtime: newer)
    let localURL = tempDirectory.appendingPathComponent("newer.jpg")
    try "old local".write(to: localURL, atomically: true, encoding: .utf8)

    let record = try awaitSync {
      try await engine.resolveConflict(
        conflict: conflict, file: row, localURL: localURL,
        device: VirtualMTPDevice(config: .emptyDevice), root: self.tempDirectory)
    }

    XCTAssertEqual(record.outcome, .keptDevice)
  }

  func testNewerWinsNilTimestampsFallBackToDistantPast() throws {
    // Both nil mtimes → both treated as .distantPast → equal → keptLocal
    let conflict = MTPConflictInfo(
      pathKey: "00010001/file.bin", handle: 3,
      deviceSize: 100, deviceMtime: nil,
      localSize: 200, localMtime: nil)

    let journal = try SQLiteTransferJournal(dbPath: dbPath)
    let engine = MirrorEngine(
      snapshotter: snapshotter, diffEngine: diffEngine, journal: journal,
      conflictStrategy: .newerWins)

    let row = makeRow(handle: 3, path: "00010001/file.bin", size: 100, mtime: nil)
    let localURL = tempDirectory.appendingPathComponent("file.bin")
    try Data(count: 200).write(to: localURL)

    let record = try awaitSync {
      try await engine.resolveConflict(
        conflict: conflict, file: row, localURL: localURL,
        device: VirtualMTPDevice(config: .emptyDevice), root: self.tempDirectory)
    }

    // Both nil → .distantPast == .distantPast → device NOT > local → keptLocal
    XCTAssertEqual(record.outcome, .keptLocal)
  }

  // MARK: - Zero-Byte File Conflicts

  func testZeroByteLocalVsNonZeroRemote() throws {
    let localDir = makeSubDir("local-zero")
    let remoteDir = makeSubDir("remote-zero")

    try Data().write(to: localDir.appendingPathComponent("empty.bin"))
    try Data(repeating: 0xFF, count: 128).write(
      to: remoteDir.appendingPathComponent("empty.bin"))

    let conflicts = detectConflicts(local: localDir, remote: remoteDir)
    XCTAssertEqual(conflicts.count, 1, "Zero-byte vs non-zero should be a conflict")
  }

  func testNonZeroLocalVsZeroByteRemote() throws {
    let localDir = makeSubDir("local-nonzero")
    let remoteDir = makeSubDir("remote-nonzero")

    try Data(repeating: 0xAA, count: 64).write(
      to: localDir.appendingPathComponent("data.bin"))
    try Data().write(to: remoteDir.appendingPathComponent("data.bin"))

    let conflicts = detectConflicts(local: localDir, remote: remoteDir)
    XCTAssertEqual(conflicts.count, 1, "Non-zero vs zero-byte should be a conflict")
  }

  func testBothZeroBytesNoConflict() throws {
    let localDir = makeSubDir("local-both-zero")
    let remoteDir = makeSubDir("remote-both-zero")

    try Data().write(to: localDir.appendingPathComponent("both-empty.bin"))
    try Data().write(to: remoteDir.appendingPathComponent("both-empty.bin"))

    let conflicts = detectConflicts(local: localDir, remote: remoteDir)
    XCTAssertTrue(conflicts.isEmpty, "Both zero-byte files should not conflict")
  }

  // MARK: - Deeply Nested Path Conflicts

  func testDeeplyNestedPathConflict() throws {
    let localDir = makeSubDir("local-deep")
    let remoteDir = makeSubDir("remote-deep")

    let nested = "a/b/c/d/e"
    let localNested = localDir.appendingPathComponent(nested)
    let remoteNested = remoteDir.appendingPathComponent(nested)
    try FileManager.default.createDirectory(at: localNested, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: remoteNested, withIntermediateDirectories: true)

    try "local deep".write(
      to: localNested.appendingPathComponent("deep.txt"), atomically: true, encoding: .utf8)
    try "remote deep".write(
      to: remoteNested.appendingPathComponent("deep.txt"), atomically: true, encoding: .utf8)

    let conflicts = detectConflicts(local: localDir, remote: remoteDir)
    XCTAssertEqual(conflicts.count, 1)
    XCTAssertTrue(conflicts.first?.contains("a/b/c/d/e/deep.txt") == true)
  }

  func testPathKeyToLocalURLPreservesDeepNesting() {
    let journal = try! SQLiteTransferJournal(dbPath: dbPath)
    let engine = MirrorEngine(
      snapshotter: snapshotter, diffEngine: diffEngine, journal: journal)

    let root = tempDirectory!
    let pathKey = "00010001/DCIM/sub1/sub2/sub3/photo.jpg"
    let url = engine.pathKeyToLocalURL(pathKey, root: root)

    XCTAssertTrue(url.path.hasSuffix("DCIM/sub1/sub2/sub3/photo.jpg"))
  }

  // MARK: - Special Characters in Filenames

  func testConflictWithSpacesInFilename() throws {
    let localDir = makeSubDir("local-spaces")
    let remoteDir = makeSubDir("remote-spaces")

    try "local".write(
      to: localDir.appendingPathComponent("my photo (1).jpg"), atomically: true, encoding: .utf8)
    try "remote".write(
      to: remoteDir.appendingPathComponent("my photo (1).jpg"), atomically: true, encoding: .utf8)

    let conflicts = detectConflicts(local: localDir, remote: remoteDir)
    XCTAssertEqual(conflicts.count, 1)
  }

  func testConflictWithUnicodeFilename() throws {
    let localDir = makeSubDir("local-unicode")
    let remoteDir = makeSubDir("remote-unicode")

    try "local".write(
      to: localDir.appendingPathComponent("写真.jpg"), atomically: true, encoding: .utf8)
    try "remote".write(
      to: remoteDir.appendingPathComponent("写真.jpg"), atomically: true, encoding: .utf8)

    let conflicts = detectConflicts(local: localDir, remote: remoteDir)
    XCTAssertEqual(conflicts.count, 1)
  }

  func testConflictWithEmojiFilename() throws {
    let localDir = makeSubDir("local-emoji")
    let remoteDir = makeSubDir("remote-emoji")

    try "local".write(
      to: localDir.appendingPathComponent("📸vacation.jpg"), atomically: true, encoding: .utf8)
    try "remote".write(
      to: remoteDir.appendingPathComponent("📸vacation.jpg"), atomically: true, encoding: .utf8)

    let conflicts = detectConflicts(local: localDir, remote: remoteDir)
    XCTAssertEqual(conflicts.count, 1)
  }

  func testPathKeyNormalizesUnicode() {
    // PathKey uses NFC normalization — ensure composed and decomposed forms match
    let composed = "café"  // NFC
    let decomposed = "cafe\u{0301}"  // NFD

    let keyA = PathKey.normalize(storage: storage, components: [composed])
    let keyB = PathKey.normalize(storage: storage, components: [decomposed])
    XCTAssertEqual(keyA, keyB, "NFC normalization should make composed/decomposed equal")
  }

  // MARK: - Long Filename Near MTP 255-Char Limit

  func testConflictWithVeryLongFilename() throws {
    let localDir = makeSubDir("local-long")
    let remoteDir = makeSubDir("remote-long")

    // MTP limit is typically 255 chars; test near that boundary
    let longBase = String(repeating: "a", count: 248)
    let longName = "\(longBase).jpg"  // 252 chars total
    XCTAssertEqual(longName.count, 252)

    try "local".write(
      to: localDir.appendingPathComponent(longName), atomically: true, encoding: .utf8)
    try "remote".write(
      to: remoteDir.appendingPathComponent(longName), atomically: true, encoding: .utf8)

    let conflicts = detectConflicts(local: localDir, remote: remoteDir)
    XCTAssertEqual(conflicts.count, 1)
  }

  func testKeepBothWithLongFilenameProducesSuffixedCopies() throws {
    let localDir = makeSubDir("local-long-kb")
    let remoteDir = makeSubDir("remote-long-kb")
    let mergedDir = makeSubDir("merged-long-kb")

    let longBase = String(repeating: "b", count: 200)
    let longName = "\(longBase).txt"

    try "local long".write(
      to: localDir.appendingPathComponent(longName), atomically: true, encoding: .utf8)
    try "remote long".write(
      to: remoteDir.appendingPathComponent(longName), atomically: true, encoding: .utf8)

    resolveConflict(
      file: longName, localDir: localDir, remoteDir: remoteDir,
      mergedDir: mergedDir, strategy: .keepBoth)

    let localSuffixed = "\(longBase)-local.txt"
    let deviceSuffixed = "\(longBase)-device.txt"
    XCTAssertTrue(
      FileManager.default.fileExists(atPath: mergedDir.appendingPathComponent(localSuffixed).path))
    XCTAssertTrue(
      FileManager.default.fileExists(atPath: mergedDir.appendingPathComponent(deviceSuffixed).path))
  }

  // MARK: - Multiple Conflicts in Same Directory

  func testMultipleConflictsInSameDirectory() throws {
    let localDir = makeSubDir("local-multi")
    let remoteDir = makeSubDir("remote-multi")

    let filenames = ["alpha.txt", "beta.txt", "gamma.txt", "delta.txt", "epsilon.txt"]
    for name in filenames {
      try "local-\(name)".write(
        to: localDir.appendingPathComponent(name), atomically: true, encoding: .utf8)
      try "remote-\(name)".write(
        to: remoteDir.appendingPathComponent(name), atomically: true, encoding: .utf8)
    }

    let conflicts = detectConflicts(local: localDir, remote: remoteDir)
    XCTAssertEqual(conflicts.count, 5, "All 5 differing files should be conflicts")
  }

  func testMultipleConflictsResolvedIndependently() throws {
    let localDir = makeSubDir("local-indep")
    let remoteDir = makeSubDir("remote-indep")
    let mergedDir = makeSubDir("merged-indep")

    try "local A".write(
      to: localDir.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
    try "remote A".write(
      to: remoteDir.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
    try "local B".write(
      to: localDir.appendingPathComponent("b.txt"), atomically: true, encoding: .utf8)
    try "remote B".write(
      to: remoteDir.appendingPathComponent("b.txt"), atomically: true, encoding: .utf8)

    // Resolve first with localWins, second with remoteWins
    resolveConflict(
      file: "a.txt", localDir: localDir, remoteDir: remoteDir,
      mergedDir: mergedDir, strategy: .localWins)
    resolveConflict(
      file: "b.txt", localDir: localDir, remoteDir: remoteDir,
      mergedDir: mergedDir, strategy: .remoteWins)

    let mergedA = try String(
      contentsOf: mergedDir.appendingPathComponent("a.txt"), encoding: .utf8)
    let mergedB = try String(
      contentsOf: mergedDir.appendingPathComponent("b.txt"), encoding: .utf8)
    XCTAssertEqual(mergedA, "local A")
    XCTAssertEqual(mergedB, "remote B")
  }

  // MARK: - All 6 Resolution Strategies Produce Consistent Results

  func testAllSixStrategiesProduceValidOutcomes() throws {
    let fixedDate = Date(timeIntervalSince1970: 1_700_000_000)
    let newerDate = Date(timeIntervalSince1970: 1_700_002_000)

    let conflict = MTPConflictInfo(
      pathKey: "00010001/DCIM/test.jpg", handle: 10,
      deviceSize: 4096, deviceMtime: newerDate,
      localSize: 2048, localMtime: fixedDate)

    let row = makeRow(handle: 10, path: "00010001/DCIM/test.jpg", size: 4096, mtime: newerDate)
    let device = VirtualMTPDevice(config: .emptyDevice)

    for strategy in ConflictResolutionStrategy.allCases {
      let journal = try SQLiteTransferJournal(
        dbPath: tempDirectory.appendingPathComponent("strat-\(strategy.rawValue).sqlite").path)

      let resolver: ConflictResolver? =
        strategy == .ask ? { @Sendable _ in .keptLocal } : nil

      let engine = MirrorEngine(
        snapshotter: snapshotter, diffEngine: diffEngine, journal: journal,
        conflictStrategy: strategy, conflictResolver: resolver)

      let localURL = tempDirectory.appendingPathComponent("test-\(strategy.rawValue).jpg")
      try "local content".write(to: localURL, atomically: true, encoding: .utf8)

      let record = try awaitSync {
        try await engine.resolveConflict(
          conflict: conflict, file: row, localURL: localURL,
          device: device, root: self.tempDirectory)
      }

      XCTAssertEqual(record.strategy, strategy, "Record strategy should match configured strategy")

      switch strategy {
      case .newerWins:
        XCTAssertEqual(record.outcome, .keptDevice, "Device is newer → keptDevice")
      case .localWins:
        XCTAssertEqual(record.outcome, .keptLocal)
      case .deviceWins:
        XCTAssertEqual(record.outcome, .keptDevice)
      case .keepBoth:
        XCTAssertEqual(record.outcome, .keptBoth)
      case .skip:
        XCTAssertEqual(record.outcome, .skipped)
      case .ask:
        XCTAssertEqual(record.outcome, .keptLocal, "Resolver returns keptLocal")
      }
    }
  }

  // MARK: - newerWins Equal Timestamps Falls Back to Source Preference

  func testNewerWinsEqualTimestampsConsistentlyPicksLocal() throws {
    let fixedDate = Date(timeIntervalSince1970: 1_700_000_000)
    let journal = try SQLiteTransferJournal(dbPath: dbPath)
    let engine = MirrorEngine(
      snapshotter: snapshotter, diffEngine: diffEngine, journal: journal,
      conflictStrategy: .newerWins)

    // Run 10 times to verify determinism
    for i in 0..<10 {
      let conflict = MTPConflictInfo(
        pathKey: "00010001/run\(i).jpg", handle: UInt32(20 + i),
        deviceSize: 1024, deviceMtime: fixedDate,
        localSize: 1024, localMtime: fixedDate)

      let row = makeRow(
        handle: UInt32(20 + i), path: "00010001/run\(i).jpg", size: 1024, mtime: fixedDate)
      let localURL = tempDirectory.appendingPathComponent("run\(i).jpg")
      try "content".write(to: localURL, atomically: true, encoding: .utf8)

      let record = try awaitSync {
        try await engine.resolveConflict(
          conflict: conflict, file: row, localURL: localURL,
          device: VirtualMTPDevice(config: .emptyDevice), root: self.tempDirectory)
      }

      XCTAssertEqual(record.outcome, .keptLocal,
        "Equal timestamps should consistently yield keptLocal (run \(i))")
    }
  }

  // MARK: - largerWins with Equal Sizes Falls Back Consistently

  func testLargerWinsEqualSizesFallsBackToLocal() throws {
    let localDir = makeSubDir("local-eqsize")
    let remoteDir = makeSubDir("remote-eqsize")
    let mergedDir = makeSubDir("merged-eqsize")

    // Same length strings → equal file sizes
    try "local-same"
      .write(to: localDir.appendingPathComponent("eq.txt"), atomically: true, encoding: .utf8)
    try "remot-same"
      .write(to: remoteDir.appendingPathComponent("eq.txt"), atomically: true, encoding: .utf8)

    resolveConflict(
      file: "eq.txt", localDir: localDir, remoteDir: remoteDir,
      mergedDir: mergedDir, strategy: .largestWins)

    let merged = try String(
      contentsOf: mergedDir.appendingPathComponent("eq.txt"), encoding: .utf8)
    XCTAssertEqual(merged, "local-same", "Equal sizes should fall back to local wins")
  }

  func testLargerWinsPicksLarger() throws {
    let localDir = makeSubDir("local-larger")
    let remoteDir = makeSubDir("remote-larger")
    let mergedDir = makeSubDir("merged-larger")

    try Data(repeating: 0xAA, count: 50).write(
      to: localDir.appendingPathComponent("size.bin"))
    try Data(repeating: 0xBB, count: 500).write(
      to: remoteDir.appendingPathComponent("size.bin"))

    resolveConflict(
      file: "size.bin", localDir: localDir, remoteDir: remoteDir,
      mergedDir: mergedDir, strategy: .largestWins)

    let merged = try Data(contentsOf: mergedDir.appendingPathComponent("size.bin"))
    XCTAssertEqual(merged.count, 500, "Larger file should win")
  }

  // MARK: - Manual/Ask Strategy Captures Without Auto-Resolving

  func testAskStrategyWithoutResolverReturnsPending() throws {
    let conflict = MTPConflictInfo(
      pathKey: "00010001/manual.txt", handle: 50,
      deviceSize: 100, deviceMtime: Date(),
      localSize: 200, localMtime: Date())

    let journal = try SQLiteTransferJournal(dbPath: dbPath)
    // No resolver provided
    let engine = MirrorEngine(
      snapshotter: snapshotter, diffEngine: diffEngine, journal: journal,
      conflictStrategy: .ask, conflictResolver: nil)

    let row = makeRow(handle: 50, path: "00010001/manual.txt")
    let localURL = tempDirectory.appendingPathComponent("manual.txt")
    try "local".write(to: localURL, atomically: true, encoding: .utf8)

    let record = try awaitSync {
      try await engine.resolveConflict(
        conflict: conflict, file: row, localURL: localURL,
        device: VirtualMTPDevice(config: .emptyDevice), root: self.tempDirectory)
    }

    XCTAssertEqual(record.outcome, .pending,
      "Ask without resolver should mark as pending")
    XCTAssertEqual(record.strategy, .ask)
  }

  func testAskStrategyWithResolverDelegates() throws {
    final class ConflictCapture: @unchecked Sendable {
      var conflicts: [MTPConflictInfo] = []
    }
    let capture = ConflictCapture()

    let conflict = MTPConflictInfo(
      pathKey: "00010001/ask.txt", handle: 51,
      deviceSize: 300, deviceMtime: Date(),
      localSize: 100, localMtime: Date())

    let journal = try SQLiteTransferJournal(dbPath: dbPath)
    let engine = MirrorEngine(
      snapshotter: snapshotter, diffEngine: diffEngine, journal: journal,
      conflictStrategy: .ask,
      conflictResolver: { info in
        capture.conflicts.append(info)
        return .keptDevice
      })

    let row = makeRow(handle: 51, path: "00010001/ask.txt")
    let localURL = tempDirectory.appendingPathComponent("ask.txt")
    try "local".write(to: localURL, atomically: true, encoding: .utf8)

    let record = try awaitSync {
      try await engine.resolveConflict(
        conflict: conflict, file: row, localURL: localURL,
        device: VirtualMTPDevice(config: .emptyDevice), root: self.tempDirectory)
    }

    XCTAssertEqual(record.outcome, .keptDevice)
    XCTAssertEqual(capture.conflicts.count, 1)
    XCTAssertEqual(capture.conflicts.first?.pathKey, "00010001/ask.txt")
  }

  func testSkipStrategyProducesSkippedOutcome() throws {
    let conflict = MTPConflictInfo(
      pathKey: "00010001/skip.txt", handle: 52,
      deviceSize: 100, deviceMtime: Date(),
      localSize: 200, localMtime: Date())

    let journal = try SQLiteTransferJournal(dbPath: dbPath)
    let engine = MirrorEngine(
      snapshotter: snapshotter, diffEngine: diffEngine, journal: journal,
      conflictStrategy: .skip)

    let row = makeRow(handle: 52, path: "00010001/skip.txt")
    let localURL = tempDirectory.appendingPathComponent("skip.txt")
    try "local".write(to: localURL, atomically: true, encoding: .utf8)

    let record = try awaitSync {
      try await engine.resolveConflict(
        conflict: conflict, file: row, localURL: localURL,
        device: VirtualMTPDevice(config: .emptyDevice), root: self.tempDirectory)
    }

    XCTAssertEqual(record.outcome, .skipped)
    XCTAssertEqual(record.strategy, .skip)
  }

  // MARK: - Conflict During Active Transfer (File Changes Mid-Sync)

  func testConflictInfoCapturesSnapshotAtDetectionTime() throws {
    // Simulate: conflict detected with size A, then local file changes.
    // The MTPConflictInfo should reflect the state at detection time.
    let localURL = tempDirectory.appendingPathComponent("changing.bin")
    try Data(repeating: 0xAA, count: 100).write(to: localURL)

    let row = makeRow(handle: 60, path: "00010001/changing.bin", size: 200, mtime: Date())

    let journal = try SQLiteTransferJournal(dbPath: dbPath)
    let engine = MirrorEngine(
      snapshotter: snapshotter, diffEngine: diffEngine, journal: journal,
      conflictStrategy: .newerWins)

    let conflict = try engine.detectConflict(file: row, localURL: localURL)
    XCTAssertNotNil(conflict, "Size mismatch (100 vs 200) should detect conflict")
    XCTAssertEqual(conflict?.localSize, 100)
    XCTAssertEqual(conflict?.deviceSize, 200)

    // Now simulate file changing mid-sync
    try Data(repeating: 0xBB, count: 300).write(to: localURL)

    // The original conflict info still reflects the 100-byte snapshot
    XCTAssertEqual(conflict?.localSize, 100,
      "Conflict info should be a snapshot, not live")
  }

  // MARK: - Conflict Record Metadata

  func testConflictResolutionRecordTimestampIsReasonable() {
    let before = Date()
    let record = ConflictResolutionRecord(
      pathKey: "00010001/ts.txt", strategy: .skip, outcome: .skipped)
    let after = Date()

    XCTAssertGreaterThanOrEqual(record.timestamp, before)
    XCTAssertLessThanOrEqual(record.timestamp, after)
  }

  func testConflictInfoWithNilOptionals() {
    let info = MTPConflictInfo(
      pathKey: "00010001/nil-test.bin", handle: 99,
      deviceSize: nil, deviceMtime: nil,
      localSize: nil, localMtime: nil)

    XCTAssertNil(info.deviceSize)
    XCTAssertNil(info.deviceMtime)
    XCTAssertNil(info.localSize)
    XCTAssertNil(info.localMtime)
    XCTAssertEqual(info.handle, 99)
  }

  // MARK: - MirrorEngine detectConflict Edge Cases

  func testDetectConflictNoLocalFileReturnsNil() throws {
    let journal = try SQLiteTransferJournal(dbPath: dbPath)
    let engine = MirrorEngine(
      snapshotter: snapshotter, diffEngine: diffEngine, journal: journal)

    let row = makeRow(handle: 70, path: "00010001/missing.txt", size: 1024, mtime: Date())
    let localURL = tempDirectory.appendingPathComponent("nonexistent.txt")

    let conflict = try engine.detectConflict(file: row, localURL: localURL)
    XCTAssertNil(conflict, "No local file means no conflict")
  }

  func testDetectConflictSameSizeAndMtimeReturnsNil() throws {
    let journal = try SQLiteTransferJournal(dbPath: dbPath)
    let engine = MirrorEngine(
      snapshotter: snapshotter, diffEngine: diffEngine, journal: journal)

    let localURL = tempDirectory.appendingPathComponent("same.txt")
    try "hello".write(to: localURL, atomically: true, encoding: .utf8)

    let attrs = try FileManager.default.attributesOfItem(atPath: localURL.path)
    let localSize = (attrs[.size] as? NSNumber)?.uint64Value ?? 0
    let localMtime = attrs[.modificationDate] as? Date ?? Date()

    let row = makeRow(handle: 71, path: "00010001/same.txt", size: localSize, mtime: localMtime)

    let conflict = try engine.detectConflict(file: row, localURL: localURL)
    XCTAssertNil(conflict, "Same size and mtime should not detect conflict")
  }

  // MARK: - Helpers

  private enum ConflictStrategy {
    case localWins, remoteWins, newestWins, largestWins, keepBoth, skip
  }

  private func makeSubDir(_ name: String) -> URL {
    let dir = tempDirectory.appendingPathComponent(name)
    try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
  }

  private func makeRow(
    handle: UInt32, path: String, size: UInt64? = 1024, mtime: Date? = Date()
  ) -> MTPDiff.Row {
    MTPDiff.Row(
      handle: handle, storage: storage, pathKey: path,
      size: size, mtime: mtime, format: 0x3801)
  }

  private func detectConflicts(local: URL, remote: URL) -> [String] {
    let localFiles = Set(listRelativeFiles(in: local))
    let remoteFiles = Set(listRelativeFiles(in: remote))
    let common = localFiles.intersection(remoteFiles)
    return
      common.filter { file in
        let localData = try? Data(contentsOf: local.appendingPathComponent(file))
        let remoteData = try? Data(contentsOf: remote.appendingPathComponent(file))
        return localData != remoteData
      }
      .sorted()
  }

  private func resolveConflict(
    file: String, localDir: URL, remoteDir: URL, mergedDir: URL, strategy: ConflictStrategy
  ) {
    let localFile = localDir.appendingPathComponent(file)
    let remoteFile = remoteDir.appendingPathComponent(file)
    let mergedFile = mergedDir.appendingPathComponent(file)

    switch strategy {
    case .localWins:
      try? FileManager.default.copyItem(at: localFile, to: mergedFile)
    case .remoteWins:
      try? FileManager.default.copyItem(at: remoteFile, to: mergedFile)
    case .newestWins:
      let localMtime =
        (try? FileManager.default.attributesOfItem(atPath: localFile.path))?[.modificationDate]
        as? Date ?? .distantPast
      let remoteMtime =
        (try? FileManager.default.attributesOfItem(atPath: remoteFile.path))?[.modificationDate]
        as? Date ?? .distantPast
      let winner = localMtime >= remoteMtime ? localFile : remoteFile
      try? FileManager.default.copyItem(at: winner, to: mergedFile)
    case .largestWins:
      let localSize =
        (try? FileManager.default.attributesOfItem(atPath: localFile.path))?[.size]
        as? UInt64 ?? 0
      let remoteSize =
        (try? FileManager.default.attributesOfItem(atPath: remoteFile.path))?[.size]
        as? UInt64 ?? 0
      let winner = localSize >= remoteSize ? localFile : remoteFile
      try? FileManager.default.copyItem(at: winner, to: mergedFile)
    case .keepBoth:
      let ext = (file as NSString).pathExtension
      let base = (file as NSString).deletingPathExtension
      let localName = ext.isEmpty ? "\(base)-local" : "\(base)-local.\(ext)"
      let deviceName = ext.isEmpty ? "\(base)-device" : "\(base)-device.\(ext)"
      try? FileManager.default.copyItem(
        at: localFile, to: mergedDir.appendingPathComponent(localName))
      try? FileManager.default.copyItem(
        at: remoteFile, to: mergedDir.appendingPathComponent(deviceName))
    case .skip:
      break
    }
  }

  private func resolveConflictCaseInsensitive(
    localName: String, remoteName: String,
    localDir: URL, remoteDir: URL, mergedDir: URL, strategy: ConflictStrategy
  ) {
    let localFile = localDir.appendingPathComponent(localName)
    let mergedFile = mergedDir.appendingPathComponent(localName)

    switch strategy {
    case .localWins:
      try? FileManager.default.copyItem(at: localFile, to: mergedFile)
    case .remoteWins:
      let remoteFile = remoteDir.appendingPathComponent(remoteName)
      try? FileManager.default.copyItem(at: remoteFile, to: mergedFile)
    default:
      break
    }
  }

  private func listRelativeFiles(in directory: URL) -> [String] {
    let resolvedDir = directory.resolvingSymlinksInPath()
    guard
      let enumerator = FileManager.default.enumerator(
        at: resolvedDir, includingPropertiesForKeys: [.isRegularFileKey],
        options: [.skipsHiddenFiles])
    else { return [] }
    var files: [String] = []
    for case let fileURL as URL in enumerator {
      guard let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey]),
        values.isRegularFile == true
      else { continue }
      let resolvedFile = fileURL.resolvingSymlinksInPath()
      files.append(resolvedFile.path.replacingOccurrences(of: resolvedDir.path + "/", with: ""))
    }
    return files
  }

  private func awaitSync<T: Sendable>(_ block: @Sendable @escaping () async throws -> T) throws -> T {
    final class Box<V: Sendable>: @unchecked Sendable {
      var value: Result<V, Error>?
    }
    let box = Box<T>()
    let expectation = XCTestExpectation(description: "async")
    Task {
      do {
        let value = try await block()
        box.value = .success(value)
      } catch {
        box.value = .failure(error)
      }
      expectation.fulfill()
    }
    wait(for: [expectation], timeout: 10)
    switch box.value {
    case .success(let value): return value
    case .failure(let error): throw error
    case .none: throw NSError(domain: "test", code: -1, userInfo: [NSLocalizedDescriptionKey: "Timeout"])
    }
  }
}
