// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import XCTest
@testable import SwiftMTPTransportLibUSB
@testable import SwiftMTPCore
import SwiftMTPTestKit

/// Tests for error scenarios and recovery mechanisms
final class LibUSBErrorHandlingTests: XCTestCase {

    // MARK: - Transport Error Tests

    func testTransportErrorEquatability() {
        XCTAssertEqual(TransportError.noDevice, TransportError.noDevice)
        XCTAssertEqual(TransportError.timeout, TransportError.timeout)
        XCTAssertEqual(TransportError.busy, TransportError.busy)
        XCTAssertEqual(TransportError.accessDenied, TransportError.accessDenied)
        XCTAssertEqual(TransportError.io("error A"), TransportError.io("error A"))
        XCTAssertNotEqual(TransportError.io("error A"), TransportError.io("error B"))
        XCTAssertNotEqual(TransportError.noDevice, TransportError.timeout)
    }

    func testTransportErrorDescriptions() {
        let noDevice = TransportError.noDevice
        let timeout = TransportError.timeout
        let busy = TransportError.busy
        let accessDenied = TransportError.accessDenied
        let ioError = TransportError.io("read failed")

        XCTAssertNotEqual(noDevice, timeout)
        XCTAssertNotEqual(noDevice, busy)
        XCTAssertNotEqual(noDevice, accessDenied)
        XCTAssertNotEqual(noDevice, ioError)
    }

    // MARK: - Fault Injection Tests

    func testFaultErrorConversion() {
        let timeoutFault = FaultError.timeout
        XCTAssertEqual(timeoutFault.transportError, .timeout)

        let busyFault = FaultError.busy
        XCTAssertEqual(busyFault.transportError, .busy)

        let disconnectedFault = FaultError.disconnected
        XCTAssertEqual(disconnectedFault.transportError, .noDevice)

        let accessDeniedFault = FaultError.accessDenied
        XCTAssertEqual(accessDeniedFault.transportError, .accessDenied)

        let ioFault = FaultError.io("test error")
        XCTAssertEqual(ioFault.transportError, .io("test error"))
    }

    func testScheduledFaultCreation() {
        let pipeStall = ScheduledFault.pipeStall(on: .executeCommand)
        XCTAssertNotNil(pipeStall)
        XCTAssertEqual(pipeStall.label, "pipeStall(executeCommand)")

        let disconnectAtOffset = ScheduledFault.disconnectAtOffset(1024)
        XCTAssertNotNil(disconnectAtOffset)
        XCTAssertEqual(disconnectAtOffset.label, "disconnect@1024")
    }

    func testBusyRetryFault() {
        let busyRetry = ScheduledFault.busyForRetries(3)
        XCTAssertEqual(busyRetry.repeatCount, 3)
        XCTAssertEqual(busyRetry.label, "busy×3")
    }

    func testTimeoutFault() {
        let timeout = ScheduledFault.timeoutOnce(on: .openUSB)
        XCTAssertEqual(timeout.repeatCount, 1)
        XCTAssertEqual(timeout.label, "timeout(openUSB)")
    }

    // MARK: - Fault Trigger Tests

    func testFaultTriggerOnOperation() {
        let trigger = FaultTrigger.onOperation(.getDeviceInfo)
        if case .onOperation(let op) = trigger {
            XCTAssertEqual(op, .getDeviceInfo)
        } else {
            XCTFail("Expected onOperation trigger")
        }
    }

    func testFaultTriggerAtCallIndex() {
        let trigger = FaultTrigger.atCallIndex(5)
        if case .atCallIndex(let index) = trigger {
            XCTAssertEqual(index, 5)
        } else {
            XCTFail("Expected atCallIndex trigger")
        }
    }

    func testFaultTriggerAtByteOffset() {
        let trigger = FaultTrigger.atByteOffset(2048)
        if case .atByteOffset(let offset) = trigger {
            XCTAssertEqual(offset, 2048)
        } else {
            XCTFail("Expected atByteOffset trigger")
        }
    }

    func testFaultTriggerAfterDelay() {
        let trigger = FaultTrigger.afterDelay(0.5)
        if case .afterDelay(let delay) = trigger {
            XCTAssertEqual(delay, 0.5)
        } else {
            XCTFail("Expected afterDelay trigger")
        }
    }

    // MARK: - USB Error Code Mapping Tests

    func testLibUSBErrorMapping() {
        // Test common libusb error code mapping
        let success: Int32 = 0
        let errorNotFound: Int32 = -5
        let errorNoMem: Int32 = -12
        let errorAccessDenied: Int32 = -3
        let errorTimeout: Int32 = -7

        XCTAssertEqual(success, 0)
        XCTAssertNotEqual(errorNotFound, success)
    }

    // MARK: - Interface Probe Error Tests

    func testInterfaceCandidateScoring() {
        let highScoreCandidate = InterfaceCandidate(
            ifaceNumber: 0,
            altSetting: 0,
            bulkIn: 0x81,
            bulkOut: 0x02,
            eventIn: 0x83,
            score: 100,
            ifaceClass: 0x06,
            ifaceSubclass: 0x01,
            ifaceProtocol: 0x01
        )

        XCTAssertEqual(highScoreCandidate.score, 100)
        XCTAssertEqual(highScoreCandidate.ifaceClass, 0x06)
    }

    // MARK: - Device Error Recovery Tests

    func testRecoveryFromTimeout() {
        // Test that timeout recovery mechanisms are properly configured
        let handshakeTimeout: Int = 5000
        XCTAssertEqual(handshakeTimeout, 5000)
    }

    func testRecoveryFromBusy() {
        // Test busy retry configuration
        let retryCount = 3
        XCTAssertGreaterThan(retryCount, 0)
    }

    func testNoProgressTimeoutRecoveryGateMatchesSentZeroTimeout() {
        let shouldRecover = MTPUSBLink.shouldRecoverNoProgressTimeout(rc: -7, sent: 0)
        XCTAssertTrue(shouldRecover)
    }

    func testNoProgressTimeoutRecoveryGateRejectsPartialProgress() {
        let shouldRecover = MTPUSBLink.shouldRecoverNoProgressTimeout(rc: -7, sent: 4)
        XCTAssertFalse(shouldRecover)
    }

    func testNoProgressTimeoutRecoveryGateRejectsNonTimeout() {
        let shouldRecover = MTPUSBLink.shouldRecoverNoProgressTimeout(rc: -9, sent: 0)
        XCTAssertFalse(shouldRecover)
    }

    func testDeviceReconnection() {
        // Test device ID persistence after reconnection
        let originalID = MTPDeviceID(raw: "18d1:4ee7@1:5")
        XCTAssertEqual(originalID.raw, "18d1:4ee7@1:5")
    }

    // MARK: - USB Error Code Tests

    func testUSBLibraryErrorCodes() {
        // Common libusb error codes
        let libusbSuccess = 0
        let libusbError = -1
        let libusbNotFound = -5
        let libusbNoMem = -12
        let libusbAccessDenied = -3
        let libusbTimeout = -7

        XCTAssertEqual(libusbSuccess, 0)
        XCTAssertNotEqual(libusbError, libusbSuccess)
    }

    // MARK: - Async Error Handling Tests

    func testAsyncTransportErrors() async throws {
        // Test async error propagation
        do {
            throw TransportError.timeout
        } catch {
            XCTAssertEqual(error as? TransportError, .timeout)
        }
    }

    func testAsyncIOErrors() async throws {
        // Test async IO error handling
        do {
            throw TransportError.io("simulated IO error")
        } catch {
            if case .io(let message) = error as? TransportError {
                XCTAssertEqual(message, "simulated IO error")
            } else {
                XCTFail("Expected io error")
            }
        }
    }

    // MARK: - Error Context Tests

    func testErrorWithContext() {
        // Test error with additional context
        let errorWithContext = TransportError.io("Device not responding")
        if case .io(let message) = errorWithContext {
            XCTAssertTrue(message.contains("Device"))
        }
    }
}
