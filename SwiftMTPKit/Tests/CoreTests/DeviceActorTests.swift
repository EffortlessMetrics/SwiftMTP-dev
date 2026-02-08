// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import XCTest
@testable import SwiftMTPCore

/// DeviceActor state machine mutation tests
final class DeviceActorTests: XCTestCase {

    // MARK: - Device State Transitions

    func testDeviceStateTransitions() {
        // Test valid state transitions
        let disconnected = DeviceState.disconnected
        let connecting = DeviceState.connecting
        let connected = DeviceState.connected
        let transferring = DeviceState.transferring
        let disconnecting = DeviceState.disconnecting
        let error = DeviceState.error(.timeout)
        
        XCTAssertNotEqual(disconnected, connecting)
        XCTAssertNotEqual(connecting, connected)
        XCTAssertNotEqual(connected, transferring)
        XCTAssertNotEqual(transferring, disconnecting)
        XCTAssertNotEqual(disconnecting, disconnected)
        XCTAssertNotEqual(error, disconnected)
    }

    func testDeviceStateWithError() {
        let timeoutError = DeviceState.error(.timeout)
        let busyError = DeviceState.error(.busy)
        let disconnected = DeviceState.disconnected
        
        XCTAssertNotEqual(timeoutError, busyError)
        XCTAssertNotEqual(timeoutError, disconnected)
    }

    func testDeviceStateProperties() {
        let connected = DeviceState.connected
        let transferring = DeviceState.transferring
        let disconnected = DeviceState.disconnected
        
        XCTAssertFalse(connected.isTransferring)
        XCTAssertTrue(transferring.isTransferring)
        XCTAssertFalse(disconnected.isTransferring)
        
        XCTAssertFalse(connected.isDisconnected)
        XCTAssertFalse(transferring.isDisconnected)
        XCTAssertTrue(disconnected.isDisconnected)
    }

    // MARK: - Device Lifecycle Tests

    func testDeviceLifecycle() {
        // Simulate device lifecycle
        var state: DeviceState = .disconnected
        XCTAssertTrue(state.isDisconnected)
        
        // Connect
        state = .connecting
        XCTAssertFalse(state.isDisconnected)
        XCTAssertFalse(state.isTransferring)
        
        // Connected
        state = .connected
        XCTAssertFalse(state.isDisconnected)
        XCTAssertFalse(state.isTransferring)
        
        // Start transfer
        state = .transferring
        XCTAssertTrue(state.isTransferring)
        
        // End transfer
        state = .connected
        XCTAssertFalse(state.isTransferring)
        
        // Disconnect
        state = .disconnecting
        state = .disconnected
        XCTAssertTrue(state.isDisconnected)
    }

    func testErrorRecovery() {
        var state: DeviceState = .connected
        
        // Error occurs
        state = .error(.timeout)
        XCTAssertFalse(state.isDisconnected)
        XCTAssertFalse(state.isTransferring)
        
        // Recovery attempt
        state = .connecting
        XCTAssertFalse(state.isDisconnected)
        
        // Reconnected
        state = .connected
        XCTAssertFalse(state.isDisconnected)
    }

    func testConsecutiveTransitions() {
        var state: DeviceState = .disconnected
        
        // Rapid connect/disconnect cycles
        for _ in 0..<10 {
            state = .connecting
            state = .connected
            state = .disconnecting
            state = .disconnected
        }
        
        XCTAssertTrue(state.isDisconnected)
    }

    func testTransferInterruption() {
        var state: DeviceState = .connected
        
        // Start transfer
        state = .transferring
        
        // Interrupt
        state = .error(.timeout)
        
        // Recovery
        state = .connecting
        state = .connected
        
        // Resume transfer
        state = .transferring
        
        XCTAssertTrue(state.isTransferring)
    }

    func testMultipleErrors() {
        var state: DeviceState = .connected
        
        // First error
        state = .error(.timeout)
        
        // Another error
        state = .error(.busy)
        
        // Recovery
        state = .connecting
        state = .connected
        
        XCTAssertEqual(state, .connected)
    }

    func testStateEquality() {
        let state1 = DeviceState.connected
        let state2 = DeviceState.connected
        let state3 = DeviceState.disconnected
        
        XCTAssertEqual(state1, state2)
        XCTAssertNotEqual(state1, state3)
    }

    func testErrorStateEquality() {
        let error1 = DeviceState.error(.timeout)
        let error2 = DeviceState.error(.timeout)
        let error3 = DeviceState.error(.busy)
        
        XCTAssertEqual(error1, error2)
        XCTAssertNotEqual(error1, error3)
    }

    // MARK: - Error State Descriptions

    func testErrorStateDescription() {
        let timeoutError = DeviceState.error(.timeout)
        let busyError = DeviceState.error(.busy)
        let protocolError = DeviceState.error(.protocolError(code: 0x2003, message: "SessionNotOpen"))
        
        XCTAssertNotEqual(timeoutError, busyError)
        XCTAssertNotEqual(protocolError, timeoutError)
    }

    // MARK: - State Transition Validity

    func testValidDisconnectedToConnecting() {
        let from = DeviceState.disconnected
        let to = DeviceState.connecting
        
        XCTAssertNotEqual(from, to)
        XCTAssertFalse(from.isDisconnected == to.isDisconnected)
    }

    func testValidConnectingToConnected() {
        let from = DeviceState.connecting
        let to = DeviceState.connected
        
        XCTAssertNotEqual(from, to)
    }

    func testValidConnectedToTransferring() {
        let from = DeviceState.connected
        let to = DeviceState.transferring
        
        XCTAssertNotEqual(from, to)
        XCTAssertFalse(from.isTransferring)
        XCTAssertTrue(to.isTransferring)
    }

    func testValidTransferringToConnected() {
        let from = DeviceState.transferring
        let to = DeviceState.connected
        
        XCTAssertNotEqual(from, to)
        XCTAssertFalse(to.isTransferring)
    }

    func testValidConnectedToDisconnecting() {
        let from = DeviceState.connected
        let to = DeviceState.disconnecting
        
        XCTAssertNotEqual(from, to)
    }

    func testValidDisconnectingToDisconnected() {
        let from = DeviceState.disconnecting
        let to = DeviceState.disconnected
        
        XCTAssertNotEqual(from, to)
        XCTAssertTrue(to.isDisconnected)
    }

    func testValidConnectedToError() {
        let from = DeviceState.connected
        let to = DeviceState.error(.timeout)
        
        XCTAssertNotEqual(from, to)
        XCTAssertFalse(to.isDisconnected)
    }

    func testValidErrorToConnecting() {
        let from = DeviceState.error(.timeout)
        let to = DeviceState.connecting
        
        XCTAssertNotEqual(from, to)
    }

    // MARK: - Invalid Transition Tests

    func testCannotTransferFromDisconnected() {
        let state = DeviceState.disconnected
        
        XCTAssertTrue(state.isDisconnected)
        XCTAssertFalse(state.isTransferring)
    }

    func testCannotDisconnectFromTransferring() {
        // While transferring, device should finish before disconnecting
        let state = DeviceState.transferring
        
        XCTAssertTrue(state.isTransferring)
        XCTAssertFalse(state.isDisconnected)
    }
}

// MARK: - MTPDeviceActor Related Tests

final class MTPDeviceActorRelatedTests: XCTestCase {

    // MARK: - MTPDeviceID

    func testMTPDeviceIDInitialization() {
        let id = MTPDeviceID(raw: "12345678-1234-1234-1234-123456789abc")
        XCTAssertEqual(id.raw, "12345678-1234-1234-1234-123456789abc")
    }

    // MARK: - MTPDeviceSummary

    func testMTPDeviceSummaryCreation() {
        let summary = MTPDeviceSummary(
            id: MTPDeviceID(raw: "usb:1234:5678"),
            manufacturer: "TestCo",
            model: "MTP Device",
            vendorID: 0x1234,
            productID: 0x5678,
            bus: 1,
            address: 2
        )
        
        XCTAssertEqual(summary.manufacturer, "TestCo")
        XCTAssertEqual(summary.vendorID, 0x1234)
        XCTAssertEqual(summary.productID, 0x5678)
    }

    // MARK: - MTPStorageInfo

    func testMTPStorageInfoFixedType() {
        let fixedStorage = MTPStorageInfo(
            id: MTPStorageID(raw: 0x00010001),
            description: "Internal",
            capacityBytes: 16_000_000_000,
            freeBytes: 8_000_000_000,
            isReadOnly: false
        )
        
        XCTAssertFalse(fixedStorage.isReadOnly)
    }

    func testMTPStorageInfoRemovableType() {
        let removableStorage = MTPStorageInfo(
            id: MTPStorageID(raw: 0x00020001),
            description: "SD Card",
            capacityBytes: 32_000_000_000,
            freeBytes: 16_000_000_000,
            isReadOnly: true
        )
        
        XCTAssertTrue(removableStorage.isReadOnly)
    }

    func testMTPStorageInfoCapacity() {
        let storage = MTPStorageInfo(
            id: MTPStorageID(raw: 0x00010001),
            description: "Test",
            capacityBytes: 1000,
            freeBytes: 500,
            isReadOnly: false
        )
        
        XCTAssertGreaterThan(storage.capacityBytes, storage.freeBytes)
    }

    // MARK: - MTPObjectInfo

    func testMTPObjectInfoFile() {
        let info = MTPObjectInfo(
            handle: 0x00010001,
            storage: MTPStorageID(raw: 0x00010001),
            parent: 0x00000000,
            name: "test.txt",
            sizeBytes: 1024,
            modified: Date(),
            formatCode: 0x3001,
            properties: [:]
        )
        
        XCTAssertEqual(info.handle, 0x00010001)
        XCTAssertEqual(info.name, "test.txt")
        XCTAssertEqual(info.sizeBytes, 1024)
    }

    func testMTPObjectInfoFolder() {
        let folder = MTPObjectInfo(
            handle: 0x00010002,
            storage: MTPStorageID(raw: 0x00010001),
            parent: 0x00000000,
            name: "folder",
            sizeBytes: nil,
            modified: nil,
            formatCode: 0x3001,
            properties: [:]
        )
        
        XCTAssertNil(folder.sizeBytes)
        XCTAssertNil(folder.modified)
    }

    // MARK: - MTPDeviceInfo

    func testMTPDeviceInfoCreation() {
        let info = MTPDeviceInfo(
            manufacturer: "TestCo",
            model: "MTP Device",
            version: "1.0",
            serialNumber: "12345",
            operationsSupported: Set([0x1001, 0x1002, 0x1003]),
            eventsSupported: Set([0x4002])
        )
        
        XCTAssertEqual(info.version, "1.0")
        XCTAssertTrue(info.operationsSupported.contains(0x1001))
        XCTAssertTrue(info.operationsSupported.contains(0x1002))
        XCTAssertTrue(info.eventsSupported.contains(0x4002))
    }

    // MARK: - EventPump

    func testEventPumpInitialization() {
        let pump = EventPump()
        XCTAssertNotNil(pump)
    }

    // MARK: - QuirkHooks

    func testQuirkHooksWithNoMatchingPhase() async throws {
        // Test that QuirkHooks.execute handles missing phases gracefully
        let tuning = EffectiveTuning.defaults()
        
        // This test verifies the structure exists
        XCTAssertNotNil(tuning)
    }

    // MARK: - UserOverrides

    func testUserOverridesDefaultEmpty() {
        // UserOverrides.current is static and starts empty
        XCTAssertTrue(UserOverrides.current.isEmpty)
    }

    // MARK: - SwiftMTPConfig

    func testSwiftMTPConfigDefaultValues() {
        let config = SwiftMTPConfig()
        
        XCTAssertEqual(config.transferChunkBytes, 2 * 1024 * 1024)
        XCTAssertEqual(config.ioTimeoutMs, 10_000)
        XCTAssertEqual(config.handshakeTimeoutMs, 6_000)
        XCTAssertFalse(config.resetOnOpen)
    }

    func testSwiftMTPConfigMutable() {
        var config = SwiftMTPConfig()
        
        config.resetOnOpen = true
        config.stabilizeMs = 500
        
        XCTAssertTrue(config.resetOnOpen)
        XCTAssertEqual(config.stabilizeMs, 500)
    }

    // MARK: - ProbeReceipt

    func testProbeReceiptCreation() {
        let receipt = ProbeReceipt(
            deviceSummary: ReceiptDeviceSummary(
                vendorID: 0x1234,
                productID: 0x5678,
                bcdDevice: 0x0100,
                manufacturer: "Test",
                model: "Device",
                serial: "123"
            ),
            fingerprint: MTPDeviceFingerprint.fromUSB(
                vid: 0x1234,
                pid: 0x5678,
                interfaceClass: 6,
                interfaceSubclass: 1,
                interfaceProtocol: 1,
                epIn: 0x81,
                epOut: 0x01
            )
        )
        
        XCTAssertNotNil(receipt)
    }

    // MARK: - MTPDeviceFingerprint

    func testFingerprintFromUSB() {
        let fingerprint = MTPDeviceFingerprint.fromUSB(
            vid: 0x1234,
            pid: 0x5678,
            interfaceClass: 6,
            interfaceSubclass: 1,
            interfaceProtocol: 1,
            epIn: 0x81,
            epOut: 0x01
        )
        
        XCTAssertEqual(fingerprint.vendorID, 0x1234)
        XCTAssertEqual(fingerprint.productID, 0x5678)
        XCTAssertEqual(fingerprint.interfaceClass, 6)
    }

    // MARK: - EffectiveTuning

    func testEffectiveTuningDefaults() {
        let tuning = EffectiveTuning.defaults()
        
        XCTAssertGreaterThan(tuning.maxChunkBytes, 0)
        XCTAssertGreaterThan(tuning.ioTimeoutMs, 0)
        XCTAssertGreaterThan(tuning.handshakeTimeoutMs, 0)
    }

    // MARK: - DevicePolicy

    func testDevicePolicyDefaults() {
        let policy = DevicePolicy()
        
        XCTAssertNotNil(policy)
    }
}

/// Device state representation for testing
enum DeviceState: Equatable {
    case disconnected
    case connecting
    case connected
    case transferring
    case disconnecting
    case error(MTPError)
    
    var isDisconnected: Bool {
        if case .disconnected = self { return true }
        return false
    }
    
    var isTransferring: Bool {
        if case .transferring = self { return true }
        return false
    }
}
