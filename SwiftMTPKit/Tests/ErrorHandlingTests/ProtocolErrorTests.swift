// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import XCTest
@testable import SwiftMTPCore
@testable import SwiftMTPTestKit

final class ProtocolErrorTests: XCTestCase {

    // MARK: - Response Code Validation

    func testProtocolErrorWithValidCodeAndMessage() {
        let error = MTPError.protocolError(code: 0x2001, message: "Invalid StorageID")
        XCTAssertEqual(error.code, 0x2001)
        XCTAssertEqual(error.message, "Invalid StorageID")
    }

    func testProtocolErrorWithNilMessage() {
        let error = MTPError.protocolError(code: 0x2009, message: nil)
        XCTAssertEqual(error.code, 0x2009)
        XCTAssertNil(error.message)
    }

    func testProtocolErrorUnknownCode() {
        let unknownCode: UInt16 = 0xFFFF
        let error = MTPError.protocolError(code: unknownCode, message: nil)
        XCTAssertEqual(error.code, unknownCode)
    }

    // MARK: - Session Errors

    func testSessionAlreadyOpenDetection() {
        let sessionError = MTPError.protocolError(code: 0x201E, message: "Session already open")
        XCTAssertTrue(sessionError.isSessionAlreadyOpen)
    }

    func testSessionAlreadyOpenFalseForOtherErrors() {
        let otherError = MTPError.protocolError(code: 0x2001, message: "Invalid StorageID")
        XCTAssertFalse(otherError.isSessionAlreadyOpen)
    }

    func testSessionAlreadyOpenFalseForTransportError() {
        let transportError = MTPError.transport(.busy)
        XCTAssertFalse(transportError.isSessionAlreadyOpen)
    }

    // MARK: - Device Busy Conditions

    func testDeviceBusyError() {
        let error = MTPError.busy
        XCTAssertEqual(error, .busy)
    }

    func testProtocolErrorDeviceBusy() {
        let error = MTPError.protocolError(code: 0x2019, message: "Device busy")
        XCTAssertEqual(error.code, 0x2019)
    }

    // MARK: - Invalid Parameters

    func testInvalidParameterStorageID() {
        let error = MTPError.protocolError(code: 0x2001, message: "Invalid StorageID")
        XCTAssertEqual(error.code, 0x2001)
    }

    func testInvalidParameterObjectHandle() {
        let error = MTPError.protocolError(code: 0x2002, message: "Invalid ObjectHandle")
        XCTAssertEqual(error.code, 0x2002)
    }

    func testInvalidParameterDeviceProp() {
        let error = MTPError.protocolError(code: 0x2003, message: "Invalid DevicePropFormat")
        XCTAssertEqual(error.code, 0x2003)
    }

    // MARK: - Not Supported Operations

    func testOperationNotSupported() {
        let error = MTPError.notSupported("GetObjectPropValue not implemented")
        if case .notSupported(let message) = error {
            XCTAssertEqual(message, "GetObjectPropValue not implemented")
        } else {
            XCTFail("Expected .notSupported case")
        }
    }

    func testProtocolErrorOperationNotSupported() {
        let error = MTPError.protocolError(code: 0x2005, message: "Operation not supported")
        XCTAssertEqual(error.code, 0x2005)
    }

    // MARK: - Object Not Found

    func testObjectNotFoundError() {
        let error = MTPError.objectNotFound
        XCTAssertEqual(error, .objectNotFound)
    }

    func testProtocolErrorObjectNotFound() {
        let error = MTPError.protocolError(code: 0x2009, message: "Object not found")
        XCTAssertEqual(error.code, 0x2009)
    }

    // MARK: - Storage Errors

    func testStorageFullError() {
        let error = MTPError.storageFull
        XCTAssertEqual(error, .storageFull)
    }

    func testProtocolErrorStorageFull() {
        let error = MTPError.protocolError(code: 0x200C, message: "Storage full")
        XCTAssertEqual(error.code, 0x200C)
    }

    // MARK: - Permission Errors

    func testPermissionDeniedError() {
        let error = MTPError.permissionDenied
        XCTAssertEqual(error, .permissionDenied)
    }

    func testProtocolErrorPermissionDenied() {
        let error = MTPError.protocolError(code: 0x200F, message: "Permission denied")
        XCTAssertEqual(error.code, 0x200F)
    }

    // MARK: - Read-Only Errors

    func testReadOnlyError() {
        let error = MTPError.readOnly
        XCTAssertEqual(error, .readOnly)
    }

    func testProtocolErrorReadOnly() {
        let error = MTPError.protocolError(code: 0x200E, message: "Object write-protected")
        XCTAssertEqual(error.code, 0x200E)
    }

    // MARK: - Timeout Errors

    func testTimeoutError() {
        let error = MTPError.timeout
        XCTAssertEqual(error, .timeout)
    }

    func testTransportWrappedTimeout() {
        let error = MTPError.transport(.timeout)
        if case .transport(let transportError) = error {
            XCTAssertEqual(transportError, .timeout)
        } else {
            XCTFail("Expected transport-wrapped timeout")
        }
    }

    // MARK: - Precondition Failed

    func testPreconditionFailedWithMessage() {
        let error = MTPError.preconditionFailed("Storage ID required")
        if case .preconditionFailed(let message) = error {
            XCTAssertEqual(message, "Storage ID required")
        } else {
            XCTFail("Expected .preconditionFailed case")
        }
    }

    // MARK: - Equatability

    func testMTPErrorEquatability() {
        XCTAssertEqual(
            MTPError.protocolError(code: 0x2001, message: "Test"),
            MTPError.protocolError(code: 0x2001, message: "Test")
        )
    }

    func testMTPErrorInequabilityDifferentCodes() {
        XCTAssertNotEqual(
            MTPError.protocolError(code: 0x2001, message: "Test"),
            MTPError.protocolError(code: 0x2002, message: "Test")
        )
    }

    func testMTPErrorInequabilityDifferentMessages() {
        XCTAssertNotEqual(
            MTPError.protocolError(code: 0x2001, message: "Test A"),
            MTPError.protocolError(code: 0x2001, message: "Test B")
        )
    }

    // MARK: - All PTP Response Codes Coverage

    func testAllCommonResponseCodes() {
        let responseCodes: [(UInt16, String)] = [
            (0x2000, "Undefined"),
            (0x2001, "Invalid StorageID"),
            (0x2002, "Invalid ObjectHandle"),
            (0x2003, "DevicePropNotSupported"),
            (0x2004, "DeleteObjectsFailed"),
            (0x2005, "OperationNotSupported"),
            (0x2006, "IncompleteTransfer"),
            (0x2007, "InvalidSyntax"),
            (0x2008, "ParameterNotSupported"),
            (0x2009, "ObjectNotFound"),
            (0x0A01, "TransactionCanceled"),
        ]

        for (code, _) in responseCodes {
            let error = MTPError.protocolError(code: code, message: nil)
            XCTAssertEqual(error.code, code)
        }
    }
}

// MARK: - MTPError Extension for Testing

extension MTPError {
    var code: UInt16 {
        switch self {
        case .protocolError(let code, _):
            return code
        default:
            return 0
        }
    }

    var message: String? {
        switch self {
        case .protocolError(_, let message):
            return message
        case .notSupported(let message):
            return message
        case .preconditionFailed(let message):
            return message
        default:
            return nil
        }
    }
}
