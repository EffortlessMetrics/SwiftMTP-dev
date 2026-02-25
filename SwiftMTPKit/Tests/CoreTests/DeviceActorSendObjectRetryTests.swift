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

  func testSendObjectRetryParametersInvalidParameterRetriesWithFormatFlip() {
    let primary = MTPDeviceActor.SendObjectRetryParameters(
      useEmptyDates: false,
      useUndefinedObjectFormat: false,
      useUnknownObjectInfoSize: false,
      omitOptionalObjectInfoFields: false,
      zeroObjectInfoParentHandle: false,
      useRootCommandParentHandle: false
    )

    let retries = MTPDeviceActor.sendObjectRetryParameters(
      primary: primary,
      retryClass: .invalidParameter,
      isRootParent: false,
      allowUnknownObjectInfoSizeRetry: false
    )

    XCTAssertEqual(
      retries,
      [
        MTPDeviceActor.SendObjectRetryParameters(
          useEmptyDates: false,
          useUndefinedObjectFormat: true,
          useUnknownObjectInfoSize: false,
          omitOptionalObjectInfoFields: false,
          zeroObjectInfoParentHandle: false,
          useRootCommandParentHandle: false
        )
      ]
    )
  }

  func testSendObjectRetryParametersInvalidParameterRootRetryZeroesDatasetParent() {
    let primary = MTPDeviceActor.SendObjectRetryParameters(
      useEmptyDates: false,
      useUndefinedObjectFormat: false,
      useUnknownObjectInfoSize: false,
      omitOptionalObjectInfoFields: false,
      zeroObjectInfoParentHandle: false,
      useRootCommandParentHandle: false
    )

    let retries = MTPDeviceActor.sendObjectRetryParameters(
      primary: primary,
      retryClass: .invalidParameter,
      isRootParent: true,
      allowUnknownObjectInfoSizeRetry: false
    )

    XCTAssertEqual(
      retries,
      [
        MTPDeviceActor.SendObjectRetryParameters(
          useEmptyDates: false,
          useUndefinedObjectFormat: true,
          useUnknownObjectInfoSize: false,
          omitOptionalObjectInfoFields: false,
          zeroObjectInfoParentHandle: true,
          useRootCommandParentHandle: false
        )
      ]
    )
  }

  func testSendObjectRetryParametersUnknownSizeRetryIsQuirkGated() {
    let primary = MTPDeviceActor.SendObjectRetryParameters(
      useEmptyDates: false,
      useUndefinedObjectFormat: false,
      useUnknownObjectInfoSize: false,
      omitOptionalObjectInfoFields: false,
      zeroObjectInfoParentHandle: false,
      useRootCommandParentHandle: false
    )

    let retries = MTPDeviceActor.sendObjectRetryParameters(
      primary: primary,
      retryClass: .invalidParameter,
      isRootParent: false,
      allowUnknownObjectInfoSizeRetry: true
    )

    XCTAssertEqual(
      retries,
      [
        MTPDeviceActor.SendObjectRetryParameters(
          useEmptyDates: false,
          useUndefinedObjectFormat: true,
          useUnknownObjectInfoSize: false,
          omitOptionalObjectInfoFields: false,
          zeroObjectInfoParentHandle: false,
          useRootCommandParentHandle: false
        ),
        MTPDeviceActor.SendObjectRetryParameters(
          useEmptyDates: false,
          useUndefinedObjectFormat: true,
          useUnknownObjectInfoSize: true,
          omitOptionalObjectInfoFields: false,
          zeroObjectInfoParentHandle: false,
          useRootCommandParentHandle: false
        ),
      ]
    )
  }

  func testSendObjectRetryParametersForTransientTransportRetryOnceWithSameParams() {
    let primary = MTPDeviceActor.SendObjectRetryParameters(
      useEmptyDates: false,
      useUndefinedObjectFormat: false,
      useUnknownObjectInfoSize: false,
      omitOptionalObjectInfoFields: false,
      zeroObjectInfoParentHandle: false,
      useRootCommandParentHandle: false
    )

    let retries = MTPDeviceActor.sendObjectRetryParameters(
      primary: primary,
      retryClass: .transientTransport,
      isRootParent: false,
      allowUnknownObjectInfoSizeRetry: false
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
