// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import XCTest
@testable import SwiftMTPCore
import SwiftMTPQuirks
import SwiftMTPTestKit

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

        switch selectDevice([], filter: broadFilter, noninteractive: true) {
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
            let summary = MTPDeviceSummary(id: MTPDeviceID(raw: "compat-device"), manufacturer: "Compat", model: "Device")
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

            func list(parent: MTPObjectHandle?, in storage: MTPStorageID) -> AsyncThrowingStream<[MTPObjectInfo], Error> {
                AsyncThrowingStream { continuation in
                    continuation.finish()
                }
            }

            func getInfo(handle: MTPObjectHandle) async throws -> MTPObjectInfo {
                throw MTPError.objectNotFound
            }

            func read(handle: MTPObjectHandle, range: Range<UInt64>?, to url: URL) async throws -> Progress {
                throw MTPError.objectNotFound
            }

            func write(parent: MTPObjectHandle?, name: String, size: UInt64, from url: URL) async throws -> Progress {
                throw MTPError.notSupported("write")
            }

            func createFolder(parent: MTPObjectHandle?, name: String, storage: MTPStorageID) async throws -> MTPObjectHandle {
                throw MTPError.notSupported("createFolder")
            }

            func delete(_ handle: MTPObjectHandle, recursive: Bool) async throws {}

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
}
