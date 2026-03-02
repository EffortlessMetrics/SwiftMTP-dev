// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import XCTest
@testable import SwiftMTPCore
@testable import SwiftMTPTestKit

// MARK: - Error Recovery Scenario Tests

/// End-to-end scenarios exercising fault injection, error handling, retry,
/// and recovery patterns. Uses FaultInjectingLink and VirtualMTPDevice.
final class ErrorRecoveryScenarioTests: XCTestCase {

  // MARK: - Helpers

  private func tempDir() throws -> URL {
    try TestUtilities.createTempDirectory(prefix: "scenario-error-recovery")
  }

  // MARK: - 1. Timeout on Listing → Retry → Success

  func testTimeoutDuringListingRetrySuccess() async throws {
    let inner = VirtualMTPLink(config: .pixel7)
    let schedule = FaultSchedule([.timeoutOnce(on: .getObjectHandles)])
    let faultyLink = FaultInjectingLink(wrapping: inner, schedule: schedule)

    // First call should timeout
    do {
      _ = try await faultyLink.getObjectHandles(
        storage: MTPStorageID(raw: 0x0001_0001), parent: nil)
      XCTFail("Expected timeout error")
    } catch {
      // Expected: timeout consumed
    }

    // Second call should succeed (fault consumed)
    let handles = try await faultyLink.getObjectHandles(
      storage: MTPStorageID(raw: 0x0001_0001), parent: nil)
    XCTAssertFalse(handles.isEmpty, "Retry should succeed after timeout consumed")
  }

  // MARK: - 2. Pipe Stall During Storage List → Recovery

  func testPipeStallDuringStorageListRecovery() async throws {
    let inner = VirtualMTPLink(config: .pixel7)
    let schedule = FaultSchedule([.pipeStall(on: .getStorageIDs)])
    let faultyLink = FaultInjectingLink(wrapping: inner, schedule: schedule)

    // First call stalls
    do {
      _ = try await faultyLink.getStorageIDs()
      XCTFail("Expected pipe stall")
    } catch {
      // Expected
    }

    // Recovery: second call succeeds
    let ids = try await faultyLink.getStorageIDs()
    XCTAssertFalse(ids.isEmpty)
  }

  // MARK: - 3. Device Busy → Wait → Retry

  func testDeviceBusyWaitRetry() async throws {
    let inner = VirtualMTPLink(config: .pixel7)
    let schedule = FaultSchedule([.busyForRetries(3)])
    let faultyLink = FaultInjectingLink(wrapping: inner, schedule: schedule)

    var failCount = 0
    var succeeded = false

    // busyForRetries triggers on executeCommand
    for _ in 0..<5 {
      do {
        _ = try await faultyLink.executeCommand(
          PTPContainer(type: 1, code: 0x1001, txid: 0, params: []))
        succeeded = true
        break
      } catch {
        failCount += 1
      }
    }

    XCTAssertEqual(failCount, 3, "Should fail exactly 3 times before success")
    XCTAssertTrue(succeeded)
  }

  // MARK: - 4. Protocol Error on GetDeviceInfo → Fallback

  func testProtocolErrorOnGetDeviceInfoFallback() async throws {
    let inner = VirtualMTPLink(config: .pixel7)
    let schedule = FaultSchedule([.timeoutOnce(on: .getDeviceInfo)])
    let faultyLink = FaultInjectingLink(wrapping: inner, schedule: schedule)

    // First attempt fails
    do {
      _ = try await faultyLink.getDeviceInfo()
      XCTFail("Expected error on first call")
    } catch {
      // Expected
    }

    // Retry succeeds
    let info = try await faultyLink.getDeviceInfo()
    XCTAssertEqual(info.manufacturer, "Google")
    XCTAssertEqual(info.model, "Pixel 7")
  }

  // MARK: - 5. Multiple Consecutive Errors Tracking

  func testMultipleConsecutiveErrorsTracking() async throws {
    let inner = VirtualMTPLink(config: .pixel7)
    let schedule = FaultSchedule([.busyForRetries(5)])
    let faultyLink = FaultInjectingLink(wrapping: inner, schedule: schedule)

    var errorCount = 0

    // busyForRetries triggers on executeCommand
    for _ in 0..<10 {
      do {
        _ = try await faultyLink.executeCommand(
          PTPContainer(type: 1, code: 0x1001, txid: 0, params: []))
      } catch {
        errorCount += 1
      }
    }

    XCTAssertEqual(errorCount, 5, "Exactly 5 errors should fire")
  }

  // MARK: - 6. Pipe Stall During GetObjectInfo → Recovery

  func testPipeStallDuringGetObjectInfoRecovery() async throws {
    let inner = VirtualMTPLink(config: .pixel7)
    let schedule = FaultSchedule([.pipeStall(on: .getObjectInfos)])
    let faultyLink = FaultInjectingLink(wrapping: inner, schedule: schedule)

    // First call stalls
    do {
      _ = try await faultyLink.getObjectInfos([3])
      XCTFail("Expected stall")
    } catch {
      // Expected
    }

    // Retry succeeds
    let infos = try await faultyLink.getObjectInfos([3])
    XCTAssertFalse(infos.isEmpty)
    XCTAssertEqual(infos.first?.name, "IMG_20250101_120000.jpg")
  }

  // MARK: - 7. Timeout on Delete → Retry

  func testTimeoutOnDeleteRetry() async throws {
    let inner = VirtualMTPLink(config: .pixel7)
    let schedule = FaultSchedule([.timeoutOnce(on: .deleteObject)])
    let faultyLink = FaultInjectingLink(wrapping: inner, schedule: schedule)

    // First delete attempt times out
    do {
      try await faultyLink.deleteObject(handle: 3)
      XCTFail("Expected timeout")
    } catch {
      // Expected: timeout was consumed
    }

    // Retry succeeds — fault is consumed, delete goes through
    try await faultyLink.deleteObject(handle: 3)
    // No crash, no error — the retry pattern works
  }

  // MARK: - 8. Stall on Move Object → Recovery

  func testStallOnMoveObjectRecovery() async throws {
    let inner = VirtualMTPLink(config: .pixel7)
    let schedule = FaultSchedule([.pipeStall(on: .moveObject)])
    let faultyLink = FaultInjectingLink(wrapping: inner, schedule: schedule)

    // First move attempt stalls
    do {
      try await faultyLink.moveObject(
        handle: 3, to: MTPStorageID(raw: 0x0001_0001), parent: 1)
      XCTFail("Expected stall")
    } catch {
      // Expected
    }

    // Retry succeeds
    try await faultyLink.moveObject(
      handle: 3, to: MTPStorageID(raw: 0x0001_0001), parent: 1)
  }

  // MARK: - 9. FallbackLadder All Rungs Fail

  func testFallbackLadderAllRungsFail() async throws {
    let rungs: [FallbackRung<String>] = [
      FallbackRung(name: "strategy-A") { throw MTPError.timeout },
      FallbackRung(name: "strategy-B") { throw MTPError.busy },
      FallbackRung(name: "strategy-C") { throw MTPError.deviceDisconnected },
    ]

    do {
      _ = try await FallbackLadder.execute(rungs)
      XCTFail("Should have thrown FallbackAllFailedError")
    } catch let error as FallbackAllFailedError {
      XCTAssertEqual(error.attempts.count, 3)
      XCTAssertTrue(error.attempts.allSatisfy { !$0.succeeded })
      XCTAssertTrue(error.description.contains("strategy-A"))
      XCTAssertTrue(error.description.contains("strategy-B"))
      XCTAssertTrue(error.description.contains("strategy-C"))
    }
  }

  // MARK: - 10. FallbackLadder First Fails, Second Succeeds

  func testFallbackLadderFirstFailsSecondSucceeds() async throws {
    let rungs: [FallbackRung<String>] = [
      FallbackRung(name: "primary") { throw MTPError.timeout },
      FallbackRung(name: "fallback") { return "success" },
    ]

    let result = try await FallbackLadder.execute(rungs)
    XCTAssertEqual(result.value, "success")
  }

  // MARK: - 11. FallbackLadder First Succeeds

  func testFallbackLadderFirstSucceeds() async throws {
    let rungs: [FallbackRung<String>] = [
      FallbackRung(name: "primary") { return "quick" },
      FallbackRung(name: "fallback") { return "slow" },
    ]

    let result = try await FallbackLadder.execute(rungs)
    XCTAssertEqual(result.value, "quick")
    XCTAssertEqual(result.winningRung, "primary",
                   "First rung should win when it succeeds")
  }

  // MARK: - 12. VirtualMTPDevice Delete Non-Existent Returns Error

  func testDeleteNonExistentObjectError() async throws {
    let device = VirtualMTPDevice(config: .pixel7)

    do {
      try await device.delete(9999, recursive: false)
      XCTFail("Expected objectNotFound")
    } catch let error as MTPError {
      XCTAssertEqual(error, .objectNotFound)
    }
  }

  // MARK: - 13. GetInfo for Non-Existent Handle

  func testGetInfoForNonExistentHandle() async throws {
    let device = VirtualMTPDevice(config: .pixel7)

    do {
      _ = try await device.getInfo(handle: 12345)
      XCTFail("Expected objectNotFound")
    } catch let error as MTPError {
      XCTAssertEqual(error, .objectNotFound)
    }
  }

  // MARK: - 14. Read Non-Existent Handle

  func testReadNonExistentHandle() async throws {
    let device = VirtualMTPDevice(config: .pixel7)

    let dir = try tempDir()
    defer { try? TestUtilities.cleanupTempDirectory(dir) }
    let outURL = dir.appendingPathComponent("nonexistent.dat")

    do {
      _ = try await device.read(handle: 9999, range: nil, to: outURL)
      XCTFail("Expected objectNotFound error")
    } catch {
      // Expected: objectNotFound or similar
    }
  }

  // MARK: - 15. Rename Non-Existent Handle

  func testRenameNonExistentHandle() async throws {
    let device = VirtualMTPDevice(config: .pixel7)

    do {
      try await device.rename(9999, to: "renamed.txt")
      XCTFail("Expected objectNotFound")
    } catch let error as MTPError {
      XCTAssertEqual(error, .objectNotFound)
    }
  }

  // MARK: - 16. Move Non-Existent Handle

  func testMoveNonExistentHandle() async throws {
    let device = VirtualMTPDevice(config: .pixel7)

    do {
      try await device.move(9999, to: 1)
      XCTFail("Expected objectNotFound")
    } catch let error as MTPError {
      XCTAssertEqual(error, .objectNotFound)
    }
  }

  // MARK: - 17. Error Recovery Across Multiple Fault Types

  func testErrorRecoveryAcrossMultipleFaultTypes() async throws {
    let inner = VirtualMTPLink(config: .pixel7)
    let schedule = FaultSchedule([
      .pipeStall(on: .getStorageIDs),
      .timeoutOnce(on: .getObjectHandles),
      .busyForRetries(1),
    ])
    let faultyLink = FaultInjectingLink(wrapping: inner, schedule: schedule)

    // 1) Stall on getStorageIDs
    do {
      _ = try await faultyLink.getStorageIDs()
      XCTFail("Expected stall")
    } catch {}

    // Recovery
    let ids = try await faultyLink.getStorageIDs()
    XCTAssertFalse(ids.isEmpty)

    // 2) Timeout on getObjectHandles
    do {
      _ = try await faultyLink.getObjectHandles(
        storage: MTPStorageID(raw: 0x0001_0001), parent: nil)
      XCTFail("Expected timeout")
    } catch {}

    // Recovery
    let handles = try await faultyLink.getObjectHandles(
      storage: MTPStorageID(raw: 0x0001_0001), parent: nil)
    XCTAssertFalse(handles.isEmpty)

    // 3) Busy on executeCommand
    do {
      _ = try await faultyLink.executeCommand(
        PTPContainer(type: 1, code: 0x1001, txid: 0, params: []))
    } catch {
      // Expected: busy
    }

    // Recovery
    _ = try await faultyLink.executeCommand(
      PTPContainer(type: 1, code: 0x1001, txid: 0, params: []))
  }

  // MARK: - 18. Retry Loop Pattern with Exponential Backoff Simulation

  func testRetryLoopWithExponentialBackoff() async throws {
    let inner = VirtualMTPLink(config: .pixel7)
    let schedule = FaultSchedule([.busyForRetries(4)])
    let faultyLink = FaultInjectingLink(wrapping: inner, schedule: schedule)

    var retryCount = 0
    let maxRetries = 8
    var succeeded = false

    // busyForRetries triggers on executeCommand
    for attempt in 0..<maxRetries {
      do {
        _ = try await faultyLink.executeCommand(
          PTPContainer(type: 1, code: 0x1001, txid: 0, params: []))
        succeeded = true
        break
      } catch {
        retryCount += 1
        // Simulated backoff: 1ms, 2ms, 4ms, 8ms...
        let backoffNs = UInt64(1_000_000 * (1 << min(attempt, 5)))
        try await Task.sleep(nanoseconds: backoffNs)
      }
    }

    XCTAssertEqual(retryCount, 4, "Should retry exactly 4 times")
    XCTAssertTrue(succeeded)
  }

  // MARK: - 19. FaultInjectingLink Multiple Stalls on Different Operations

  func testMultipleStallsOnDifferentOperations() async throws {
    let inner = VirtualMTPLink(config: .pixel7)
    let schedule = FaultSchedule([
      .pipeStall(on: .getStorageIDs),
      .pipeStall(on: .getDeviceInfo),
      .pipeStall(on: .getObjectHandles),
    ])
    let faultyLink = FaultInjectingLink(wrapping: inner, schedule: schedule)

    // Each operation fails once, then succeeds
    for operation in ["getStorageIDs", "getDeviceInfo", "getObjectHandles"] {
      switch operation {
      case "getStorageIDs":
        do { _ = try await faultyLink.getStorageIDs() } catch {}
        let result = try await faultyLink.getStorageIDs()
        XCTAssertFalse(result.isEmpty, "\(operation) retry should succeed")

      case "getDeviceInfo":
        do { _ = try await faultyLink.getDeviceInfo() } catch {}
        let result = try await faultyLink.getDeviceInfo()
        XCTAssertEqual(result.model, "Pixel 7")

      case "getObjectHandles":
        do {
          _ = try await faultyLink.getObjectHandles(
            storage: MTPStorageID(raw: 0x0001_0001), parent: nil)
        } catch {}
        let result = try await faultyLink.getObjectHandles(
          storage: MTPStorageID(raw: 0x0001_0001), parent: nil)
        XCTAssertFalse(result.isEmpty)

      default: break
      }
    }
  }

  // MARK: - 20. Stall on Session Open → Recovery

  func testStallOnSessionOpenRecovery() async throws {
    let inner = VirtualMTPLink(config: .pixel7)
    let schedule = FaultSchedule([.pipeStall(on: .openSession)])
    let faultyLink = FaultInjectingLink(wrapping: inner, schedule: schedule)

    // First open stalls
    do {
      try await faultyLink.openSession(id: 1)
      XCTFail("Expected stall")
    } catch {
      // Expected
    }

    // Recovery: second attempt succeeds
    try await faultyLink.openSession(id: 1)
  }

  // MARK: - 21. Stall on Close Session → Recovery

  func testStallOnCloseSessionRecovery() async throws {
    let inner = VirtualMTPLink(config: .pixel7)
    try await inner.openSession(id: 1)

    let schedule = FaultSchedule([.pipeStall(on: .closeSession)])
    let faultyLink = FaultInjectingLink(wrapping: inner, schedule: schedule)

    // First close stalls
    do {
      try await faultyLink.closeSession()
      XCTFail("Expected stall")
    } catch {
      // Expected
    }

    // Recovery
    try await faultyLink.closeSession()
  }

  // MARK: - 22. Timeout on GetStorageInfo → Recovery

  func testTimeoutOnGetStorageInfoRecovery() async throws {
    let inner = VirtualMTPLink(config: .pixel7)
    let schedule = FaultSchedule([.timeoutOnce(on: .getStorageInfo)])
    let faultyLink = FaultInjectingLink(wrapping: inner, schedule: schedule)

    let storageId = MTPStorageID(raw: 0x0001_0001)

    // First call times out
    do {
      _ = try await faultyLink.getStorageInfo(id: storageId)
      XCTFail("Expected timeout")
    } catch {
      // Expected
    }

    // Retry succeeds
    let info = try await faultyLink.getStorageInfo(id: storageId)
    XCTAssertGreaterThan(info.capacityBytes, 0)
  }

  // MARK: - 23. FallbackLadder Single Rung Failure

  func testFallbackLadderSingleRungFailure() async throws {
    let rungs: [FallbackRung<Int>] = [
      FallbackRung(name: "only-option") { throw MTPError.deviceDisconnected },
    ]

    do {
      _ = try await FallbackLadder.execute(rungs)
      XCTFail("Should have thrown")
    } catch let error as FallbackAllFailedError {
      XCTAssertEqual(error.attempts.count, 1)
      XCTAssertEqual(error.attempts[0].name, "only-option")
    }
  }

  // MARK: - 24. Error After Successful Operations

  func testErrorAfterSuccessfulOperations() async throws {
    let inner = VirtualMTPLink(config: .pixel7)
    let faultyLink = FaultInjectingLink(wrapping: inner, schedule: FaultSchedule([]))

    // Multiple successful operations first
    let ids = try await faultyLink.getStorageIDs()
    XCTAssertFalse(ids.isEmpty)

    let info = try await faultyLink.getDeviceInfo()
    XCTAssertEqual(info.model, "Pixel 7")

    // Now schedule a fault dynamically
    faultyLink.scheduleFault(.pipeStall(on: .getObjectHandles))

    // This should fail
    do {
      _ = try await faultyLink.getObjectHandles(
        storage: MTPStorageID(raw: 0x0001_0001), parent: nil)
      XCTFail("Expected stall after dynamic fault injection")
    } catch {
      // Expected
    }

    // Recovery
    let handles = try await faultyLink.getObjectHandles(
      storage: MTPStorageID(raw: 0x0001_0001), parent: nil)
    XCTAssertFalse(handles.isEmpty)
  }

  // MARK: - 25. FallbackLadder with Different Error Types

  func testFallbackLadderWithDifferentErrorTypes() async throws {
    let rungs: [FallbackRung<String>] = [
      FallbackRung(name: "timeout-strategy") { throw MTPError.timeout },
      FallbackRung(name: "busy-strategy") { throw MTPError.busy },
      FallbackRung(name: "working-strategy") { return "recovered" },
    ]

    let result = try await FallbackLadder.execute(rungs)
    XCTAssertEqual(result.value, "recovered")
  }

  // MARK: - 26. Device Operations on Empty Device Error Handling

  func testEmptyDeviceErrorHandling() async throws {
    let device = VirtualMTPDevice(config: .emptyDevice)

    // All basic operations should succeed even on empty device
    let info = try await device.info
    XCTAssertEqual(info.model, "Empty Device")

    let storages = try await device.storages()
    XCTAssertEqual(storages.count, 1)

    // Non-existent handle operations should fail cleanly
    do {
      _ = try await device.getInfo(handle: 1)
      XCTFail("Expected objectNotFound on empty device")
    } catch let error as MTPError {
      XCTAssertEqual(error, .objectNotFound)
    }

    do {
      try await device.delete(1, recursive: false)
      XCTFail("Expected objectNotFound on empty device")
    } catch let error as MTPError {
      XCTAssertEqual(error, .objectNotFound)
    }
  }

  // MARK: - 27. Busy on Execute Command → Recovery After N Retries

  func testBusyOnExecuteCommandRecoveryAfterNRetries() async throws {
    let inner = VirtualMTPLink(config: .samsungGalaxy)
    let schedule = FaultSchedule([.busyForRetries(3)])
    let faultyLink = FaultInjectingLink(wrapping: inner, schedule: schedule)

    var attempts = 0
    var succeeded = false

    for _ in 0..<10 {
      attempts += 1
      do {
        _ = try await faultyLink.executeCommand(
          PTPContainer(type: 1, code: 0x1001, txid: 0, params: []))
        succeeded = true
        break
      } catch {
        continue
      }
    }

    XCTAssertTrue(succeeded, "Should eventually succeed")
    XCTAssertEqual(attempts, 4, "Should succeed on 4th attempt (3 failures + 1 success)")
  }

  // MARK: - 28. Concurrent Error Recovery on Same Link

  func testConcurrentErrorRecoveryOnSameLink() async throws {
    let inner = VirtualMTPLink(config: .pixel7)
    let schedule = FaultSchedule([.busyForRetries(2)])
    let faultyLink = FaultInjectingLink(wrapping: inner, schedule: schedule)

    // Multiple concurrent callers hitting the same fault (busy on executeCommand)
    let results = try await withThrowingTaskGroup(
      of: Bool.self
    ) { group -> [Bool] in
      for _ in 0..<5 {
        group.addTask {
          var success = false
          for _ in 0..<5 {
            do {
              _ = try await faultyLink.executeCommand(
                PTPContainer(type: 1, code: 0x1001, txid: 0, params: []))
              success = true
              break
            } catch {
              continue
            }
          }
          return success
        }
      }
      var collected: [Bool] = []
      for try await r in group { collected.append(r) }
      return collected
    }

    // At least some should succeed (busy faults are limited to 2)
    XCTAssertTrue(results.contains(true), "At least some concurrent calls should succeed")
  }

  // MARK: - 29. Schedule Clear and Re-Fault

  func testScheduleClearAndReFault() async throws {
    let inner = VirtualMTPLink(config: .pixel7)
    let schedule = FaultSchedule([.pipeStall(on: .getStorageIDs)])
    let faultyLink = FaultInjectingLink(wrapping: inner, schedule: schedule)

    // First: stall
    do {
      _ = try await faultyLink.getStorageIDs()
      XCTFail("Expected stall")
    } catch {}

    // Clear schedule
    schedule.clear()

    // Should work now
    let ids = try await faultyLink.getStorageIDs()
    XCTAssertFalse(ids.isEmpty)

    // Add new fault
    schedule.add(.timeoutOnce(on: .getDeviceInfo))

    // New fault fires
    do {
      _ = try await faultyLink.getDeviceInfo()
      XCTFail("Expected timeout after re-fault")
    } catch {}

    // Cleared again
    let info = try await faultyLink.getDeviceInfo()
    XCTAssertEqual(info.model, "Pixel 7")
  }

  // MARK: - 30. VirtualMTPDevice Survives After Error Operations

  func testDeviceSurvivesAfterErrorOperations() async throws {
    let device = VirtualMTPDevice(config: .pixel7)

    // Trigger various errors
    do { try await device.delete(9999, recursive: false) } catch {}
    do { _ = try await device.getInfo(handle: 9999) } catch {}
    do { try await device.rename(9999, to: "x.txt") } catch {}
    do { try await device.move(9999, to: 1) } catch {}

    // Device should still be fully functional
    let storages = try await device.storages()
    XCTAssertFalse(storages.isEmpty)

    let info = try await device.info
    XCTAssertEqual(info.model, "Pixel 7")

    let dir = try tempDir()
    defer { try? TestUtilities.cleanupTempDirectory(dir) }
    let outURL = dir.appendingPathComponent("after_errors.jpg")
    let progress = try await device.read(handle: 3, range: nil, to: outURL)
    XCTAssertGreaterThan(progress.completedUnitCount, 0)
  }
}
