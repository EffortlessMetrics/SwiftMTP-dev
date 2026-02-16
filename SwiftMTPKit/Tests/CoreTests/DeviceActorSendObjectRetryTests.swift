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

  func testSendObjectRetryParametersFollowDeterministicInvalidParameterMatrix() {
    let primary = MTPDeviceActor.SendObjectRetryParameters(
      forceWildcardStorage: false,
      useEmptyDates: false
    )

    let retries = MTPDeviceActor.sendObjectRetryParameters(
      primary: primary,
      retryClass: .invalidParameter
    )

    XCTAssertEqual(
      retries,
      [
        MTPDeviceActor.SendObjectRetryParameters(forceWildcardStorage: false, useEmptyDates: true),
        MTPDeviceActor.SendObjectRetryParameters(forceWildcardStorage: true, useEmptyDates: false),
        MTPDeviceActor.SendObjectRetryParameters(forceWildcardStorage: true, useEmptyDates: true),
      ]
    )
  }

  func testSendObjectRetryParametersDedupesWhenPrimaryAlreadyWildcard() {
    let primary = MTPDeviceActor.SendObjectRetryParameters(
      forceWildcardStorage: true,
      useEmptyDates: false
    )

    let retries = MTPDeviceActor.sendObjectRetryParameters(
      primary: primary,
      retryClass: .invalidParameter
    )

    XCTAssertEqual(
      retries,
      [
        MTPDeviceActor.SendObjectRetryParameters(forceWildcardStorage: true, useEmptyDates: true)
      ]
    )
  }

  func testTargetLadderFallbackOnlyForRootInvalidParameter() {
    XCTAssertTrue(
      MTPDeviceActor.shouldAttemptTargetLadderFallback(parent: nil, retryClass: .invalidParameter)
    )
    XCTAssertTrue(
      MTPDeviceActor.shouldAttemptTargetLadderFallback(parent: 0, retryClass: .invalidParameter)
    )
    XCTAssertFalse(
      MTPDeviceActor.shouldAttemptTargetLadderFallback(parent: 42, retryClass: .invalidParameter)
    )
    XCTAssertFalse(
      MTPDeviceActor.shouldAttemptTargetLadderFallback(parent: nil, retryClass: .transientTransport)
    )
  }
}
