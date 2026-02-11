// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import XCTest
@testable import SwiftMTPCore

final class MTPErrorTests: XCTestCase {

    func testMTPErrorEquatability() {
        // Test same cases are equal
        XCTAssertEqual(MTPError.deviceDisconnected, MTPError.deviceDisconnected)
        XCTAssertEqual(MTPError.permissionDenied, MTPError.permissionDenied)
        XCTAssertEqual(MTPError.timeout, MTPError.timeout)
        XCTAssertEqual(MTPError.busy, MTPError.busy)
        XCTAssertEqual(MTPError.readOnly, MTPError.readOnly)
        XCTAssertEqual(MTPError.objectNotFound, MTPError.objectNotFound)
        XCTAssertEqual(MTPError.storageFull, MTPError.storageFull)

        // Test different cases are not equal
        XCTAssertNotEqual(MTPError.deviceDisconnected, MTPError.permissionDenied)
        XCTAssertNotEqual(MTPError.timeout, MTPError.busy)
    }

    func testMTPErrorWithMessages() {
        let error1 = MTPError.notSupported("Feature X")
        let error2 = MTPError.notSupported("Feature X")
        let error3 = MTPError.notSupported("Feature Y")

        XCTAssertEqual(error1, error2)
        XCTAssertNotEqual(error1, error3)
    }

    func testMTPErrorProtocolError() {
        let error1 = MTPError.protocolError(code: 0x2001, message: "Invalid parameter")
        let error2 = MTPError.protocolError(code: 0x2001, message: "Invalid parameter")
        let error3 = MTPError.protocolError(code: 0x2002, message: "Invalid parameter")

        XCTAssertEqual(error1, error2)
        XCTAssertNotEqual(error1, error3)
    }

    func testMTPErrorPreconditionFailed() {
        let error1 = MTPError.preconditionFailed("Device not initialized")
        let error2 = MTPError.preconditionFailed("Device not initialized")
        let error3 = MTPError.preconditionFailed("Session not open")

        XCTAssertEqual(error1, error2)
        XCTAssertNotEqual(error1, error3)
    }

    func testMTPErrorTransportMapping() {
        let transportError = TransportError.timeout
        let mtpError = MTPError.transport(transportError)

        // Test that transport error is wrapped correctly
        if case .transport(.timeout) = mtpError {
            // Expected
        } else {
            XCTFail("Expected transport(.timeout)")
        }
    }

    func testTransportErrorEquatability() {
        XCTAssertEqual(TransportError.noDevice, TransportError.noDevice)
        XCTAssertEqual(TransportError.timeout, TransportError.timeout)
        XCTAssertEqual(TransportError.busy, TransportError.busy)
        XCTAssertEqual(TransportError.accessDenied, TransportError.accessDenied)
        XCTAssertEqual(TransportError.io("read failed"), TransportError.io("read failed"))

        XCTAssertNotEqual(TransportError.noDevice, TransportError.timeout)
        XCTAssertNotEqual(TransportError.io("error A"), TransportError.io("error B"))
    }

    func testMTPErrorInternalError() {
        let error = MTPError.internalError("Something went wrong")
        
        // The factory maps to .notSupported
        if case .notSupported(let message) = error {
            XCTAssertEqual(message, "Something went wrong")
        } else {
            XCTFail("Expected .notSupported case")
        }
    }
}
