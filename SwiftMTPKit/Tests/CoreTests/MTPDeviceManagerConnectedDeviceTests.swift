// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import XCTest
@testable import SwiftMTPCore
@testable import SwiftMTPTransportLibUSB

final class MTPDeviceManagerConnectedDeviceTests: XCTestCase {
  private actor SnapshotSource {
    private var snapshot: [MTPDeviceSummary]

    init(snapshot: [MTPDeviceSummary]) {
      self.snapshot = snapshot
    }

    func set(_ snapshot: [MTPDeviceSummary]) {
      self.snapshot = snapshot
    }

    func get() -> [MTPDeviceSummary] {
      snapshot
    }
  }

  func testSyncConnectedDeviceSnapshotDeduplicatesByID() async {
    let manager = MTPDeviceManager()
    let sharedID = MTPDeviceID(raw: "18d1:4ee1@1:2")

    let first = MTPDeviceSummary(
      id: sharedID,
      manufacturer: "Google",
      model: "Pixel 7",
      vendorID: 0x18d1,
      productID: 0x4ee1,
      bus: 1,
      address: 2
    )
    let updated = MTPDeviceSummary(
      id: sharedID,
      manufacturer: "Google",
      model: "Pixel 7 Pro",
      vendorID: 0x18d1,
      productID: 0x4ee1,
      bus: 1,
      address: 2
    )

    await manager.syncConnectedDeviceSnapshot([first, updated])
    let devices = await manager.devices

    XCTAssertEqual(devices.count, 1)
    XCTAssertEqual(devices[0].id, sharedID)
    XCTAssertEqual(devices[0].model, "Pixel 7 Pro")
  }

  func testRefreshConnectedDevicesUsesSnapshotProvider() async throws {
    let manager = MTPDeviceManager()
    let first = MockDeviceData.androidPixel7.deviceSummary
    let second = MockDeviceData.androidOnePlus3T.deviceSummary
    let source = SnapshotSource(snapshot: [first])

    await manager.setDiscoverySnapshotProvider {
      await source.get()
    }

    var refreshed = try await manager.refreshConnectedDevices()
    XCTAssertEqual(refreshed.map(\.id), [first.id])

    await source.set([second])
    refreshed = try await manager.refreshConnectedDevices()

    XCTAssertEqual(refreshed.map(\.id), [second.id])
    let deviceIDs = await manager.devices.map(\.id)
    XCTAssertEqual(deviceIDs, [second.id])
  }

  func testOpenByIDUsesDefaultTransportFactoryAfterRefreshFallback() async throws {
    let manager = MTPDeviceManager()
    let expected = MockDeviceData.androidPixel7.deviceSummary
    let source = SnapshotSource(snapshot: [expected])

    await manager.setDiscoverySnapshotProvider {
      await source.get()
    }
    await manager.setDefaultTransportFactory {
      MockTransport(deviceData: .androidPixel7)
    }

    let opened = try await manager.open(expected.id)
    try await opened.openIfNeeded()

    XCTAssertEqual(opened.summary.id, expected.id)
    let model = try await opened.info.model
    XCTAssertEqual(model, "Pixel 7")
  }

  func testOpenByIDThrowsNoDeviceWhenNotConnected() async throws {
    let manager = MTPDeviceManager()
    let source = SnapshotSource(snapshot: [])

    await manager.setDiscoverySnapshotProvider {
      await source.get()
    }
    await manager.setDefaultTransportFactory {
      MockTransport(deviceData: .androidPixel7)
    }

    do {
      _ = try await manager.open(MTPDeviceID(raw: "18d1:ffff@1:9"))
      XCTFail("Expected no-device error")
    } catch let error as MTPError {
      XCTAssertEqual(error, .transport(.noDevice))
    }
  }
}
