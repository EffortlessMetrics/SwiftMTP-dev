// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import XCTest
@testable import SwiftMTPCore
@testable import SwiftMTPTestKit

final class TransportErrorTests: XCTestCase {

    // MARK: - No Device

    func testNoDeviceError() {
        let error = TransportError.noDevice
        XCTAssertEqual(error, .noDevice)
    }

    func testMTPErrorNoDevice() {
        let error = MTPError.transport(.noDevice)
        if case .transport(let transportError) = error {
            XCTAssertEqual(transportError, .noDevice)
        } else {
            XCTFail("Expected transport-wrapped noDevice")
        }
    }

    // MARK: - Timeout

    func testTransportTimeoutError() {
        let error = TransportError.timeout
        XCTAssertEqual(error, .timeout)
    }

    func testMTPErrorTransportTimeout() {
        let error = MTPError.transport(.timeout)
        if case .transport(let te) = error, case .timeout = te {
            // Success
        } else {
            XCTFail("Expected transport timeout")
        }
    }

    // MARK: - Busy

    func testTransportBusyError() {
        let error = TransportError.busy
        XCTAssertEqual(error, .busy)
    }

    func testMTPErrorTransportBusy() {
        let error = MTPError.transport(.busy)
        if case .transport(let te) = error, case .busy = te {
            // Success
        } else {
            XCTFail("Expected transport busy")
        }
    }

    // MARK: - Access Denied

    func testAccessDeniedError() {
        let error = TransportError.accessDenied
        XCTAssertEqual(error, .accessDenied)
    }

    func testMTPErrorAccessDenied() {
        let error = MTPError.transport(.accessDenied)
        if case .transport(let te) = error, case .accessDenied = te {
            // Success
        } else {
            XCTFail("Expected access denied")
        }
    }

    // MARK: - IO Errors

    func testIOErrorWithMessage() {
        let error = TransportError.io("USB transfer failed")
        if case .io(let message) = error {
            XCTAssertEqual(message, "USB transfer failed")
        } else {
            XCTFail("Expected IO error")
        }
    }

    func testMTPErrorWrappedIOError() {
        let error = MTPError.transport(.io("Pipe stall"))
        if case .transport(let te) = error {
            if case .io(let message) = te {
                XCTAssertEqual(message, "Pipe stall")
            } else {
                XCTFail("Expected IO case")
            }
        } else {
            XCTFail("Expected transport error")
        }
    }

    // MARK: - Equatability

    func testTransportErrorEquatability() {
        XCTAssertEqual(
            TransportError.io("Test"),
            TransportError.io("Test")
        )
    }

    func testTransportErrorInequability() {
        XCTAssertNotEqual(
            TransportError.io("Test A"),
            TransportError.io("Test B")
        )
    }

    func testTransportErrorDifferentCases() {
        XCTAssertNotEqual(
            TransportError.timeout,
            TransportError.busy
        )
    }

    // MARK: - Fault Error Conversion

    func testFaultErrorTimeoutConversion() {
        let faultError = FaultError.timeout
        XCTAssertEqual(faultError.transportError, .timeout)
    }

    func testFaultErrorBusyConversion() {
        let faultError = FaultError.busy
        XCTAssertEqual(faultError.transportError, .busy)
    }

    func testFaultErrorDisconnectedConversion() {
        let faultError = FaultError.disconnected
        XCTAssertEqual(faultError.transportError, .noDevice)
    }

    func testFaultErrorAccessDeniedConversion() {
        let faultError = FaultError.accessDenied
        XCTAssertEqual(faultError.transportError, .accessDenied)
    }

    func testFaultErrorIOConversion() {
        let faultError = FaultError.io("Custom IO error")
        if case .io(let message) = faultError.transportError {
            XCTAssertEqual(message, "Custom IO error")
        } else {
            XCTFail("Expected IO transport error")
        }
    }

    func testFaultErrorProtocolErrorConversion() {
        let faultError = FaultError.protocolError(code: 0x2009)
        if case .io(let message) = faultError.transportError {
            XCTAssertEqual(message, "Protocol error injected by fault")
        } else {
            XCTFail("Expected IO transport error from protocol error")
        }
    }

    // MARK: - Fault Schedule

    func testFaultScheduleEmpty() {
        let schedule = FaultSchedule()
        XCTAssertNil(schedule.check(operation: .openSession, callIndex: 0, byteOffset: nil))
    }

    func testFaultScheduleMatchesOperation() {
        let fault = ScheduledFault(
            trigger: .onOperation(.openSession),
            error: .timeout,
            repeatCount: 1
        )
        let schedule = FaultSchedule([fault])

        let result = schedule.check(operation: .openSession, callIndex: 0, byteOffset: nil)
        XCTAssertNotNil(result)
        XCTAssertEqual(result, .timeout)
    }

    func testFaultScheduleDoesNotMatchDifferentOperation() {
        let fault = ScheduledFault(
            trigger: .onOperation(.openSession),
            error: .timeout,
            repeatCount: 1
        )
        let schedule = FaultSchedule([fault])

        let result = schedule.check(operation: .closeSession, callIndex: 0, byteOffset: nil)
        XCTAssertNil(result)
    }

    func testFaultScheduleAtCallIndex() {
        let fault = ScheduledFault(
            trigger: .atCallIndex(2),
            error: .busy,
            repeatCount: 1
        )
        let schedule = FaultSchedule([fault])

        XCTAssertNil(schedule.check(operation: .openSession, callIndex: 0, byteOffset: nil))
        XCTAssertNil(schedule.check(operation: .openSession, callIndex: 1, byteOffset: nil))
        XCTAssertNotNil(schedule.check(operation: .openSession, callIndex: 2, byteOffset: nil))
    }

    func testFaultScheduleAtByteOffset() {
        let fault = ScheduledFault(
            trigger: .atByteOffset(1024),
            error: .disconnected,
            repeatCount: 1
        )
        let schedule = FaultSchedule([fault])

        XCTAssertNil(schedule.check(operation: .executeStreamingCommand, callIndex: 0, byteOffset: 512))
        XCTAssertNotNil(schedule.check(operation: .executeStreamingCommand, callIndex: 0, byteOffset: 1024))
    }

    func testFaultScheduleRepeatCount() {
        let fault = ScheduledFault(
            trigger: .onOperation(.executeCommand),
            error: .busy,
            repeatCount: 3,
            label: "busy×3"
        )
        let schedule = FaultSchedule([fault])

        XCTAssertNotNil(schedule.check(operation: .executeCommand, callIndex: 0, byteOffset: nil))
        XCTAssertNotNil(schedule.check(operation: .executeCommand, callIndex: 1, byteOffset: nil))
        XCTAssertNotNil(schedule.check(operation: .executeCommand, callIndex: 2, byteOffset: nil))
        XCTAssertNil(schedule.check(operation: .executeCommand, callIndex: 3, byteOffset: nil))
    }

    func testFaultScheduleUnlimitedRepeat() {
        let fault = ScheduledFault(
            trigger: .onOperation(.executeCommand),
            error: .busy,
            repeatCount: 0  // unlimited
        )
        let schedule = FaultSchedule([fault])

        for i in 0..<5 {
            XCTAssertNotNil(schedule.check(operation: .executeCommand, callIndex: i, byteOffset: nil))
        }
    }

    func testFaultScheduleClear() {
        let fault = ScheduledFault(
            trigger: .onOperation(.openSession),
            error: .timeout,
            repeatCount: 1
        )
        let schedule = FaultSchedule([fault])
        schedule.clear()

        XCTAssertNil(schedule.check(operation: .openSession, callIndex: 0, byteOffset: nil))
    }

    func testFaultScheduleAdd() {
        let schedule = FaultSchedule()
        let fault = ScheduledFault(
            trigger: .onOperation(.getDeviceInfo),
            error: .accessDenied,
            repeatCount: 1
        )
        schedule.add(fault)

        XCTAssertNotNil(schedule.check(operation: .getDeviceInfo, callIndex: 0, byteOffset: nil))
    }

    // MARK: - Predefined Fault Patterns

    func testPipeStallPattern() {
        let fault = ScheduledFault.pipeStall(on: .executeCommand)
        XCTAssertEqual(fault.trigger, .onOperation(.executeCommand))
        if case .io(let message) = fault.error {
            XCTAssertEqual(message, "USB pipe stall")
        } else {
            XCTFail("Expected IO error")
        }
        XCTAssertEqual(fault.label, "pipeStall(executeCommand)")
    }

    func testDisconnectAtOffsetPattern() {
        let fault = ScheduledFault.disconnectAtOffset(2048)
        XCTAssertEqual(fault.trigger, .atByteOffset(2048))
        XCTAssertEqual(fault.error, .disconnected)
        XCTAssertEqual(fault.label, "disconnect@2048")
    }

    func testBusyForRetriesPattern() {
        let fault = ScheduledFault.busyForRetries(5)
        XCTAssertEqual(fault.trigger, .onOperation(.executeCommand))
        XCTAssertEqual(fault.error, .busy)
        XCTAssertEqual(fault.repeatCount, 5)
        XCTAssertEqual(fault.label, "busy×5")
    }

    func testTimeoutOncePattern() {
        let fault = ScheduledFault.timeoutOnce(on: .getObjectInfos)
        XCTAssertEqual(fault.trigger, .onOperation(.getObjectInfos))
        XCTAssertEqual(fault.error, .timeout)
        XCTAssertEqual(fault.repeatCount, 1)
    }

    // MARK: - Device Disconnection

    func testDeviceDisconnectedError() {
        let error = MTPError.deviceDisconnected
        XCTAssertEqual(error, .deviceDisconnected)
    }

    // MARK: - Permission Denied

    func testPermissionDeniedTransportWrapped() {
        let error = MTPError.permissionDenied
        XCTAssertEqual(error, .permissionDenied)
    }
}
