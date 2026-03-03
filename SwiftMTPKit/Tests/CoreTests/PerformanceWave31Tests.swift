// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import XCTest

@testable import SwiftMTPCore
import SwiftMTPIndex
import SwiftMTPQuirks
import SwiftMTPSync
import SwiftMTPTestKit

// MARK: - Wave 31 Performance Benchmark Tests

final class PerformanceWave31Tests: XCTestCase {

  // MARK: - 1. PTP Container Encode/Decode Throughput (10,000 ops)

  func testPTPContainerEncodeDecodeThroughput10K() {
    let iterations = 10_000
    var buffer = [UInt8](repeating: 0, count: 64)

    let start = CFAbsoluteTimeGetCurrent()
    for i in 0..<iterations {
      let container = PTPContainer(
        length: 20,
        type: PTPContainer.Kind.command.rawValue,
        code: PTPOp.getObjectHandles.rawValue,
        txid: UInt32(i),
        params: [0x0001_0001, 0, 0]
      )
      buffer.withUnsafeMutableBufferPointer { ptr in
        _ = container.encode(into: ptr.baseAddress!)
      }
    }
    let elapsed = CFAbsoluteTimeGetCurrent() - start

    // 10x headroom: 10K encodes should finish well under 5s even in debug
    XCTAssertLessThan(
      elapsed, 5.0,
      "PTP container encode 10K took \(elapsed)s, expected <5s")
    let opsPerSec = Double(iterations) / elapsed
    XCTAssertGreaterThan(
      opsPerSec, 2000,
      "PTP container encode ops/sec: \(Int(opsPerSec)), expected >2000")
  }

  // MARK: - 2. PTP String Encode/Decode with Unicode (1,000 ops)

  func testPTPStringEncodeDecodeUnicode1K() {
    let iterations = 1_000
    let testStrings = [
      "DCIM/Camera/IMG_20250101_120000.jpg",
      "フォルダ/写真/テスト画像.png",
      "Ünïcödé/Spëcîäl/Chàrâctérs.mp4",
      "日本語/中文/한국어/file.dat",
      "emoji_🎉_📸_🌍/photo.heic",
    ]

    let start = CFAbsoluteTimeGetCurrent()
    for i in 0..<iterations {
      let str = testStrings[i % testStrings.count]
      let encoded = PTPString.encode(str)
      var offset = 0
      let decoded = PTPString.parse(from: encoded, at: &offset)
      XCTAssertNotNil(decoded)
    }
    let elapsed = CFAbsoluteTimeGetCurrent() - start

    XCTAssertLessThan(
      elapsed, 5.0,
      "PTP string unicode encode/decode 1K took \(elapsed)s, expected <5s")
  }

  // MARK: - 3. ObjectInfo Serialization Batch (1,000 objects)

  func testObjectInfoSerializationBatch1K() {
    let iterations = 1_000

    let start = CFAbsoluteTimeGetCurrent()
    for i in 0..<iterations {
      _ = PTPObjectInfoDataset.encode(
        storageID: 0x0001_0001,
        parentHandle: UInt32(i / 10 + 1),
        format: 0x3801,
        size: UInt64(i * 1024),
        name: "photo_\(i).jpg"
      )
    }
    let elapsed = CFAbsoluteTimeGetCurrent() - start

    XCTAssertLessThan(
      elapsed, 5.0,
      "ObjectInfo serialization 1K took \(elapsed)s, expected <5s")
    let opsPerSec = Double(iterations) / elapsed
    XCTAssertGreaterThan(
      opsPerSec, 200,
      "ObjectInfo serialization ops/sec: \(Int(opsPerSec)), expected >200")
  }

  // MARK: - 4. SQLite Index Bulk Insert (10,000 objects)

  func testSQLiteIndexBulkInsert10K() async throws {
    let tempDir = FileManager.default.temporaryDirectory
      .appendingPathComponent("perf-w31-insert-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let dbPath = tempDir.appendingPathComponent("bench.sqlite").path
    let index = try SQLiteLiveIndex(path: dbPath)

    let objectCount = 10_000
    let deviceId = "perf-w31-device"
    let storageId: UInt32 = 0x0001_0001

    var objects: [IndexedObject] = []
    objects.reserveCapacity(objectCount)
    for i in 0..<objectCount {
      objects.append(
        IndexedObject(
          deviceId: deviceId,
          storageId: storageId,
          handle: MTPObjectHandle(i + 1),
          parentHandle: i > 0 ? MTPObjectHandle(i / 10 + 1) : nil,
          name: "file_\(i).jpg",
          pathKey: "/DCIM/batch/file_\(i).jpg",
          sizeBytes: UInt64(i * 512),
          mtime: Date(),
          formatCode: 0x3801,
          isDirectory: false,
          changeCounter: 1
        ))
    }

    let start = CFAbsoluteTimeGetCurrent()
    try await index.upsertObjects(objects, deviceId: deviceId)
    let elapsed = CFAbsoluteTimeGetCurrent() - start

    // 10K inserts should complete in well under 30s even in debug
    XCTAssertLessThan(
      elapsed, 30.0,
      "SQLite bulk insert 10K took \(elapsed)s, expected <30s")
    let objPerSec = Double(objectCount) / elapsed
    XCTAssertGreaterThan(
      objPerSec, 300,
      "SQLite insert rate: \(Int(objPerSec)) obj/s, expected >300 obj/s")
  }

  // MARK: - 5. SQLite Index Lookup by Handle (10,000 lookups)

  func testSQLiteIndexLookupByHandle10K() async throws {
    let tempDir = FileManager.default.temporaryDirectory
      .appendingPathComponent("perf-w31-lookup-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let dbPath = tempDir.appendingPathComponent("bench.sqlite").path
    let index = try SQLiteLiveIndex(path: dbPath)

    let objectCount = 1_000
    let deviceId = "perf-w31-lookup"
    let storageId: UInt32 = 0x0001_0001

    // Seed the index
    var objects: [IndexedObject] = []
    objects.reserveCapacity(objectCount)
    for i in 0..<objectCount {
      objects.append(
        IndexedObject(
          deviceId: deviceId,
          storageId: storageId,
          handle: MTPObjectHandle(i + 1),
          parentHandle: nil,
          name: "lookup_\(i).jpg",
          pathKey: "/DCIM/lookup_\(i).jpg",
          sizeBytes: UInt64(i * 1024),
          mtime: Date(),
          formatCode: 0x3801,
          isDirectory: false,
          changeCounter: 1
        ))
    }
    try await index.upsertObjects(objects, deviceId: deviceId)

    // Perform 10,000 lookups (cycling through handles)
    let lookupCount = 10_000
    let start = CFAbsoluteTimeGetCurrent()
    for i in 0..<lookupCount {
      let handle = MTPObjectHandle((i % objectCount) + 1)
      let result = try await index.object(deviceId: deviceId, handle: handle)
      XCTAssertNotNil(result)
    }
    let elapsed = CFAbsoluteTimeGetCurrent() - start

    XCTAssertLessThan(
      elapsed, 30.0,
      "SQLite lookup 10K took \(elapsed)s, expected <30s")
    let lookupsPerSec = Double(lookupCount) / elapsed
    XCTAssertGreaterThan(
      lookupsPerSec, 500,
      "SQLite lookup rate: \(Int(lookupsPerSec)) ops/s, expected >500 ops/s")
  }

  // MARK: - 6. SQLite Index Path Resolution (1,000 paths via children)

  func testSQLiteIndexPathResolution1K() async throws {
    let tempDir = FileManager.default.temporaryDirectory
      .appendingPathComponent("perf-w31-path-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let dbPath = tempDir.appendingPathComponent("bench.sqlite").path
    let index = try SQLiteLiveIndex(path: dbPath)

    let deviceId = "perf-w31-path"
    let storageId: UInt32 = 0x0001_0001

    // Create a tree: 10 parent dirs, each with 100 children
    var objects: [IndexedObject] = []
    var handle: MTPObjectHandle = 1

    for dirIdx in 0..<10 {
      let dirHandle = handle
      objects.append(
        IndexedObject(
          deviceId: deviceId,
          storageId: storageId,
          handle: dirHandle,
          parentHandle: nil,
          name: "dir_\(dirIdx)",
          pathKey: "/dir_\(dirIdx)",
          sizeBytes: nil,
          mtime: Date(),
          formatCode: 0x3001,
          isDirectory: true,
          changeCounter: 1
        ))
      handle += 1

      for fileIdx in 0..<100 {
        objects.append(
          IndexedObject(
            deviceId: deviceId,
            storageId: storageId,
            handle: handle,
            parentHandle: dirHandle,
            name: "file_\(fileIdx).jpg",
            pathKey: "/dir_\(dirIdx)/file_\(fileIdx).jpg",
            sizeBytes: UInt64(fileIdx * 1024),
            mtime: Date(),
            formatCode: 0x3801,
            isDirectory: false,
            changeCounter: 1
          ))
        handle += 1
      }
    }
    try await index.upsertObjects(objects, deviceId: deviceId)

    // Resolve paths: list children for each directory 100 times = 1,000 resolutions
    let iterations = 100
    let start = CFAbsoluteTimeGetCurrent()
    for _ in 0..<iterations {
      for dirIdx in 0..<10 {
        let dirHandle = MTPObjectHandle(dirIdx * 101 + 1)
        let children = try await index.children(
          deviceId: deviceId, storageId: storageId, parentHandle: dirHandle)
        XCTAssertEqual(children.count, 100)
      }
    }
    let elapsed = CFAbsoluteTimeGetCurrent() - start

    let resolutions = iterations * 10
    XCTAssertLessThan(
      elapsed, 30.0,
      "SQLite path resolution 1K took \(elapsed)s, expected <30s")
    let opsPerSec = Double(resolutions) / elapsed
    XCTAssertGreaterThan(
      opsPerSec, 100,
      "SQLite path resolution rate: \(Int(opsPerSec)) ops/s, expected >100 ops/s")
  }

  // MARK: - 7. PathKey Normalization Throughput (10,000 paths)

  func testPathKeyNormalizationThroughput10K() {
    let iterations = 10_000
    let components = [
      ["DCIM", "Camera", "IMG_20250101.jpg"],
      ["Music", "Albums", "トラック1.mp3"],
      ["Documents", "Wörk", "Ünïcödé.pdf"],
      ["Pictures", "2025", "photo_001.png"],
      ["Downloads", "archive", "data.zip"],
    ]

    let start = CFAbsoluteTimeGetCurrent()
    for i in 0..<iterations {
      let comps = components[i % components.count]
      let key = PathKey.normalize(storage: 0x0001_0001, components: comps)
      XCTAssertFalse(key.isEmpty)
    }
    let elapsed = CFAbsoluteTimeGetCurrent() - start

    XCTAssertLessThan(
      elapsed, 60.0,
      "PathKey normalization 10K took \(elapsed)s, expected <60s")
    let opsPerSec = Double(iterations) / elapsed
    XCTAssertGreaterThan(
      opsPerSec, 200,
      "PathKey normalization ops/sec: \(Int(opsPerSec)), expected >200")
  }

  // MARK: - 8. QuirkDatabase Lookup Performance (1,000 lookups)

  func testQuirkDatabaseLookup1K() {
    // Build a database with 5,000 synthetic entries
    let entryCount = 5_000
    var entries: [DeviceQuirk] = []
    entries.reserveCapacity(entryCount)
    for i in 0..<entryCount {
      let vid = UInt16(truncatingIfNeeded: (i / 256) + 1)
      let pid = UInt16(truncatingIfNeeded: (i % 256) + 1)
      entries.append(
        DeviceQuirk(
          id: "w31-device-\(i)",
          vid: vid,
          pid: pid,
          maxChunkBytes: 1_048_576
        ))
    }
    let db = QuirkDatabase(schemaVersion: "2.0", entries: entries)

    let lookupCount = 1_000
    let start = CFAbsoluteTimeGetCurrent()
    for i in 0..<lookupCount {
      let idx = (i * 7) % entryCount  // spread lookups across the DB
      let vid = UInt16(truncatingIfNeeded: (idx / 256) + 1)
      let pid = UInt16(truncatingIfNeeded: (idx % 256) + 1)
      let result = db.match(
        vid: vid, pid: pid,
        bcdDevice: nil, ifaceClass: nil, ifaceSubclass: nil, ifaceProtocol: nil
      )
      XCTAssertNotNil(result)
    }
    let elapsed = CFAbsoluteTimeGetCurrent() - start

    XCTAssertLessThan(
      elapsed, 60.0,
      "QuirkDatabase lookup 1K took \(elapsed)s, expected <60s")
    let lookupsPerSec = Double(lookupCount) / elapsed
    XCTAssertGreaterThan(
      lookupsPerSec, 10,
      "QuirkDatabase lookup ops/sec: \(Int(lookupsPerSec)), expected >10")
  }

  // MARK: - 9. Diff Engine Computation (5K added + 5K deleted)

  func testDiffEngineComputation5KAdded5KDeleted() async throws {
    let tempDir = FileManager.default.temporaryDirectory
      .appendingPathComponent("perf-w31-diff-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let dbPath = tempDir.appendingPathComponent("diff.sqlite").path
    let diffEngine = try DiffEngine(dbPath: dbPath)

    // Manually create the objects table & populate two generations
    let db = try SQLiteDB(path: dbPath)
    try db.exec(
      """
        CREATE TABLE IF NOT EXISTS objects(
            deviceId TEXT NOT NULL,
            storageId INTEGER NOT NULL,
            handle INTEGER NOT NULL,
            parentHandle INTEGER,
            name TEXT NOT NULL,
            pathKey TEXT NOT NULL,
            size INTEGER,
            mtime INTEGER,
            format INTEGER NOT NULL,
            gen INTEGER NOT NULL,
            tombstone INTEGER NOT NULL DEFAULT 0,
            PRIMARY KEY(deviceId, handle, gen)
        )
      """)

    let deviceId = "diff-bench-device"
    let now = Int(Date().timeIntervalSince1970)

    // Gen 1: 5,000 objects (these will be "deleted" in gen 2)
    try db.exec("BEGIN TRANSACTION")
    for i in 0..<5_000 {
      try db.exec(
        """
          INSERT INTO objects (deviceId, storageId, handle, name, pathKey, size, mtime, format, gen, tombstone)
          VALUES ('\(deviceId)', 65537, \(i + 1), 'old_\(i).jpg', '/DCIM/old_\(i).jpg', \(i * 1024), \(now), 14337, 1, 0)
        """)
    }
    try db.exec("COMMIT")

    // Gen 2: 5,000 different objects (these will be "added" relative to gen 1)
    try db.exec("BEGIN TRANSACTION")
    for i in 0..<5_000 {
      try db.exec(
        """
          INSERT INTO objects (deviceId, storageId, handle, name, pathKey, size, mtime, format, gen, tombstone)
          VALUES ('\(deviceId)', 65537, \(i + 10001), 'new_\(i).jpg', '/DCIM/new_\(i).jpg', \(i * 2048), \(now), 14337, 2, 0)
        """)
    }
    try db.exec("COMMIT")

    // Measure diff computation
    let start = CFAbsoluteTimeGetCurrent()
    let result = try await diffEngine.diff(
      deviceId: MTPDeviceID(raw: deviceId), oldGen: 1, newGen: 2)
    let elapsed = CFAbsoluteTimeGetCurrent() - start

    XCTAssertEqual(
      result.added.count, 5_000,
      "Expected 5000 added, got \(result.added.count)")
    XCTAssertEqual(
      result.removed.count, 5_000,
      "Expected 5000 removed, got \(result.removed.count)")
    XCTAssertLessThan(
      elapsed, 30.0,
      "Diff engine computation took \(elapsed)s, expected <30s")
  }

  // MARK: - 10. FallbackLadder Evaluation (100 iterations)

  func testFallbackLadderEvaluation100() async throws {
    let iterations = 100

    let start = CFAbsoluteTimeGetCurrent()
    for i in 0..<iterations {
      let rungs: [FallbackRung<Int>] = [
        FallbackRung(name: "primary") { return i }
      ]
      let result = try await FallbackLadder.execute(rungs)
      XCTAssertEqual(result.value, i)
    }
    let elapsed = CFAbsoluteTimeGetCurrent() - start

    XCTAssertLessThan(
      elapsed, 5.0,
      "FallbackLadder 100 iterations took \(elapsed)s, expected <5s")
    let opsPerSec = Double(iterations) / elapsed
    XCTAssertGreaterThan(
      opsPerSec, 20,
      "FallbackLadder ops/sec: \(Int(opsPerSec)), expected >20")
  }

  func testFallbackLadderWithFailingRungs100() async throws {
    let iterations = 100

    let start = CFAbsoluteTimeGetCurrent()
    for _ in 0..<iterations {
      let rungs: [FallbackRung<String>] = [
        FallbackRung(name: "fail1") { throw NSError(domain: "test", code: 1) },
        FallbackRung(name: "fail2") { throw NSError(domain: "test", code: 2) },
        FallbackRung(name: "succeed") { return "ok" },
      ]
      let result = try await FallbackLadder.execute(rungs)
      XCTAssertEqual(result.winningRung, "succeed")
      XCTAssertEqual(result.attempts.count, 3)
    }
    let elapsed = CFAbsoluteTimeGetCurrent() - start

    XCTAssertLessThan(
      elapsed, 10.0,
      "FallbackLadder with failures 100 iterations took \(elapsed)s, expected <10s")
  }
}
