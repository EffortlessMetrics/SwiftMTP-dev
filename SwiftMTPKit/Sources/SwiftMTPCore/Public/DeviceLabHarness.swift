// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import SwiftMTPQuirks

/// Result of a single capability test.
public struct CapabilityTestResult: Sendable, Codable {
  public let name: String
  public let opcode: String?
  public let supported: Bool
  public let durationMs: Int
  public let errorMessage: String?

  public init(name: String, opcode: String? = nil, supported: Bool, durationMs: Int, errorMessage: String? = nil) {
    self.name = name
    self.opcode = opcode
    self.supported = supported
    self.durationMs = durationMs
    self.errorMessage = errorMessage
  }
}

/// Full report produced by the device lab harness.
public struct DeviceLabReport: Sendable, Codable {
  public let timestamp: Date
  public let manufacturer: String
  public let model: String
  public let serialNumber: String?
  public let fingerprint: MTPDeviceFingerprint
  public let operationsSupported: [String]
  public let eventsSupported: [String]
  public let capabilityTests: [CapabilityTestResult]
  public let suggestedFlags: QuirkFlags
  public let suggestedTuning: SuggestedTuning

  public init(
    timestamp: Date = Date(),
    manufacturer: String,
    model: String,
    serialNumber: String?,
    fingerprint: MTPDeviceFingerprint,
    operationsSupported: [String],
    eventsSupported: [String],
    capabilityTests: [CapabilityTestResult],
    suggestedFlags: QuirkFlags,
    suggestedTuning: SuggestedTuning
  ) {
    self.timestamp = timestamp
    self.manufacturer = manufacturer
    self.model = model
    self.serialNumber = serialNumber
    self.fingerprint = fingerprint
    self.operationsSupported = operationsSupported
    self.eventsSupported = eventsSupported
    self.capabilityTests = capabilityTests
    self.suggestedFlags = suggestedFlags
    self.suggestedTuning = suggestedTuning
  }
}

/// Suggested tuning values based on harness results.
public struct SuggestedTuning: Sendable, Codable {
  public var maxChunkBytes: Int
  public var ioTimeoutMs: Int
  public var handshakeTimeoutMs: Int

  public init(maxChunkBytes: Int = 1 << 20, ioTimeoutMs: Int = 8000, handshakeTimeoutMs: Int = 6000) {
    self.maxChunkBytes = maxChunkBytes
    self.ioTimeoutMs = ioTimeoutMs
    self.handshakeTimeoutMs = handshakeTimeoutMs
  }
}

/// Deterministic, read-only test suite that characterizes a connected
/// MTP device's capabilities and produces a `DeviceLabReport`.
public struct DeviceLabHarness: Sendable {

  public init() {}

  /// Run the full capability test suite against an open device.
  @_spi(Dev)
  public func collect(device: any MTPDevice) async throws -> DeviceLabReport {
    try await device.openIfNeeded()
    let info = try await device.info
    let policy = await device.devicePolicy
    let fingerprint = MTPDeviceFingerprint.fromUSB(
      vid: device.summary.vendorID ?? 0,
      pid: device.summary.productID ?? 0,
      interfaceClass: 0x06, interfaceSubclass: 0x01, interfaceProtocol: 0x01,
      epIn: 0x81, epOut: 0x01
    )

    var tests: [CapabilityTestResult] = []

    // Test GetDeviceInfo
    tests.append(await testOperation(device: device, name: "GetDeviceInfo", opcode: 0x1001) {
      _ = try await device.devGetDeviceInfoUncached()
    })

    // Test GetStorageIDs
    tests.append(await testOperation(device: device, name: "GetStorageIDs", opcode: 0x1004) {
      _ = try await device.devGetStorageIDsUncached()
    })

    // Test storages enumeration
    let storages = try? await device.storages()
    if let firstStorage = storages?.first {
      tests.append(await testOperation(device: device, name: "GetObjectHandles", opcode: 0x1007) {
        _ = try await device.devGetRootHandlesUncached(storage: firstStorage.id)
      })
    }

    // Check supported operations
    let opsHex = info.operationsSupported.sorted().map { String(format: "0x%04X", $0) }
    let evtsHex = info.eventsSupported.sorted().map { String(format: "0x%04X", $0) }

    // Build suggested flags from actual capabilities
    var flags = QuirkFlags()
    flags.supportsPartialRead64 = info.operationsSupported.contains(0x95C4)
    flags.supportsPartialRead32 = info.operationsSupported.contains(0x101B)
    flags.supportsPartialWrite = info.operationsSupported.contains(0x95C1)
    flags.prefersPropListEnumeration = info.operationsSupported.contains(0x9805)
    flags.disableEventPump = info.eventsSupported.isEmpty

    // Suggest tuning based on what we learned
    let tuning = SuggestedTuning(
      maxChunkBytes: policy?.tuning.maxChunkBytes ?? (1 << 20),
      ioTimeoutMs: policy?.tuning.ioTimeoutMs ?? 8000,
      handshakeTimeoutMs: policy?.tuning.handshakeTimeoutMs ?? 6000
    )

    return DeviceLabReport(
      manufacturer: info.manufacturer,
      model: info.model,
      serialNumber: info.serialNumber,
      fingerprint: fingerprint,
      operationsSupported: opsHex,
      eventsSupported: evtsHex,
      capabilityTests: tests,
      suggestedFlags: flags,
      suggestedTuning: tuning
    )
  }

  private func testOperation(
    device: any MTPDevice, name: String, opcode: UInt16,
    body: @Sendable () async throws -> Void
  ) async -> CapabilityTestResult {
    let start = DispatchTime.now()
    do {
      try await body()
      let elapsed = Int((DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000)
      return CapabilityTestResult(name: name, opcode: String(format: "0x%04X", opcode), supported: true, durationMs: elapsed)
    } catch {
      let elapsed = Int((DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000)
      return CapabilityTestResult(name: name, opcode: String(format: "0x%04X", opcode), supported: false, durationMs: elapsed, errorMessage: "\(error)")
    }
  }
}
