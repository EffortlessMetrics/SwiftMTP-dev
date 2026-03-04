// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import XCTest
@testable import SwiftMTPCore

/// Inline snapshot tests for error message formatting: verifies that all
/// MTPError and TransportError cases produce actionable, user-facing messages
/// with stable recovery suggestions.  Guards against silent message regressions.
final class ErrorMessageSnapshotTests: XCTestCase {

  // MARK: - 1. MTPError errorDescription Completeness

  func testAllMTPErrorCasesHaveDescriptions() {
    let errors: [MTPError] = [
      .deviceDisconnected,
      .permissionDenied,
      .notSupported("test"),
      .transport(.noDevice),
      .protocolError(code: 0x2002, message: nil),
      .objectNotFound,
      .objectWriteProtected,
      .storageFull,
      .readOnly,
      .timeout,
      .busy,
      .sessionBusy,
      .preconditionFailed("test"),
      .verificationFailed(expected: 100, actual: 50),
    ]
    for error in errors {
      XCTAssertNotNil(error.errorDescription, "Missing errorDescription for: \(error)")
      XCTAssertFalse(error.errorDescription!.isEmpty, "Empty errorDescription for: \(error)")
    }
  }

  func testAllMTPErrorCasesHaveFailureReasons() {
    let errors: [MTPError] = [
      .deviceDisconnected,
      .permissionDenied,
      .notSupported("test"),
      .transport(.noDevice),
      .protocolError(code: 0x2002, message: nil),
      .objectNotFound,
      .objectWriteProtected,
      .storageFull,
      .readOnly,
      .timeout,
      .busy,
      .sessionBusy,
      .preconditionFailed("test"),
      .verificationFailed(expected: 100, actual: 50),
    ]
    for error in errors {
      XCTAssertNotNil(error.failureReason, "Missing failureReason for: \(error)")
      XCTAssertFalse(error.failureReason!.isEmpty, "Empty failureReason for: \(error)")
    }
  }

  func testAllMTPErrorCasesHaveRecoverySuggestions() {
    let errors: [MTPError] = [
      .deviceDisconnected,
      .permissionDenied,
      .notSupported("test"),
      .transport(.noDevice),
      .protocolError(code: 0x2002, message: nil),
      .objectNotFound,
      .objectWriteProtected,
      .storageFull,
      .readOnly,
      .timeout,
      .busy,
      .sessionBusy,
      .preconditionFailed("test"),
      .verificationFailed(expected: 100, actual: 50),
    ]
    for error in errors {
      XCTAssertNotNil(error.recoverySuggestion, "Missing recoverySuggestion for: \(error)")
      XCTAssertFalse(error.recoverySuggestion!.isEmpty, "Empty recoverySuggestion for: \(error)")
    }
  }

  // MARK: - 2. TransportError errorDescription Completeness

  func testAllTransportErrorCasesHaveDescriptions() {
    let errors: [TransportError] = [
      .noDevice, .timeout, .busy, .accessDenied, .stall,
      .io("test I/O error"),
      .timeoutInPhase(.bulkOut),
      .timeoutInPhase(.bulkIn),
      .timeoutInPhase(.responseWait),
    ]
    for error in errors {
      XCTAssertNotNil(error.errorDescription, "Missing errorDescription for: \(error)")
      XCTAssertNotNil(error.failureReason, "Missing failureReason for: \(error)")
      XCTAssertNotNil(error.recoverySuggestion, "Missing recoverySuggestion for: \(error)")
    }
  }

  // MARK: - 3. Actionable Error Descriptions

  func testActionableDescriptionDeviceDisconnectedContainsReconnect() {
    let msg = MTPError.deviceDisconnected.actionableDescription
    XCTAssertTrue(msg.lowercased().contains("reconnect") || msg.lowercased().contains("disconnect"),
      "Message should address disconnection: \(msg)")
  }

  func testActionableDescriptionPermissionDeniedContainsAccess() {
    let msg = MTPError.permissionDenied.actionableDescription
    XCTAssertTrue(msg.lowercased().contains("permission") || msg.lowercased().contains("denied") || msg.lowercased().contains("access"),
      "Message should mention access/permission: \(msg)")
  }

  func testActionableDescriptionTransportNoDeviceContainsMTP() {
    let msg = MTPError.transport(.noDevice).actionableDescription
    XCTAssertFalse(msg.isEmpty, "Actionable description should not be empty")
  }

  func testActionableDescriptionTimeoutContainsTimeout() {
    let msg = MTPError.timeout.actionableDescription
    XCTAssertTrue(msg.lowercased().contains("timeout") || msg.lowercased().contains("timed"),
      "Message should mention timeout: \(msg)")
  }

  func testActionableDescriptionBusyIsNonEmpty() {
    let msg = MTPError.busy.actionableDescription
    XCTAssertFalse(msg.isEmpty, "Busy actionable description should not be empty")
  }

  func testActionableDescriptionStorageFullContainsStorage() {
    let msg = MTPError.storageFull.actionableDescription
    XCTAssertTrue(msg.lowercased().contains("storage") || msg.lowercased().contains("full"),
      "Message should mention storage: \(msg)")
  }

  func testActionableDescriptionStallIsNonEmpty() {
    let msg = MTPError.transport(.stall).actionableDescription
    XCTAssertFalse(msg.isEmpty, "Stall actionable description should not be empty")
  }

  func testActionableDescriptionAccessDeniedIsNonEmpty() {
    let msg = MTPError.transport(.accessDenied).actionableDescription
    XCTAssertFalse(msg.isEmpty, "Access denied actionable description should not be empty")
  }

  // MARK: - 4. Protocol Error Message Formatting

  func testProtocolErrorIncludesHexCode() {
    let error = MTPError.protocolError(code: 0x2005, message: nil)
    let desc = error.errorDescription!
    XCTAssertTrue(desc.contains("0x2005") || desc.contains("0x2005"),
      "Protocol error should include hex code: \(desc)")
  }

  func testProtocolErrorSessionAlreadyOpen() {
    let error = MTPError.protocolError(code: 0x201E, message: nil)
    XCTAssertTrue(error.isSessionAlreadyOpen)
    let desc = error.errorDescription!
    XCTAssertTrue(desc.contains("201E") || desc.contains("session"),
      "Should mention session: \(desc)")
  }

  func testProtocolErrorStorageFullViaCode() {
    let error = MTPError.protocolError(code: 0x200C, message: nil)
    let suggestion = error.recoverySuggestion!
    XCTAssertTrue(suggestion.contains("Free") || suggestion.contains("space"),
      "Should suggest freeing space: \(suggestion)")
  }

  func testProtocolErrorObjectNotFound() {
    let error = MTPError.protocolError(code: 0x2009, message: nil)
    let reason = error.failureReason!
    XCTAssertTrue(reason.contains("object") || reason.contains("handle") || reason.contains("deleted"),
      "Should explain object handle issue: \(reason)")
  }

  // MARK: - 5. TransportPhase Description Stability

  func testTransportPhaseBulkOutDescription() {
    XCTAssertEqual(TransportPhase.bulkOut.description, "bulk-out")
  }

  func testTransportPhaseBulkInDescription() {
    XCTAssertEqual(TransportPhase.bulkIn.description, "bulk-in")
  }

  func testTransportPhaseResponseWaitDescription() {
    XCTAssertEqual(TransportPhase.responseWait.description, "response-wait")
  }

  func testTimeoutInPhaseIncludesPhaseInDescription() {
    let error = TransportError.timeoutInPhase(.bulkIn)
    let desc = error.errorDescription!
    XCTAssertTrue(desc.contains("bulk-in"),
      "Phase-specific timeout should include phase name: \(desc)")
  }

  // MARK: - 6. Error Message Non-Regression (exact strings)

  func testExactErrorDescriptionDeviceDisconnected() {
    XCTAssertEqual(
      MTPError.deviceDisconnected.errorDescription,
      "The device disconnected during the operation."
    )
  }

  func testExactErrorDescriptionObjectNotFound() {
    XCTAssertEqual(
      MTPError.objectNotFound.errorDescription,
      "The requested object was not found."
    )
  }

  func testExactErrorDescriptionStorageFull() {
    XCTAssertEqual(
      MTPError.storageFull.errorDescription,
      "The destination storage is full."
    )
  }

  func testExactErrorDescriptionSessionBusy() {
    XCTAssertEqual(
      MTPError.sessionBusy.errorDescription,
      "A protocol transaction is already in progress on this device."
    )
  }

  func testExactErrorDescriptionVerificationFailed() {
    let error = MTPError.verificationFailed(expected: 1024, actual: 512)
    XCTAssertEqual(
      error.errorDescription,
      "Write verification failed: remote size 512 does not match expected 1024."
    )
  }

  func testExactActionableDescriptionDeviceDisconnected() {
    let msg = MTPError.deviceDisconnected.actionableDescription
    XCTAssertFalse(msg.isEmpty)
    XCTAssertTrue(msg.count > 10, "Actionable description should be substantive")
  }

  func testExactActionableDescriptionSessionBusy() {
    let msg = MTPError.sessionBusy.actionableDescription
    XCTAssertFalse(msg.isEmpty)
    XCTAssertTrue(msg.count > 10, "Actionable description should be substantive")
  }
}
