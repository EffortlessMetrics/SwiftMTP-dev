// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import XCTest

@testable import SwiftMTPCore

/// Tests for USBClaimDiagnostics – claim error analysis, diagnostic messages, and recovery suggestions.
final class USBClaimDiagnosticsTests: XCTestCase {

  // MARK: - Claim Success Path

  func testClaimSuccessDoesNotProduceError() {
    // A successful claim (rc == 0) should not trigger analyzeClaimFailure;
    // verify that the diagnostics utility correctly returns a non-conflict
    // error when given an rc that is neither BUSY nor ACCESS.
    let result = USBClaimDiagnostics.analyzeClaimFailure(error: 0, interface: 0)
    if case .claimFailed(let code, let iface) = result {
      XCTAssertEqual(code, 0)
      XCTAssertEqual(iface, 0)
    } else {
      // rc == 0 is not BUSY (-6) or ACCESS (-3), so falls through to generic.
      XCTFail("Expected generic claimFailed for non-conflict error code 0")
    }
  }

  // MARK: - Claim Failure with Kernel Driver Conflict

  func testClaimFailureBusyReturnsConflict() {
    let error = USBClaimDiagnostics.analyzeClaimFailure(error: -6, interface: 2)
    if case .claimFailedWithConflict(let code, let iface, _) = error {
      XCTAssertEqual(code, -6)
      XCTAssertEqual(iface, 2)
    } else {
      XCTFail("Expected claimFailedWithConflict for BUSY error")
    }
  }

  func testClaimFailureAccessDeniedReturnsConflict() {
    let error = USBClaimDiagnostics.analyzeClaimFailure(error: -3, interface: 1)
    if case .claimFailedWithConflict(let code, let iface, _) = error {
      XCTAssertEqual(code, -3)
      XCTAssertEqual(iface, 1)
    } else {
      XCTFail("Expected claimFailedWithConflict for ACCESS error")
    }
  }

  func testKernelDriverErrorDescription() {
    let error = USBClaimError.kernelDriverError("Could not detach kernel driver on interface 0")
    XCTAssertTrue(error.localizedDescription.contains("Kernel driver error"))
    XCTAssertTrue(error.localizedDescription.contains("interface 0"))
  }

  // MARK: - Claim with Multiple Interfaces

  func testClaimFailureOnDifferentInterfaces() {
    let error0 = USBClaimDiagnostics.analyzeClaimFailure(error: -6, interface: 0)
    let error1 = USBClaimDiagnostics.analyzeClaimFailure(error: -6, interface: 1)
    let error3 = USBClaimDiagnostics.analyzeClaimFailure(error: -6, interface: 3)

    if case .claimFailedWithConflict(_, let iface0, _) = error0,
      case .claimFailedWithConflict(_, let iface1, _) = error1,
      case .claimFailedWithConflict(_, let iface3, _) = error3
    {
      XCTAssertEqual(iface0, 0)
      XCTAssertEqual(iface1, 1)
      XCTAssertEqual(iface3, 3)
    } else {
      XCTFail("Expected claimFailedWithConflict for all interfaces")
    }
  }

  // MARK: - Diagnostic Message Formatting

  func testConflictMessageWithKnownProcess() {
    let error = USBClaimError.claimFailedWithConflict(
      libusbError: -6, interface: 0, conflictingProcess: "Google Chrome")
    let desc = error.localizedDescription
    XCTAssertTrue(desc.contains("LIBUSB_ERROR_BUSY"))
    XCTAssertTrue(desc.contains("Google Chrome"))
    XCTAssertTrue(desc.contains("interface 0"))
    XCTAssertTrue(desc.contains("Quit the application"))
  }

  func testConflictMessageWithoutKnownProcess() {
    let error = USBClaimError.claimFailedWithConflict(
      libusbError: -3, interface: 1, conflictingProcess: nil)
    let desc = error.localizedDescription
    XCTAssertTrue(desc.contains("LIBUSB_ERROR_ACCESS"))
    XCTAssertTrue(desc.contains("interface 1"))
    XCTAssertTrue(desc.contains("Chrome/WebUSB or Android File Transfer"))
  }

  func testGenericClaimFailedMessage() {
    let error = USBClaimError.claimFailed(libusbError: -7, interface: 2)
    let desc = error.localizedDescription
    XCTAssertTrue(desc.contains("LIBUSB_ERROR_TIMEOUT"))
    XCTAssertTrue(desc.contains("interface 2"))
  }

  func testDeviceDisconnectedMessage() {
    let error = USBClaimError.deviceDisconnected
    XCTAssertTrue(error.localizedDescription.contains("disconnected"))
  }

  func testUnknownErrorCodeFormatsAsUnknown() {
    let error = USBClaimError.claimFailed(libusbError: -99, interface: 0)
    let desc = error.localizedDescription
    XCTAssertTrue(desc.contains("LIBUSB_ERROR_UNKNOWN"))
    XCTAssertTrue(desc.contains("-99"))
  }

  // MARK: - Recovery Suggestions for Common Claim Errors

  func testBusyErrorSuggestsQuittingConflictingApp() {
    let error = USBClaimError.claimFailedWithConflict(
      libusbError: -6, interface: 0, conflictingProcess: "Android File Transfer")
    XCTAssertTrue(error.localizedDescription.contains("Quit the application"))
  }

  func testAccessErrorSuggestsCommonConflicts() {
    let error = USBClaimError.claimFailedWithConflict(
      libusbError: -3, interface: 0, conflictingProcess: nil)
    let desc = error.localizedDescription
    // Should mention common macOS MTP conflict sources
    XCTAssertTrue(desc.contains("Chrome") || desc.contains("Android File Transfer"))
  }

  func testNoDeviceErrorMapsCorrectly() {
    let error = USBClaimError.claimFailed(libusbError: -4, interface: 0)
    XCTAssertTrue(error.localizedDescription.contains("LIBUSB_ERROR_NO_DEVICE"))
  }

  func testNotSupportedErrorMapsCorrectly() {
    let error = USBClaimError.claimFailed(libusbError: -12, interface: 0)
    XCTAssertTrue(error.localizedDescription.contains("LIBUSB_ERROR_NOT_SUPPORTED"))
  }

  func testNotFoundErrorMapsCorrectly() {
    let error = USBClaimError.claimFailed(libusbError: -5, interface: 0)
    XCTAssertTrue(error.localizedDescription.contains("LIBUSB_ERROR_NOT_FOUND"))
  }

  // MARK: - Known Conflicting Processes

  func testKnownConflictingProcessesNotEmpty() {
    XCTAssertFalse(USBClaimDiagnostics.knownConflictingProcesses.isEmpty)
  }

  func testKnownConflictingProcessesIncludeChrome() {
    XCTAssertTrue(USBClaimDiagnostics.knownConflictingProcesses.contains("Google Chrome"))
  }

  func testKnownConflictingProcessesIncludeAndroidFileTransfer() {
    XCTAssertTrue(
      USBClaimDiagnostics.knownConflictingProcesses.contains("Android File Transfer"))
  }

  func testKnownConflictingProcessesIncludeADB() {
    XCTAssertTrue(USBClaimDiagnostics.knownConflictingProcesses.contains("adb"))
  }

  func testKnownConflictingProcessesIncludeChromiumBrowsers() {
    let processes = USBClaimDiagnostics.knownConflictingProcesses
    XCTAssertTrue(processes.contains("Chromium"))
    XCTAssertTrue(processes.contains("Microsoft Edge"))
    XCTAssertTrue(processes.contains("Brave"))
  }

  // MARK: - Analyze Claim Failure

  func testAnalyzeClaimFailureWithPID() {
    let error = USBClaimDiagnostics.analyzeClaimFailure(error: -6, interface: 0, pid: 12345)
    if case .claimFailedWithConflict(_, _, let process) = error {
      // processName(for:) returns "a conflicting application" for any PID
      XCTAssertNotNil(process)
    } else {
      XCTFail("Expected claimFailedWithConflict when PID is provided")
    }
  }

  func testAnalyzeClaimFailureWithoutPID() {
    let error = USBClaimDiagnostics.analyzeClaimFailure(error: -6, interface: 0)
    if case .claimFailedWithConflict(_, _, let process) = error {
      XCTAssertNil(process)
    } else {
      XCTFail("Expected claimFailedWithConflict for BUSY error")
    }
  }

  func testAnalyzeClaimFailureNonConflictError() {
    // -7 (TIMEOUT) is not BUSY or ACCESS, so should return generic claimFailed
    let error = USBClaimDiagnostics.analyzeClaimFailure(error: -7, interface: 0)
    if case .claimFailed(let code, _) = error {
      XCTAssertEqual(code, -7)
    } else {
      XCTFail("Expected generic claimFailed for TIMEOUT error")
    }
  }

  // MARK: - Equatable Conformance

  func testClaimErrorEquatable() {
    let a = USBClaimError.deviceDisconnected
    let b = USBClaimError.deviceDisconnected
    XCTAssertEqual(a, b)

    let c = USBClaimError.claimFailed(libusbError: -6, interface: 0)
    let d = USBClaimError.claimFailed(libusbError: -6, interface: 0)
    XCTAssertEqual(c, d)

    let e = USBClaimError.claimFailed(libusbError: -6, interface: 0)
    let f = USBClaimError.claimFailed(libusbError: -3, interface: 0)
    XCTAssertNotEqual(e, f)
  }

  func testClaimErrorConflictEquatable() {
    let a = USBClaimError.claimFailedWithConflict(
      libusbError: -6, interface: 0, conflictingProcess: "Chrome")
    let b = USBClaimError.claimFailedWithConflict(
      libusbError: -6, interface: 0, conflictingProcess: "Chrome")
    XCTAssertEqual(a, b)

    let c = USBClaimError.claimFailedWithConflict(
      libusbError: -6, interface: 0, conflictingProcess: nil)
    let d = USBClaimError.claimFailedWithConflict(
      libusbError: -6, interface: 0, conflictingProcess: "Chrome")
    XCTAssertNotEqual(c, d)
  }

  func testKernelDriverErrorEquatable() {
    let a = USBClaimError.kernelDriverError("msg")
    let b = USBClaimError.kernelDriverError("msg")
    XCTAssertEqual(a, b)

    let c = USBClaimError.kernelDriverError("different")
    XCTAssertNotEqual(a, c)
  }

  // MARK: - Error Code Mapping Exhaustiveness

  func testAllDocumentedLibusbErrorCodes() {
    let codes: [(Int32, String)] = [
      (-3, "LIBUSB_ERROR_ACCESS"),
      (-4, "LIBUSB_ERROR_NO_DEVICE"),
      (-5, "LIBUSB_ERROR_NOT_FOUND"),
      (-6, "LIBUSB_ERROR_BUSY"),
      (-7, "LIBUSB_ERROR_TIMEOUT"),
      (-12, "LIBUSB_ERROR_NOT_SUPPORTED"),
    ]
    for (code, expectedName) in codes {
      let error = USBClaimError.claimFailed(libusbError: code, interface: 0)
      XCTAssertTrue(
        error.localizedDescription.contains(expectedName),
        "Error code \(code) should map to \(expectedName), got: \(error.localizedDescription)")
    }
  }
}
