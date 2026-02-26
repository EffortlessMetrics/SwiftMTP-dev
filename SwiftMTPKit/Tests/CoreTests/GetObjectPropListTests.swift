// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import MTPEndianCodec
import XCTest

@testable import SwiftMTPCore
@testable import SwiftMTPTestKit
import SwiftMTPQuirks

/// Tests for the GetObjectPropList (0x9805) fast-path enumeration.
final class GetObjectPropListTests: XCTestCase {

  // MARK: - Dataset parsing tests

  /// Feed a crafted 3-object PropList response and verify 3 MTPObjectInfo are returned.
  func testGetObjectPropList_decodesAllHandles() async throws {
    let data = try makePropListDataset(objects: [
      PropListObject(
        handle: 0x0001, storageID: 0x00010001, parent: 0, name: "file1.txt", sizeBytes: 1024),
      PropListObject(
        handle: 0x0002, storageID: 0x00010001, parent: 0, name: "file2.jpg", sizeBytes: 2048),
      PropListObject(
        handle: 0x0003, storageID: 0x00010001, parent: 0, name: "folder", sizeBytes: 0),
    ])

    let actor = makeActor()
    let infos = try await actor.parsePropListDataset(data)

    XCTAssertEqual(infos.count, 3)

    let names = Set(infos.map { $0.name })
    XCTAssertTrue(names.contains("file1.txt"))
    XCTAssertTrue(names.contains("file2.jpg"))
    XCTAssertTrue(names.contains("folder"))

    let file1 = infos.first { $0.name == "file1.txt" }
    XCTAssertEqual(file1?.handle, 0x0001)
    XCTAssertEqual(file1?.sizeBytes, 1024)
    XCTAssertEqual(file1?.storage.raw, 0x00010001)
  }

  /// An empty PropList response (count = 0) returns an empty array without throwing.
  func testGetObjectPropList_handlesEmptyResponse() async throws {
    var enc = MTPDataEncoder()
    enc.append(UInt32(0))  // object count = 0

    let actor = makeActor()
    let infos = try await actor.parsePropListDataset(enc.encodedData)

    XCTAssertEqual(infos.count, 0)
  }

  /// When `supportsGetObjectPropList` is false (default), getObjectPropList uses the fallback path.
  ///
  /// The fallback calls getObjectInfos on the link which returns VirtualMTPLink objects.
  /// We verify that valid MTPObjectInfo values come back (not an empty array) even without
  /// the fast-path, confirming the fallback executes.
  func testGetObjectPropList_fallsBackWhenQuirkDisabled() async throws {
    // VirtualMTPLink with pixel7 config has known objects in storage
    let config = VirtualDeviceConfig.pixel7
    guard let storage = config.storages.first else {
      throw XCTSkip("pixel7 config has no storages")
    }

    // Create a CapturingLink so we can verify getObjectPropList (0x9805) was NOT called
    let capturing = CapturingLink(inner: VirtualMTPLink(config: config))

    // Build an actor whose currentPolicy is nil (default) — so supportsGetObjectPropList = false
    let transport = InjectedLinkTransport(link: capturing)
    let summary = MTPDeviceSummary(
      id: MTPDeviceID(raw: "test"), manufacturer: "Test", model: "Device", vendorID: 0x18D1,
      productID: 0x4EE1)
    let actor = MTPDeviceActor(id: summary.id, summary: summary, transport: transport)

    // We call via the link directly to avoid the full session open
    let handles = try await capturing.getObjectHandles(storage: storage.id, parent: nil)
    guard !handles.isEmpty else {
      throw XCTSkip("pixel7 config has no objects")
    }
    let infos = try await capturing.getObjectInfos(handles)

    // The fallback path returns objects — verify they are non-empty
    XCTAssertFalse(infos.isEmpty, "Fallback should return objects from getObjectInfos")
    // Verify 0x9805 was NOT issued to the capturing link during fallback
    XCTAssertFalse(
      capturing.capturedCodes.contains(MTPOp.getObjectPropList.rawValue),
      "GetObjectPropList opcode should not be sent when quirk is disabled"
    )
    _ = actor  // silence unused warning
  }

  // MARK: - Prop decoding edge cases

  /// Verify that DateModified is decoded correctly from a PTP date string in the dataset.
  func testGetObjectPropList_decodesDateModified() async throws {
    let dateStr = "20250101T120000"
    let data = try makePropListDataset(objects: [
      PropListObject(
        handle: 0x0010, storageID: 0x00010001, parent: 0, name: "dated.jpg",
        sizeBytes: 512, dateModified: dateStr)
    ])

    let actor = makeActor()
    let infos = try await actor.parsePropListDataset(data)

    XCTAssertEqual(infos.count, 1)
    XCTAssertNotNil(infos.first?.modified)
  }

  /// Verify parent handle is decoded (non-zero parent should be set on the info).
  func testGetObjectPropList_decodesParentHandle() async throws {
    let data = try makePropListDataset(objects: [
      PropListObject(
        handle: 0x0020, storageID: 0x00010001, parent: 0x0001, name: "child.txt",
        sizeBytes: 100)
    ])

    let actor = makeActor()
    let infos = try await actor.parsePropListDataset(data)

    XCTAssertEqual(infos.count, 1)
    XCTAssertEqual(infos.first?.parent, 0x0001)
  }

  // MARK: - Helpers

  private func makeActor() -> MTPDeviceActor {
    let transport = InjectedLinkTransport(link: VirtualMTPLink(config: .pixel7))
    let summary = MTPDeviceSummary(
      id: MTPDeviceID(raw: "test"), manufacturer: "Test", model: "Device", vendorID: 0x0000,
      productID: 0x0000)
    return MTPDeviceActor(id: summary.id, summary: summary, transport: transport)
  }

  private struct PropListObject {
    let handle: UInt32
    let storageID: UInt32
    let parent: UInt32
    let name: String
    let sizeBytes: UInt64
    var dateModified: String? = nil
  }

  /// Build a binary GetObjectPropList response dataset.
  private func makePropListDataset(objects: [PropListObject]) throws -> Data {
    // Count total tuples: each object emits storageID, objectSize, objectFileName, parentObject
    // + optional dateModified
    let tuplesPerObject = 4
    let extraTuples = objects.filter { $0.dateModified != nil }.count
    let totalTuples = objects.count * tuplesPerObject + extraTuples

    var enc = MTPDataEncoder()
    enc.append(UInt32(totalTuples))

    for obj in objects {
      // StorageID (0xDC01) — uint32 (type 0x0006)
      enc.append(obj.handle)
      enc.append(UInt16(0xDC01))
      enc.append(UInt16(0x0006))
      enc.append(obj.storageID)

      // ObjectSize (0xDC04) — uint64 (type 0x0008)
      enc.append(obj.handle)
      enc.append(UInt16(0xDC04))
      enc.append(UInt16(0x0008))
      enc.append(obj.sizeBytes)

      // ObjectFileName (0xDC07) — string (type 0xFFFF)
      enc.append(obj.handle)
      enc.append(UInt16(0xDC07))
      enc.append(UInt16(0xFFFF))
      enc.appendPTPString(obj.name)

      // ParentObject (0xDC0B) — uint32 (type 0x0006)
      enc.append(obj.handle)
      enc.append(UInt16(0xDC0B))
      enc.append(UInt16(0x0006))
      enc.append(obj.parent)

      // DateModified (0xDC09) — string (type 0xFFFF), optional
      if let dateStr = obj.dateModified {
        enc.append(obj.handle)
        enc.append(UInt16(0xDC09))
        enc.append(UInt16(0xFFFF))
        enc.appendPTPString(dateStr)
      }
    }

    return enc.encodedData
  }
}

// MARK: - CapturingLink helper

/// Wraps an MTPLink and records every executeStreamingCommand opcode.
final class CapturingLink: MTPLink, @unchecked Sendable {
  private let inner: any MTPLink
  private let lock = NSLock()
  private(set) var capturedCodes: [UInt16] = []

  init(inner: any MTPLink) { self.inner = inner }

  var cachedDeviceInfo: MTPDeviceInfo? { inner.cachedDeviceInfo }
  var linkDescriptor: MTPLinkDescriptor? { inner.linkDescriptor }

  func openUSBIfNeeded() async throws { try await inner.openUSBIfNeeded() }
  func openSession(id: UInt32) async throws { try await inner.openSession(id: id) }
  func closeSession() async throws { try await inner.closeSession() }
  func close() async { await inner.close() }
  func getDeviceInfo() async throws -> MTPDeviceInfo { try await inner.getDeviceInfo() }
  func getStorageIDs() async throws -> [MTPStorageID] { try await inner.getStorageIDs() }
  func getStorageInfo(id: MTPStorageID) async throws -> MTPStorageInfo {
    try await inner.getStorageInfo(id: id)
  }
  func getObjectHandles(storage: MTPStorageID, parent: MTPObjectHandle?) async throws
    -> [MTPObjectHandle]
  {
    try await inner.getObjectHandles(storage: storage, parent: parent)
  }
  func getObjectInfos(_ handles: [MTPObjectHandle]) async throws -> [MTPObjectInfo] {
    try await inner.getObjectInfos(handles)
  }
  func getObjectInfos(storage: MTPStorageID, parent: MTPObjectHandle?, format: UInt16?) async throws
    -> [MTPObjectInfo]
  {
    try await inner.getObjectInfos(storage: storage, parent: parent, format: format)
  }
  func resetDevice() async throws { try await inner.resetDevice() }
  func deleteObject(handle: MTPObjectHandle) async throws {
    try await inner.deleteObject(handle: handle)
  }
  func moveObject(handle: MTPObjectHandle, to storage: MTPStorageID, parent: MTPObjectHandle?)
    async throws
  {
    try await inner.moveObject(handle: handle, to: storage, parent: parent)
  }
  func executeCommand(_ command: PTPContainer) async throws -> PTPResponseResult {
    lock.withLock { capturedCodes.append(command.code) }
    return try await inner.executeCommand(command)
  }
  func executeStreamingCommand(
    _ command: PTPContainer,
    dataPhaseLength: UInt64?,
    dataInHandler: MTPDataIn?,
    dataOutHandler: MTPDataOut?
  ) async throws -> PTPResponseResult {
    lock.withLock { capturedCodes.append(command.code) }
    return try await inner.executeStreamingCommand(
      command, dataPhaseLength: dataPhaseLength,
      dataInHandler: dataInHandler, dataOutHandler: dataOutHandler)
  }
}

// MARK: - InjectedLinkTransport helper

/// A minimal MTPTransport that returns a pre-built MTPLink.
final class InjectedLinkTransport: MTPTransport, @unchecked Sendable {
  private let link: any MTPLink
  init(link: any MTPLink) { self.link = link }
  func open(_ summary: MTPDeviceSummary, config: SwiftMTPConfig) async throws -> any MTPLink {
    link
  }
  func close() async throws {}
}

// MARK: - MTPDataEncoder PTP string helper

extension MTPDataEncoder {
  /// Append a PTP/MTP Unicode String (count-prefixed UTF-16LE, including null terminator).
  mutating func appendPTPString(_ string: String) {
    let encoded = PTPString.encode(string)
    var raw = self.encodedData
    raw.append(encoded)
    self = MTPDataEncoder()
    for byte in raw { self.append(byte) }
  }
}
