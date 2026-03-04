// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import XCTest

@testable import SwiftMTPCore

/// Tests for PTPResponseCode name lookup and description formatting.
final class ResponseCodeTests: XCTestCase {

  // MARK: - Standard Response Codes Have Names

  func testAllStandardResponseCodesHaveNames() {
    let standardCodes: [UInt16: String] = [
      0x2001: "OK",
      0x2002: "GeneralError",
      0x2003: "SessionNotOpen",
      0x2004: "InvalidTransactionID",
      0x2005: "OperationNotSupported",
      0x2006: "ParameterNotSupported",
      0x2007: "IncompleteTransfer",
      0x2008: "InvalidStorageID",
      0x2009: "InvalidObjectHandle",
      0x200A: "DevicePropNotSupported",
      0x200B: "InvalidObjectFormatCode",
      0x200C: "StoreFull",
      0x200D: "ObjectWriteProtected",
      0x200E: "StoreReadOnly",
      0x200F: "AccessDenied",
      0x2010: "NoThumbnailPresent",
      0x2011: "SelfTestFailed",
      0x2012: "PartialDeletion",
      0x2013: "StoreNotAvailable",
      0x2014: "SpecificationByFormatUnsupported",
      0x2015: "NoValidObjectInfo",
      0x2016: "InvalidCodeFormat",
      0x2017: "UnknownVendorCode",
      0x2018: "CaptureAlreadyTerminated",
      0x2019: "DeviceBusy",
      0x201A: "InvalidParentObject",
      0x201B: "InvalidDevicePropFormat",
      0x201C: "InvalidDevicePropValue",
      0x201D: "InvalidParameter",
      0x201E: "SessionAlreadyOpen",
      0x201F: "TransactionCancelled",
      0x2020: "SpecificationOfDestinationUnsupported",
    ]

    for (code, expectedName) in standardCodes {
      let name = PTPResponseCode.name(for: code)
      XCTAssertEqual(
        name, expectedName,
        "Code 0x\(String(code, radix: 16)) should be '\(expectedName)', got '\(name ?? "nil")'")
    }
  }

  // MARK: - Description Formatting

  func testDescribeFormatsCorrectly() {
    let desc = PTPResponseCode.describe(0x2001)
    XCTAssertEqual(desc, "OK (0x2001)")
  }

  func testDescribeDeviceBusy() {
    let desc = PTPResponseCode.describe(0x2019)
    XCTAssertEqual(desc, "DeviceBusy (0x2019)")
  }

  func testDescribeInvalidParameter() {
    let desc = PTPResponseCode.describe(0x201D)
    XCTAssertEqual(desc, "InvalidParameter (0x201d)")
  }

  func testDescribeTransactionCancelled() {
    let desc = PTPResponseCode.describe(0x201F)
    XCTAssertEqual(desc, "TransactionCancelled (0x201f)")
  }

  // MARK: - Unknown Response Codes

  func testUnknownResponseCodeReturnsNilName() {
    XCTAssertNil(PTPResponseCode.name(for: 0xBEEF))
    XCTAssertNil(PTPResponseCode.name(for: 0xA801))
    XCTAssertNil(PTPResponseCode.name(for: 0x0000))
  }

  func testUnknownResponseCodeDescribePreservesRawValue() {
    let desc = PTPResponseCode.describe(0xBEEF)
    XCTAssertTrue(desc.contains("Unknown"), "Should contain 'Unknown': \(desc)")
    XCTAssertTrue(desc.contains("beef"), "Should contain hex value: \(desc)")
  }

  func testUnknownVendorExtensionCode() {
    let desc = PTPResponseCode.describe(0xA801)
    XCTAssertTrue(desc.contains("Unknown"), "Vendor extension codes are not in standard table")
    XCTAssertTrue(desc.contains("a801"))
  }

  // MARK: - Boundary Codes

  func testOKIsFirstValidCode() {
    XCTAssertEqual(PTPResponseCode.name(for: 0x2001), "OK")
    XCTAssertNil(PTPResponseCode.name(for: 0x2000))
  }

  func testLastStandardCode() {
    XCTAssertEqual(PTPResponseCode.name(for: 0x2020), "SpecificationOfDestinationUnsupported")
    XCTAssertNil(PTPResponseCode.name(for: 0x2021))
  }

  // MARK: - MTPError Integration

  func testMTPErrorProtocolCodeNameFallback() {
    // When MTPError.protocolError has no message, it should derive a name from the code
    let error = MTPError.protocolError(code: 0x2019, message: nil)
    let desc = error.errorDescription ?? ""
    XCTAssertTrue(desc.contains("DeviceBusy"), "Error description should contain code name: \(desc)")
  }

  func testMTPErrorWithCustomMessage() {
    let error = MTPError.protocolError(code: 0x2002, message: "CustomMsg")
    let desc = error.errorDescription ?? ""
    XCTAssertTrue(desc.contains("CustomMsg"), "Should use custom message: \(desc)")
  }
}
