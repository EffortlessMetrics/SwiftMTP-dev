// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import XCTest
@testable import SwiftMTPCore
@testable import SwiftMTPTestKit

/// Tests for FallbackAllFailedError surfacing — ensures that when all fallback
/// rungs fail the combined diagnostic error is propagated with full context.
final class FallbackAllFailedErrorTests: XCTestCase {

  // MARK: - Structure

  func testFallbackAllFailedCarriesAttemptCount() async {
    let rungs: [FallbackRung<Int>] = [
      FallbackRung(name: "rung1") { throw MTPError.timeout },
      FallbackRung(name: "rung2") { throw MTPError.busy },
    ]
    do {
      _ = try await FallbackLadder.execute(rungs)
      XCTFail("Expected FallbackAllFailedError")
    } catch let err as FallbackAllFailedError {
      XCTAssertEqual(err.attempts.count, 2)
    } catch {
      XCTFail("Unexpected error type: \(error)")
    }
  }

  func testFallbackAllFailedAttemptsHaveCorrectNames() async {
    let rungs: [FallbackRung<String>] = [
      FallbackRung(name: "alpha") { throw MTPError.timeout },
      FallbackRung(name: "beta") { throw MTPError.busy },
      FallbackRung(name: "gamma") { throw MTPError.objectNotFound },
    ]
    do {
      _ = try await FallbackLadder.execute(rungs)
      XCTFail("Expected FallbackAllFailedError")
    } catch let err as FallbackAllFailedError {
      XCTAssertEqual(err.attempts.map(\.name), ["alpha", "beta", "gamma"])
      XCTAssertTrue(err.attempts.allSatisfy { !$0.succeeded })
    } catch {
      XCTFail("Unexpected error: \(error)")
    }
  }

  func testFallbackAllFailedAttemptsCarryErrorStrings() async {
    let rungs: [FallbackRung<Data>] = [
      FallbackRung(name: "timeout-rung") { throw MTPError.timeout },
    ]
    do {
      _ = try await FallbackLadder.execute(rungs)
      XCTFail("Expected FallbackAllFailedError")
    } catch let err as FallbackAllFailedError {
      XCTAssertNotNil(err.attempts.first?.error)
    } catch {
      XCTFail("Unexpected error: \(error)")
    }
  }

  func testFallbackAllFailedDescriptionContainsSymbols() async {
    let rungs: [FallbackRung<Int>] = [
      FallbackRung(name: "a") { throw MTPError.timeout },
    ]
    do {
      _ = try await FallbackLadder.execute(rungs)
      XCTFail("Expected FallbackAllFailedError")
    } catch let err as FallbackAllFailedError {
      XCTAssertTrue(err.description.contains("✗"), "description should contain ✗: \(err.description)")
    } catch {
      XCTFail("Unexpected error: \(error)")
    }
  }

  // MARK: - DeviceServiceRegistry surfacing

  func testDeviceServiceRegistryBasicRegistration() async throws {
    // Verifies the registry correctly stores and removes device service entries
    let reg = DeviceServiceRegistry()
    let config = VirtualDeviceConfig.pixel7

    // Before registration, service should be absent
    let before = await reg.service(for: config.deviceId)
    XCTAssertNil(before)

    // Register via a VirtualMTPDevice acting as a device service
    let device = VirtualMTPDevice(config: config)
    let service = DeviceService(device: device)
    await reg.register(deviceId: config.deviceId, service: service)

    let after = await reg.service(for: config.deviceId)
    XCTAssertNotNil(after)

    // Remove
    await reg.remove(deviceId: config.deviceId)
    let finalService = await reg.service(for: config.deviceId)
    XCTAssertNil(finalService)
  }

  // MARK: - Duration tracking

  func testFallbackAttemptsDurationIsNonNegative() async {
    let rungs: [FallbackRung<Int>] = [
      FallbackRung(name: "slow") {
        try await Task.sleep(nanoseconds: 1_000_000)  // 1ms
        throw MTPError.timeout
      },
    ]
    do {
      _ = try await FallbackLadder.execute(rungs)
      XCTFail("Expected FallbackAllFailedError")
    } catch let err as FallbackAllFailedError {
      let durationMs = err.attempts.first?.durationMs ?? -1
      XCTAssertGreaterThanOrEqual(durationMs, 0)
    } catch {
      XCTFail("Unexpected error: \(error)")
    }
  }

  // MARK: - Success path does not throw

  func testFallbackSucceedingRungDoesNotThrow() async throws {
    let rungs: [FallbackRung<Int>] = [
      FallbackRung(name: "fail") { throw MTPError.timeout },
      FallbackRung(name: "succeed") { return 42 },
    ]
    let result = try await FallbackLadder.execute(rungs)
    XCTAssertEqual(result.value, 42)
    XCTAssertEqual(result.winningRung, "succeed")
    XCTAssertEqual(result.attempts.count, 2)
  }

  func testFallbackFirstRungSucceedsSingleAttempt() async throws {
    let rungs: [FallbackRung<String>] = [
      FallbackRung(name: "first") { return "ok" },
    ]
    let result = try await FallbackLadder.execute(rungs)
    XCTAssertEqual(result.value, "ok")
    XCTAssertEqual(result.winningRung, "first")
    XCTAssertEqual(result.attempts.count, 1)
    XCTAssertTrue(result.attempts.first?.succeeded ?? false)
  }
}
