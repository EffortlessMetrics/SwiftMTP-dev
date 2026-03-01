// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import SwiftCheck
import XCTest

@testable import SwiftMTPCore
@testable import SwiftMTPIndex

// MARK: - Index Property Tests

final class IndexPropertyTests: XCTestCase {

  // MARK: - PathKey Round-Trip

  /// PathKey normalize then parse should always round-trip.
  func testPathKeyNormalizeParseLossless() {
    property("PathKey.normalize then .parse should round-trip for simple ASCII components")
      <- forAll(
        Gen<UInt32>.choose((1, UInt32.max)),
        Gen<[String]>.fromElements(of: [
          ["DCIM", "2024", "photos"],
          ["Music", "Albums"],
          ["Documents"],
          ["a", "b", "c", "d", "e"],
        ])
      ) { storageId, components in
        let normalized = PathKey.normalize(storage: storageId, components: components)
        let (parsedStorage, parsedComponents) = PathKey.parse(normalized)
        return parsedStorage == storageId && parsedComponents == components
      }
  }

  /// PathKey.basename should return the last component.
  func testPathKeyBasename() {
    property("PathKey.basename should return the last component")
      <- forAll(
        Gen<UInt32>.choose((1, UInt32.max)),
        Gen<[String]>.fromElements(of: [
          ["DCIM", "photo.jpg"],
          ["Music", "track.mp3"],
          ["notes.txt"],
        ])
      ) { storageId, components in
        let pathKey = PathKey.normalize(storage: storageId, components: components)
        return PathKey.basename(of: pathKey) == components.last
      }
  }

  /// PathKey.parent should return the parent path or nil for root.
  func testPathKeyParentConsistency() {
    property("PathKey.parent should remove the last component")
      <- forAll(
        Gen<UInt32>.choose((1, UInt32.max)),
        Gen<[String]>.fromElements(of: [
          ["DCIM", "2024", "photo.jpg"],
          ["Music", "Albums", "Artist", "track.mp3"],
        ])
      ) { storageId, components in
        let pathKey = PathKey.normalize(storage: storageId, components: components)
        guard let parentKey = PathKey.parent(of: pathKey) else { return false }
        let (_, parentComponents) = PathKey.parse(parentKey)
        return parentComponents == Array(components.dropLast())
      }
  }

  /// PathKey.isPrefix should hold for ancestor paths.
  func testPathKeyIsPrefixProperty() {
    property("PathKey of ancestor should be prefix of descendant")
      <- forAll(
        Gen<UInt32>.choose((1, UInt32.max)),
        Gen<[String]>.fromElements(of: [
          ["DCIM", "2024", "photo.jpg"],
          ["Music", "Albums", "track.mp3"],
          ["a", "b", "c", "d"],
        ])
      ) { storageId, components in
        guard components.count >= 2 else { return true }
        let prefix = PathKey.normalize(storage: storageId, components: Array(components.dropLast()))
        let full = PathKey.normalize(storage: storageId, components: components)
        return PathKey.isPrefix(prefix, of: full)
      }
  }

  // MARK: - PathKey Unicode Handling

  /// PathKey normalizes to NFC and strips control characters.
  func testPathKeyUnicodeNormalization() {
    property("PathKey.normalizeComponent should produce NFC form")
      <- forAll(
        Gen<String>.fromElements(of: [
          "café", "naïve", "Señor", "Ångström", "日本語", "한국어",
          "emoji📷🎵", "Müller", "niño",
        ])
      ) { component in
        let normalized = PathKey.normalizeComponent(component)
        // NFC form should equal precomposedStringWithCanonicalMapping
        return normalized == normalized.precomposedStringWithCanonicalMapping
      }
  }

  /// PathKey should strip control characters from components.
  func testPathKeyStripsControlChars() {
    property("PathKey.normalizeComponent should not contain control characters")
      <- forAll(
        Gen<String>.fromElements(of: [
          "file\u{0000}name", "path\u{001F}test", "null\u{007F}byte",
          "tab\there", "newline\nhere",
        ])
      ) { component in
        let normalized = PathKey.normalizeComponent(component)
        return !normalized.unicodeScalars.contains(where: {
          CharacterSet.controlCharacters.contains($0)
        })
      }
  }

  /// PathKey should handle emoji in paths.
  func testPathKeyEmojiPaths() {
    property("PathKey should handle emoji in components")
      <- forAll(
        Gen<UInt32>.choose((1, UInt32.max)),
        Gen<[String]>.fromElements(of: [
          ["📷Photos", "2024"],
          ["🎵Music", "🎸Rock"],
          ["📁Documents", "📝Notes"],
        ])
      ) { storageId, components in
        let pathKey = PathKey.normalize(storage: storageId, components: components)
        let (parsed, parsedComponents) = PathKey.parse(pathKey)
        // Components should survive the round-trip (they are already NFC-clean)
        return parsed == storageId && parsedComponents.count == components.count
      }
  }

  // MARK: - SQLiteLiveIndex Insert / Query Round-Trip

  /// Inserting an object and querying it back should return equivalent data.
  func testLiveIndexInsertThenQuery() {
    property("Insert then query should return the same object")
      <- forAll(
        Gen<UInt32>.choose((1, 10000)),
        Gen<String>.fromElements(of: [
          "photo.jpg", "track.mp3", "notes.txt", "video.mp4", "archive.zip",
        ]),
        Gen<UInt64>.choose((0, 10_000_000_000))
      ) { handle, name, size in
        let tempPath = self.makeTempDBPath()
        defer { try? FileManager.default.removeItem(atPath: tempPath) }

        guard let index = try? SQLiteLiveIndex(path: tempPath) else { return false }

        let deviceId = "test-device"
        let storageId: UInt32 = 0x00010001
        let pathKey = PathKey.normalize(storage: storageId, components: [name])

        let obj = IndexedObject(
          deviceId: deviceId, storageId: storageId, handle: handle,
          parentHandle: nil, name: name, pathKey: pathKey,
          sizeBytes: size, mtime: nil, formatCode: 0x3001,
          isDirectory: false, changeCounter: 0
        )

        let semaphore = DispatchSemaphore(value: 0)
        var result = false

        Task {
          do {
            try await index.upsertObjects([obj], deviceId: deviceId)
            let queried = try await index.object(deviceId: deviceId, handle: handle)
            result = queried?.name == name && queried?.sizeBytes == size
              && queried?.handle == handle
          } catch {
            result = false
          }
          semaphore.signal()
        }
        semaphore.wait()
        return result
      }
  }

  /// Batch upsert should maintain all inserted objects.
  func testLiveIndexBatchConsistency() {
    property("Batch upsert should make all objects queryable")
      <- forAll(Gen<Int>.choose((1, 20))) { count in
        let tempPath = self.makeTempDBPath()
        defer { try? FileManager.default.removeItem(atPath: tempPath) }

        guard let index = try? SQLiteLiveIndex(path: tempPath) else { return false }

        let deviceId = "batch-device"
        let storageId: UInt32 = 0x00010001
        var objects: [IndexedObject] = []
        for i in 0..<count {
          let handle = UInt32(i + 1)
          let name = "file_\(i).dat"
          objects.append(IndexedObject(
            deviceId: deviceId, storageId: storageId, handle: handle,
            parentHandle: nil, name: name,
            pathKey: PathKey.normalize(storage: storageId, components: [name]),
            sizeBytes: UInt64(i * 1024), mtime: nil, formatCode: 0x3001,
            isDirectory: false, changeCounter: 0
          ))
        }

        let semaphore = DispatchSemaphore(value: 0)
        var result = false

        Task {
          do {
            try await index.upsertObjects(objects, deviceId: deviceId)
            let children = try await index.children(
              deviceId: deviceId, storageId: storageId, parentHandle: nil)
            result = children.count == count
          } catch {
            result = false
          }
          semaphore.signal()
        }
        semaphore.wait()
        return result
      }
  }

  /// Upserting an object twice should not duplicate it.
  func testLiveIndexUpsertIdempotent() {
    property("Upserting the same object twice should not duplicate it")
      <- forAll(
        Gen<UInt32>.choose((1, 10000)),
        Gen<String>.fromElements(of: ["photo.jpg", "doc.pdf", "track.mp3"])
      ) { handle, name in
        let tempPath = self.makeTempDBPath()
        defer { try? FileManager.default.removeItem(atPath: tempPath) }

        guard let index = try? SQLiteLiveIndex(path: tempPath) else { return false }

        let deviceId = "idempotent-device"
        let storageId: UInt32 = 0x00010001
        let obj = IndexedObject(
          deviceId: deviceId, storageId: storageId, handle: handle,
          parentHandle: nil, name: name,
          pathKey: PathKey.normalize(storage: storageId, components: [name]),
          sizeBytes: 1024, mtime: nil, formatCode: 0x3001,
          isDirectory: false, changeCounter: 0
        )

        let semaphore = DispatchSemaphore(value: 0)
        var result = false

        Task {
          do {
            try await index.upsertObjects([obj], deviceId: deviceId)
            try await index.upsertObjects([obj], deviceId: deviceId)
            let children = try await index.children(
              deviceId: deviceId, storageId: storageId, parentHandle: nil)
            result = children.count == 1
          } catch {
            result = false
          }
          semaphore.signal()
        }
        semaphore.wait()
        return result
      }
  }

  /// Removing an object should make it non-queryable (stale).
  func testLiveIndexRemoveThenQuery() {
    property("Removed object should not appear in non-stale queries")
      <- forAll(
        Gen<UInt32>.choose((1, 10000)),
        Gen<String>.fromElements(of: ["photo.jpg", "doc.pdf"])
      ) { handle, name in
        let tempPath = self.makeTempDBPath()
        defer { try? FileManager.default.removeItem(atPath: tempPath) }

        guard let index = try? SQLiteLiveIndex(path: tempPath) else { return false }

        let deviceId = "remove-device"
        let storageId: UInt32 = 0x00010001
        let obj = IndexedObject(
          deviceId: deviceId, storageId: storageId, handle: handle,
          parentHandle: nil, name: name,
          pathKey: PathKey.normalize(storage: storageId, components: [name]),
          sizeBytes: 1024, mtime: nil, formatCode: 0x3001,
          isDirectory: false, changeCounter: 0
        )

        let semaphore = DispatchSemaphore(value: 0)
        var result = false

        Task {
          do {
            try await index.upsertObjects([obj], deviceId: deviceId)
            try await index.removeObject(deviceId: deviceId, storageId: storageId, handle: handle)
            let queried = try await index.object(deviceId: deviceId, handle: handle)
            result = queried == nil  // removed objects are stale, not returned
          } catch {
            result = false
          }
          semaphore.signal()
        }
        semaphore.wait()
        return result
      }
  }

  // MARK: - Change Counter Monotonicity

  /// Change counter should monotonically increase.
  func testChangeCounterMonotonic() {
    property("Change counter should always increase")
      <- forAll(Gen<Int>.choose((2, 10))) { iterations in
        let tempPath = self.makeTempDBPath()
        defer { try? FileManager.default.removeItem(atPath: tempPath) }

        guard let index = try? SQLiteLiveIndex(path: tempPath) else { return false }

        let deviceId = "counter-device"

        let semaphore = DispatchSemaphore(value: 0)
        var result = false

        Task {
          do {
            var counters: [Int64] = []
            for _ in 0..<iterations {
              let c = try await index.nextChangeCounter(deviceId: deviceId)
              counters.append(c)
            }
            // Verify strictly increasing
            result = zip(counters, counters.dropFirst()).allSatisfy { $0 < $1 }
          } catch {
            result = false
          }
          semaphore.signal()
        }
        semaphore.wait()
        return result
      }
  }

  // MARK: - Helpers

  private func makeTempDBPath() -> String {
    FileManager.default.temporaryDirectory
      .appendingPathComponent("index_prop_test_\(UUID().uuidString).db")
      .path
  }
}
