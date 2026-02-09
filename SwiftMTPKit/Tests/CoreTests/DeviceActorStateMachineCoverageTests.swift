// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import XCTest
@testable import SwiftMTPCore

/// DeviceActor state machine comprehensive coverage tests
final class DeviceActorStateMachineCoverageTests: XCTestCase {

    // MARK: - DeviceError Type Tests

    func testDeviceErrorTypeVariants() {
        // Test all DeviceError variants
        let timeoutError = DeviceError.timeout
        let busyError = DeviceError.busy
        let unexpectedError = DeviceError.unexpected

        XCTAssertNotEqual(timeoutError, busyError)
        XCTAssertNotEqual(timeoutError, unexpectedError)
        XCTAssertNotEqual(busyError, unexpectedError)
    }

    func testDeviceErrorEquatable() {
        // Test error equality
        let error1 = DeviceError.timeout
        let error2 = DeviceError.timeout
        let error3 = DeviceError.busy

        XCTAssertEqual(error1, error2)
        XCTAssertNotEqual(error1, error3)
    }

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

        state = .error(.unexpected)
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
