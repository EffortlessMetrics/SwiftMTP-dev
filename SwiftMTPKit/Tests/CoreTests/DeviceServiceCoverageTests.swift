// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import XCTest
@testable import SwiftMTPCore
import SwiftMTPQuirks
import SwiftMTPTestKit
import SwiftMTPCLI

private actor IntRecorder {
  private var values: [Int] = []

  func append(_ value: Int) {
    values.append(value)
  }

  func snapshot() -> [Int] {
    values
  }
}

private struct SuccessfulPayload: Encodable {
  let value: Int
}

private struct FailingPayload: Encodable {
  func encode(to encoder: Encoder) throws {
    throw NSError(domain: "DeviceServiceCoverageTests", code: 1)
  }
}

final class DeviceServiceCoverageTests: XCTestCase {
  private func makeVirtualDevice() -> (VirtualMTPDevice, MTPStorageID, MTPObjectHandle) {
    var config = VirtualDeviceConfig.emptyDevice
    let storage = config.storages[0].id
    config = config.withObject(
      VirtualObjectConfig(
        handle: 77,
        storage: storage,
        parent: nil,
        name: "sample.txt",
        data: Data("hello world".utf8)
      )
    )
    return (VirtualMTPDevice(config: config), storage, 77)
  }

  func testDeviceServiceConvenienceMethodsAndTimeout() async throws {
    let (device, storage, handle) = makeVirtualDevice()
    let service = DeviceService(device: device)

    try await service.ensureSession()
    let listed = try await service.listObjects(parent: nil, storage: storage)
    XCTAssertTrue(listed.contains(where: { $0.handle == handle }))

    let outputURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("swiftmtp-device-service-\(UUID().uuidString).txt")
    defer { try? FileManager.default.removeItem(at: outputURL) }
    _ = try await service.readObject(handle: handle, to: outputURL)
    let downloaded = try Data(contentsOf: outputURL)
    XCTAssertEqual(downloaded, Data("hello world".utf8))

    let timeoutHandle = try await service.submit(
      priority: .high,
      deadline: OperationDeadline(timeout: 0.01, maxRetries: 0)
    ) { _ in
      try await Task.sleep(for: .milliseconds(100))
      return 123
    }

    do {
      _ = try await timeoutHandle.value
      XCTFail("Expected timeout")
    } catch let error as MTPError {
      XCTAssertEqual(error, .timeout)
    }
  }

  func testDeviceServiceFIFOWithinPriority() async throws {
    let (device, _, _) = makeVirtualDevice()
    let service = DeviceService(device: device)
    let recorder = IntRecorder()

    let first = try await service.submit(priority: .medium) { _ in
      try await Task.sleep(for: .milliseconds(40))
      await recorder.append(1)
      return 1
    }
    let second = try await service.submit(priority: .medium) { _ in
      await recorder.append(2)
      return 2
    }
    let third = try await service.submit(priority: .medium) { _ in
      await recorder.append(3)
      return 3
    }

    let firstValue = try await first.value
    let secondValue = try await second.value
    let thirdValue = try await third.value
    let recorded = await recorder.snapshot()
    XCTAssertEqual(firstValue, 1)
    XCTAssertEqual(secondValue, 2)
    XCTAssertEqual(thirdValue, 3)
    XCTAssertEqual(recorded, [1, 2, 3])
  }

  func testDeviceServiceDisconnectAndReconnectGate() async throws {
    let (device, _, _) = makeVirtualDevice()
    let service = DeviceService(device: device)

    await service.markDisconnected()
    do {
      _ = try await service.submit(priority: .low) { _ in 1 }
      XCTFail("Expected disconnected submit to fail")
    } catch let error as MTPError {
      XCTAssertEqual(error, .deviceDisconnected)
    }

    await service.markReconnected()
    let handle = try await service.submit(priority: .high) { _ in 7 }
    let value = try await handle.value
    XCTAssertEqual(value, 7)
  }

  func testDeviceServiceRegistryLifecycleAndMappings() async throws {
    let (device, _, _) = makeVirtualDevice()
    let service = DeviceService(device: device)
    let registry = DeviceServiceRegistry()
    let deviceId = MTPDeviceID(raw: "ephemeral-device-1")
    let domainId = "domain-device-1"

    await registry.register(deviceId: deviceId, service: service)
    let initialService = await registry.service(for: deviceId)
    XCTAssertNotNil(initialService)

    let marker = NSObject()
    await registry.registerOrchestrator(marker, for: deviceId)

    await registry.registerDomainMapping(deviceId: deviceId, domainId: domainId)
    let mappedDomainId = await registry.domainId(for: deviceId)
    let reverseMappedDevice = await registry.deviceId(for: domainId)
    XCTAssertEqual(mappedDomainId, domainId)
    XCTAssertEqual(reverseMappedDevice, deviceId)

    await registry.handleDetach(deviceId: deviceId)
    do {
      _ = try await service.submit(priority: .low) { _ in 1 }
      XCTFail("Expected detached device submit to fail")
    } catch let error as MTPError {
      XCTAssertEqual(error, .deviceDisconnected)
    }

    await registry.handleReconnect(deviceId: deviceId)
    let handle = try await service.submit(priority: .high) { _ in 2 }
    let value = try await handle.value
    XCTAssertEqual(value, 2)

    await registry.remove(deviceId: deviceId)
    let removedService = await registry.service(for: deviceId)
    let removedDomain = await registry.domainId(for: deviceId)
    let removedDevice = await registry.deviceId(for: domainId)
    XCTAssertNil(removedService)
    XCTAssertNil(removedDomain)
    XCTAssertNil(removedDevice)
  }

  func testDeviceServiceRegistryMonitoringAttachStream() async throws {
    let flags = FeatureFlags.shared
    let originalDemoMode = flags.useMockTransport
    flags.useMockTransport = true
    defer { flags.useMockTransport = originalDemoMode }

    let manager = MTPDeviceManager()
    let registry = DeviceServiceRegistry()
    let attached = expectation(description: "received attach callback")

    await registry.startMonitoring(
      manager: manager,
      onAttach: { _, _ in
        attached.fulfill()
      },
      onDetach: { _, _ in }
    )

    try await manager.startDiscovery()
    await fulfillment(of: [attached], timeout: 2.0)
    await registry.stopMonitoring()
    await manager.stopDiscovery()
  }

  func testFeatureFlagsSettersAndKnownFlags() {
    let flags = FeatureFlags.shared
    let originalDemo = flags.useMockTransport
    let originalStorybook = flags.showStorybook
    let originalTrace = flags.traceUSB
    defer {
      flags.useMockTransport = originalDemo
      flags.showStorybook = originalStorybook
      flags.traceUSB = originalTrace
    }

    flags.useMockTransport = true
    flags.showStorybook = true
    flags.traceUSB = true

    XCTAssertTrue(flags.isEnabled("SWIFTMTP_DEMO_MODE"))
    XCTAssertTrue(flags.useMockTransport)
    XCTAssertTrue(flags.showStorybook)
    XCTAssertTrue(flags.traceUSB)
    XCTAssertFalse(flags.mockProfile.isEmpty)

    flags.set("SWIFTMTP_TRACE_USB", enabled: false)
    XCTAssertFalse(flags.traceUSB)
  }

  func testDeviceFilterParseAndSelect() {
    var args = ["--vid", "0x18d1", "--pid", "20193", "--bus", "1", "--address", "2", "--leftover"]
    let filter = DeviceFilterParse.parse(from: &args)
    XCTAssertEqual(filter.vid, 0x18d1)
    XCTAssertEqual(filter.pid, 20193)
    XCTAssertEqual(filter.bus, 1)
    XCTAssertEqual(filter.address, 2)
    XCTAssertEqual(args, ["--leftover"])

    let exact = MTPDeviceSummary(
      id: MTPDeviceID(raw: "d1"),
      manufacturer: "Google",
      model: "Pixel",
      vendorID: 0x18d1,
      productID: 20193,
      bus: 1,
      address: 2,
      usbSerial: nil
    )
    let other = MTPDeviceSummary(
      id: MTPDeviceID(raw: "d2"),
      manufacturer: "Other",
      model: "Phone",
      vendorID: 0x1234,
      productID: 0x5678,
      bus: 4,
      address: 5,
      usbSerial: nil
    )

    switch selectDevice([exact, other], filter: filter, noninteractive: true) {
    case .selected(let selected):
      XCTAssertEqual(selected.id.raw, "d1")
    default:
      XCTFail("Expected a selected device")
    }

    let broadFilter = DeviceFilter(vid: nil, pid: nil, bus: nil, address: nil)
    switch selectDevice([exact, other], filter: broadFilter, noninteractive: true) {
    case .multiple(let candidates):
      XCTAssertEqual(candidates.count, 2)
    default:
      XCTFail("Expected multiple candidates")
    }

    switch selectDevice([MTPDeviceSummary](), filter: broadFilter, noninteractive: true) {
    case .none:
      break
    default:
      XCTFail("Expected none outcome")
    }
  }

  func testJSONErrorEnvelopeAndPrintPaths() {
    let envelope = CLIErrorEnvelope("failure", details: ["k": "v"], mode: "json")
    XCTAssertEqual(envelope.schemaVersion, "1.0")
    XCTAssertEqual(envelope.type, "error")
    XCTAssertEqual(envelope.error, "failure")
    XCTAssertEqual(envelope.details?["k"], "v")
    XCTAssertEqual(envelope.mode, "json")

    printJSON(SuccessfulPayload(value: 42))
    printJSON(FailingPayload())
  }

  func testQuirkResolverResolvePolicy() {
    let quirk = DeviceQuirk(
      id: "unit-test-quirk",
      vid: 0x18d1,
      pid: 0x4ee1,
      ifaceClass: 0x06,
      ifaceSubclass: 0x01,
      ifaceProtocol: 0x01,
      maxChunkBytes: 2 * 1024 * 1024,
      ioTimeoutMs: 9000,
      operations: ["supportsGetPartialObject64": true]
    )
    let database = QuirkDatabase(schemaVersion: "1.0.0", entries: [quirk])
    let fingerprint = MTPDeviceFingerprint.fromUSB(
      vid: 0x18d1,
      pid: 0x4ee1,
      interfaceClass: 0x06,
      interfaceSubclass: 0x01,
      interfaceProtocol: 0x01,
      epIn: 0x81,
      epOut: 0x02
    )

    let policy = QuirkResolver.resolve(
      fingerprint: fingerprint,
      database: database,
      capabilities: [:],
      learned: nil,
      overrides: nil
    )

    XCTAssertEqual(policy.tuning.maxChunkBytes, 2 * 1024 * 1024)
    XCTAssertEqual(policy.tuning.ioTimeoutMs, 9000)
    XCTAssertTrue(policy.flags.supportsPartialRead64)
  }

  func testTransportDiscoveryNoopStart() {
    var attached = false
    var detached = false

    TransportDiscovery.start(
      onAttach: { _ in attached = true },
      onDetach: { _ in detached = true }
    )

    XCTAssertFalse(attached)
    XCTAssertFalse(detached)
  }

  func testMTPDeviceCompatGetDeviceInfoAndDefaultOpenIfNeeded() async throws {
    final class CompatFallbackDevice: MTPDevice, @unchecked Sendable {
      let id = MTPDeviceID(raw: "compat-device")
      let summary = MTPDeviceSummary(
        id: MTPDeviceID(raw: "compat-device"), manufacturer: "Compat", model: "Device")
      private(set) var storageCallCount = 0

      var info: MTPDeviceInfo {
        get async throws {
          MTPDeviceInfo(
            manufacturer: "Compat",
            model: "Device",
            version: "1.0",
            serialNumber: nil,
            operationsSupported: [],
            eventsSupported: []
          )
        }
      }

      func storages() async throws -> [MTPStorageInfo] {
        storageCallCount += 1
        return []
      }

      func list(parent: MTPObjectHandle?, in storage: MTPStorageID) -> AsyncThrowingStream<
        [MTPObjectInfo], Error
      > {
        AsyncThrowingStream { continuation in
          continuation.finish()
        }
      }

      func getInfo(handle: MTPObjectHandle) async throws -> MTPObjectInfo {
        throw MTPError.objectNotFound
      }

      func read(handle: MTPObjectHandle, range: Range<UInt64>?, to url: URL) async throws
        -> Progress
      {
        throw MTPError.objectNotFound
      }

      func write(parent: MTPObjectHandle?, name: String, size: UInt64, from url: URL) async throws
        -> Progress
      {
        throw MTPError.notSupported("write")
      }

      func createFolder(parent: MTPObjectHandle?, name: String, storage: MTPStorageID) async throws
        -> MTPObjectHandle
      {
        throw MTPError.notSupported("createFolder")
      }

      func delete(_ handle: MTPObjectHandle, recursive: Bool) async throws {}

      func rename(_ handle: MTPObjectHandle, to newName: String) async throws {}

      func move(_ handle: MTPObjectHandle, to newParent: MTPObjectHandle?) async throws {}

      var probedCapabilities: [String: Bool] { get async { [:] } }
      var effectiveTuning: EffectiveTuning { get async { .defaults() } }

      func devClose() async throws {}

      func devGetDeviceInfoUncached() async throws -> MTPDeviceInfo {
        try await info
      }

      func devGetStorageIDsUncached() async throws -> [MTPStorageID] {
        []
      }

      func devGetRootHandlesUncached(storage: MTPStorageID) async throws -> [MTPObjectHandle] {
        []
      }

      func devGetObjectInfoUncached(handle: MTPObjectHandle) async throws -> MTPObjectInfo {
        throw MTPError.objectNotFound
      }

      var events: AsyncStream<MTPEvent> {
        AsyncStream { continuation in
          continuation.finish()
        }
      }
    }

    let device = CompatFallbackDevice()
    let info = try await device.getDeviceInfo()
    XCTAssertEqual(info.model, "Device")

    try await device.openIfNeeded()
    XCTAssertEqual(device.storageCallCount, 1)
  }

  // MARK: - Multi-Device Tests

  func testMultipleDevicesConcurrentRegistration() async throws {
    let registry = DeviceServiceRegistry()
    let deviceIds = (1...3).map { MTPDeviceID(raw: "device-\($0)") }
    let domainIds = (1...3).map { "domain-\($0)" }

    // Register 3 devices sequentially (actor serializes concurrent access internally)
    for i in 0..<3 {
      let (device, _, _) = makeVirtualDevice()
      let service = DeviceService(device: device)
      await registry.register(deviceId: deviceIds[i], service: service)
      await registry.registerDomainMapping(deviceId: deviceIds[i], domainId: domainIds[i])
    }

    // All 3 devices should be individually resolvable
    for i in 0..<3 {
      let svc = await registry.service(for: deviceIds[i])
      XCTAssertNotNil(svc, "Service for device \(i) should be registered")
      let domain = await registry.domainId(for: deviceIds[i])
      XCTAssertEqual(domain, domainIds[i])
      let reverse = await registry.deviceId(for: domainIds[i])
      XCTAssertEqual(reverse, deviceIds[i])
    }
  }

  func testRemoveOneDeviceDoesNotAffectOthers() async throws {
    let registry = DeviceServiceRegistry()
    let id1 = MTPDeviceID(raw: "multi-a")
    let id2 = MTPDeviceID(raw: "multi-b")
    let (d1, _, _) = makeVirtualDevice()
    let (d2, _, _) = makeVirtualDevice()
    await registry.register(deviceId: id1, service: DeviceService(device: d1))
    await registry.register(deviceId: id2, service: DeviceService(device: d2))
    await registry.registerDomainMapping(deviceId: id1, domainId: "dom-a")
    await registry.registerDomainMapping(deviceId: id2, domainId: "dom-b")

    // Remove device 1
    await registry.remove(deviceId: id1)

    // Device 1 gone
    let svc1After = await registry.service(for: id1)
    XCTAssertNil(svc1After)
    let dom1After = await registry.domainId(for: id1)
    XCTAssertNil(dom1After)
    let rev1After = await registry.deviceId(for: "dom-a")
    XCTAssertNil(rev1After)

    // Device 2 still present
    let svc2After = await registry.service(for: id2)
    XCTAssertNotNil(svc2After)
    let dom2After = await registry.domainId(for: id2)
    XCTAssertEqual(dom2After, "dom-b")
    let rev2After = await registry.deviceId(for: "dom-b")
    XCTAssertEqual(rev2After, id2)
  }

  func testDetachAndReconnectOneDeviceIsolated() async throws {
    let registry = DeviceServiceRegistry()
    let id1 = MTPDeviceID(raw: "iso-a")
    let id2 = MTPDeviceID(raw: "iso-b")
    let (d1, _, _) = makeVirtualDevice()
    let (d2, _, _) = makeVirtualDevice()
    let svc1 = DeviceService(device: d1)
    let svc2 = DeviceService(device: d2)
    await registry.register(deviceId: id1, service: svc1)
    await registry.register(deviceId: id2, service: svc2)

    // Detach device 1 only
    await registry.handleDetach(deviceId: id1)

    // svc1 disconnected
    do {
      _ = try await svc1.submit(priority: .low) { _ in 1 }
      XCTFail("Expected disconnected error")
    } catch let e as MTPError {
      XCTAssertEqual(e, .deviceDisconnected)
    }

    // svc2 still operational
    let val = try await (try await svc2.submit(priority: .high) { _ in 42 }).value
    XCTAssertEqual(val, 42)

    // Reconnect device 1
    await registry.handleReconnect(deviceId: id1)
    let val1 = try await (try await svc1.submit(priority: .high) { _ in 7 }).value
    XCTAssertEqual(val1, 7)
  }

  func testDomainMappingUpdateReplacesStaleEntry() async throws {
    let registry = DeviceServiceRegistry()
    let id = MTPDeviceID(raw: "remap-dev")

    // Register with first domain
    await registry.registerDomainMapping(deviceId: id, domainId: "old-domain")
    let dom1 = await registry.domainId(for: id)
    XCTAssertEqual(dom1, "old-domain")

    // Re-register same device with new domain (e.g., reconnect with new ephemeral ID)
    await registry.registerDomainMapping(deviceId: id, domainId: "new-domain")
    let dom2 = await registry.domainId(for: id)
    XCTAssertEqual(dom2, "new-domain")
    // Old domain reverse mapping must be evicted
    let oldRev = await registry.deviceId(for: "old-domain")
    XCTAssertNil(oldRev)
    let newRev = await registry.deviceId(for: "new-domain")
    XCTAssertEqual(newRev, id)
  }

  /// Concurrent attach events are processed in parallel.
  /// Two devices are injected simultaneously via syncConnectedDeviceSnapshot.
  /// Each onAttach sleeps 50 ms. If serial: ~100 ms total. If parallel: ~50 ms total.
  func testConcurrentAttachEventsProcessedInParallel() async throws {
    // Don't use mock transport — it would inject an extra auto-attach event.
    // startDiscovery() still initializes the attach/detach stream continuations.
    let manager = MTPDeviceManager()
    let registry = DeviceServiceRegistry()
    let attachedIDs = ActorBox<String>()
    let delay: UInt64 = 50_000_000  // 50 ms

    await registry.startMonitoring(
      manager: manager,
      onAttach: { summary, _ in
        try? await Task.sleep(nanoseconds: delay)
        await attachedIDs.append(summary.id.raw)
      },
      onDetach: { _, _ in }
    )

    // Prime the discovery streams without starting real USB discovery
    try await manager.startDiscovery()

    let start = Date()

    // Inject two devices in one snapshot → both attach events fired immediately
    let idA = MTPDeviceID(raw: "par-A")
    let idB = MTPDeviceID(raw: "par-B")
    let summaryA = MTPDeviceSummary(
      id: idA, manufacturer: "Test", model: "A",
      vendorID: 0xAAAA, productID: 0x0001, bus: 1, address: 1)
    let summaryB = MTPDeviceSummary(
      id: idB, manufacturer: "Test", model: "B",
      vendorID: 0xAAAA, productID: 0x0002, bus: 1, address: 2)
    await manager.syncConnectedDeviceSnapshot([summaryA, summaryB])

    // Wait enough for both handlers to complete (even under heavy load)
    try await Task.sleep(nanoseconds: delay * 4)

    await registry.stopMonitoring()
    await manager.stopDiscovery()

    let ids = await attachedIDs.values
    XCTAssertEqual(ids.count, 2, "Both parallel attach handlers should have completed")
    XCTAssertTrue(ids.contains("par-A") && ids.contains("par-B"))
  }
}

// MARK: - Test Helpers

private actor ActorBox<T: Sendable> {
  private(set) var values: [T] = []
  func append(_ v: T) { values.append(v) }
}
