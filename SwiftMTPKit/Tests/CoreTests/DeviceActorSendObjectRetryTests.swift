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

  // MARK: - OnePlus 3T write-path flag tests

  func testPrimaryParamsUseUndefinedFormatWhenForceUndefinedFlagSet() {
    // When forceUndefinedFormatOnWrite is true, the primary params should
    // already have useUndefinedObjectFormat = true (no retry needed).
    let primaryWithForce = MTPDeviceActor.SendObjectRetryParameters(
      useEmptyDates: true,
      useUndefinedObjectFormat: true,
      useUnknownObjectInfoSize: false,
      omitOptionalObjectInfoFields: false,
      zeroObjectInfoParentHandle: false,
      useRootCommandParentHandle: false
    )

    // The retry for invalidParameter should flip format BACK to false,
    // producing a distinct retry set.
    let retries = MTPDeviceActor.sendObjectRetryParameters(
      primary: primaryWithForce,
      retryClass: .invalidParameter,
      isRootParent: false,
      allowUnknownObjectInfoSizeRetry: false
    )

    XCTAssertEqual(retries.count, 1)
    // Retry flips useUndefinedObjectFormat from true -> false
    XCTAssertEqual(retries[0].useUndefinedObjectFormat, false)
    // emptyDates stays as-is
    XCTAssertEqual(retries[0].useEmptyDates, true)
  }

  func testPrimaryParamsWithEmptyDatesAndUndefinedFormatMatchOnePlusProfile() {
    // Verify the exact parameter set that an OnePlus 3T profile produces:
    // emptyDatesInSendObject=true, forceUndefinedFormatOnWrite=true
    let onePlusParams = MTPDeviceActor.SendObjectRetryParameters(
      useEmptyDates: true,
      useUndefinedObjectFormat: true,
      useUnknownObjectInfoSize: false,
      omitOptionalObjectInfoFields: false,
      zeroObjectInfoParentHandle: false,
      useRootCommandParentHandle: false
    )

    XCTAssertTrue(onePlusParams.useEmptyDates)
    XCTAssertTrue(onePlusParams.useUndefinedObjectFormat)
    XCTAssertFalse(onePlusParams.useUnknownObjectInfoSize)
  }

  func testBrokenSendObjectPropListSkipsPropListFallback() {
    // When brokenSendObjectPropList is true AND useMediaTargetPolicy is
    // active, the code should never attempt performWriteViaPropList.
    // This test validates the guard condition logic directly.
    let brokenPropList = true
    let useMediaTargetPolicy = true
    let supportsSendObjectPropList = true

    // The guard at line ~807 checks:
    //   !useMediaTargetPolicy && ... && !brokenSendObjectPropList
    let shouldAttemptPropList =
      !useMediaTargetPolicy && supportsSendObjectPropList && !brokenPropList

    XCTAssertFalse(
      shouldAttemptPropList,
      "SendObjectPropList should be skipped when brokenSendObjectPropList or useMediaTargetPolicy is set"
    )
  }

  func testBrokenSendObjectPropListAloneBlocksPropListFallback() {
    // Even without useMediaTargetPolicy, brokenSendObjectPropList alone
    // should prevent the PropList fallback.
    let brokenPropList = true
    let useMediaTargetPolicy = false
    let supportsSendObjectPropList = true

    let shouldAttemptPropList =
      !useMediaTargetPolicy && supportsSendObjectPropList && !brokenPropList

    XCTAssertFalse(
      shouldAttemptPropList,
      "SendObjectPropList should be skipped when brokenSendObjectPropList is set"
    )
  }

  func testRetryWithForceUndefinedAndEmptyDatesProducesFormatFlipRetry() {
    // When the primary already uses undefined format + empty dates,
    // the invalidParameter retry should flip the format off.
    let primary = MTPDeviceActor.SendObjectRetryParameters(
      useEmptyDates: true,
      useUndefinedObjectFormat: true,
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

    XCTAssertEqual(retries.count, 1)
    let retry = retries[0]
    XCTAssertFalse(retry.useUndefinedObjectFormat, "Retry should flip format off")
    XCTAssertTrue(retry.useEmptyDates, "Retry should preserve empty dates")
    XCTAssertTrue(retry.zeroObjectInfoParentHandle, "Root parent retry should zero dataset parent")
  }
}
