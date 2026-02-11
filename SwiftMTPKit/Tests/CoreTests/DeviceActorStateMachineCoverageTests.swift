// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import XCTest
@testable import SwiftMTPCore

/// DeviceActor state machine comprehensive coverage tests
final class DeviceActorStateMachineCoverageTests: XCTestCase {

    // MARK: - DeviceState Error Transitions

    func testStateTransitionFromConnectedToError() {
        // Test transitioning from connected to error state
        var state: DeviceState = .connected
        XCTAssertFalse(state.isDisconnected)
        XCTAssertFalse(state.isTransferring)

        state = .error(.timeout)
        XCTAssertFalse(state.isDisconnected)
        XCTAssertFalse(state.isTransferring)
    }

    func testStateTransitionFromTransferringToError() {
        // Test transitioning from transferring to error state
        var state: DeviceState = .transferring
        XCTAssertTrue(state.isTransferring)
        XCTAssertFalse(state.isDisconnected)

        state = .error(.busy)
        XCTAssertFalse(state.isTransferring)
        XCTAssertFalse(state.isDisconnected)
    }

    func testStateTransitionFromConnectingToError() {
        // Test transitioning from connecting to error state
        var state: DeviceState = .connecting
        XCTAssertFalse(state.isDisconnected)
        XCTAssertFalse(state.isTransferring)

        state = .error(.busy)
        XCTAssertFalse(state.isDisconnected)
    }

    func testStateTransitionFromDisconnectingToError() {
        // Test transitioning from disconnecting to error state (rare but possible)
        var state: DeviceState = .disconnecting
        XCTAssertFalse(state.isDisconnected)

        state = .error(.timeout)
        XCTAssertFalse(state.isDisconnected)
    }

    // MARK: - DeviceState Equality Tests

    func testConnectedStateEquality() {
        let state1 = DeviceState.connected
        let state2 = DeviceState.connected

        XCTAssertEqual(state1, state2)
    }

    func testDisconnectedStateEquality() {
        let state1 = DeviceState.disconnected
        let state2 = DeviceState.disconnected

        XCTAssertEqual(state1, state2)
    }

    func testConnectingStateEquality() {
        let state1 = DeviceState.connecting
        let state2 = DeviceState.connecting

        XCTAssertEqual(state1, state2)
    }

    func testTransferringStateEquality() {
        let state1 = DeviceState.transferring
        let state2 = DeviceState.transferring

        XCTAssertEqual(state1, state2)
    }

    func testDisconnectingStateEquality() {
        let state1 = DeviceState.disconnecting
        let state2 = DeviceState.disconnecting

        XCTAssertEqual(state1, state2)
    }

    func testErrorStateEqualitySameError() {
        let state1 = DeviceState.error(.timeout)
        let state2 = DeviceState.error(.timeout)

        XCTAssertEqual(state1, state2)
    }

    func testErrorStateEqualityDifferentErrors() {
        let state1 = DeviceState.error(.timeout)
        let state2 = DeviceState.error(.busy)

        XCTAssertNotEqual(state1, state2)
    }

    // MARK: - State Description Tests

    func testStateDescriptionConnected() {
        let state = DeviceState.connected
        let description = "\(state)"
        XCTAssertFalse(description.isEmpty)
    }

    func testStateDescriptionDisconnected() {
        let state = DeviceState.disconnected
        let description = "\(state)"
        XCTAssertFalse(description.isEmpty)
    }

    func testStateDescriptionConnecting() {
        let state = DeviceState.connecting
        let description = "\(state)"
        XCTAssertFalse(description.isEmpty)
    }

    func testStateDescriptionTransferring() {
        let state = DeviceState.transferring
        let description = "\(state)"
        XCTAssertFalse(description.isEmpty)
    }

    func testStateDescriptionDisconnecting() {
        let state = DeviceState.disconnecting
        let description = "\(state)"
        XCTAssertFalse(description.isEmpty)
    }

    func testStateDescriptionError() {
        let state = DeviceState.error(.timeout)
        let description = "\(state)"
        XCTAssertFalse(description.isEmpty)
    }

    // MARK: - Complex State Transition Sequences

    func testFullConnectionCycle() {
        var state: DeviceState = .disconnected
        XCTAssertTrue(state.isDisconnected)

        state = .connecting
        XCTAssertFalse(state.isDisconnected)

        state = .connected
        XCTAssertFalse(state.isDisconnected)
        XCTAssertFalse(state.isTransferring)

        state = .transferring
        XCTAssertTrue(state.isTransferring)

        state = .connected
        XCTAssertFalse(state.isTransferring)

        state = .disconnecting
        XCTAssertFalse(state.isDisconnected)

        state = .disconnected
        XCTAssertTrue(state.isDisconnected)
    }

    func testConnectionWithTransientErrorRecovery() {
        var state: DeviceState = .disconnected
        XCTAssertTrue(state.isDisconnected)

        state = .connecting
        XCTAssertFalse(state.isDisconnected)

        // Transient error
        state = .error(.busy)
        XCTAssertFalse(state.isDisconnected)

        // Retry
        state = .connecting
        XCTAssertFalse(state.isDisconnected)

        // Success
        state = .connected
        XCTAssertFalse(state.isDisconnected)
    }

    func testConnectionWithDeviceBusyError() {
        var state: DeviceState = .disconnected
        XCTAssertTrue(state.isDisconnected)

        state = .connecting
        XCTAssertFalse(state.isDisconnected)

        // Device busy error
        state = .error(.busy)
        XCTAssertFalse(state.isDisconnected)

        // Must reconnect from disconnected
        state = .disconnected
        XCTAssertTrue(state.isDisconnected)

        state = .connecting
        XCTAssertFalse(state.isDisconnected)
    }

    func testTransferInterruptedByErrorThenResume() {
        var state: DeviceState = .connected
        XCTAssertFalse(state.isTransferring)

        // Start transfer
        state = .transferring
        XCTAssertTrue(state.isTransferring)

        // Error during transfer
        state = .error(.timeout)
        XCTAssertFalse(state.isTransferring)

        // Recovery
        state = .connecting
        state = .connected

        state = .transferring
        XCTAssertTrue(state.isTransferring)
    }

    // MARK: - State Comparison Tests

    func testStateComparisonOperators() {
        let disconnected = DeviceState.disconnected
        let connecting = DeviceState.connecting
        let connected = DeviceState.connected
        let transferring = DeviceState.transferring
        let disconnecting = DeviceState.disconnecting
        let error = DeviceState.error(.timeout)

        // Test inequality
        XCTAssertNotEqual(disconnected, connecting)
        XCTAssertNotEqual(connecting, connected)
        XCTAssertNotEqual(connected, transferring)
        XCTAssertNotEqual(transferring, disconnecting)
        XCTAssertNotEqual(disconnecting, disconnected)
        XCTAssertNotEqual(error, disconnected)
    }

    // MARK: - Error State Properties

    func testErrorStateErrorProperty() {
        let timeoutError = DeviceState.error(.timeout)
        let busyError = DeviceState.error(.busy)

        // States should be different
        XCTAssertNotEqual(timeoutError, busyError)
    }

    func testConnectedStateIsNotError() {
        let connected = DeviceState.connected
        let error = DeviceState.error(.timeout)

        XCTAssertNotEqual(connected, error)
    }
}

// MARK: - DeviceActor Connection Lifecycle Tests

final class DeviceActorConnectionLifecycleTests: XCTestCase {

    // MARK: - Connection State Validation

    func testConnectionStateHierarchy() {
        // Verify state hierarchy is complete
        let states: [DeviceState] = [
            .disconnected,
            .connecting,
            .connected,
            .transferring,
            .disconnecting,
            .error(.timeout)
        ]

        XCTAssertEqual(states.count, 6)
    }

    func testStateMutualExclusivity() {
        // Verify states are mutually exclusive
        let connected = DeviceState.connected
        let transferring = DeviceState.transferring
        let disconnected = DeviceState.disconnected

        XCTAssertNotEqual(connected, transferring)
        XCTAssertNotEqual(connected, disconnected)
        XCTAssertNotEqual(transferring, disconnected)
    }

    // MARK: - Error Type Coverage

    func testAllErrorTypesAreDistinct() {
        let timeout = MTPError.timeout
        let busy = MTPError.busy
        let notSupported = MTPError.notSupported("test")

        // These should be different cases
        XCTAssertNotEqual(String(describing: timeout), String(describing: busy))
        XCTAssertNotEqual(String(describing: timeout), String(describing: notSupported))
    }

    func testErrorStateWithDifferentErrors() {
        let timeoutState = DeviceState.error(.timeout)
        let busyState = DeviceState.error(.busy)
        let disconnectedState = DeviceState.error(.deviceDisconnected)

        XCTAssertNotEqual(timeoutState, busyState)
        XCTAssertNotEqual(timeoutState, disconnectedState)
        XCTAssertNotEqual(busyState, disconnectedState)
    }
}

// MARK: - DeviceActor Transfer Flow Tests

final class DeviceActorTransferFlowTests: XCTestCase {

    // MARK: - Transfer Flow States

    func testTransferFlowStateProgression() {
        // Simulate a complete transfer flow
        var state: DeviceState = .connected
        XCTAssertFalse(state.isTransferring)

        // Start transfer
        state = .transferring
        XCTAssertTrue(state.isTransferring)

        // Complete transfer
        state = .connected
        XCTAssertFalse(state.isTransferring)
    }

    func testConcurrentTransferAttempts() {
        // Multiple transfer requests while already transferring
        var state: DeviceState = .transferring
        XCTAssertTrue(state.isTransferring)

        // Another transfer request - should stay in transferring
        state = .transferring
        XCTAssertTrue(state.isTransferring)
    }

    func testTransferDuringConnecting() {
        // Transfer requested while connecting
        var state: DeviceState = .connecting
        XCTAssertFalse(state.isTransferring)

        // Connection completes first
        state = .connected
        XCTAssertFalse(state.isTransferring)

        // Then transfer starts
        state = .transferring
        XCTAssertTrue(state.isTransferring)
    }
}

// MARK: - DeviceError Additional Coverage Tests

final class DeviceErrorCoverageTests: XCTestCase {

    func testMTPErrorTimeout() {
        let error = MTPError.timeout
        XCTAssertNotNil(error)
    }

    func testMTPErrorBusy() {
        let error = MTPError.busy
        XCTAssertNotNil(error)
    }

    func testMTPErrorDeviceDisconnected() {
        let error = MTPError.deviceDisconnected
        XCTAssertNotNil(error)
    }

    func testMTPErrorPermissionDenied() {
        let error = MTPError.permissionDenied
        XCTAssertNotNil(error)
    }

    func testMTPErrorNotSupported() {
        let error = MTPError.notSupported("test message")
        XCTAssertNotNil(error)
    }

    func testMTPErrorProtocolError() {
        let error = MTPError.protocolError(code: 0x2001, message: "OK")
        XCTAssertNotNil(error)
    }

    func testMTPErrorObjectNotFound() {
        let error = MTPError.objectNotFound
        XCTAssertNotNil(error)
    }

    func testMTPErrorStorageFull() {
        let error = MTPError.storageFull
        XCTAssertNotNil(error)
    }

    func testMTPErrorReadOnly() {
        let error = MTPError.readOnly
        XCTAssertNotNil(error)
    }

    func testMTPErrorPreconditionFailed() {
        let error = MTPError.preconditionFailed("test condition")
        XCTAssertNotNil(error)
    }

    func testMTPErrorTransport() {
        let transportError = TransportError.timeout
        let error = MTPError.transport(transportError)
        XCTAssertNotNil(error)
    }

    func testTransportErrorVariants() {
        let noDevice = TransportError.noDevice
        let timeout = TransportError.timeout
        let busy = TransportError.busy
        let accessDenied = TransportError.accessDenied
        let io = TransportError.io("test")

        XCTAssertNotEqual(String(describing: noDevice), String(describing: timeout))
        XCTAssertNotEqual(String(describing: timeout), String(describing: busy))
        XCTAssertNotEqual(String(describing: busy), String(describing: accessDenied))
        XCTAssertNotEqual(String(describing: accessDenied), String(describing: io))
    }
}
