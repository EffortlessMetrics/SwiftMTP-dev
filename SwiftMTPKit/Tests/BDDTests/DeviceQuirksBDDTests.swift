// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import XCTest
@testable import SwiftMTPCore
import SwiftMTPTestKit
import SwiftMTPQuirks

// MARK: - Device Quirks BDD Scenarios

final class DeviceQuirksBDDTests: XCTestCase {

  // MARK: Scenario: Known quirky device gets correct tuning

  func testKnownDevice_OnePlus3T_GetsPropListDisabled() throws {
    let db = try QuirkDatabase.load()
    guard
      let quirk = db.match(
        vid: 0x2A70, pid: 0xF003, bcdDevice: nil,
        ifaceClass: 0x06, ifaceSubclass: 0x01, ifaceProtocol: 0x01)
    else {
      XCTFail("OnePlus 3T quirk expected in DB")
      return
    }
    XCTAssertFalse(
      quirk.resolvedFlags().supportsGetObjectPropList,
      "OnePlus 3T must have supportsGetObjectPropList=false")
  }

  func testKnownDevice_SamsungGalaxy_GetsKernelDetach() throws {
    let db = try QuirkDatabase.load()
    guard
      let quirk = db.match(
        vid: 0x04E8, pid: 0x6860, bcdDevice: nil,
        ifaceClass: 0xFF, ifaceSubclass: nil, ifaceProtocol: nil)
    else {
      XCTFail("Samsung Galaxy quirk expected in DB")
      return
    }
    XCTAssertTrue(
      quirk.resolvedFlags().requiresKernelDetach,
      "Samsung Galaxy must require kernel detach")
  }

  func testKnownDevice_Pixel7_RequiresKernelDetach() throws {
    let db = try QuirkDatabase.load()
    guard
      let quirk = db.match(
        vid: 0x18D1, pid: 0x4EE1, bcdDevice: nil,
        ifaceClass: 0x06, ifaceSubclass: 0x01, ifaceProtocol: 0x01)
    else {
      XCTFail("Pixel 7 quirk expected in DB")
      return
    }
    XCTAssertTrue(
      quirk.resolvedFlags().requiresKernelDetach,
      "Pixel 7 must require kernel detach")
  }

  func testKnownDevice_CanonEOS_CameraClass() throws {
    let db = try QuirkDatabase.load()
    guard
      let quirk = db.match(
        vid: 0x04A9, pid: 0x3139, bcdDevice: nil,
        ifaceClass: 0x06, ifaceSubclass: 0x01, ifaceProtocol: 0x01)
    else {
      XCTFail("Canon EOS Rebel quirk expected in DB")
      return
    }
    XCTAssertTrue(
      quirk.resolvedFlags().cameraClass,
      "Canon EOS must have cameraClass flag set")
  }

  func testKnownDevice_NikonDSLR_CameraClass() throws {
    let db = try QuirkDatabase.load()
    guard
      let quirk = db.match(
        vid: 0x04B0, pid: 0x0410, bcdDevice: nil,
        ifaceClass: 0x06, ifaceSubclass: 0x01, ifaceProtocol: 0x01)
    else {
      XCTFail("Nikon DSLR quirk expected in DB")
      return
    }
    XCTAssertTrue(
      quirk.resolvedFlags().cameraClass,
      "Nikon DSLR must have cameraClass flag set")
  }

  func testKnownDevice_XiaomiMiNote2_QuirkPresent() throws {
    let db = try QuirkDatabase.load()
    let quirk = db.match(
      vid: 0x2717, pid: 0xFF10, bcdDevice: nil,
      ifaceClass: 0x06, ifaceSubclass: 0x01, ifaceProtocol: 0x01)
    XCTAssertNotNil(quirk, "Xiaomi Mi Note 2 (ff10) must have a quirk entry")
    XCTAssertEqual(quirk?.id, "xiaomi-mi-note-2-ff10")
  }

  // MARK: Scenario: Unknown device uses safe defaults

  func testUnknownDevice_NoQuirkMatch() throws {
    let db = try QuirkDatabase.load()
    let quirk = db.match(
      vid: 0xFFFF, pid: 0xFFFF, bcdDevice: nil,
      ifaceClass: 0xFF, ifaceSubclass: 0xFF, ifaceProtocol: 0x00)
    XCTAssertNil(quirk, "Unknown VID:PID should not match any quirk entry")
  }

  func testUnknownDevice_SafeDefaultPolicy() throws {
    let policy = EffectiveTuningBuilder.buildPolicy(
      capabilities: [:], learned: nil, quirk: nil, overrides: nil, ifaceClass: nil)
    XCTAssertFalse(
      policy.flags.supportsGetObjectPropList,
      "Safe defaults should disable GetObjectPropList")
    XCTAssertTrue(
      policy.flags.requiresKernelDetach,
      "Safe defaults require kernel detach (safety-first)")
  }

  func testUnknownDevice_PolicyWithPTPClass() throws {
    let policy = EffectiveTuningBuilder.buildPolicy(
      capabilities: [:], learned: nil, quirk: nil, overrides: nil, ifaceClass: 0x06)
    XCTAssertTrue(
      policy.flags.supportsGetObjectPropList,
      "PTP class device should have supportsGetObjectPropList=true by default")
  }

  func testUnknownDevice_PolicyWithAndroidClass() throws {
    let policy = EffectiveTuningBuilder.buildPolicy(
      capabilities: [:], learned: nil, quirk: nil, overrides: nil, ifaceClass: 0xFF)
    XCTAssertFalse(
      policy.flags.supportsGetObjectPropList,
      "Android vendor-specific class should default to proplist disabled")
  }

  // MARK: Scenario: Device with broken GetObjectPropList uses fallback

  func testBrokenPropList_AutoDisablesOnNotSupported() async throws {
    let inner = VirtualMTPLink(config: .pixel7)
    let notSupportedLink = QuirkBDDNotSupportedLink(inner: inner)
    let transport = QuirkBDDInjectedLinkTransport(link: notSupportedLink)
    let summary = MTPDeviceSummary(
      id: MTPDeviceID(raw: "bdd-broken-proplist"),
      manufacturer: "Test", model: "BrokenPropListDevice",
      vendorID: 0x0000, productID: 0x0002)
    let actor = MTPDeviceActor(id: summary.id, summary: summary, transport: transport)

    try await actor.openIfNeeded()

    var flags = QuirkFlags()
    flags.supportsGetObjectPropList = true
    await actor.bddOverridePolicy(flags: flags)

    _ = try await actor.getObjectPropList(parentHandle: 0xFFFF_FFFF)

    let policy = await actor.devicePolicy
    XCTAssertFalse(
      policy?.flags.supportsGetObjectPropList ?? true,
      "GetObjectPropList must be auto-disabled after OperationNotSupported response")
  }

  func testBrokenPropList_FallbackEnumerationWorks() async throws {
    let device = VirtualMTPDevice(config: .pixel7)
    try await device.openIfNeeded()
    let storage = MTPStorageID(raw: 0x0001_0001)
    await device.addObject(
      VirtualObjectConfig(
        handle: 900, storage: storage, parent: nil,
        name: "fallback-test.txt", formatCode: 0x3000, data: Data("fb".utf8)))
    var names: [String] = []
    for try await batch in device.list(parent: nil, in: storage) {
      names.append(contentsOf: batch.map(\.name))
    }
    XCTAssertTrue(
      names.contains("fallback-test.txt"),
      "Fallback enumeration must list objects correctly")
  }

  // MARK: Scenario: Device requiring kernel detach is handled automatically

  func testKernelDetach_SamsungRequiresIt() throws {
    let db = try QuirkDatabase.load()
    guard
      let quirk = db.match(
        vid: 0x04E8, pid: 0x6860, bcdDevice: nil,
        ifaceClass: 0xFF, ifaceSubclass: nil, ifaceProtocol: nil)
    else {
      XCTFail("Samsung Galaxy quirk expected in DB")
      return
    }
    let policy = EffectiveTuningBuilder.buildPolicy(
      capabilities: [:], learned: nil, quirk: quirk, overrides: nil,
      ifaceClass: quirk.ifaceClass)
    XCTAssertTrue(
      policy.flags.requiresKernelDetach,
      "Samsung Galaxy policy must require kernel detach")
  }

  func testKernelDetach_AmazonKindleFire() throws {
    let db = try QuirkDatabase.load()
    guard
      let quirk = db.match(
        vid: 0x1949, pid: 0x0007, bcdDevice: nil,
        ifaceClass: 0xFF, ifaceSubclass: 0xFF, ifaceProtocol: 0x00)
    else {
      XCTFail("Amazon Kindle Fire quirk expected in DB")
      return
    }
    XCTAssertTrue(
      quirk.resolvedFlags().requiresKernelDetach,
      "Kindle Fire must require kernel detach")
  }

  func testKernelDetach_CameraStillRequiresIt() throws {
    let db = try QuirkDatabase.load()
    guard
      let quirk = db.match(
        vid: 0x04A9, pid: 0x32B4, bcdDevice: nil,
        ifaceClass: 0x06, ifaceSubclass: 0x01, ifaceProtocol: 0x01)
    else {
      XCTFail("Canon EOS R5 quirk expected in DB")
      return
    }
    XCTAssertTrue(
      quirk.resolvedFlags().requiresKernelDetach,
      "Canon EOS R5 requires kernel detach per quirk DB")
  }

  // MARK: Scenario: Quirk database structural integrity

  func testQuirkDatabase_HasReasonableSize() throws {
    let db = try QuirkDatabase.load()
    XCTAssertGreaterThan(
      db.entries.count, 100,
      "Quirk database should have substantial entries")
  }

  func testQuirkDatabase_AllEntriesHaveIDs() throws {
    let db = try QuirkDatabase.load()
    for entry in db.entries {
      XCTAssertFalse(entry.id.isEmpty, "Every quirk entry must have a non-empty ID")
    }
  }

  func testQuirkDatabase_NoDuplicateIDs() throws {
    let db = try QuirkDatabase.load()
    let ids = db.entries.map(\.id)
    let uniqueIDs = Set(ids)
    XCTAssertEqual(ids.count, uniqueIDs.count, "Quirk IDs must be unique")
  }

  func testQuirkDatabase_MaxChunkBytesReasonable() throws {
    let db = try QuirkDatabase.load()
    for entry in db.entries where entry.maxChunkBytes != nil {
      XCTAssertGreaterThan(
        entry.maxChunkBytes!, 0,
        "maxChunkBytes for \(entry.id) must be positive")
      XCTAssertLessThanOrEqual(
        entry.maxChunkBytes!, 64 * 1024 * 1024,
        "maxChunkBytes for \(entry.id) must not exceed 64MB")
    }
  }

  // MARK: Scenario: Policy resolution with overrides

  func testPolicyOverride_ChangesChunkSize() throws {
    let db = try QuirkDatabase.load()
    guard
      let quirk = db.match(
        vid: 0x04A9, pid: 0x32B4, bcdDevice: nil,
        ifaceClass: 0x06, ifaceSubclass: 0x01, ifaceProtocol: 0x01)
    else {
      XCTFail("Canon EOS R5 quirk expected")
      return
    }
    let overrides = ["maxChunkBytes": "1048576"]
    let policy = EffectiveTuningBuilder.buildPolicy(
      capabilities: [:], learned: nil, quirk: quirk, overrides: overrides,
      ifaceClass: quirk.ifaceClass)
    XCTAssertEqual(
      policy.tuning.maxChunkBytes, 1_048_576,
      "Override should set custom chunk size")
  }

  // MARK: Scenario: Virtual device respects quirk-based configuration

  func testVirtualDevice_Pixel7_OpensWithQuirkAwareConfig() async throws {
    let device = VirtualMTPDevice(config: .pixel7)
    try await device.openIfNeeded()
    let info = try await device.devGetDeviceInfoUncached()
    XCTAssertEqual(info.manufacturer, "Google")
    XCTAssertEqual(info.model, "Pixel 7")
  }

  func testVirtualDevice_SamsungGalaxy_OpensWithQuirkAwareConfig() async throws {
    let device = VirtualMTPDevice(config: .samsungGalaxy)
    try await device.openIfNeeded()
    let info = try await device.devGetDeviceInfoUncached()
    XCTAssertEqual(info.manufacturer, "Samsung")
  }

  func testVirtualDevice_CanonCamera_OpensWithQuirkAwareConfig() async throws {
    let device = VirtualMTPDevice(config: .canonEOSR5)
    try await device.openIfNeeded()
    let info = try await device.devGetDeviceInfoUncached()
    XCTAssertEqual(info.manufacturer, "Canon")
  }
}

// MARK: - Helper Links (quirk-specific BDD tests)

/// Link that returns OperationNotSupported (0x2005) for GetObjectPropList.
private final class QuirkBDDNotSupportedLink: MTPLink, @unchecked Sendable {
  private let inner: any MTPLink

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
    try await inner.executeCommand(command)
  }
  func executeStreamingCommand(
    _ command: PTPContainer,
    dataPhaseLength: UInt64?,
    dataInHandler: MTPDataIn?,
    dataOutHandler: MTPDataOut?
  ) async throws -> PTPResponseResult {
    if command.code == MTPOp.getObjectPropList.rawValue {
      return PTPResponseResult(code: 0x2005, txid: command.txid)
    }
    return try await inner.executeStreamingCommand(
      command, dataPhaseLength: dataPhaseLength,
      dataInHandler: dataInHandler, dataOutHandler: dataOutHandler)
  }
}

/// Injects a custom link into a transport for BDD testing.
private final class QuirkBDDInjectedLinkTransport: MTPTransport, @unchecked Sendable {
  private let link: any MTPLink
  init(link: any MTPLink) { self.link = link }
  func open(_ summary: MTPDeviceSummary, config: SwiftMTPConfig) async throws -> any MTPLink {
    link
  }
  func close() async throws {}
}
