// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import XCTest
@testable import SwiftMTPStore
@testable import SwiftMTPCore

final class StoreActorCoverageTests: XCTestCase {
  private var store: SwiftMTPStore!

  override func setUp() {
    super.setUp()
    setenv("SWIFTMTP_STORE_TYPE", "memory", 1)
    store = .shared
  }

  override func tearDown() {
    store = nil
    super.tearDown()
  }

  func testUpsertObjectsInsertsRowsWhenDeviceExists() async throws {
    let actor = store.createActor()
    let deviceId = "batch-device-insert-\(UUID().uuidString)"
    _ = try await actor.upsertDevice(id: deviceId, manufacturer: "Test", model: "Model")

    let now = Date()
    try await actor.upsertObjects(
      deviceId: deviceId,
      objects: [
        (
          storageId: 1,
          handle: 101,
          parentHandle: nil,
          name: "a.txt",
          pathKey: "/a.txt",
          size: 100,
          mtime: now,
          format: 0x3004,
          generation: 1
        ),
        (
          storageId: 1,
          handle: 102,
          parentHandle: nil,
          name: "b.txt",
          pathKey: "/b.txt",
          size: nil,
          mtime: nil,
          format: 0x3004,
          generation: 1
        ),
      ]
    )

    let rows = try await actor.fetchObjects(deviceId: deviceId, generation: 1)
    XCTAssertEqual(rows.count, 2)
    XCTAssertEqual(Set(rows.map(\.pathKey)), Set(["/a.txt", "/b.txt"]))
  }

  func testUpsertObjectsUpdatesExistingRows() async throws {
    let actor = store.createActor()
    let deviceId = "batch-device-update-\(UUID().uuidString)"
    _ = try await actor.upsertDevice(id: deviceId, manufacturer: "Test", model: "Model")

    try await actor.upsertObjects(
      deviceId: deviceId,
      objects: [
        (
          storageId: 2,
          handle: 201,
          parentHandle: nil,
          name: "old.txt",
          pathKey: "/old.txt",
          size: 100,
          mtime: Date(timeIntervalSince1970: 100),
          format: 0x3004,
          generation: 1
        )
      ]
    )

    try await actor.upsertObjects(
      deviceId: deviceId,
      objects: [
        (
          storageId: 2,
          handle: 201,
          parentHandle: 1,
          name: "new.txt",
          pathKey: "/new.txt",
          size: 200,
          mtime: Date(timeIntervalSince1970: 200),
          format: 0x3005,
          generation: 1
        )
      ]
    )

    let rows = try await actor.fetchObjects(deviceId: deviceId, generation: 1)
    XCTAssertEqual(rows.count, 1)
    XCTAssertEqual(rows.first?.pathKey, "/new.txt")
    XCTAssertEqual(rows.first?.size, 200)
    XCTAssertEqual(rows.first?.format, 0x3005)
  }

  func testFetchResumableTransfersMapsFinalURLWhenPresent() async throws {
    let actor = store.createActor()
    let deviceId = "transfer-device-\(UUID().uuidString)"
    let finalURLPath = "/tmp/final-\(UUID().uuidString)"

    try await actor.createTransfer(
      id: "transfer-\(UUID().uuidString)",
      deviceId: deviceId,
      kind: "read",
      handle: 10,
      parentHandle: nil,
      name: "photo.jpg",
      totalBytes: 1024,
      supportsPartial: true,
      localTempURL: "/tmp/temp-\(UUID().uuidString)",
      finalURL: finalURLPath,
      etagSize: nil,
      etagMtime: nil
    )

    let rows = try await actor.fetchResumableTransfers(for: deviceId)
    XCTAssertEqual(rows.count, 1)
    XCTAssertEqual(rows.first?.finalURL?.path, finalURLPath)
  }
}
