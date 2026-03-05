// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import XCTest
@testable import SwiftMTPCore

final class DiagnosticFormatterTests: XCTestCase {

  // MARK: - MTPError diagnostics

  func testDiagnoseDeviceDisconnected() {
    let diag = DiagnosticFormatter.diagnose(MTPError.deviceDisconnected)
    XCTAssertTrue(diag.summary.contains("disconnected"))
    XCTAssertTrue(diag.suggestion.contains("Reconnect"))
    XCTAssertEqual(diag.relatedCommand, "swiftmtp probe")
  }

  func testDiagnosePermissionDenied() {
    let diag = DiagnosticFormatter.diagnose(MTPError.permissionDenied)
    XCTAssertTrue(diag.summary.contains("denied"))
    XCTAssertTrue(diag.suggestion.contains("Trust"))
    XCTAssertEqual(diag.relatedCommand, "swiftmtp health")
  }

  func testDiagnoseNotSupported() {
    let diag = DiagnosticFormatter.diagnose(MTPError.notSupported("GetObjectPropList"))
    XCTAssertTrue(diag.summary.contains("GetObjectPropList"))
    XCTAssertEqual(diag.relatedCommand, "swiftmtp info --device")
  }

  func testDiagnoseTimeout() {
    let diag = DiagnosticFormatter.diagnose(MTPError.timeout)
    XCTAssertTrue(diag.summary.contains("timed out"))
    XCTAssertTrue(diag.suggestion.contains("SWIFTMTP_IO_TIMEOUT_MS"))
    XCTAssertEqual(diag.relatedCommand, "swiftmtp probe")
  }

  func testDiagnoseBusy() {
    let diag = DiagnosticFormatter.diagnose(MTPError.busy)
    XCTAssertTrue(diag.summary.contains("busy"))
    XCTAssertTrue(diag.suggestion.contains("retry"))
  }

  func testDiagnoseStorageFull() {
    let diag = DiagnosticFormatter.diagnose(MTPError.storageFull)
    XCTAssertTrue(diag.summary.contains("full"))
    XCTAssertEqual(diag.relatedCommand, "swiftmtp storages")
  }

  func testDiagnoseReadOnly() {
    let diag = DiagnosticFormatter.diagnose(MTPError.readOnly)
    XCTAssertTrue(diag.summary.contains("read-only"))
    XCTAssertEqual(diag.relatedCommand, "swiftmtp storages")
  }

  func testDiagnoseObjectNotFound() {
    let diag = DiagnosticFormatter.diagnose(MTPError.objectNotFound)
    XCTAssertTrue(diag.summary.contains("not found"))
    XCTAssertTrue(diag.relatedCommand?.contains("ls") == true)
  }

  func testDiagnoseSessionBusy() {
    let diag = DiagnosticFormatter.diagnose(MTPError.sessionBusy)
    XCTAssertTrue(diag.summary.contains("transaction"))
    XCTAssertTrue(diag.suggestion.contains("Wait"))
  }

  func testDiagnoseVerificationFailed() {
    let diag = DiagnosticFormatter.diagnose(MTPError.verificationFailed(expected: 1000, actual: 500))
    XCTAssertTrue(diag.summary.contains("1000"))
    XCTAssertTrue(diag.summary.contains("500"))
  }

  func testDiagnosePreconditionFailed() {
    let diag = DiagnosticFormatter.diagnose(MTPError.preconditionFailed("No storage"))
    XCTAssertTrue(diag.summary.contains("No storage"))
  }

  // MARK: - Protocol error diagnostics

  func testDiagnoseProtocolUndefined() {
    let diag = DiagnosticFormatter.diagnose(MTPError.protocolError(code: 0x2001, message: nil))
    XCTAssertTrue(diag.summary.contains("0x2001"))
    XCTAssertEqual(diag.relatedCommand, "swiftmtp probe")
  }

  func testDiagnoseProtocolOperationNotSupported() {
    let diag = DiagnosticFormatter.diagnose(MTPError.protocolError(code: 0x2005, message: nil))
    XCTAssertTrue(diag.summary.contains("not supported"))
    XCTAssertEqual(diag.relatedCommand, "swiftmtp info --device")
  }

  func testDiagnoseProtocolInvalidParameter() {
    let diag = DiagnosticFormatter.diagnose(MTPError.protocolError(code: 0x201D, message: nil))
    XCTAssertTrue(diag.summary.contains("0x201D"))
    XCTAssertTrue(diag.suggestion.contains("quirk"))
    XCTAssertEqual(diag.relatedCommand, "swiftmtp quirks")
  }

  func testDiagnoseProtocolStorageFull() {
    let diag = DiagnosticFormatter.diagnose(MTPError.protocolError(code: 0x200C, message: nil))
    XCTAssertTrue(diag.summary.contains("full"))
    XCTAssertEqual(diag.relatedCommand, "swiftmtp storages")
  }

  func testDiagnoseProtocolSessionAlreadyOpen() {
    let diag = DiagnosticFormatter.diagnose(MTPError.protocolError(code: 0x201E, message: nil))
    XCTAssertTrue(diag.summary.contains("already open"))
    XCTAssertEqual(diag.relatedCommand, "swiftmtp probe")
  }

  func testDiagnoseProtocolUnknownCode() {
    let diag = DiagnosticFormatter.diagnose(MTPError.protocolError(code: 0xFFFF, message: nil))
    XCTAssertTrue(diag.summary.contains("Protocol error"))
  }

  // MARK: - Transport error diagnostics

  func testDiagnoseTransportNoDevice() {
    let diag = DiagnosticFormatter.diagnose(MTPError.transport(.noDevice))
    XCTAssertTrue(diag.summary.contains("No MTP"))
    XCTAssertTrue(diag.suggestion.contains("File Transfer"))
    XCTAssertEqual(diag.relatedCommand, "swiftmtp probe")
  }

  func testDiagnoseTransportTimeout() {
    let diag = DiagnosticFormatter.diagnose(MTPError.transport(.timeout))
    XCTAssertTrue(diag.summary.contains("timed out"))
  }

  func testDiagnoseTransportAccessDenied() {
    let diag = DiagnosticFormatter.diagnose(MTPError.transport(.accessDenied))
    XCTAssertTrue(diag.summary.contains("denied"))
    XCTAssertTrue(diag.cause.contains("Android File Transfer"))
    XCTAssertEqual(diag.relatedCommand, "swiftmtp diag")
  }

  func testDiagnoseTransportStall() {
    let diag = DiagnosticFormatter.diagnose(MTPError.transport(.stall))
    XCTAssertTrue(diag.summary.contains("stall"))
  }

  func testDiagnoseTransportTimeoutInPhase() {
    let diag = DiagnosticFormatter.diagnose(MTPError.transport(.timeoutInPhase(.bulkIn)))
    XCTAssertTrue(diag.summary.contains("bulk-in"))
  }

  func testDiagnoseTransportIO() {
    let diag = DiagnosticFormatter.diagnose(MTPError.transport(.io("pipe broken")))
    XCTAssertTrue(diag.summary.contains("pipe broken"))
  }

  func testDiagnoseTransportBusy() {
    let diag = DiagnosticFormatter.diagnose(MTPError.transport(.busy))
    XCTAssertTrue(diag.summary.contains("busy"))
  }

  // MARK: - Standalone TransportError

  func testDiagnoseStandaloneTransportError() {
    let diag = DiagnosticFormatter.diagnose(TransportError.noDevice)
    XCTAssertTrue(diag.summary.contains("No MTP"))
  }

  // MARK: - Unknown error fallback

  func testDiagnoseUnknownError() {
    struct CustomError: Error {}
    let diag = DiagnosticFormatter.diagnose(CustomError())
    XCTAssertTrue(diag.cause.contains("unexpected"))
  }

  // MARK: - Formatted output

  func testFormattedOutputNonVerbose() {
    let output = DiagnosticFormatter.format(MTPError.deviceDisconnected, verbose: false)
    XCTAssertTrue(output.contains("Error:"))
    XCTAssertTrue(output.contains("Cause:"))
    XCTAssertTrue(output.contains("Try:"))
    XCTAssertTrue(output.contains("Run:"))
    XCTAssertFalse(output.contains("Detail:"))
  }

  func testFormattedOutputVerbose() {
    let output = DiagnosticFormatter.format(MTPError.deviceDisconnected, verbose: true)
    XCTAssertTrue(output.contains("Error:"))
    XCTAssertTrue(output.contains("Detail:"))
    XCTAssertTrue(output.contains("Reason:"))
  }

  func testFormattedOutputNoRelatedCommand() {
    let output = DiagnosticFormatter.format(MTPError.busy, verbose: false)
    XCTAssertTrue(output.contains("Error:"))
    XCTAssertFalse(output.contains("Run:"))
  }

  // MARK: - Index (DBError) diagnostics

  func testDiagnoseIndexCorruption() {
    let diag = DiagnosticFormatter.diagnoseIndexDB("database disk image is malformed")
    XCTAssertTrue(diag.summary.contains("corrupted"))
    XCTAssertEqual(diag.relatedCommand, "swiftmtp index --rebuild")
  }

  func testDiagnoseIndexCorruptionAlt() {
    let diag = DiagnosticFormatter.diagnoseIndexDB("file is corrupt")
    XCTAssertTrue(diag.summary.contains("corrupted"))
  }

  func testDiagnoseIndexDiskFull() {
    let diag = DiagnosticFormatter.diagnoseIndexDB("database or disk is full")
    XCTAssertTrue(diag.summary.contains("Disk full"))
    XCTAssertTrue(diag.suggestion.contains("Free disk space"))
  }

  func testDiagnoseIndexDiskFullNoSpace() {
    let diag = DiagnosticFormatter.diagnoseIndexDB("no space left on device")
    XCTAssertTrue(diag.summary.contains("Disk full"))
  }

  func testDiagnoseIndexGeneric() {
    let diag = DiagnosticFormatter.diagnoseIndexDB("constraint violation")
    XCTAssertTrue(diag.summary.contains("Index database error"))
    XCTAssertTrue(diag.cause.contains("constraint violation"))
    XCTAssertEqual(diag.relatedCommand, "swiftmtp index --rebuild")
  }

  func testDiagnoseDBErrorViaTypeName() {
    // Local type matching cross-module DBError by type name.
    enum DBError: Error, CustomStringConvertible {
      case open(String)
      var description: String {
        switch self { case .open(let m): return m }
      }
    }
    let diag = DiagnosticFormatter.diagnose(DBError.open("database disk image is malformed"))
    XCTAssertTrue(diag.summary.contains("corrupted"))
    XCTAssertEqual(diag.relatedCommand, "swiftmtp index --rebuild")
  }

  // MARK: - XPC diagnostics

  func testDiagnoseXPCConnectionInvalidated() {
    let diag = DiagnosticFormatter.diagnoseXPC("XPC connection permanently invalidated")
    XCTAssertTrue(diag.summary.contains("disconnected"))
    XCTAssertTrue(diag.suggestion.contains("retry automatically"))
  }

  func testDiagnoseXPCQueueFull() {
    let diag = DiagnosticFormatter.diagnoseXPC("XPC operation queue full — service unreachable")
    XCTAssertTrue(diag.summary.contains("overloaded"))
    XCTAssertTrue(diag.suggestion.contains("Wait"))
  }

  func testDiagnoseXPCGeneric() {
    let diag = DiagnosticFormatter.diagnoseXPC("unknown XPC error")
    XCTAssertTrue(diag.summary.contains("System service error"))
    XCTAssertTrue(diag.suggestion.contains("restart"))
  }

  func testDiagnoseXPCErrorViaTypeName() {
    // Local type matching cross-module XPCConnectionError by type name.
    enum XPCConnectionError: Error, CustomStringConvertible {
      case connectionInvalidated
      var description: String { "XPC connection permanently invalidated" }
    }
    let diag = DiagnosticFormatter.diagnose(XPCConnectionError.connectionInvalidated)
    XCTAssertTrue(diag.summary.contains("disconnected"))
  }

  // MARK: - ErrorDiagnostic equatable

  func testErrorDiagnosticEquatable() {
    let d1 = ErrorDiagnostic(summary: "a", cause: "b", suggestion: "c", relatedCommand: "d")
    let d2 = ErrorDiagnostic(summary: "a", cause: "b", suggestion: "c", relatedCommand: "d")
    let d3 = ErrorDiagnostic(summary: "x", cause: "b", suggestion: "c")
    XCTAssertEqual(d1, d2)
    XCTAssertNotEqual(d1, d3)
  }
}
