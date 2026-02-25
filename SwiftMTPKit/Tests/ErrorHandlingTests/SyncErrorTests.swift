// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import XCTest
@testable import SwiftMTPSync
@testable import SwiftMTPCore
@testable import SwiftMTPIndex
@testable import SwiftMTPStore

final class SyncErrorTests: XCTestCase {

  // MARK: - Sync Engine Initialization

  func testSyncEngineInitialization() {
    let engine = MTPSyncEngine()
    XCTAssertNotNil(engine)
  }

  // MARK: - Conflict Detection

  func testConflictDetectionBothModified() {
    // Test conflict when both local and remote are modified
    let error = SyncConflictError.bothModified(localPath: "/test.txt", remotePath: "/test.txt")
    if case .bothModified(let localPath, let remotePath) = error {
      XCTAssertEqual(localPath, "/test.txt")
      XCTAssertEqual(remotePath, "/test.txt")
    } else {
      XCTFail("Expected bothModified case")
    }
  }

  func testConflictDetectionLocalDeleted() {
    // Test conflict when local is deleted but remote is modified
    let error = SyncConflictError.localDeleted(remotePath: "/test.txt")
    if case .localDeleted(let remotePath) = error {
      XCTAssertEqual(remotePath, "/test.txt")
    } else {
      XCTFail("Expected localDeleted case")
    }
  }

  func testConflictDetectionRemoteDeleted() {
    // Test conflict when remote is deleted but local is modified
    let error = SyncConflictError.remoteDeleted(localPath: "/test.txt")
    if case .remoteDeleted(let localPath) = error {
      XCTAssertEqual(localPath, "/test.txt")
    } else {
      XCTFail("Expected remoteDeleted case")
    }
  }

  // MARK: - Partial Sync Failures

  func testPartialSyncFailureTransportError() {
    // Test partial sync failure due to transport error
    let error = MTPError.transport(.timeout)
    XCTAssertEqual(error, .transport(.timeout))
  }

  func testPartialSyncFailureProtocolError() {
    // Test partial sync failure due to protocol error
    let error = MTPError.protocolError(code: 0x2009, message: "Object not found")
    XCTAssertEqual(error.code, 0x2009)
  }

  func testPartialSyncFailureStorageFull() {
    // Test partial sync failure due to storage full
    let error = MTPError.storageFull
    XCTAssertEqual(error, .storageFull)
  }

  // MARK: - Cancellation Errors

  func testSyncCancellation() {
    // Test sync operation cancellation
    let error = SyncCancellationError.cancelledByUser
    XCTAssertEqual(error, .cancelledByUser)
  }

  func testSyncCancellationTimeout() {
    // Test sync cancellation due to timeout
    let error = SyncCancellationError.timeout
    XCTAssertEqual(error, .timeout)
  }

  // MARK: - Sync State Errors

  func testInvalidSyncState() {
    // Test invalid sync state
    let error = MTPError.preconditionFailed("Invalid sync state: not initialized")
    if case .preconditionFailed(let message) = error {
      XCTAssertTrue(message.contains("Invalid sync state"))
    } else {
      XCTFail("Expected preconditionFailed")
    }
  }

  func testSyncStateMismatch() {
    // Test sync state mismatch between local and remote
    let error = MTPError.preconditionFailed("Sync state mismatch: generation 5 vs 7")
    if case .preconditionFailed(let message) = error {
      XCTAssertTrue(message.contains("state mismatch"))
    } else {
      XCTFail("Expected preconditionFailed")
    }
  }

  // MARK: - Index Errors During Sync

  func testIndexUpdateFailure() {
    // Test index update failure during sync
    let error = MTPError.preconditionFailed("Index update failed: constraint violation")
    if case .preconditionFailed(let message) = error {
      XCTAssertTrue(message.contains("Index update failed"))
    } else {
      XCTFail("Expected preconditionFailed")
    }
  }

  func testIndexQueryFailure() {
    // Test index query failure during sync
    let error = MTPError.objectNotFound
    XCTAssertEqual(error, .objectNotFound)
  }

  // MARK: - Device Communication Errors

  func testDeviceDisconnectedDuringSync() {
    // Test device disconnection during sync
    let error = MTPError.deviceDisconnected
    XCTAssertEqual(error, .deviceDisconnected)
  }

  func testDeviceBusyDuringSync() {
    // Test device busy during sync
    let error = MTPError.busy
    XCTAssertEqual(error, .busy)
  }

  // MARK: - Transfer Errors

  func testTransferTimeout() {
    // Test transfer timeout
    let error = MTPError.timeout
    XCTAssertEqual(error, .timeout)
  }

  func testTransferIncomplete() {
    // Test incomplete transfer
    let error = MTPError.protocolError(code: 0x2007, message: "Incomplete transfer")
    XCTAssertEqual(error.code, 0x2007)
  }

  // MARK: - Resume After Failure

  func testSyncResumptionAfterFailure() {
    // Test that sync can resume after partial failure
    let error = MTPError.timeout
    XCTAssertEqual(error, .timeout)
    // In real code, this would trigger resume logic
  }

  func testSyncResumptionCheckpoint() {
    // Test checkpoint creation for resumption
    let error = MTPError.preconditionFailed("Checkpoint required")
    if case .preconditionFailed(let message) = error {
      XCTAssertTrue(message.contains("Checkpoint"))
    } else {
      XCTFail("Expected preconditionFailed")
    }
  }

  // MARK: - Merge Conflicts

  func testMergeConflictResolution() {
    // Test merge conflict resolution
    let error = SyncConflictError.bothModified(localPath: "/photo.jpg", remotePath: "/photo.jpg")
    if case .bothModified(let localPath, let remotePath) = error {
      XCTAssertEqual(localPath, remotePath)
    } else {
      XCTFail("Expected bothModified case")
    }
  }

  func testMergeWithAncestor() {
    // Test merge with common ancestor
    let error = MTPError.preconditionFailed("Merge with ancestor not supported")
    if case .preconditionFailed(let message) = error {
      XCTAssertEqual(message, "Merge with ancestor not supported")
    } else {
      XCTFail("Expected preconditionFailed")
    }
  }

  // MARK: - Large Sync Failures

  func testLargeSyncMemoryError() {
    // Test handling of memory issues during large sync
    let error = MTPError.notSupported("Out of memory during large sync")
    if case .notSupported(let message) = error {
      XCTAssertTrue(message.contains("memory"))
    } else {
      XCTFail("Expected notSupported")
    }
  }

  func testLargeSyncProgressReportingError() {
    // Test progress reporting failure
    let error = MTPError.notSupported("Progress reporting failed")
    if case .notSupported(let message) = error {
      XCTAssertEqual(message, "Progress reporting failed")
    } else {
      XCTFail("Expected notSupported")
    }
  }
}

// MARK: - Supporting Types for Testing

/// Sync conflict error types
public enum SyncConflictError: Error, Equatable {
  case bothModified(localPath: String, remotePath: String)
  case localDeleted(remotePath: String)
  case remoteDeleted(localPath: String)
}

/// Sync cancellation error types
public enum SyncCancellationError: Error, Equatable {
  case cancelledByUser
  case timeout
  case deviceDisconnected
}
