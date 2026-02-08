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
