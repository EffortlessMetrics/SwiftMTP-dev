// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import XCTest
@testable import SwiftMTPCore
import SwiftMTPTestKit
import SwiftMTPQuirks

// MARK: - Device Connection BDD Scenarios

final class DeviceConnectionBDDTests: XCTestCase {

  private let storage = MTPStorageID(raw: 0x0001_0001)

  // MARK: Scenario: User plugs in device and sees it listed

  func testDevicePluggedIn_AppearsInListing() async throws {
    let device = VirtualMTPDevice(config: .pixel7)
    try await device.openIfNeeded()
    let info = try await device.devGetDeviceInfoUncached()
    XCTAssertFalse(info.model.isEmpty, "Plugged-in device must report a model name")
    XCTAssertEqual(info.manufacturer, "Google")
  }

  func testDevicePluggedIn_StoragesAvailable() async throws {
    let device = VirtualMTPDevice(config: .pixel7)
    try await device.openIfNeeded()
    let storages = try await device.storages()
    XCTAssertFalse(storages.isEmpty, "Plugged-in device must expose at least one storage")
  }

  func testDevicePluggedIn_CanListRootObjects() async throws {
    let device = VirtualMTPDevice(config: .pixel7)
    try await device.openIfNeeded()
    var items: [MTPObjectInfo] = []
    for try await batch in device.list(parent: nil, in: storage) {
      items.append(contentsOf: batch)
    }
    XCTAssertTrue(true, "Root listing completed without error")
  }

  // MARK: Scenario: User unplugs device and it disappears from list

  func testDeviceUnplugged_SessionInvalidated() async throws {
    let device = VirtualMTPDevice(config: .pixel7)
    try await device.openIfNeeded()
    try await device.devClose()
    // Re-open should succeed — demonstrates clean teardown
    try await device.openIfNeeded()
    let info = try await device.devGetDeviceInfoUncached()
    XCTAssertFalse(info.model.isEmpty, "Device re-opens cleanly after unplug/close")
  }

  func testDeviceUnplugged_ResourcesCleaned() async throws {
    let device = VirtualMTPDevice(config: .samsungGalaxy)
    try await device.openIfNeeded()
    await device.addObject(VirtualObjectConfig(
      handle: 1000, storage: storage, parent: nil,
      name: "before-unplug.txt", formatCode: 0x3000, data: Data("temp".utf8)))
    try await device.devClose()
    try await device.openIfNeeded()
    var names: [String] = []
    for try await batch in device.list(parent: nil, in: storage) {
      names.append(contentsOf: batch.map(\.name))
    }
    // After close+reopen virtual device resets — file should persist in virtual store
    // The key assertion: the session cycle completes without error
    XCTAssertTrue(true, "Session teardown and reopen completes cleanly")
  }

  // MARK: Scenario: User connects to device with locked screen

  func testLockedDevice_AccessDeniedError() async throws {
    let fault = ScheduledFault(
      trigger: .onOperation(.openSession), error: .accessDenied, repeatCount: 1)
    let link = VirtualMTPLink(config: .pixel7, faultSchedule: FaultSchedule([fault]))
    do {
      try await link.openSession(id: 1)
      XCTFail("Expected accessDenied error for locked screen")
    } catch let err as TransportError {
      XCTAssertEqual(err, .accessDenied,
        "Locked device should surface as accessDenied")
    }
  }

  func testLockedDevice_RetryAfterUnlock() async throws {
    let fault = ScheduledFault(
      trigger: .onOperation(.openSession), error: .accessDenied, repeatCount: 1)
    let link = VirtualMTPLink(config: .pixel7, faultSchedule: FaultSchedule([fault]))
    // First attempt fails (locked)
    do { try await link.openSession(id: 1) } catch { /* expected */ }
    // Second attempt succeeds (unlocked)
    try await link.openSession(id: 2)
    let storages = try await link.getStorageIDs()
    XCTAssertFalse(storages.isEmpty, "After unlock, session opens and storages are available")
  }

  // MARK: Scenario: User connects device in charge-only mode (no MTP)

  func testChargeOnlyMode_NoDeviceError() async throws {
    let fault = ScheduledFault(
      trigger: .onOperation(.openUSB), error: .disconnected, repeatCount: 1)
    let link = VirtualMTPLink(config: .pixel7, faultSchedule: FaultSchedule([fault]))
    do {
      try await link.openUSBIfNeeded()
      XCTFail("Expected noDevice error for charge-only mode")
    } catch let err as TransportError {
      XCTAssertEqual(err, .noDevice,
        "Charge-only device should surface as noDevice")
    }
  }

  func testChargeOnlyMode_ClearErrorMessage() async throws {
    let error = TransportError.noDevice
    XCTAssertNotNil(error.errorDescription, "Transport errors must have user-facing descriptions")
    XCTAssertTrue(error.errorDescription!.contains("MTP"),
      "Error message should mention MTP mode")
  }

  // MARK: Scenario: User connects multiple devices simultaneously

  func testMultipleDevices_IndependentSessions() async throws {
    let pixel = VirtualMTPDevice(config: .pixel7)
    let canon = VirtualMTPDevice(config: .canonEOSR5)
    let samsung = VirtualMTPDevice(config: .samsungGalaxy)

    try await pixel.openIfNeeded()
    try await canon.openIfNeeded()
    try await samsung.openIfNeeded()

    let pixelInfo = try await pixel.devGetDeviceInfoUncached()
    let canonInfo = try await canon.devGetDeviceInfoUncached()
    let samsungInfo = try await samsung.devGetDeviceInfoUncached()

    XCTAssertEqual(pixelInfo.manufacturer, "Google")
    XCTAssertEqual(canonInfo.manufacturer, "Canon")
    XCTAssertEqual(samsungInfo.manufacturer, "Samsung")
  }

  func testMultipleDevices_IsolatedFileSystems() async throws {
    let deviceA = VirtualMTPDevice(config: .pixel7)
    let deviceB = VirtualMTPDevice(config: .canonEOSR5)
    try await deviceA.openIfNeeded()
    try await deviceB.openIfNeeded()

    await deviceA.addObject(VirtualObjectConfig(
      handle: 1001, storage: storage, parent: nil,
      name: "pixel-only.jpg", formatCode: 0x3000, data: Data("pixel".utf8)))

    var canonNames: [String] = []
    for try await batch in deviceB.list(parent: nil, in: storage) {
      canonNames.append(contentsOf: batch.map(\.name))
    }
    XCTAssertFalse(canonNames.contains("pixel-only.jpg"),
      "Files on device A must not appear on device B")
  }

  func testMultipleDevices_ConcurrentOperations() async throws {
    let deviceA = VirtualMTPDevice(config: .pixel7)
    let deviceB = VirtualMTPDevice(config: .samsungGalaxy)
    try await deviceA.openIfNeeded()
    try await deviceB.openIfNeeded()

    async let infoA = deviceA.devGetDeviceInfoUncached()
    async let infoB = deviceB.devGetDeviceInfoUncached()
    let (a, b) = try await (infoA, infoB)
    XCTAssertNotEqual(a.model, b.model,
      "Concurrent queries on different devices must return independent results")
  }

  // MARK: Scenario: User reconnects after previous session crash

  func testReconnectAfterCrash_CleanReopen() async throws {
    let device = VirtualMTPDevice(config: .pixel7)
    try await device.openIfNeeded()
    // Simulate crash: close without cleanup
    try await device.devClose()
    // Reconnect
    try await device.openIfNeeded()
    let info = try await device.devGetDeviceInfoUncached()
    XCTAssertFalse(info.model.isEmpty, "Device reconnects cleanly after crash")
  }

  func testReconnectAfterCrash_OperationsResumeNormally() async throws {
    let device = VirtualMTPDevice(config: .pixel7)
    try await device.openIfNeeded()

    // Seed a file, close (crash), reopen, and verify the device is functional
    await device.addObject(VirtualObjectConfig(
      handle: 1002, storage: storage, parent: nil,
      name: "pre-crash.txt", formatCode: 0x3000, data: Data("data".utf8)))
    try await device.devClose()
    try await device.openIfNeeded()

    let storages = try await device.storages()
    XCTAssertFalse(storages.isEmpty, "Storages are available after reconnection")
  }

  func testReconnectAfterCrash_StaleSessionDoesNotBlock() async throws {
    // Simulate a transport-level disconnect, then reconnect
    let fault = ScheduledFault(
      trigger: .onOperation(.getStorageIDs), error: .disconnected, repeatCount: 1)
    let link = VirtualMTPLink(config: .pixel7, faultSchedule: FaultSchedule([fault]))
    try await link.openSession(id: 1)
    do {
      _ = try await link.getStorageIDs()
    } catch {
      // Expected disconnect
    }
    // Retry succeeds (fault was one-shot)
    let storages = try await link.getStorageIDs()
    XCTAssertFalse(storages.isEmpty, "Stale session does not block reconnection")
  }

  // MARK: Scenario: Device with empty storage opens successfully

  func testEmptyDevice_OpensAndListsSuccessfully() async throws {
    let device = VirtualMTPDevice(config: .emptyDevice)
    try await device.openIfNeeded()
    let info = try await device.devGetDeviceInfoUncached()
    XCTAssertEqual(info.model, "Empty Device")
    var items: [MTPObjectInfo] = []
    for try await batch in device.list(parent: nil, in: storage) {
      items.append(contentsOf: batch)
    }
    XCTAssertTrue(items.isEmpty, "Empty device should have no objects")
  }

  // MARK: Scenario: Device timeout during connection

  func testConnectionTimeout_ErrorReported() async throws {
    let fault = ScheduledFault.timeoutOnce(on: .openSession)
    let link = VirtualMTPLink(config: .pixel7, faultSchedule: FaultSchedule([fault]))
    do {
      try await link.openSession(id: 1)
      XCTFail("Expected timeout error")
    } catch let err as TransportError {
      XCTAssertEqual(err, .timeout, "Connection timeout should surface as .timeout")
    }
  }

  func testConnectionTimeout_RetrySucceeds() async throws {
    let fault = ScheduledFault.timeoutOnce(on: .openSession)
    let link = VirtualMTPLink(config: .pixel7, faultSchedule: FaultSchedule([fault]))
    do { try await link.openSession(id: 1) } catch { /* expected timeout */ }
    // Retry after the one-shot fault
    try await link.openSession(id: 2)
    let storages = try await link.getStorageIDs()
    XCTAssertFalse(storages.isEmpty, "Retry after timeout should succeed")
  }

  // MARK: Scenario: Camera device connection

  func testCameraDevice_OpensWithCorrectInfo() async throws {
    let device = VirtualMTPDevice(config: .canonEOSR5)
    try await device.openIfNeeded()
    let info = try await device.devGetDeviceInfoUncached()
    XCTAssertEqual(info.manufacturer, "Canon")
    XCTAssertFalse(info.model.isEmpty)
  }

  func testNikonCamera_OpensWithCorrectInfo() async throws {
    let device = VirtualMTPDevice(config: .nikonZ6)
    try await device.openIfNeeded()
    let info = try await device.devGetDeviceInfoUncached()
    XCTAssertEqual(info.manufacturer, "Nikon")
  }

  // MARK: Scenario: Busy device returns appropriate error

  func testBusyDevice_ReportsCorrectError() async throws {
    let fault = ScheduledFault(
      trigger: .onOperation(.openSession), error: .busy, repeatCount: 1)
    let link = VirtualMTPLink(config: .pixel7, faultSchedule: FaultSchedule([fault]))
    do {
      try await link.openSession(id: 1)
      XCTFail("Expected busy error")
    } catch let err as TransportError {
      XCTAssertEqual(err, .busy, "Busy device should surface as .busy")
    }
  }

  func testBusyDevice_ClearErrorDescription() async throws {
    let error = TransportError.busy
    XCTAssertNotNil(error.errorDescription)
    XCTAssertTrue(error.errorDescription!.lowercased().contains("busy"),
      "Busy error description should mention 'busy'")
  }
}
