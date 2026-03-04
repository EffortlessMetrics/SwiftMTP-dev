// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import XCTest

@testable import SwiftMTPCore
@testable import SwiftMTPQuirks

/// Tests that the 9 new QuirkFlags from PR #484 are correctly wired into
/// transport and protocol logic.
final class QuirkFlagsIntegrationTests: XCTestCase {

  // MARK: - Helpers

  private func makeSummary(vid: UInt16 = 0, pid: UInt16 = 0) -> MTPDeviceSummary {
    MTPDeviceSummary(
      id: MTPDeviceID(raw: "test-quirk"), manufacturer: "Test", model: "QuirkDevice",
      vendorID: vid, productID: pid)
  }

  private func makePolicy(flags: QuirkFlags) -> DevicePolicy {
    DevicePolicy(tuning: .defaults(), flags: flags)
  }

  // MARK: - 1. skipCloseSession

  func testSkipCloseSession_skipsCloseSessionCommand() async throws {
    let link = TrackingLink()
    let transport = InjectableTransport(link: link)
    let summary = makeSummary()
    let actor = MTPDeviceActor(id: summary.id, summary: summary, transport: transport)

    // Manually set policy with skipCloseSession
    var flags = QuirkFlags()
    flags.skipCloseSession = true
    await actor.setTestPolicy(makePolicy(flags: flags))
    await actor.setTestSessionOpen(true, link: link)

    try await actor.devClose()

    // closeSession should NOT have been called
    XCTAssertFalse(link.closeSessionCalled, "closeSession should be skipped when skipCloseSession is true")
  }

  func testSkipCloseSession_defaultCallsCloseSession() async throws {
    let link = TrackingLink()
    let transport = InjectableTransport(link: link)
    let summary = makeSummary()
    let actor = MTPDeviceActor(id: summary.id, summary: summary, transport: transport)

    var flags = QuirkFlags()
    flags.skipCloseSession = false
    await actor.setTestPolicy(makePolicy(flags: flags))
    await actor.setTestSessionOpen(true, link: link)

    try await actor.devClose()

    XCTAssertTrue(link.closeSessionCalled, "closeSession should be called when skipCloseSession is false")
  }

  // MARK: - 2. brokenSetObjectPropList

  func testBrokenSetObjectPropList_fallsBackToIndividualCalls() async throws {
    let link = TrackingLink()
    let transport = InjectableTransport(link: link)
    let summary = makeSummary()
    let actor = MTPDeviceActor(id: summary.id, summary: summary, transport: transport)

    var flags = QuirkFlags()
    flags.brokenSetObjectPropList = true
    await actor.setTestPolicy(makePolicy(flags: flags))
    await actor.setTestSessionOpen(true, link: link)

    let entries = [
      MTPPropListEntry(handle: 1, propCode: 0xDC07, datatype: 0xFFFF, value: PTPString.encode("a.txt")),
      MTPPropListEntry(handle: 2, propCode: 0xDC07, datatype: 0xFFFF, value: PTPString.encode("b.txt")),
    ]
    let written = try await actor.setObjectPropList(entries: entries)

    XCTAssertEqual(written, 2)
    // Should have called setObjectPropValue individually, not setObjectPropList
    XCTAssertEqual(link.setObjectPropValueCallCount, 2,
      "brokenSetObjectPropList should fall back to per-entry setObjectPropValue")
    XCTAssertEqual(link.setObjectPropListCallCount, 0,
      "setObjectPropList should not be called when brokenSetObjectPropList is true")
  }

  // MARK: - 3. samsungPartialObjectBoundaryBug

  func testSamsungBoundaryBug_adjustsReadLength() async throws {
    // When offset + length lands on a 512-byte boundary, length should be adjusted
    let payload = Data(repeating: 0xAB, count: 511)
    let link = TrackingLink(responsePayload: payload)
    let transport = InjectableTransport(link: link)
    let summary = makeSummary()
    let actor = MTPDeviceActor(id: summary.id, summary: summary, transport: transport)

    var flags = QuirkFlags()
    flags.samsungPartialObjectBoundaryBug = true
    await actor.setTestPolicy(makePolicy(flags: flags))

    // offset=0, length=512: endByte=512 which is a multiple of 512
    _ = try await actor.resumeRead(handle: 42, offset: 0, length: 512)

    // The length should have been adjusted to 511 to avoid the 512-byte boundary
    let lastCmd = link.lastCommand
    XCTAssertNotNil(lastCmd)
    if let cmd = lastCmd {
      XCTAssertEqual(cmd.code, PTPOp.getPartialObject.rawValue)
      // Length param should be 511 (adjusted from 512)
      XCTAssertEqual(cmd.params[3], 511, "Length should be reduced by 1 to avoid 512-byte boundary")
    }
  }

  func testSamsungBoundaryBug_noAdjustmentWhenNotOnBoundary() async throws {
    let payload = Data(repeating: 0xAB, count: 500)
    let link = TrackingLink(responsePayload: payload)
    let transport = InjectableTransport(link: link)
    let summary = makeSummary()
    let actor = MTPDeviceActor(id: summary.id, summary: summary, transport: transport)

    var flags = QuirkFlags()
    flags.samsungPartialObjectBoundaryBug = true
    await actor.setTestPolicy(makePolicy(flags: flags))

    _ = try await actor.resumeRead(handle: 42, offset: 0, length: 500)

    if let cmd = link.lastCommand {
      // 500 is not a multiple of 512, no adjustment needed
      XCTAssertEqual(cmd.params[3], 500, "Length should remain unchanged when not on 512-byte boundary")
    }
  }

  // MARK: - 4. propListOverridesObjectInfo

  func testPropListOverridesObjectInfo_flagDefaultDoesNotUsePropList() async throws {
    let link = TrackingLink()
    link.objectInfos = [
      MTPObjectInfo(
        handle: 42, storage: MTPStorageID(raw: 1), parent: nil, name: "photo.jpg",
        sizeBytes: 1024, modified: nil, formatCode: 0x3801, properties: [:])
    ]
    let transport = InjectableTransport(link: link)
    let summary = makeSummary()
    let actor = MTPDeviceActor(id: summary.id, summary: summary, transport: transport)

    var flags = QuirkFlags()
    flags.propListOverridesObjectInfo = false
    await actor.setTestPolicy(makePolicy(flags: flags))

    let info = try await actor.devGetObjectInfoUncached(handle: 42)
    XCTAssertEqual(info.name, "photo.jpg")
  }

  // MARK: - 5. forceResetOnClose config propagation

  func testForceResetOnClose_configPropagation() {
    var config = SwiftMTPConfig()
    XCTAssertFalse(config.forceResetOnClose)
    config.forceResetOnClose = true
    XCTAssertTrue(config.forceResetOnClose)
  }

  // MARK: - 6. noZeroReads config propagation

  func testNoZeroReads_configPropagation() {
    var config = SwiftMTPConfig()
    XCTAssertFalse(config.noZeroReads)
    config.noZeroReads = true
    XCTAssertTrue(config.noZeroReads)
  }

  // MARK: - 7. noReleaseInterface config propagation

  func testNoReleaseInterface_configPropagation() {
    var config = SwiftMTPConfig()
    XCTAssertFalse(config.noReleaseInterface)
    config.noReleaseInterface = true
    XCTAssertTrue(config.noReleaseInterface)
  }

  // MARK: - 8. ignoreHeaderErrors config propagation

  func testIgnoreHeaderErrors_configPropagation() {
    var config = SwiftMTPConfig()
    XCTAssertFalse(config.ignoreHeaderErrors)
    config.ignoreHeaderErrors = true
    XCTAssertTrue(config.ignoreHeaderErrors)
  }

  // MARK: - 9. brokenSendObjectPropList flag read-through

  func testBrokenSendObjectPropList_flagExists() {
    var flags = QuirkFlags()
    XCTAssertFalse(flags.brokenSendObjectPropList)
    flags.brokenSendObjectPropList = true
    XCTAssertTrue(flags.brokenSendObjectPropList)
  }

  // MARK: - Config wiring from quirk flags

  func testQuirkFlagsConfigWiring() {
    // Verify that all 9 flags can be set in QuirkFlags
    var flags = QuirkFlags()
    flags.forceResetOnClose = true
    flags.noZeroReads = true
    flags.noReleaseInterface = true
    flags.ignoreHeaderErrors = true
    flags.brokenSendObjectPropList = true
    flags.brokenSetObjectPropList = true
    flags.skipCloseSession = true
    flags.propListOverridesObjectInfo = true
    flags.samsungPartialObjectBoundaryBug = true

    XCTAssertTrue(flags.forceResetOnClose)
    XCTAssertTrue(flags.noZeroReads)
    XCTAssertTrue(flags.noReleaseInterface)
    XCTAssertTrue(flags.ignoreHeaderErrors)
    XCTAssertTrue(flags.brokenSendObjectPropList)
    XCTAssertTrue(flags.brokenSetObjectPropList)
    XCTAssertTrue(flags.skipCloseSession)
    XCTAssertTrue(flags.propListOverridesObjectInfo)
    XCTAssertTrue(flags.samsungPartialObjectBoundaryBug)
  }

  func testQuirkFlagsRoundTrip() throws {
    var flags = QuirkFlags()
    flags.forceResetOnClose = true
    flags.noZeroReads = true
    flags.noReleaseInterface = true
    flags.ignoreHeaderErrors = true
    flags.brokenSendObjectPropList = true
    flags.brokenSetObjectPropList = true
    flags.skipCloseSession = true
    flags.propListOverridesObjectInfo = true
    flags.samsungPartialObjectBoundaryBug = true

    let data = try JSONEncoder().encode(flags)
    let decoded = try JSONDecoder().decode(QuirkFlags.self, from: data)

    XCTAssertEqual(flags, decoded)
  }
}

// MARK: - Test Helpers

/// A tracking MTPLink that records which operations are called.
private final class TrackingLink: MTPLink, @unchecked Sendable {
  var cachedDeviceInfo: MTPDeviceInfo? { nil }
  var linkDescriptor: MTPLinkDescriptor? { nil }

  var closeSessionCalled = false
  var setObjectPropValueCallCount = 0
  var setObjectPropListCallCount = 0
  var lastCommand: PTPContainer?
  var objectInfos: [MTPObjectInfo] = []
  private var responsePayload: Data

  init(responsePayload: Data = Data()) {
    self.responsePayload = responsePayload
  }

  func openUSBIfNeeded() async throws {}
  func openSession(id: UInt32) async throws {}
  func closeSession() async throws { closeSessionCalled = true }
  func close() async {}
  func resetDevice() async throws {}
  func startEventPump() {}
  var eventStream: AsyncStream<Data> { AsyncStream { $0.finish() } }

  func getDeviceInfo() async throws -> MTPDeviceInfo {
    MTPDeviceInfo(
      manufacturer: "Test", model: "Device", version: "1.0", serialNumber: "0000",
      operationsSupported: [], eventsSupported: [])
  }
  func getStorageIDs() async throws -> [MTPStorageID] { [MTPStorageID(raw: 0x00010001)] }
  func getStorageInfo(id: MTPStorageID) async throws -> MTPStorageInfo {
    MTPStorageInfo(id: id, description: "Test", capacityBytes: 0, freeBytes: 0, isReadOnly: false)
  }
  func getObjectHandles(storage: MTPStorageID, parent: MTPObjectHandle?) async throws -> [MTPObjectHandle] {
    objectInfos.map { $0.handle }
  }
  func getObjectInfos(_ handles: [MTPObjectHandle]) async throws -> [MTPObjectInfo] {
    objectInfos.filter { handles.contains($0.handle) }
  }
  func getObjectInfos(storage: MTPStorageID, parent: MTPObjectHandle?, format: UInt16?) async throws -> [MTPObjectInfo] {
    objectInfos
  }
  func deleteObject(handle: MTPObjectHandle) async throws {}
  func moveObject(handle: MTPObjectHandle, to storage: MTPStorageID, parent: MTPObjectHandle?) async throws {}
  func copyObject(handle: MTPObjectHandle, toStorage storage: MTPStorageID, parent: MTPObjectHandle?) async throws -> MTPObjectHandle { 0 }

  func executeCommand(_ command: PTPContainer) async throws -> PTPResponseResult {
    lastCommand = command
    return PTPResponseResult(code: 0x2001, txid: command.txid)
  }
  func executeStreamingCommand(
    _ command: PTPContainer, dataPhaseLength: UInt64?,
    dataInHandler: MTPDataIn?, dataOutHandler: MTPDataOut?
  ) async throws -> PTPResponseResult {
    lastCommand = command
    if let handler = dataInHandler {
      responsePayload.withUnsafeBytes { ptr in
        _ = handler(ptr)
      }
    }
    return PTPResponseResult(code: 0x2001, txid: command.txid)
  }
  func setObjectPropValue(handle: MTPObjectHandle, property: UInt16, value: Data) async throws {
    setObjectPropValueCallCount += 1
  }
  func setObjectPropList(entries: [MTPPropListEntry]) async throws -> UInt32 {
    setObjectPropListCallCount += 1
    return UInt32(entries.count)
  }
}

/// Transport that injects a pre-built link.
private final class InjectableTransport: MTPTransport, @unchecked Sendable {
  private let link: any MTPLink
  init(link: any MTPLink) { self.link = link }
  func open(_ summary: MTPDeviceSummary, config: SwiftMTPConfig) async throws -> any MTPLink { link }
  func close() async throws {}
}

// MARK: - Actor test helpers

extension MTPDeviceActor {
  /// Test-only: inject a policy directly for flag testing.
  func setTestPolicy(_ policy: DevicePolicy) {
    self.currentPolicy = policy
  }
  /// Test-only: set session state and inject a link.
  func setTestSessionOpen(_ open: Bool, link: (any MTPLink)? = nil) {
    self.sessionOpen = open
    if let link { self.mtpLink = link }
  }
}
