// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import XCTest

@testable import SwiftMTPCore
@testable import SwiftMTPTestKit
@testable import SwiftMTPTransportLibUSB

/// Tests for USB transport error recovery, retry logic, and edge cases.
final class TransportRecoveryTests: XCTestCase {

  // MARK: - Helpers

  private func makeLink(
    config: VirtualDeviceConfig = .pixel7,
    schedule: FaultSchedule? = nil
  ) -> VirtualMTPLink {
    VirtualMTPLink(config: config, faultSchedule: schedule)
  }

  private func makeFaultLink(
    config: VirtualDeviceConfig = .pixel7,
    faults: [ScheduledFault]
  ) -> FaultInjectingLink {
    let inner = VirtualMTPLink(config: config)
    return FaultInjectingLink(wrapping: inner, schedule: FaultSchedule(faults))
  }

  // MARK: - 1. USB Timeout Recovery

  func testTimeoutOnOpenUSBThrowsTimeout() async throws {
    let link = makeFaultLink(faults: [.timeoutOnce(on: .openUSB)])
    do {
      try await link.openUSBIfNeeded()
      XCTFail("Expected timeout error")
    } catch {
      XCTAssertEqual(error as? TransportError, .timeout)
    }
  }

  func testTimeoutOnGetDeviceInfoThrowsTimeout() async throws {
    let link = makeFaultLink(faults: [.timeoutOnce(on: .getDeviceInfo)])
    do {
      _ = try await link.getDeviceInfo()
      XCTFail("Expected timeout error")
    } catch {
      XCTAssertEqual(error as? TransportError, .timeout)
    }
  }

  func testTimeoutOnGetStorageIDsRecovery() async throws {
    let schedule = FaultSchedule([.timeoutOnce(on: .getStorageIDs)])
    let inner = VirtualMTPLink(config: .pixel7)
    let link = FaultInjectingLink(wrapping: inner, schedule: schedule)

    // First call should fail with timeout
    do {
      _ = try await link.getStorageIDs()
      XCTFail("Expected timeout")
    } catch {
      XCTAssertEqual(error as? TransportError, .timeout)
    }

    // Fault consumed — second call should succeed
    let ids = try await link.getStorageIDs()
    XCTAssertFalse(ids.isEmpty)
  }

  func testRetryAfterTimeoutSucceeds() async throws {
    let schedule = FaultSchedule([
      ScheduledFault(trigger: .onOperation(.getStorageInfo), error: .timeout, repeatCount: 2)
    ])
    let inner = VirtualMTPLink(config: .pixel7)
    let link = FaultInjectingLink(wrapping: inner, schedule: schedule)
    let storageID = MTPStorageID(raw: 0x0001_0001)

    // Two calls should fail
    for _ in 0..<2 {
      do {
        _ = try await link.getStorageInfo(id: storageID)
        XCTFail("Expected timeout")
      } catch {
        XCTAssertEqual(error as? TransportError, .timeout)
      }
    }

    // Third call succeeds after faults are exhausted
    let info = try await link.getStorageInfo(id: storageID)
    XCTAssertEqual(info.id.raw, storageID.raw)
  }

  // MARK: - 2. Disconnection Detection and Cleanup

  func testDisconnectionOnOpenSession() async throws {
    let link = makeFaultLink(faults: [
      ScheduledFault(trigger: .onOperation(.openSession), error: .disconnected)
    ])
    do {
      try await link.openSession(id: 1)
      XCTFail("Expected noDevice error")
    } catch {
      XCTAssertEqual(error as? TransportError, .noDevice)
    }
  }

  func testDisconnectionOnGetObjectHandles() async throws {
    let link = makeFaultLink(faults: [
      ScheduledFault(trigger: .onOperation(.getObjectHandles), error: .disconnected)
    ])
    do {
      _ = try await link.getObjectHandles(
        storage: MTPStorageID(raw: 0x0001_0001), parent: nil)
      XCTFail("Expected noDevice error")
    } catch {
      XCTAssertEqual(error as? TransportError, .noDevice)
    }
  }

  func testDisconnectionDuringExecuteCommand() async throws {
    let link = makeFaultLink(faults: [
      ScheduledFault(trigger: .onOperation(.executeCommand), error: .disconnected)
    ])
    let cmd = PTPContainer(type: 1, code: 0x1001, txid: 1, params: [])
    do {
      _ = try await link.executeCommand(cmd)
      XCTFail("Expected noDevice error")
    } catch {
      XCTAssertEqual(error as? TransportError, .noDevice)
    }
  }

  func testCloseAfterDisconnectionDoesNotThrow() async throws {
    let inner = VirtualMTPLink(config: .pixel7)
    let link = FaultInjectingLink(
      wrapping: inner,
      schedule: FaultSchedule([
        ScheduledFault(trigger: .onOperation(.openSession), error: .disconnected)
      ]))

    do { try await link.openSession(id: 1) } catch {}

    // close() should not throw even after disconnection
    await link.close()
  }

  // MARK: - 3. Partial Transfer / Streaming Command Recovery

  func testStreamingCommandTimeoutThrows() async throws {
    let link = makeFaultLink(faults: [
      .timeoutOnce(on: .executeStreamingCommand)
    ])
    let cmd = PTPContainer(type: 1, code: 0x100D, txid: 1, params: [])
    do {
      _ = try await link.executeStreamingCommand(
        cmd, dataPhaseLength: 1024, dataInHandler: nil, dataOutHandler: nil)
      XCTFail("Expected timeout")
    } catch {
      XCTAssertEqual(error as? TransportError, .timeout)
    }
  }

  func testStreamingCommandRecoveryAfterFault() async throws {
    let schedule = FaultSchedule([.timeoutOnce(on: .executeStreamingCommand)])
    let inner = VirtualMTPLink(config: .pixel7)
    let link = FaultInjectingLink(wrapping: inner, schedule: schedule)
    let cmd = PTPContainer(type: 1, code: 0x1001, txid: 1, params: [])

    // First call fails
    do {
      _ = try await link.executeStreamingCommand(
        cmd, dataPhaseLength: nil, dataInHandler: nil, dataOutHandler: nil)
      XCTFail("Expected timeout")
    } catch {}

    // Second call succeeds
    let result = try await link.executeStreamingCommand(
      cmd, dataPhaseLength: nil, dataInHandler: nil, dataOutHandler: nil)
    XCTAssertTrue(result.isOK)
  }

  // MARK: - 4. Endpoint Stall / Pipe Error Recovery

  func testPipeStallOnExecuteCommand() async throws {
    let link = makeFaultLink(faults: [.pipeStall(on: .executeCommand)])
    let cmd = PTPContainer(type: 1, code: 0x1001, txid: 1, params: [])
    do {
      _ = try await link.executeCommand(cmd)
      XCTFail("Expected IO error for pipe stall")
    } catch {
      if case .io(let msg) = error as? TransportError {
        XCTAssertTrue(msg.contains("pipe stall"), "Expected pipe stall message, got: \(msg)")
      } else {
        XCTFail("Expected TransportError.io, got \(error)")
      }
    }
  }

  func testPipeStallOnGetObjectInfos() async throws {
    let link = makeFaultLink(faults: [.pipeStall(on: .getObjectInfos)])
    do {
      _ = try await link.getObjectInfos([1, 2])
      XCTFail("Expected IO error")
    } catch {
      if case .io(let msg) = error as? TransportError {
        XCTAssertTrue(msg.contains("pipe stall"))
      } else {
        XCTFail("Expected TransportError.io")
      }
    }
  }

  func testPipeStallRecoveryOnRetry() async throws {
    let schedule = FaultSchedule([.pipeStall(on: .getStorageIDs)])
    let inner = VirtualMTPLink(config: .pixel7)
    let link = FaultInjectingLink(wrapping: inner, schedule: schedule)

    // First call stalls
    do {
      _ = try await link.getStorageIDs()
      XCTFail("Expected stall")
    } catch {}

    // Retry succeeds after stall is cleared
    let ids = try await link.getStorageIDs()
    XCTAssertFalse(ids.isEmpty)
  }

  // MARK: - 5. Concurrent Transfer Cancellation

  func testConcurrentOperationsWithFaultIsolation() async throws {
    let schedule = FaultSchedule([
      ScheduledFault(trigger: .atCallIndex(1), error: .timeout)
    ])
    let inner = VirtualMTPLink(config: .pixel7)
    let link = FaultInjectingLink(wrapping: inner, schedule: schedule)

    // Call index 0 — succeeds
    let info = try await link.getDeviceInfo()
    XCTAssertEqual(info.manufacturer, "Google")

    // Call index 1 — faulted
    do {
      _ = try await link.getStorageIDs()
      XCTFail("Expected timeout at call index 1")
    } catch {
      XCTAssertEqual(error as? TransportError, .timeout)
    }

    // Call index 2 — succeeds, fault was one-shot
    let ids = try await link.getStorageIDs()
    XCTAssertFalse(ids.isEmpty)
  }

  func testParallelFaultedOperations() async throws {
    // Schedule faults on two different operations
    let schedule = FaultSchedule([
      .timeoutOnce(on: .getDeviceInfo),
      .pipeStall(on: .getStorageIDs),
    ])
    let inner = VirtualMTPLink(config: .pixel7)
    let link = FaultInjectingLink(wrapping: inner, schedule: schedule)

    // Both should fail with their respective errors
    await withTaskGroup(of: Void.self) { group in
      group.addTask {
        do {
          _ = try await link.getDeviceInfo()
        } catch {
          XCTAssertEqual(error as? TransportError, .timeout)
        }
      }
      group.addTask {
        do {
          _ = try await link.getStorageIDs()
        } catch {
          if case .io = error as? TransportError {
          } else {
            XCTAssertEqual(error as? TransportError, .timeout)
          }
        }
      }
    }
  }

  func testTaskCancellationDuringOperation() async throws {
    let config = VirtualDeviceConfig.pixel7
      .withLatency(.getDeviceInfo, duration: .seconds(10))
    let link = VirtualMTPLink(config: config)

    let task = Task {
      _ = try await link.getDeviceInfo()
    }

    // Cancel almost immediately
    try await Task.sleep(nanoseconds: 10_000_000)
    task.cancel()

    let result = await task.result
    switch result {
    case .success:
      break  // cancellation may not interrupt immediately
    case .failure(let error):
      XCTAssertTrue(error is CancellationError, "Expected CancellationError, got \(error)")
    }
  }

  // MARK: - 6. Transfer Size Edge Cases

  func testZeroBytePTPResponse() async throws {
    let link = makeLink()
    // executeCommand with no data phase should return OK
    let cmd = PTPContainer(type: 1, code: 0x1001, txid: 1, params: [])
    let result = try await link.executeCommand(cmd)
    XCTAssertTrue(result.isOK)
  }

  func testEmptyStorageDeviceHandles() async throws {
    let link = makeLink(config: .emptyDevice)
    try await link.openUSBIfNeeded()
    try await link.openSession(id: 1)

    let storageIDs = try await link.getStorageIDs()
    XCTAssertFalse(storageIDs.isEmpty, "Empty device should still have a storage")

    let handles = try await link.getObjectHandles(storage: storageIDs[0], parent: nil)
    XCTAssertTrue(handles.isEmpty, "Empty device should return no object handles")
  }

  func testGetObjectInfosWithEmptyHandleList() async throws {
    let link = makeLink()
    let infos = try await link.getObjectInfos([])
    XCTAssertTrue(infos.isEmpty)
  }

  func testGetObjectInfosWithNonexistentHandle() async throws {
    let link = makeLink()
    let infos = try await link.getObjectInfos([0xDEAD_BEEF])
    XCTAssertTrue(infos.isEmpty, "Nonexistent handle should return empty list")
  }

  func testLargeObjectSizeMetadata() async throws {
    let largeSize: UInt64 = 4 * 1024 * 1024 * 1024 + 1  // Just over 4GB
    let config = VirtualDeviceConfig.pixel7
      .withObject(
        VirtualObjectConfig(
          handle: 100,
          storage: MTPStorageID(raw: 0x0001_0001),
          parent: nil,
          name: "large_video.mp4",
          sizeBytes: largeSize,
          formatCode: 0x3009
        ))
    let link = makeLink(config: config)

    let infos = try await link.getObjectInfos([100])
    XCTAssertEqual(infos.count, 1)
    XCTAssertEqual(infos[0].sizeBytes, largeSize)
  }

  func testChunkBoundarySize() async throws {
    // Object size exactly at 2MB chunk boundary
    let chunkSize: UInt64 = 2 * 1024 * 1024
    let config = VirtualDeviceConfig.pixel7
      .withObject(
        VirtualObjectConfig(
          handle: 200,
          storage: MTPStorageID(raw: 0x0001_0001),
          parent: nil,
          name: "boundary.bin",
          sizeBytes: chunkSize,
          formatCode: 0x3000
        ))
    let link = makeLink(config: config)

    let infos = try await link.getObjectInfos([200])
    XCTAssertEqual(infos.count, 1)
    XCTAssertEqual(infos[0].sizeBytes, chunkSize)
  }

  func testJustOverChunkBoundarySize() async throws {
    // One byte over 2MB chunk boundary
    let size: UInt64 = 2 * 1024 * 1024 + 1
    let config = VirtualDeviceConfig.pixel7
      .withObject(
        VirtualObjectConfig(
          handle: 201,
          storage: MTPStorageID(raw: 0x0001_0001),
          parent: nil,
          name: "over_boundary.bin",
          sizeBytes: size,
          formatCode: 0x3000
        ))
    let link = makeLink(config: config)

    let infos = try await link.getObjectInfos([201])
    XCTAssertEqual(infos.count, 1)
    XCTAssertEqual(infos[0].sizeBytes, size)
  }

  // MARK: - 7. Busy Retry Logic

  func testBusyRetryExhaustsAndSucceeds() async throws {
    let schedule = FaultSchedule([.busyForRetries(3)])
    let inner = VirtualMTPLink(config: .pixel7)
    let link = FaultInjectingLink(wrapping: inner, schedule: schedule)
    let cmd = PTPContainer(type: 1, code: 0x1001, txid: 1, params: [])

    // Three calls should fail with busy
    for _ in 0..<3 {
      do {
        _ = try await link.executeCommand(cmd)
        XCTFail("Expected busy")
      } catch {
        XCTAssertEqual(error as? TransportError, .busy)
      }
    }

    // Fourth call succeeds
    let result = try await link.executeCommand(cmd)
    XCTAssertTrue(result.isOK)
  }

  func testBusyOnOpenSessionRetry() async throws {
    let schedule = FaultSchedule([
      ScheduledFault(trigger: .onOperation(.openSession), error: .busy, repeatCount: 1)
    ])
    let inner = VirtualMTPLink(config: .pixel7)
    let link = FaultInjectingLink(wrapping: inner, schedule: schedule)

    do {
      try await link.openSession(id: 1)
      XCTFail("Expected busy")
    } catch {
      XCTAssertEqual(error as? TransportError, .busy)
    }

    // Retry succeeds
    try await link.openSession(id: 1)
  }

  // MARK: - 8. Access Denied Error

  func testAccessDeniedOnOpenUSB() async throws {
    let link = makeFaultLink(faults: [
      ScheduledFault(trigger: .onOperation(.openUSB), error: .accessDenied)
    ])
    do {
      try await link.openUSBIfNeeded()
      XCTFail("Expected accessDenied")
    } catch {
      XCTAssertEqual(error as? TransportError, .accessDenied)
    }
  }

  // MARK: - 9. No-Progress Timeout Recovery Gate

  func testShouldRecoverNoProgressTimeout_ZeroSent() {
    XCTAssertTrue(MTPUSBLink.shouldRecoverNoProgressTimeout(rc: -7, sent: 0))
  }

  func testShouldRecoverNoProgressTimeout_PartialSent() {
    XCTAssertFalse(MTPUSBLink.shouldRecoverNoProgressTimeout(rc: -7, sent: 512))
  }

  func testShouldRecoverNoProgressTimeout_NonTimeoutCode() {
    XCTAssertFalse(MTPUSBLink.shouldRecoverNoProgressTimeout(rc: -1, sent: 0))
  }

  func testShouldRecoverNoProgressTimeout_NegativeSent() {
    XCTAssertFalse(MTPUSBLink.shouldRecoverNoProgressTimeout(rc: -7, sent: -1))
  }

  func testProbeShouldRecoverNoProgressTimeout_ZeroSent() {
    XCTAssertTrue(probeShouldRecoverNoProgressTimeout(rc: -7, sent: 0))
  }

  func testProbeShouldRecoverNoProgressTimeout_NonTimeout() {
    XCTAssertFalse(probeShouldRecoverNoProgressTimeout(rc: -3, sent: 0))
  }

  // MARK: - 10. Fault Schedule Management

  func testFaultScheduleClearRemovesAllFaults() async throws {
    let schedule = FaultSchedule([
      .timeoutOnce(on: .getDeviceInfo),
      .pipeStall(on: .getStorageIDs),
    ])
    let inner = VirtualMTPLink(config: .pixel7)
    let link = FaultInjectingLink(wrapping: inner, schedule: schedule)

    // Clear all faults — operations should succeed
    schedule.clear()

    let info = try await link.getDeviceInfo()
    XCTAssertEqual(info.manufacturer, "Google")

    let ids = try await link.getStorageIDs()
    XCTAssertFalse(ids.isEmpty)
  }

  func testDynamicFaultAddition() async throws {
    let schedule = FaultSchedule()
    let inner = VirtualMTPLink(config: .pixel7)
    let link = FaultInjectingLink(wrapping: inner, schedule: schedule)

    // First call succeeds — no faults
    let info = try await link.getDeviceInfo()
    XCTAssertEqual(info.model, "Pixel 7")

    // Add a fault dynamically
    link.scheduleFault(.timeoutOnce(on: .getDeviceInfo))

    // Next getDeviceInfo should fail
    do {
      _ = try await link.getDeviceInfo()
      XCTFail("Expected timeout after dynamic fault")
    } catch {
      XCTAssertEqual(error as? TransportError, .timeout)
    }

    // Fault consumed — subsequent call succeeds
    let info2 = try await link.getDeviceInfo()
    XCTAssertEqual(info2.model, "Pixel 7")
  }

  // MARK: - 11. MockTransport Error Scenarios

  func testMockTransportTimeoutOnOpen() async throws {
    let transport = MockTransport(deviceData: .failureTimeout)
    do {
      _ = try await transport.open(
        MockDeviceData.failureTimeout.deviceSummary, config: SwiftMTPConfig())
      XCTFail("Expected timeout")
    } catch {
      XCTAssertEqual(error as? TransportError, .timeout)
    }
  }

  func testMockTransportBusyOnOpen() async throws {
    let transport = MockTransport(deviceData: .failureBusy)
    do {
      _ = try await transport.open(
        MockDeviceData.failureBusy.deviceSummary, config: SwiftMTPConfig())
      XCTFail("Expected busy")
    } catch {
      XCTAssertEqual(error as? TransportError, .busy)
    }
  }

  func testMockTransportDisconnectedOnOpen() async throws {
    let transport = MockTransport(deviceData: .failureDisconnected)
    do {
      _ = try await transport.open(
        MockDeviceData.failureDisconnected.deviceSummary, config: SwiftMTPConfig())
      XCTFail("Expected disconnected")
    } catch {
      XCTAssertTrue(error is MTPError, "Expected MTPError.deviceDisconnected, got \(error)")
    }
  }

  func testMockTransportDeviceIDMismatchOnOpen() async throws {
    let transport = MockTransport(deviceData: .androidPixel7)
    let wrongSummary = MTPDeviceSummary(
      id: MTPDeviceID(raw: "ffff:ffff@0:0"),
      manufacturer: "Unknown",
      model: "Wrong"
    )
    do {
      _ = try await transport.open(wrongSummary, config: SwiftMTPConfig())
      XCTFail("Expected notSupported error")
    } catch {
      XCTAssertTrue(error is MTPError)
    }
  }

  // MARK: - 12. Delete and Move With Faults

  func testDeleteObjectWithIOFault() async throws {
    let link = makeFaultLink(faults: [
      ScheduledFault(trigger: .onOperation(.deleteObject), error: .io("write protected"))
    ])
    do {
      try await link.deleteObject(handle: 3)
      XCTFail("Expected IO error")
    } catch {
      if case .io(let msg) = error as? TransportError {
        XCTAssertTrue(msg.contains("write protected"))
      } else {
        XCTFail("Expected TransportError.io")
      }
    }
  }

  func testMoveObjectWithDisconnectionFault() async throws {
    let link = makeFaultLink(faults: [
      ScheduledFault(trigger: .onOperation(.moveObject), error: .disconnected)
    ])
    do {
      try await link.moveObject(
        handle: 3, to: MTPStorageID(raw: 0x0001_0001), parent: nil)
      XCTFail("Expected noDevice error")
    } catch {
      XCTAssertEqual(error as? TransportError, .noDevice)
    }
  }
}
