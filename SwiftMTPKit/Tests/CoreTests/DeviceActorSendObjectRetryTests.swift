// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import XCTest
@testable import SwiftMTPCore

final class DeviceActorSendObjectRetryTests: XCTestCase {
  func testRetryableSendObjectFailureReasonClassifiesInvalidStorageID() {
    let reason = MTPDeviceActor.retryableSendObjectFailureReason(
      for: MTPError.protocolError(code: 0x2008, message: "InvalidStorageID")
    )

    XCTAssertEqual(reason, "invalid-storage-id-0x2008")
  }

  func testSendObjectRetryClassClassifiesInvalidStorageIDAsInvalidParameter() {
    let retryClass = MTPDeviceActor.sendObjectRetryClass(for: "invalid-storage-id-0x2008")
    XCTAssertEqual(retryClass, .invalidParameter)
  }

  func testRetryableSendObjectFailureReasonClassifiesInvalidObjectHandle() {
    let reason = MTPDeviceActor.retryableSendObjectFailureReason(
      for: MTPError.objectNotFound
    )

    XCTAssertEqual(reason, "invalid-object-handle-0x2009")
  }

  func testSendObjectRetryClassClassifiesInvalidObjectHandle() {
    let retryClass = MTPDeviceActor.sendObjectRetryClass(for: "invalid-object-handle-0x2009")
    XCTAssertEqual(retryClass, .invalidObjectHandle)
  }

  func testRetryableSendObjectFailureReasonClassifiesSessionNotOpen() {
    let reason = MTPDeviceActor.retryableSendObjectFailureReason(
      for: MTPError.protocolError(code: 0x2003, message: "SessionNotOpen")
    )

    XCTAssertEqual(reason, "session-not-open-0x2003")
  }

  func testSendObjectRetryClassClassifiesSessionNotOpenAsTransient() {
    let retryClass = MTPDeviceActor.sendObjectRetryClass(for: "session-not-open-0x2003")
    XCTAssertEqual(retryClass, .transientTransport)
  }

  func testSendObjectRetryParametersFollowDeterministicInvalidParameterMatrix() {
    let primary = MTPDeviceActor.SendObjectRetryParameters(
      useEmptyDates: false,
      useUndefinedObjectFormat: false,
      useUnknownObjectInfoSize: false,
      omitOptionalObjectInfoFields: false,
      zeroObjectInfoParentHandle: false
    )

    let retries = MTPDeviceActor.sendObjectRetryParameters(
      primary: primary,
      retryClass: .invalidParameter
    )

    XCTAssertEqual(
      retries,
      [
        MTPDeviceActor.SendObjectRetryParameters(
          useEmptyDates: false,
          useUndefinedObjectFormat: true,
          useUnknownObjectInfoSize: false,
          omitOptionalObjectInfoFields: false,
          zeroObjectInfoParentHandle: false
        ),
        MTPDeviceActor.SendObjectRetryParameters(
          useEmptyDates: true,
          useUndefinedObjectFormat: true,
          useUnknownObjectInfoSize: false,
          omitOptionalObjectInfoFields: false,
          zeroObjectInfoParentHandle: false
        ),
        MTPDeviceActor.SendObjectRetryParameters(
          useEmptyDates: true,
          useUndefinedObjectFormat: true,
          useUnknownObjectInfoSize: true,
          omitOptionalObjectInfoFields: false,
          zeroObjectInfoParentHandle: false
        ),
        MTPDeviceActor.SendObjectRetryParameters(
          useEmptyDates: true,
          useUndefinedObjectFormat: true,
          useUnknownObjectInfoSize: true,
          omitOptionalObjectInfoFields: true,
          zeroObjectInfoParentHandle: false
        ),
        MTPDeviceActor.SendObjectRetryParameters(
          useEmptyDates: true,
          useUndefinedObjectFormat: true,
          useUnknownObjectInfoSize: true,
          omitOptionalObjectInfoFields: true,
          zeroObjectInfoParentHandle: true
        ),
      ]
    )
  }

  func testSendObjectRetryParametersDedupesWhenPrimaryAlreadyUsesMostConservativeSettings() {
    let primary = MTPDeviceActor.SendObjectRetryParameters(
      useEmptyDates: true,
      useUndefinedObjectFormat: true,
      useUnknownObjectInfoSize: true,
      omitOptionalObjectInfoFields: true,
      zeroObjectInfoParentHandle: true
    )

    let retries = MTPDeviceActor.sendObjectRetryParameters(
      primary: primary,
      retryClass: .invalidParameter
    )

    XCTAssertEqual(retries, [])
  }

  func testSendObjectRetryParametersKeepsUndefinedFormatRungWhenPrimaryUsesOnlyEmptyDates() {
    let primary = MTPDeviceActor.SendObjectRetryParameters(
      useEmptyDates: true,
      useUndefinedObjectFormat: false,
      useUnknownObjectInfoSize: false,
      omitOptionalObjectInfoFields: false,
      zeroObjectInfoParentHandle: false
    )

    let retries = MTPDeviceActor.sendObjectRetryParameters(
      primary: primary,
      retryClass: .invalidParameter
    )

    XCTAssertEqual(
      retries,
      [
        MTPDeviceActor.SendObjectRetryParameters(
          useEmptyDates: true,
          useUndefinedObjectFormat: true,
          useUnknownObjectInfoSize: false,
          omitOptionalObjectInfoFields: false,
          zeroObjectInfoParentHandle: false
        ),
        MTPDeviceActor.SendObjectRetryParameters(
          useEmptyDates: true,
          useUndefinedObjectFormat: true,
          useUnknownObjectInfoSize: true,
          omitOptionalObjectInfoFields: false,
          zeroObjectInfoParentHandle: false
        ),
        MTPDeviceActor.SendObjectRetryParameters(
          useEmptyDates: true,
          useUndefinedObjectFormat: true,
          useUnknownObjectInfoSize: true,
          omitOptionalObjectInfoFields: true,
          zeroObjectInfoParentHandle: false
        ),
        MTPDeviceActor.SendObjectRetryParameters(
          useEmptyDates: true,
          useUndefinedObjectFormat: true,
          useUnknownObjectInfoSize: true,
          omitOptionalObjectInfoFields: true,
          zeroObjectInfoParentHandle: true
        )
      ]
    )
  }

  func testSendObjectRetryParametersForTransientTransportRetryOnceWithSameParams() {
    let primary = MTPDeviceActor.SendObjectRetryParameters(
      useEmptyDates: false,
      useUndefinedObjectFormat: false,
      useUnknownObjectInfoSize: false,
      omitOptionalObjectInfoFields: false,
      zeroObjectInfoParentHandle: false
    )

    let retries = MTPDeviceActor.sendObjectRetryParameters(
      primary: primary,
      retryClass: .transientTransport
    )

    XCTAssertEqual(retries, [primary])
  }

  func testTargetLadderFallbackPolicy() {
    XCTAssertTrue(
      MTPDeviceActor.shouldAttemptTargetLadderFallback(parent: nil, retryClass: .invalidParameter)
    )
    XCTAssertTrue(
      MTPDeviceActor.shouldAttemptTargetLadderFallback(parent: 0, retryClass: .invalidParameter)
    )
    XCTAssertTrue(
      MTPDeviceActor.shouldAttemptTargetLadderFallback(parent: 42, retryClass: .invalidParameter)
    )
    XCTAssertFalse(
      MTPDeviceActor.shouldAttemptTargetLadderFallback(parent: nil, retryClass: .transientTransport)
    )
    XCTAssertTrue(
      MTPDeviceActor.shouldAttemptTargetLadderFallback(
        parent: 42,
        retryClass: .invalidObjectHandle
      )
    )
    XCTAssertFalse(
      MTPDeviceActor.shouldAttemptTargetLadderFallback(
        parent: nil,
        retryClass: .invalidObjectHandle
      )
    )
  }
}
