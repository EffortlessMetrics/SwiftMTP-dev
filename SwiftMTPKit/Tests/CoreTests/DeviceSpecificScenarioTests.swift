// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import Testing
@testable import SwiftMTPCore
@testable import SwiftMTPTransportLibUSB

@Suite("Device-Specific Scenario Tests")
struct DeviceSpecificScenarioTests {

  @Test("OnePlus 3T mock probe and session")
  func testOnePlus3TMockProbeAndSession() async throws {
    let mockData = MockTransportFactory.deviceData(for: .androidOnePlus3T)
    let transport = MockTransport(deviceData: mockData)

    // Verify device summary
    #expect(mockData.deviceSummary.manufacturer == "OnePlus")
    #expect(mockData.deviceSummary.model == "ONEPLUS A3010")

    // Open and verify link
    let link = try await transport.open(mockData.deviceSummary, config: SwiftMTPConfig())
    try await link.openSession(id: 1)

    // Verify device info (MockTransport uses summary fields + hardcoded version)
    let info = try await link.getDeviceInfo()
    #expect(info.manufacturer == "OnePlus")
    #expect(info.model == "ONEPLUS A3010")

    // Verify storages
    let storageIDs = try await link.getStorageIDs()
    #expect(storageIDs.count == 1)

    let storageInfo = try await link.getStorageInfo(id: storageIDs[0])
    #expect(storageInfo.description.contains("Internal"))

    // Verify root objects
    let rootParent: MTPObjectHandle? = nil
    let handles = try await link.getObjectHandles(storage: storageIDs[0], parent: rootParent)
    #expect(handles.count > 0, "Should have root-level objects")

    await link.close()
  }

  @Test("Pixel 7 mock probe and session")
  func testPixel7MockProbeAndSession() async throws {
    let mockData = MockTransportFactory.deviceData(for: .androidPixel7)
    let transport = MockTransport(deviceData: mockData)

    #expect(mockData.deviceSummary.manufacturer == "Google")
    #expect(mockData.deviceSummary.model == "Pixel 7")

    let link = try await transport.open(mockData.deviceSummary, config: SwiftMTPConfig())
    try await link.openSession(id: 1)

    let info = try await link.getDeviceInfo()
    #expect(info.manufacturer == "Google")
    #expect(info.model == "Pixel 7")

    let storageIDs = try await link.getStorageIDs()
    #expect(storageIDs.count >= 1)

    await link.close()
  }

  @Test("OnePlus 3T operations list matches real device")
  func testOnePlus3TOperations() async throws {
    let mockData = MockTransportFactory.deviceData(for: .androidOnePlus3T)

    // Verify real operation codes captured from device
    let ops = mockData.deviceInfo.operationsSupported
    #expect(ops.contains(0x1001), "GetDeviceInfo")
    #expect(ops.contains(0x1002), "OpenSession")
    #expect(ops.contains(0x1003), "CloseSession")
    #expect(ops.contains(0x1004), "GetStorageIDs")
    #expect(ops.contains(0x1005), "GetStorageInfo")
    #expect(ops.contains(0x100C), "SendObjectInfo")
    #expect(ops.contains(0x100D), "SendObject")
    #expect(ops.contains(0x101B), "GetPartialObject")
    #expect(ops.contains(0x95C5), "GetObjectPropList (MTP)")
    #expect(ops.contains(0x9810), "GetObjectPropList (vendor)")
  }

  @Test("OnePlus 3T events list matches real device")
  func testOnePlus3TEvents() async throws {
    let mockData = MockTransportFactory.deviceData(for: .androidOnePlus3T)
    let events = mockData.deviceInfo.eventsSupported

    #expect(events.contains(0x4002), "ObjectAdded")
    #expect(events.contains(0x4003), "ObjectRemoved")
    #expect(events.contains(0x4004), "StoreAdded")
    #expect(events.contains(0x4005), "StoreRemoved")
    #expect(events.contains(0x4006), "DevicePropChanged")
    #expect(events.contains(0xC801), "Vendor-specific event")
  }
}
