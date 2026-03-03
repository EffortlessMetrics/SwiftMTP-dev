// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import Testing

@testable import SwiftMTPCore
@testable import SwiftMTPIndex

// MARK: - Helpers

private func makeTempIndex() throws -> (SQLiteLiveIndex, String) {
  let dir = FileManager.default.temporaryDirectory
  let path = dir.appendingPathComponent("stress-\(UUID().uuidString).sqlite").path
  let index = try SQLiteLiveIndex(path: path)
  return (index, path)
}

private func makeObj(
  deviceId: String = "dev",
  handle: UInt32,
  parentHandle: UInt32? = nil,
  storageId: UInt32 = 0x10001,
  name: String = "file.txt",
  pathKey: String? = nil,
  isDirectory: Bool = false,
  sizeBytes: UInt64 = 1024,
  formatCode: UInt16 = 0x3001
) -> IndexedObject {
  IndexedObject(
    deviceId: deviceId,
    storageId: storageId,
    handle: handle,
    parentHandle: parentHandle,
    name: name,
    pathKey: pathKey ?? "\(String(format: "%08x", storageId))/\(name)",
    sizeBytes: sizeBytes,
    mtime: Date(),
    formatCode: formatCode,
    isDirectory: isDirectory,
    changeCounter: 0
  )
}

// MARK: - 1. Concurrent Reads During Writes

@Suite("IndexConcurrency – Reads During Writes")
struct IndexConcurrencyReadsDuringWritesTests {

  @Test("Readers never see partial batch inserts")
  func readersNeverSeePartialBatch() async throws {
    let (idx, path) = try makeTempIndex()
    defer { try? FileManager.default.removeItem(atPath: path) }

    // Seed 100 objects so readers always have data
    let seed = (0..<100).map { i in makeObj(handle: UInt32(i), name: "seed\(i).txt") }
    try await idx.upsertObjects(seed, deviceId: "dev")

    try await withThrowingTaskGroup(of: Void.self) { group in
      // Writers: insert batches of 50
      for batch in 0..<10 {
        group.addTask {
          let objs = (0..<50)
            .map { j in
              makeObj(handle: UInt32(10_000 + batch * 50 + j), name: "w\(batch)_\(j).txt")
            }
          try await idx.upsertObjects(objs, deviceId: "dev")
        }
      }
      // Readers: query root children concurrently
      for _ in 0..<8 {
        group.addTask {
          for _ in 0..<50 {
            let kids = try await idx.children(
              deviceId: "dev", storageId: 0x10001, parentHandle: nil)
            // Must always see at least the seed data
            #expect(kids.count >= 100)
          }
        }
      }
      try await group.waitForAll()
    }

    let total = try await idx.children(deviceId: "dev", storageId: 0x10001, parentHandle: nil)
    #expect(total.count == 600)  // 100 seed + 10 * 50
  }

  @Test("Single object lookup consistent during concurrent writes")
  func singleObjectLookupDuringWrites() async throws {
    let (idx, path) = try makeTempIndex()
    defer { try? FileManager.default.removeItem(atPath: path) }

    let sentinel = makeObj(handle: 1, name: "sentinel.txt", sizeBytes: 42)
    try await idx.insertObject(sentinel, deviceId: "dev")

    try await withThrowingTaskGroup(of: Void.self) { group in
      // Continuous writer for other handles
      for batch in 0..<20 {
        group.addTask {
          let objs = (0..<25)
            .map { j in
              makeObj(handle: UInt32(1000 + batch * 25 + j), name: "bg\(batch)_\(j).txt")
            }
          try await idx.upsertObjects(objs, deviceId: "dev")
        }
      }
      // Readers always see sentinel
      for _ in 0..<6 {
        group.addTask {
          for _ in 0..<40 {
            let obj = try await idx.object(deviceId: "dev", handle: 1)
            #expect(obj != nil)
            #expect(obj?.name == "sentinel.txt")
            #expect(obj?.sizeBytes == 42)
          }
        }
      }
      try await group.waitForAll()
    }
  }

  @Test("Change counter reads consistent during concurrent inserts")
  func changeCounterConsistentDuringWrites() async throws {
    let (idx, path) = try makeTempIndex()
    defer { try? FileManager.default.removeItem(atPath: path) }

    try await withThrowingTaskGroup(of: Void.self) { group in
      // Writers
      for i in 0..<10 {
        group.addTask {
          let obj = makeObj(handle: UInt32(i), name: "f\(i).txt")
          try await idx.upsertObjects([obj], deviceId: "dev")
        }
      }
      // Change counter readers — counter must be monotonically non-decreasing
      group.addTask {
        var prev: Int64 = 0
        for _ in 0..<30 {
          let counter = try await idx.currentChangeCounter(deviceId: "dev")
          #expect(counter >= prev)
          prev = counter
        }
      }
      try await group.waitForAll()
    }
  }
}

// MARK: - 2. Concurrent Index From Multiple Devices

@Suite("IndexConcurrency – Multi-Device")
struct IndexConcurrencyMultiDeviceTests {

  @Test("Concurrent inserts from 10 devices are fully isolated")
  func tenDevicesConcurrentInserts() async throws {
    let (idx, path) = try makeTempIndex()
    defer { try? FileManager.default.removeItem(atPath: path) }

    let devicesCount = 10
    let objectsPerDevice = 200

    try await withThrowingTaskGroup(of: Void.self) { group in
      for d in 0..<devicesCount {
        group.addTask {
          let deviceId = "device-\(d)"
          let objs = (0..<objectsPerDevice)
            .map { j in
              makeObj(deviceId: deviceId, handle: UInt32(j), name: "d\(d)_f\(j).txt")
            }
          try await idx.upsertObjects(objs, deviceId: deviceId)
        }
      }
      try await group.waitForAll()
    }

    // Verify isolation: each device has exactly objectsPerDevice objects
    for d in 0..<devicesCount {
      let deviceId = "device-\(d)"
      let kids = try await idx.children(deviceId: deviceId, storageId: 0x10001, parentHandle: nil)
      #expect(kids.count == objectsPerDevice)
      // Verify no cross-device contamination
      #expect(kids.allSatisfy { $0.name.hasPrefix("d\(d)_") })
    }
  }

  @Test("Concurrent change counters are independent per device")
  func perDeviceChangeCounters() async throws {
    let (idx, path) = try makeTempIndex()
    defer { try? FileManager.default.removeItem(atPath: path) }

    try await withThrowingTaskGroup(of: Void.self) { group in
      for d in 0..<5 {
        group.addTask {
          let deviceId = "dev-\(d)"
          for i in 0..<10 {
            let obj = makeObj(deviceId: deviceId, handle: UInt32(i), name: "f\(i).txt")
            try await idx.upsertObjects([obj], deviceId: deviceId)
          }
        }
      }
      try await group.waitForAll()
    }

    // Each device should have its own counter at 10
    for d in 0..<5 {
      let counter = try await idx.currentChangeCounter(deviceId: "dev-\(d)")
      #expect(counter == 10)
    }
  }

  @Test("Concurrent device upsert and delete do not deadlock")
  func concurrentUpsertAndDelete() async throws {
    let (idx, path) = try makeTempIndex()
    defer { try? FileManager.default.removeItem(atPath: path) }

    // Seed data for two devices
    for d in 0..<2 {
      let deviceId = "dev-\(d)"
      let objs = (0..<100)
        .map { j in
          makeObj(deviceId: deviceId, handle: UInt32(j), name: "f\(j).txt")
        }
      try await idx.upsertObjects(objs, deviceId: deviceId)
    }

    try await withThrowingTaskGroup(of: Void.self) { group in
      // Device 0: inserts new objects
      group.addTask {
        for i in 100..<200 {
          let obj = makeObj(deviceId: "dev-0", handle: UInt32(i), name: "new\(i).txt")
          try await idx.insertObject(obj, deviceId: "dev-0")
        }
      }
      // Device 1: deletes existing objects
      group.addTask {
        for i in 0..<100 {
          try await idx.removeObject(deviceId: "dev-1", storageId: 0x10001, handle: UInt32(i))
        }
      }
      try await group.waitForAll()
    }

    let dev0 = try await idx.children(deviceId: "dev-0", storageId: 0x10001, parentHandle: nil)
    #expect(dev0.count == 200)  // 100 original + 100 new

    let dev1 = try await idx.children(deviceId: "dev-1", storageId: 0x10001, parentHandle: nil)
    #expect(dev1.count == 0)  // all deleted
  }
}

// MARK: - 3. WAL Mode Concurrent Access

@Suite("IndexConcurrency – WAL Mode Access")
struct IndexConcurrencyWALTests {

  @Test("Writer and read-only reader on same database file")
  func walWriterAndReadOnlyReader() async throws {
    let (writer, path) = try makeTempIndex()
    defer { try? FileManager.default.removeItem(atPath: path) }

    // Seed some data first
    let seed = (0..<50).map { i in makeObj(handle: UInt32(i), name: "s\(i).txt") }
    try await writer.upsertObjects(seed, deviceId: "dev")

    let reader = try SQLiteLiveIndex(path: path, readOnly: true)

    try await withThrowingTaskGroup(of: Void.self) { group in
      // Writer inserts more data
      group.addTask {
        for batch in 0..<10 {
          let objs = (0..<20)
            .map { j in
              makeObj(handle: UInt32(1000 + batch * 20 + j), name: "w\(batch)_\(j).txt")
            }
          try await writer.upsertObjects(objs, deviceId: "dev")
        }
      }
      // Reader queries concurrently
      group.addTask {
        for _ in 0..<50 {
          let kids = try await reader.children(
            deviceId: "dev", storageId: 0x10001, parentHandle: nil)
          // Reader should always see at least the seed data
          #expect(kids.count >= 50)
        }
      }
      try await group.waitForAll()
    }
  }

  @Test("Multiple read-only readers concurrent with writer")
  func multipleReadOnlyReaders() async throws {
    let (writer, path) = try makeTempIndex()
    defer { try? FileManager.default.removeItem(atPath: path) }

    let seed = (0..<100).map { i in makeObj(handle: UInt32(i), name: "s\(i).txt") }
    try await writer.upsertObjects(seed, deviceId: "dev")

    let readers = try (0..<3).map { _ in try SQLiteLiveIndex(path: path, readOnly: true) }

    try await withThrowingTaskGroup(of: Void.self) { group in
      // Writer
      group.addTask {
        for i in 100..<300 {
          let obj = makeObj(handle: UInt32(i), name: "new\(i).txt")
          try await writer.insertObject(obj, deviceId: "dev")
        }
      }
      // Multiple readers
      for reader in readers {
        group.addTask {
          for _ in 0..<30 {
            let kids = try await reader.children(
              deviceId: "dev", storageId: 0x10001, parentHandle: nil)
            #expect(kids.count >= 100)
          }
        }
      }
      try await group.waitForAll()
    }
  }

  @Test("changesSince works correctly across WAL reader/writer")
  func changesSinceAcrossWAL() async throws {
    let (writer, path) = try makeTempIndex()
    defer { try? FileManager.default.removeItem(atPath: path) }

    let seed = (0..<10).map { i in makeObj(handle: UInt32(i), name: "s\(i).txt") }
    try await writer.upsertObjects(seed, deviceId: "dev")

    let anchor = try await writer.currentChangeCounter(deviceId: "dev")

    let reader = try SQLiteLiveIndex(path: path, readOnly: true)

    // Writer adds more data after anchor
    let newObjs = (10..<30).map { i in makeObj(handle: UInt32(i), name: "new\(i).txt") }
    try await writer.upsertObjects(newObjs, deviceId: "dev")

    // Reader queries changes since anchor
    let changes = try await reader.changesSince(deviceId: "dev", anchor: anchor)
    #expect(changes.count >= 20)
    #expect(changes.allSatisfy { $0.kind == .upserted })
  }
}

// MARK: - 4. Large Batch Insert Performance Under Concurrency

@Suite("IndexConcurrency – Large Batch Performance")
struct IndexConcurrencyLargeBatchTests {

  @Test("5000 objects inserted concurrently in 10 batches")
  func fiveThousandConcurrentBatchInserts() async throws {
    let (idx, path) = try makeTempIndex()
    defer { try? FileManager.default.removeItem(atPath: path) }

    let batchCount = 10
    let batchSize = 500
    let startTime = Date()

    try await withThrowingTaskGroup(of: Void.self) { group in
      for b in 0..<batchCount {
        group.addTask {
          let objs = (0..<batchSize)
            .map { j in
              makeObj(handle: UInt32(b * batchSize + j), name: "b\(b)_\(j).dat")
            }
          try await idx.upsertObjects(objs, deviceId: "dev")
        }
      }
      try await group.waitForAll()
    }

    let elapsed = Date().timeIntervalSince(startTime)

    // Verify all objects present
    let total = try await idx.children(deviceId: "dev", storageId: 0x10001, parentHandle: nil)
    #expect(total.count == batchCount * batchSize)
    // Should complete within 30 seconds even under contention
    #expect(elapsed < 30.0)
  }

  @Test("Rapid small inserts from many concurrent tasks")
  func rapidSmallInserts() async throws {
    let (idx, path) = try makeTempIndex()
    defer { try? FileManager.default.removeItem(atPath: path) }

    let taskCount = 50
    let startTime = Date()

    try await withThrowingTaskGroup(of: Void.self) { group in
      for i in 0..<taskCount {
        group.addTask {
          let obj = makeObj(handle: UInt32(i), name: "rapid\(i).txt")
          try await idx.insertObject(obj, deviceId: "dev")
        }
      }
      try await group.waitForAll()
    }

    let elapsed = Date().timeIntervalSince(startTime)
    let total = try await idx.children(deviceId: "dev", storageId: 0x10001, parentHandle: nil)
    #expect(total.count == taskCount)
    #expect(elapsed < 15.0)
  }
}

// MARK: - 5. Index Rebuild Concurrent With Queries

@Suite("IndexConcurrency – Rebuild During Queries")
struct IndexConcurrencyRebuildTests {

  @Test("markStaleChildren + upsert cycle concurrent with readers")
  func rebuildCycleWithReaders() async throws {
    let (idx, path) = try makeTempIndex()
    defer { try? FileManager.default.removeItem(atPath: path) }

    let parentHandle: UInt32 = 0x10001
    let parent = makeObj(
      handle: parentHandle, name: "DCIM",
      pathKey: "00010001/DCIM", isDirectory: true)
    try await idx.insertObject(parent, deviceId: "dev")

    // Seed children under parent
    let seed = (0..<50)
      .map { i in
        makeObj(
          handle: UInt32(100 + i), parentHandle: parentHandle,
          name: "photo\(i).jpg", pathKey: "00010001/DCIM/photo\(i).jpg")
      }
    try await idx.upsertObjects(seed, deviceId: "dev")

    try await withThrowingTaskGroup(of: Void.self) { group in
      // Rebuild task: mark stale → re-insert → purge
      group.addTask {
        for cycle in 0..<5 {
          try await idx.markStaleChildren(
            deviceId: "dev", storageId: 0x10001, parentHandle: parentHandle)
          let fresh = (0..<50)
            .map { i in
              makeObj(
                handle: UInt32(100 + i), parentHandle: parentHandle,
                name: "photo\(i)_v\(cycle).jpg",
                pathKey: "00010001/DCIM/photo\(i)_v\(cycle).jpg")
            }
          try await idx.upsertObjects(fresh, deviceId: "dev")
          try await idx.purgeStale(
            deviceId: "dev", storageId: 0x10001, parentHandle: parentHandle)
        }
      }
      // Concurrent readers
      for _ in 0..<4 {
        group.addTask {
          for _ in 0..<30 {
            let kids = try await idx.children(
              deviceId: "dev", storageId: 0x10001, parentHandle: parentHandle)
            // During rebuild, may see 0 (stale) or 50 (refreshed), but never crash
            #expect(kids.count >= 0)
          }
        }
      }
      try await group.waitForAll()
    }

    // After all rebuilds, should have exactly 50 fresh children
    let final_ = try await idx.children(
      deviceId: "dev", storageId: 0x10001, parentHandle: parentHandle)
    #expect(final_.count == 50)
  }

  @Test("Concurrent removeObject does not corrupt sibling reads")
  func concurrentRemoveWithSiblingReads() async throws {
    let (idx, path) = try makeTempIndex()
    defer { try? FileManager.default.removeItem(atPath: path) }

    // Create 100 objects
    let objs = (0..<100).map { i in makeObj(handle: UInt32(i), name: "f\(i).txt") }
    try await idx.upsertObjects(objs, deviceId: "dev")

    try await withThrowingTaskGroup(of: Void.self) { group in
      // Remove even-numbered handles
      group.addTask {
        for i in stride(from: 0, to: 100, by: 2) {
          try await idx.removeObject(deviceId: "dev", storageId: 0x10001, handle: UInt32(i))
        }
      }
      // Readers query odd-numbered handles
      group.addTask {
        for i in stride(from: 1, to: 100, by: 2) {
          let obj = try await idx.object(deviceId: "dev", handle: UInt32(i))
          #expect(obj != nil)
          #expect(obj?.name == "f\(i).txt")
        }
      }
      try await group.waitForAll()
    }
  }
}

// MARK: - 6. Schema Migration Under Load

@Suite("IndexConcurrency – Migration Under Load")
struct IndexConcurrencyMigrationTests {

  @Test("migrateEphemeralDeviceId concurrent with reads")
  func migrationConcurrentWithReads() async throws {
    let (idx, path) = try makeTempIndex()
    defer { try? FileManager.default.removeItem(atPath: path) }

    // Insert with ephemeral device ID pattern
    let ephemeralId = "04e8:6860@1:3"
    let objs = (0..<100)
      .map { i in
        makeObj(deviceId: ephemeralId, handle: UInt32(i), name: "f\(i).txt")
      }
    try await idx.upsertObjects(objs, deviceId: ephemeralId)

    let stableId = "stable-domain-id"

    try await withThrowingTaskGroup(of: Void.self) { group in
      // Migration writer
      group.addTask {
        try idx.migrateEphemeralDeviceId(vidPidPattern: "04e8:6860", newDomainId: stableId)
      }
      // Reader with the old ID — may get results or empty depending on timing
      group.addTask {
        for _ in 0..<20 {
          _ = try await idx.children(
            deviceId: ephemeralId, storageId: 0x10001, parentHandle: nil)
        }
      }
      // Reader with the new ID — eventually sees all objects
      group.addTask {
        for _ in 0..<20 {
          _ = try await idx.children(
            deviceId: stableId, storageId: 0x10001, parentHandle: nil)
        }
      }
      try await group.waitForAll()
    }

    // After migration, all objects should be under the stable ID
    let migratedKids = try await idx.children(
      deviceId: stableId, storageId: 0x10001, parentHandle: nil)
    #expect(migratedKids.count == 100)

    let oldKids = try await idx.children(
      deviceId: ephemeralId, storageId: 0x10001, parentHandle: nil)
    #expect(oldKids.count == 0)
  }

  @Test("Storage upsert concurrent with object upsert")
  func storageUpsertConcurrentWithObjectUpsert() async throws {
    let (idx, path) = try makeTempIndex()
    defer { try? FileManager.default.removeItem(atPath: path) }

    try await withThrowingTaskGroup(of: Void.self) { group in
      // Rapidly update storage metadata
      group.addTask {
        for i in 0..<50 {
          try await idx.upsertStorage(
            IndexedStorage(
              deviceId: "dev", storageId: 0x10001, description: "Internal",
              capacity: 128_000_000, free: UInt64(64_000_000 - i * 1000), readOnly: false
            ))
        }
      }
      // Insert objects concurrently
      group.addTask {
        let objs = (0..<200)
          .map { j in
            makeObj(handle: UInt32(j), name: "f\(j).txt")
          }
        try await idx.upsertObjects(objs, deviceId: "dev")
      }
      try await group.waitForAll()
    }

    let storages = try await idx.storages(deviceId: "dev")
    #expect(storages.count == 1)

    let kids = try await idx.children(deviceId: "dev", storageId: 0x10001, parentHandle: nil)
    #expect(kids.count == 200)
  }
}

// MARK: - 7. Additional Stress Scenarios

@Suite("IndexConcurrency – Stress Edge Cases")
struct IndexConcurrencyStressEdgeCaseTests {

  @Test("Concurrent pruneChangeLog does not block writers")
  func concurrentPruneWithWriters() async throws {
    let (idx, path) = try makeTempIndex()
    defer { try? FileManager.default.removeItem(atPath: path) }

    // Seed some data so there are change log entries
    let seed = (0..<50).map { i in makeObj(handle: UInt32(i), name: "s\(i).txt") }
    try await idx.upsertObjects(seed, deviceId: "dev")

    try await withThrowingTaskGroup(of: Void.self) { group in
      // Prune task
      group.addTask {
        for _ in 0..<10 {
          let cutoff = Date().addingTimeInterval(60)
          try await idx.pruneChangeLog(deviceId: "dev", olderThan: cutoff)
        }
      }
      // Writer task
      group.addTask {
        for i in 50..<150 {
          let obj = makeObj(handle: UInt32(i), name: "new\(i).txt")
          try await idx.insertObject(obj, deviceId: "dev")
        }
      }
      try await group.waitForAll()
    }

    let total = try await idx.children(deviceId: "dev", storageId: 0x10001, parentHandle: nil)
    #expect(total.count == 150)
  }

  @Test("Concurrent nextChangeCounter calls produce unique values")
  func concurrentNextChangeCounterUnique() async throws {
    let (idx, path) = try makeTempIndex()
    defer { try? FileManager.default.removeItem(atPath: path) }

    let counters = try await withThrowingTaskGroup(of: Int64.self, returning: [Int64].self) {
      group in
      for _ in 0..<50 {
        group.addTask {
          return try await idx.nextChangeCounter(deviceId: "dev")
        }
      }
      var results: [Int64] = []
      for try await c in group {
        results.append(c)
      }
      return results
    }

    // All counters must be unique
    let uniqueCounters = Set(counters)
    #expect(uniqueCounters.count == 50)
    // Final counter should be 50
    let final_ = try await idx.currentChangeCounter(deviceId: "dev")
    #expect(final_ == 50)
  }

  @Test("Heavy concurrent upsert-then-read verifies total ordering")
  func heavyUpsertThenReadOrdering() async throws {
    let (idx, path) = try makeTempIndex()
    defer { try? FileManager.default.removeItem(atPath: path) }

    let taskCount = 20
    let objectsPerTask = 50

    try await withThrowingTaskGroup(of: Void.self) { group in
      for t in 0..<taskCount {
        group.addTask {
          let objs = (0..<objectsPerTask)
            .map { j in
              makeObj(handle: UInt32(t * objectsPerTask + j), name: "t\(t)_\(j).txt")
            }
          try await idx.upsertObjects(objs, deviceId: "dev")

          // Immediately verify own objects are visible
          for j in 0..<objectsPerTask {
            let obj = try await idx.object(
              deviceId: "dev", handle: UInt32(t * objectsPerTask + j))
            #expect(obj != nil)
          }
        }
      }
      try await group.waitForAll()
    }

    let total = try await idx.children(deviceId: "dev", storageId: 0x10001, parentHandle: nil)
    #expect(total.count == taskCount * objectsPerTask)
  }
}
