// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import XCTest
@testable import SwiftMTPCore
@testable import SwiftMTPXPC
import SwiftMTPTestKit

/// Tests for XPC connection lifecycle: connect, disconnect, reconnect, timeout scenarios.
@MainActor
final class XPCConnectionLifecycleTests: XCTestCase {

  // MARK: - Helpers

  private func makeService(
    config: VirtualDeviceConfig? = nil
  ) async -> (impl: MTPXPCServiceImpl, registry: DeviceServiceRegistry, deviceId: MTPDeviceID, stableId: String) {
    let cfg = config ?? VirtualDeviceConfig.emptyDevice
    let virtual = VirtualMTPDevice(config: cfg)
    let deviceService = DeviceService(device: virtual)
    let registry = DeviceServiceRegistry()
    let stableId = "domain-\(UUID().uuidString)"
    await registry.register(deviceId: cfg.deviceId, service: deviceService)
    await registry.registerDomainMapping(deviceId: cfg.deviceId, domainId: stableId)

    let impl = MTPXPCServiceImpl(deviceManager: .shared)
    impl.registry = registry
    return (impl, registry, cfg.deviceId, stableId)
  }

  private func pingResult(_ impl: MTPXPCServiceImpl) async -> String {
    await withCheckedContinuation { c in
      impl.ping { c.resume(returning: $0) }
    }
  }

  private func statusResult(_ impl: MTPXPCServiceImpl, deviceId: String) async -> DeviceStatusResponse {
    await withCheckedContinuation { c in
      impl.deviceStatus(DeviceStatusRequest(deviceId: deviceId)) { c.resume(returning: $0) }
    }
  }

  // MARK: - Connect

  func testPingReturnsRunningMessage() async {
    let svc = await makeService()
    let msg = await pingResult(svc.impl)
    XCTAssertTrue(msg.lowercased().contains("running"))
  }

  func testDeviceStatusConnectedAfterRegistration() async {
    let svc = await makeService()
    let resp = await statusResult(svc.impl, deviceId: svc.deviceId.raw)
    XCTAssertTrue(resp.connected)
    XCTAssertTrue(resp.sessionOpen)
  }

  func testDeviceStatusViaStableIdNotFound() async {
    // Stable domain IDs go through reverseDomainMap → deviceStatus uses ephemeral lookup
    let svc = await makeService()
    let resp = await statusResult(svc.impl, deviceId: svc.stableId)
    // stableId is not an ephemeral ID, so registry.service(for:) won't find it directly
    // deviceStatus uses MTPDeviceID(raw:) which wraps the string; only ephemeral IDs match
    XCTAssertFalse(resp.connected)
  }

  // MARK: - Disconnect

  func testDeviceStatusAfterDisconnect() async {
    let svc = await makeService()
    if let service = await svc.registry.service(for: svc.deviceId) {
      await service.markDisconnected()
    }
    let resp = await statusResult(svc.impl, deviceId: svc.deviceId.raw)
    XCTAssertFalse(resp.connected)
    XCTAssertFalse(resp.sessionOpen)
  }

  func testReadFailsAfterDeviceRemoval() async {
    let svc = await makeService()
    await svc.registry.remove(deviceId: svc.deviceId)
    let resp = await withCheckedContinuation { (c: CheckedContinuation<ReadResponse, Never>) in
      svc.impl.readObject(ReadRequest(deviceId: svc.stableId, objectHandle: 1)) {
        c.resume(returning: $0)
      }
    }
    XCTAssertFalse(resp.success)
    XCTAssertNotNil(resp.errorMessage)
  }

  func testListStoragesFailsForRemovedDevice() async {
    let svc = await makeService()
    await svc.registry.remove(deviceId: svc.deviceId)
    let resp = await withCheckedContinuation { (c: CheckedContinuation<StorageListResponse, Never>) in
      svc.impl.listStorages(StorageListRequest(deviceId: svc.stableId)) {
        c.resume(returning: $0)
      }
    }
    XCTAssertFalse(resp.success)
  }

  // MARK: - Reconnect

  func testDeviceStatusRestoredAfterReconnect() async {
    let svc = await makeService()
    if let service = await svc.registry.service(for: svc.deviceId) {
      await service.markDisconnected()
      let mid = await statusResult(svc.impl, deviceId: svc.deviceId.raw)
      XCTAssertFalse(mid.connected)
      await service.markReconnected()
    }
    let resp = await statusResult(svc.impl, deviceId: svc.deviceId.raw)
    XCTAssertTrue(resp.connected)
  }

  // MARK: - Listener lifecycle

  func testListenerStartAndStop() async {
    let impl = MTPXPCServiceImpl(deviceManager: .shared)
    let listener = MTPXPCListener(serviceImpl: impl)
    listener.start()
    listener.stop()
    // No crash = pass; verifying idempotent stop
    listener.stop()
  }

  func testListenerAcceptsConnection() async {
    let impl = MTPXPCServiceImpl(deviceManager: .shared)
    let listener = MTPXPCListener(serviceImpl: impl)
    listener.start()
    let conn = NSXPCConnection(machServiceName: MTPXPCServiceName, options: [])
    let accepted = listener.listener(NSXPCListener.anonymous(), shouldAcceptNewConnection: conn)
    XCTAssertTrue(accepted)
    listener.stop()
  }

  func testListenerCleanupTimerRuns() async {
    let impl = MTPXPCServiceImpl(deviceManager: .shared)
    let listener = MTPXPCListener(serviceImpl: impl)
    listener.startTempFileCleanupTimer(interval: 0.01)
    try? await Task.sleep(for: .milliseconds(50))
    listener.stop()
  }

  // MARK: - Multiple connections

  func testMultipleConnectionsAccepted() async {
    let impl = MTPXPCServiceImpl(deviceManager: .shared)
    let listener = MTPXPCListener(serviceImpl: impl)
    listener.start()
    for _ in 0..<5 {
      let conn = NSXPCConnection(machServiceName: MTPXPCServiceName, options: [])
      let accepted = listener.listener(NSXPCListener.anonymous(), shouldAcceptNewConnection: conn)
      XCTAssertTrue(accepted)
    }
    listener.stop()
  }

  func testDeviceManagerXPCServiceStartStop() async {
    MTPDeviceManager.shared.startXPCService()
    MTPDeviceManager.shared.startXPCService() // idempotent
    MTPDeviceManager.shared.stopXPCService()
    MTPDeviceManager.shared.stopXPCService() // idempotent
  }
}
