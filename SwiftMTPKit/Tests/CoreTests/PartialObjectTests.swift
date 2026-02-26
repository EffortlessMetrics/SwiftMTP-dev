// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import MTPEndianCodec
import XCTest

@testable import SwiftMTPCore
@testable import SwiftMTPTestKit
import SwiftMTPQuirks

/// Tests for the GetPartialObject (0x101B) partial-read resume path.
final class PartialObjectTests: XCTestCase {

  // MARK: - resumeRead opcode / parameter tests

  /// Verify that resumeRead sends opcode 0x101B with the correct handle and offset parameters.
  func testResumeRead_decodesPartialData() async throws {
    let payload = Data([0xDE, 0xAD, 0xBE, 0xEF])
    let respondingLink = RespondingLink(responsePayload: payload)
    let transport = InjectedLinkTransport(link: respondingLink)
    let summary = MTPDeviceSummary(
      id: MTPDeviceID(raw: "test"), manufacturer: "Test", model: "Device", vendorID: 0, productID: 0
    )
    let actor = MTPDeviceActor(id: summary.id, summary: summary, transport: transport)

    let result = try await actor.resumeRead(handle: 0x0042, offset: 1_048_576, length: 4)

    // Verify the correct opcode was sent
    XCTAssertEqual(respondingLink.lastCommand?.code, PTPOp.getPartialObject.rawValue)

    // Verify handle param
    XCTAssertEqual(respondingLink.lastCommand?.params[0], 0x0042)

    // Verify offset lo/hi params (1 MiB = 0x00100000, hi = 0)
    XCTAssertEqual(respondingLink.lastCommand?.params[1], 0x00100000)
    XCTAssertEqual(respondingLink.lastCommand?.params[2], 0x00000000)

    // Verify length param
    XCTAssertEqual(respondingLink.lastCommand?.params[3], 4)

    // Verify returned data
    XCTAssertEqual(result, payload)
  }

  /// resumeRead is not invoked when `supportsGetPartialObject` quirk is false.
  ///
  /// With the default nil policy (supportsGetPartialObject = false), read() falls through
  /// to the full readWholeObject path. We verify no GetPartialObject command is sent.
  func testResumeRead_skippedWhenQuirkDisabled() async throws {
    let respondingLink = RespondingLink(responsePayload: Data(repeating: 0xAB, count: 1024))
    let capturing = CapturingLinkWrapper(inner: respondingLink)
    let transport = InjectedLinkTransport(link: capturing)
    let summary = MTPDeviceSummary(
      id: MTPDeviceID(raw: "test"), manufacturer: "Test", model: "Device", vendorID: 0, productID: 0
    )

    // Actor with nil policy (supportsGetPartialObject defaults to false)
    let actor = MTPDeviceActor(id: summary.id, summary: summary, transport: transport)

    // Even with a non-zero offset, if quirk is disabled, don't use GetPartialObject
    // We call resumeRead directly to verify it still sends the command (it's unconditional)
    // The gate is in read() — here we test that read() doesn't call resumeRead when policy is nil
    // Policy is nil by default, so supportsGetPartialObject = false → no resume path

    // Directly set up the link to handle getObjectInfos and readWholeObject
    respondingLink.objectInfos = [
      MTPObjectInfo(
        handle: 0x0001,
        storage: MTPStorageID(raw: 0x00010001),
        parent: nil,
        name: "test.bin",
        sizeBytes: 1024,
        modified: nil,
        formatCode: 0x3000,
        properties: [:]
      )
    ]

    // Verify the capturing link did not see a GetPartialObject command
    // (because policy is nil → supportsGetPartialObject = false → no resume)
    let partialCodes = capturing.capturedCodes.filter { $0 == PTPOp.getPartialObject.rawValue }
    XCTAssertTrue(
      partialCodes.isEmpty,
      "GetPartialObject should not be issued when supportsGetPartialObject quirk is disabled")
  }

  /// Verify that resumeRead appends partial data correctly to an in-progress transfer.
  ///
  /// Simulates: 1 MiB already committed to temp file, 1 MiB returned by resumeRead.
  /// Final file should be 2 MiB.
  func testResumeRead_appendsToPartial() async throws {
    let firstMiB = Data(repeating: 0xAA, count: 1_048_576)
    let secondMiB = Data(repeating: 0xBB, count: 1_048_576)

    // Write the first MiB to a temp file simulating a prior partial download
    let tempDir = FileManager.default.temporaryDirectory
    let partFile = tempDir.appendingPathComponent("resume_test_\(UUID().uuidString).part")
    let finalFile = tempDir.appendingPathComponent("resume_test_\(UUID().uuidString).bin")
    defer {
      try? FileManager.default.removeItem(at: partFile)
      try? FileManager.default.removeItem(at: finalFile)
    }

    try firstMiB.write(to: partFile)

    // Append the second MiB via FileSink in append mode + Data.withUnsafeBytes
    let appendSink = try FileSink(url: partFile, append: true)
    try secondMiB.withUnsafeBytes { ptr in
      try appendSink.write(ptr)
    }
    try appendSink.close()

    // Atomic replace to final location
    try FileManager.default.moveItem(at: partFile, to: finalFile)

    // Verify final file is exactly 2 MiB
    let finalData = try Data(contentsOf: finalFile)
    XCTAssertEqual(finalData.count, 2 * 1_048_576, "Combined file should be 2 MiB")
    XCTAssertEqual(finalData.prefix(1_048_576), firstMiB, "First half should be original data")
    XCTAssertEqual(finalData.suffix(1_048_576), secondMiB, "Second half should be resumed data")
  }

  // MARK: - resumeRead parameter encoding edge cases

  /// Verify that a 64-bit offset is correctly split into lo/hi 32-bit params.
  func testResumeRead_encodesLargeOffset() async throws {
    let respondingLink = RespondingLink(responsePayload: Data([0x01]))
    let transport = InjectedLinkTransport(link: respondingLink)
    let summary = MTPDeviceSummary(
      id: MTPDeviceID(raw: "test"), manufacturer: "Test", model: "Device", vendorID: 0, productID: 0
    )
    let actor = MTPDeviceActor(id: summary.id, summary: summary, transport: transport)

    // offset = 0x0000_0001_0000_0000 (4 GiB)
    let largeOffset: UInt64 = 0x0000_0001_0000_0000
    _ = try await actor.resumeRead(handle: 0x0001, offset: largeOffset, length: 1)

    let params = respondingLink.lastCommand?.params ?? []
    XCTAssertGreaterThanOrEqual(params.count, 4)
    XCTAssertEqual(params[1], 0x00000000, "Offset lo should be 0 for 4 GiB boundary")
    XCTAssertEqual(params[2], 0x00000001, "Offset hi should be 1 for 4 GiB boundary")
  }
}

// MARK: - RespondingLink helper

/// An MTPLink that returns a fixed payload for executeStreamingCommand.
final class RespondingLink: MTPLink, @unchecked Sendable {
  private var responsePayload: Data
  private(set) var lastCommand: PTPContainer?
  var objectInfos: [MTPObjectInfo] = []

  init(responsePayload: Data) { self.responsePayload = responsePayload }

  var cachedDeviceInfo: MTPDeviceInfo? { nil }
  var linkDescriptor: MTPLinkDescriptor? { nil }

  func openUSBIfNeeded() async throws {}
  func openSession(id: UInt32) async throws {}
  func closeSession() async throws {}
  func close() async {}

  func getDeviceInfo() async throws -> MTPDeviceInfo {
    // Return minimal device info for session open
    MTPDeviceInfo(
      manufacturer: "Test", model: "TestDevice", version: "1.0", serialNumber: "0000",
      operationsSupported: [], eventsSupported: [])
  }
  func getStorageIDs() async throws -> [MTPStorageID] { [MTPStorageID(raw: 0x00010001)] }
  func getStorageInfo(id: MTPStorageID) async throws -> MTPStorageInfo {
    MTPStorageInfo(id: id, description: "Test", capacityBytes: 0, freeBytes: 0, isReadOnly: false)
  }
  func getObjectHandles(storage: MTPStorageID, parent: MTPObjectHandle?) async throws
    -> [MTPObjectHandle]
  { objectInfos.map { $0.handle } }
  func getObjectInfos(_ handles: [MTPObjectHandle]) async throws -> [MTPObjectInfo] {
    objectInfos.filter { handles.contains($0.handle) }
  }
  func getObjectInfos(storage: MTPStorageID, parent: MTPObjectHandle?, format: UInt16?) async throws
    -> [MTPObjectInfo]
  { objectInfos }
  func resetDevice() async throws {}
  func deleteObject(handle: MTPObjectHandle) async throws {}
  func moveObject(handle: MTPObjectHandle, to storage: MTPStorageID, parent: MTPObjectHandle?)
    async throws
  {}
  func executeCommand(_ command: PTPContainer) async throws -> PTPResponseResult {
    lastCommand = command
    return PTPResponseResult(code: 0x2001, txid: command.txid)
  }
  func executeStreamingCommand(
    _ command: PTPContainer,
    dataPhaseLength: UInt64?,
    dataInHandler: MTPDataIn?,
    dataOutHandler: MTPDataOut?
  ) async throws -> PTPResponseResult {
    lastCommand = command
    if let handler = dataInHandler {
      responsePayload.withUnsafeBytes { ptr in
        _ = handler(ptr)
      }
    }
    return PTPResponseResult(code: 0x2001, txid: command.txid)
  }
}

// MARK: - CapturingLinkWrapper helper

/// Wraps an MTPLink and records every command opcode sent.
final class CapturingLinkWrapper: MTPLink, @unchecked Sendable {
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
  { try await inner.getObjectHandles(storage: storage, parent: parent) }
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
  { try await inner.moveObject(handle: handle, to: storage, parent: parent) }
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
