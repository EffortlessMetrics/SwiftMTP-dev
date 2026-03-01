// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import XCTest

@testable import SwiftMTPCore
import SwiftMTPIndex
import SwiftMTPQuirks
import SwiftMTPTestKit

// MARK: - Performance Benchmark Tests

final class PerformanceBenchmarkTests: XCTestCase {

  // MARK: - 1. Codec Throughput

  func testPTPContainerEncodeDecodeThroughput() {
    let iterations = 50_000
    var buffer = [UInt8](repeating: 0, count: 64)

    measure {
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
    }
  }

  func testPTPStringEncodeDecodeThroughput() {
    let iterations = 20_000
    let testString = "DCIM/Camera/IMG_20250101_120000.jpg"

    measure {
      for _ in 0..<iterations {
        let encoded = PTPString.encode(testString)
        var offset = 0
        _ = PTPString.parse(from: encoded, at: &offset)
      }
    }
  }

  func testPTPReaderParseThroughput() {
    // Build a synthetic prop list payload once
    let entryCount: UInt32 = 100
    var payload = Data()
    payload.append(contentsOf: withUnsafeBytes(of: entryCount.littleEndian, Array.init))
    for i in 0..<entryCount {
      // handle (u32), propertyCode (u16), dataType (u16 = 0x0006 for uint32), value (u32)
      payload.append(contentsOf: withUnsafeBytes(of: i.littleEndian, Array.init))
      payload.append(contentsOf: withUnsafeBytes(of: UInt16(0xDC01).littleEndian, Array.init))
      payload.append(contentsOf: withUnsafeBytes(of: UInt16(0x0006).littleEndian, Array.init))
      payload.append(contentsOf: withUnsafeBytes(of: (i * 1024).littleEndian, Array.init))
    }

    let iterations = 5_000
    measure {
      for _ in 0..<iterations {
        _ = PTPPropList.parse(from: payload)
      }
    }
  }

  // MARK: - 2. Quirks Database Lookup

  func testQuirksDatabaseMatchPerformanceWith20KEntries() {
    // Build a large database with 20K synthetic entries
    let count = 20_000
    var entries: [DeviceQuirk] = []
    entries.reserveCapacity(count)
    for i in 0..<count {
      let vid = UInt16(truncatingIfNeeded: (i / 256) + 1)
      let pid = UInt16(truncatingIfNeeded: (i % 256) + 1)
      entries.append(DeviceQuirk(
        id: "synth-device-\(i)",
        vid: vid,
        pid: pid,
        maxChunkBytes: 1_048_576
      ))
    }

    let db = QuirkDatabase(schemaVersion: "2.0", entries: entries)

    // Search for the last entry (worst case linear scan)
    let targetVid: UInt16 = UInt16(truncatingIfNeeded: ((count - 1) / 256) + 1)
    let targetPid: UInt16 = UInt16(truncatingIfNeeded: ((count - 1) % 256) + 1)

    let iterations = 200
    measure {
      for _ in 0..<iterations {
        let result = db.match(
          vid: targetVid, pid: targetPid,
          bcdDevice: nil, ifaceClass: nil, ifaceSubclass: nil, ifaceProtocol: nil
        )
        XCTAssertNotNil(result)
      }
    }

    // Verify single lookup time < 50ms (debug builds are ~10x slower than release)
    let start = CFAbsoluteTimeGetCurrent()
    _ = db.match(
      vid: targetVid, pid: targetPid,
      bcdDevice: nil, ifaceClass: nil, ifaceSubclass: nil, ifaceProtocol: nil
    )
    let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1000
    XCTAssertLessThan(elapsed, 50.0, "Single quirk lookup took \(elapsed)ms, expected <50ms")
  }

  // MARK: - 3. SQLite Index Write Throughput

  func testSQLiteIndexInsertThroughput() async throws {
    let tempDir = FileManager.default.temporaryDirectory
      .appendingPathComponent("perf-bench-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let dbPath = tempDir.appendingPathComponent("bench.sqlite").path
    let index = try SQLiteLiveIndex(path: dbPath)

    let objectCount = 2_000
    let deviceId = "bench-device-001"
    let storageId: UInt32 = 0x0001_0001

    var objects: [IndexedObject] = []
    objects.reserveCapacity(objectCount)
    for i in 0..<objectCount {
      objects.append(IndexedObject(
        deviceId: deviceId,
        storageId: storageId,
        handle: MTPObjectHandle(i + 1),
        parentHandle: nil,
        name: "file_\(i).jpg",
        pathKey: "/DCIM/file_\(i).jpg",
        sizeBytes: UInt64(i * 1024),
        mtime: Date(),
        formatCode: 0x3801,
        isDirectory: false,
        changeCounter: 1
      ))
    }

    let start = CFAbsoluteTimeGetCurrent()
    try await index.upsertObjects(objects, deviceId: deviceId)
    let elapsed = CFAbsoluteTimeGetCurrent() - start

    let objectsPerSecond = Double(objectCount) / elapsed
    XCTAssertGreaterThan(
      objectsPerSecond, 1000,
      "Insert rate \(Int(objectsPerSecond)) obj/s, expected >1000 obj/s"
    )
  }

  // MARK: - 4. Transfer Chunk Assembly

  func testTransferChunkAssemblyPerformance() {
    let chunkSizes = [512 * 1024, 1024 * 1024, 4 * 1024 * 1024, 8 * 1024 * 1024]

    measure {
      for chunkSize in chunkSizes {
        let sourceData = Data(repeating: 0xAB, count: chunkSize)
        let subBlockSize = 65_536
        var assembled = Data()
        assembled.reserveCapacity(chunkSize)
        var offset = 0
        while offset < sourceData.count {
          let end = min(offset + subBlockSize, sourceData.count)
          assembled.append(sourceData[offset..<end])
          offset = end
        }
        XCTAssertEqual(assembled.count, chunkSize)
      }
    }
  }

  // MARK: - 5. VirtualMTPDevice Operation Throughput

  func testVirtualDeviceListThroughput() async throws {
    let config = VirtualDeviceConfig.pixel7
    let device = VirtualMTPDevice(config: config)

    let storages = try await device.storages()
    guard let storage = storages.first else {
      XCTFail("No storages on pixel7 config")
      return
    }

    let iterations = 1_000
    let start = CFAbsoluteTimeGetCurrent()
    for _ in 0..<iterations {
      let stream = device.list(parent: nil, in: storage.id)
      for try await _ in stream {}
    }
    let elapsed = CFAbsoluteTimeGetCurrent() - start

    let opsPerSecond = Double(iterations) / elapsed
    XCTAssertGreaterThan(
      opsPerSecond, 100,
      "List ops/sec: \(Int(opsPerSecond)), expected >100"
    )
  }

  func testVirtualDeviceGetInfoThroughput() async throws {
    let config = VirtualDeviceConfig.pixel7
    let device = VirtualMTPDevice(config: config)

    let iterations = 5_000
    let start = CFAbsoluteTimeGetCurrent()
    for _ in 0..<iterations {
      _ = try await device.getInfo(handle: 1)
    }
    let elapsed = CFAbsoluteTimeGetCurrent() - start

    let opsPerSecond = Double(iterations) / elapsed
    XCTAssertGreaterThan(
      opsPerSecond, 1000,
      "GetInfo ops/sec: \(Int(opsPerSecond)), expected >1000"
    )
  }

  func testVirtualDeviceWriteThroughput() async throws {
    let config = VirtualDeviceConfig.pixel7
    let device = VirtualMTPDevice(config: config)

    let tempDir = FileManager.default.temporaryDirectory
      .appendingPathComponent("perf-write-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let fileURL = tempDir.appendingPathComponent("test.bin")
    let testData = Data(repeating: 0xCC, count: 1024)
    try testData.write(to: fileURL)

    let iterations = 500
    let start = CFAbsoluteTimeGetCurrent()
    for i in 0..<iterations {
      _ = try await device.write(
        parent: 1, name: "test_\(i).bin",
        size: UInt64(testData.count), from: fileURL
      )
    }
    let elapsed = CFAbsoluteTimeGetCurrent() - start

    let opsPerSecond = Double(iterations) / elapsed
    XCTAssertGreaterThan(
      opsPerSecond, 50,
      "Write ops/sec: \(Int(opsPerSecond)), expected >50"
    )
  }

  // MARK: - 6. JSON Parsing

  func testQuirksJSONParsePerformanceLargeDatabase() throws {
    // Generate a large quirks JSON with 20K entries
    let count = 20_000
    var entriesJSON: [String] = []
    entriesJSON.reserveCapacity(count)
    for i in 0..<count {
      let vid = String(format: "0x%04x", (i / 256) + 1)
      let pid = String(format: "0x%04x", (i % 256) + 1)
      entriesJSON.append("""
        {
          "id": "synth-\(i)",
          "match": { "vid": "\(vid)", "pid": "\(pid)" },
          "tuning": { "maxChunkBytes": 1048576 }
        }
        """)
    }

    let jsonString = """
      {
        "schemaVersion": "2.0",
        "entries": [\(entriesJSON.joined(separator: ",\n"))]
      }
      """
    let jsonData = Data(jsonString.utf8)

    let start = CFAbsoluteTimeGetCurrent()
    let db = try JSONDecoder().decode(QuirkDatabase.self, from: jsonData)
    let elapsed = CFAbsoluteTimeGetCurrent() - start

    XCTAssertEqual(db.entries.count, count)
    XCTAssertLessThan(elapsed, 2.0, "JSON parse took \(elapsed)s, expected <2s for \(count) entries")
  }

  // MARK: - 7. Object Path Construction

  func testObjectPathConstructionPerformance() {
    // Build a tree: depth 10, breadth 5 at each level
    struct PathNode {
      let handle: MTPObjectHandle
      let parentHandle: MTPObjectHandle?
      let name: String
    }

    var nodes: [MTPObjectHandle: PathNode] = [:]
    var handle: MTPObjectHandle = 1

    func buildTree(parent: MTPObjectHandle?, depth: Int) {
      guard depth > 0 else { return }
      for i in 0..<5 {
        let current = handle
        nodes[current] = PathNode(
          handle: current, parentHandle: parent, name: "dir_\(depth)_\(i)")
        handle += 1
        buildTree(parent: current, depth: depth - 1)
      }
    }
    buildTree(parent: nil, depth: 8)

    // Resolve full path for a leaf node
    func buildPath(handle: MTPObjectHandle) -> String {
      var components: [String] = []
      var current: MTPObjectHandle? = handle
      while let h = current, let node = nodes[h] {
        components.append(node.name)
        current = node.parentHandle
      }
      return "/" + components.reversed().joined(separator: "/")
    }

    let leafHandles = Array(nodes.keys.suffix(1000))

    let iterations = 100
    measure {
      for _ in 0..<iterations {
        for h in leafHandles {
          _ = buildPath(handle: h)
        }
      }
    }
  }

  // MARK: - 8. FallbackLadder Evaluation

  func testFallbackLadderEvaluationSpeed() async throws {
    let iterations = 1_000

    let start = CFAbsoluteTimeGetCurrent()
    for i in 0..<iterations {
      let rungs: [FallbackRung<Int>] = [
        FallbackRung(name: "fast") { return i },
      ]
      let result = try await FallbackLadder.execute(rungs)
      XCTAssertEqual(result.value, i)
    }
    let elapsed = CFAbsoluteTimeGetCurrent() - start

    let opsPerSecond = Double(iterations) / elapsed
    XCTAssertGreaterThan(
      opsPerSecond, 500,
      "FallbackLadder ops/sec: \(Int(opsPerSecond)), expected >500"
    )
  }

  func testFallbackLadderWithFailingRungs() async throws {
    let iterations = 500

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

    let opsPerSecond = Double(iterations) / elapsed
    XCTAssertGreaterThan(
      opsPerSecond, 200,
      "FallbackLadder (with failures) ops/sec: \(Int(opsPerSecond)), expected >200"
    )
  }

  // MARK: - 9. Concurrent Operation Throughput

  func testConcurrentOperationThroughput() async throws {
    let config = VirtualDeviceConfig.pixel7
    let device = VirtualMTPDevice(config: config)

    let concurrency = 10
    let opsPerTask = 200

    let start = CFAbsoluteTimeGetCurrent()
    try await withThrowingTaskGroup(of: Void.self) { group in
      for _ in 0..<concurrency {
        group.addTask {
          for _ in 0..<opsPerTask {
            _ = try await device.getInfo(handle: 1)
          }
        }
      }
      try await group.waitForAll()
    }
    let elapsed = CFAbsoluteTimeGetCurrent() - start

    let totalOps = concurrency * opsPerTask
    let opsPerSecond = Double(totalOps) / elapsed
    XCTAssertGreaterThan(
      opsPerSecond, 500,
      "Concurrent ops/sec: \(Int(opsPerSecond)), expected >500"
    )
  }

  func testConcurrentQuirksLookupThroughput() async throws {
    let count = 5_000
    var entries: [DeviceQuirk] = []
    entries.reserveCapacity(count)
    for i in 0..<count {
      let vid = UInt16(truncatingIfNeeded: (i / 256) + 1)
      let pid = UInt16(truncatingIfNeeded: (i % 256) + 1)
      entries.append(DeviceQuirk(
        id: "conc-device-\(i)",
        vid: vid,
        pid: pid
      ))
    }
    let db = QuirkDatabase(schemaVersion: "2.0", entries: entries)

    let concurrency = 8
    let lookupsPerTask = 500

    let start = CFAbsoluteTimeGetCurrent()
    await withTaskGroup(of: Void.self) { group in
      for taskIdx in 0..<concurrency {
        group.addTask {
          for j in 0..<lookupsPerTask {
            let idx = (taskIdx * lookupsPerTask + j) % count
            let vid = UInt16(truncatingIfNeeded: (idx / 256) + 1)
            let pid = UInt16(truncatingIfNeeded: (idx % 256) + 1)
            _ = db.match(
              vid: vid, pid: pid,
              bcdDevice: nil, ifaceClass: nil, ifaceSubclass: nil, ifaceProtocol: nil
            )
          }
        }
      }
      await group.waitForAll()
    }
    let elapsed = CFAbsoluteTimeGetCurrent() - start

    let totalLookups = concurrency * lookupsPerTask
    let lookupsPerSecond = Double(totalLookups) / elapsed
    XCTAssertGreaterThan(
      lookupsPerSecond, 1000,
      "Concurrent quirk lookups/sec: \(Int(lookupsPerSecond)), expected >1000"
    )
  }
}
