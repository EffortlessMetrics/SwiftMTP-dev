// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import SwiftMTPQuirks

// MARK: - Mock USB Transport Layer

/// Mock USB transport layer for testing without real devices
public actor MockUSBTransport: @unchecked Sendable {
  public private(set) var isConnected: Bool = false
  public private(set) var endpointIn: UInt8 = 0x81
  public private(set) var endpointOut: UInt8 = 0x01
  public private(set) var configurationValue: UInt8 = 1

  private var responseQueue: [Data] = []
  private var requestLog: [RequestRecord] = []
  private var programmableDelays: [UInt16: TimeInterval] = [:]
  private var errorInjectionMode: ErrorInjectionMode = .none
  private var bandwidthThrottling: Double = 1.0

  public struct RequestRecord: Sendable, Codable {
    public let timestamp: Date
    public let data: Data
    public let direction: Direction
    public let durationNs: UInt64

    public enum Direction: String, Sendable, Codable {
      case inRequest = "IN"
      case outRequest = "OUT"
    }
  }

  public enum ErrorInjectionMode: Sendable {
    case none
    case corruptNextPacket
    case timeoutNextRequest
    case stallNextRequest
    case randomBitFlips(probability: Double)
  }

  public init() {}

  public func connect(vid: UInt16, pid: UInt16) async throws {
    isConnected = true
    responseQueue.removeAll()
    requestLog.removeAll()
  }

  public func disconnect() {
    isConnected = false
  }

  public func write(_ data: Data, timeout: Int) async throws -> Int {
    guard isConnected else { throw USBTransportError.notConnected }

    let startTime = DispatchTime.now()

    // Apply delay if programmed
    if let opcode = parseOpcode(from: data), let delay = programmableDelays[opcode] {
      try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
    }

    // Apply bandwidth throttling
    let transferTime = Double(data.count) / (12_000_000 * bandwidthThrottling)  // USB 2.0 HS
    try await Task.sleep(nanoseconds: UInt64(transferTime * 1_000_000_000))

    // Handle error injection
    switch errorInjectionMode {
    case .none:
      break
    case .corruptNextPacket:
      errorInjectionMode = .none
      throw USBTransportError.crcMismatch
    case .timeoutNextRequest:
      errorInjectionMode = .none
      throw USBTransportError.timeout
    case .stallNextRequest:
      errorInjectionMode = .none
      throw USBTransportError.stall
    case .randomBitFlips(let probability):
      if Double.random(in: 0...1) < probability {
        throw USBTransportError.crcMismatch
      }
    }

    let endTime = DispatchTime.now()
    let duration = endTime.uptimeNanoseconds - startTime.uptimeNanoseconds

    let record = RequestRecord(
      timestamp: Date(),
      data: data,
      direction: .outRequest,
      durationNs: duration
    )
    requestLog.append(record)

    return data.count
  }

  public func read(into buffer: inout Data, timeout: Int) async throws -> Int {
    guard isConnected else { throw USBTransportError.notConnected }

    switch errorInjectionMode {
    case .timeoutNextRequest:
      errorInjectionMode = .none
      throw USBTransportError.timeout
    default:
      break
    }

    guard !responseQueue.isEmpty else {
      throw USBTransportError.noData
    }

    let response = responseQueue.removeFirst()
    let copyCount = min(response.count, buffer.count)
    buffer.replaceSubrange(0..<copyCount, with: response.prefix(copyCount))

    return copyCount
  }

  public func queueResponse(_ data: Data) {
    responseQueue.append(data)
  }

  public func programDelay(opcode: UInt16, delay: TimeInterval) {
    programmableDelays[opcode] = delay
  }

  public func setErrorInjection(_ injection: ErrorInjectionMode) {
    errorInjectionMode = injection
  }

  public func setBandwidthThrottling(_ factor: Double) {
    bandwidthThrottling = factor
  }

  public func clearRequests() {
    requestLog.removeAll()
  }

  public func getRequestLog() -> [RequestRecord] {
    return requestLog
  }

  private func parseOpcode(from data: Data) -> UInt16? {
    guard data.count >= 2 else { return nil }
    return UInt16(data[0]) | (UInt16(data[1]) << 8)
  }
}

public enum USBTransportError: Error, Sendable, Equatable {
  case notConnected
  case noData
  case timeout
  case stall
  case crcMismatch
  case babble
  case deviceDisconnected
}

// MARK: - Virtual Device Profiles

/// Virtual device profiles for testing
public struct VirtualDeviceProfile: Sendable {
  public let name: String
  public let vendorID: UInt16
  public let productID: UInt16
  public let manufacturer: String
  public let model: String
  public let serialNumber: String
  public let supportedOperations: [UInt16]
  public let supportedEvents: [UInt16]
  public let quirks: QuirkFlags
  public let storageInfo: [VirtualStorageInfo]

  public struct VirtualStorageInfo: Sendable {
    public let storageID: UInt32
    public let capacity: UInt64
    public let freeSpace: UInt64
    public let fileSystemType: String
    public let accessCapability: UInt16

    public init(
      storageID: UInt32, capacity: UInt64, freeSpace: UInt64, fileSystemType: String,
      accessCapability: UInt16
    ) {
      self.storageID = storageID
      self.capacity = capacity
      self.freeSpace = freeSpace
      self.fileSystemType = fileSystemType
      self.accessCapability = accessCapability
    }
  }

  public init(
    name: String,
    vendorID: UInt16,
    productID: UInt16,
    manufacturer: String,
    model: String,
    serialNumber: String,
    supportedOperations: [UInt16],
    supportedEvents: [UInt16],
    quirks: QuirkFlags,
    storageInfo: [VirtualStorageInfo]
  ) {
    self.name = name
    self.vendorID = vendorID
    self.productID = productID
    self.manufacturer = manufacturer
    self.model = model
    self.serialNumber = serialNumber
    self.supportedOperations = supportedOperations
    self.supportedEvents = supportedEvents
    self.quirks = quirks
    self.storageInfo = storageInfo
  }
}

/// Predefined virtual device profiles
public enum VirtualDeviceProfiles {
  public static let pixel7 = VirtualDeviceProfile(
    name: "pixel7",
    vendorID: 0x18D1,
    productID: 0x4EE1,
    manufacturer: "Google",
    model: "Pixel 7",
    serialNumber: "pixel7-001",
    supportedOperations: [
      0x1001, 0x1002, 0x1003, 0x1004, 0x1005, 0x1006, 0x1007, 0x1008, 0x1009,
      0x100A, 0x100B, 0x100C, 0x100D, 0x100E, 0x100F, 0x1014, 0x1015, 0x1016,
      0x1017, 0x1018, 0x1019, 0x101A, 0x101B, 0x101C, 0x101D, 0x101E, 0x101F,
      0x9801, 0x9802, 0x9803, 0x9804, 0x9805, 0x9806, 0x9807, 0x9808, 0x9809,
      0x980A, 0x980B, 0x980C, 0x980D, 0x980E, 0x980F, 0x9810, 0x9811, 0x9812,
      0x95C1, 0x95C2, 0x95C3, 0x95C4, 0x95C5, 0x95C6,
    ],
    supportedEvents: [
      0x4001, 0x4002, 0x4003, 0x4004, 0x4005, 0x4006, 0x4007, 0x4008,
    ],
    quirks: {
      var q = QuirkFlags()
      q.supportsPartialRead64 = true
      q.supportsPartialRead32 = true
      q.supportsPartialWrite = true
      q.prefersPropListEnumeration = true
      q.disableEventPump = false
      return q
    }(),
    storageInfo: [
      VirtualDeviceProfile.VirtualStorageInfo(
        storageID: 0x00010001,
        capacity: 128_000_000_000,
        freeSpace: 64_000_000_000,
        fileSystemType: "FAT32",
        accessCapability: 0x0003
      )
    ]
  )

  public static let onePlus3T = VirtualDeviceProfile(
    name: "oneplus3t",
    vendorID: 0x2A70,
    productID: 0x9038,
    manufacturer: "OnePlus",
    model: "ONEPLUS A3010",
    serialNumber: "oneplus3t-f003",
    supportedOperations: [
      0x1001, 0x1002, 0x1003, 0x1004, 0x1005, 0x1006, 0x1007, 0x1008, 0x1009,
      0x100A, 0x100B, 0x100C, 0x100D, 0x100E, 0x100F, 0x1014, 0x1015, 0x1016,
      0x1017, 0x1018, 0x1019, 0x101A, 0x101B, 0x101C, 0x9801, 0x9802, 0x9803,
      0x9804, 0x9805, 0x9806, 0x9807, 0x9808, 0x95C1, 0x95C2, 0x95C3, 0x95C4,
    ],
    supportedEvents: [
      0x4001, 0x4002, 0x4003, 0x4004, 0x4005, 0x4006,
    ],
    quirks: {
      var q = QuirkFlags()
      q.supportsPartialRead64 = false
      q.supportsPartialRead32 = true
      q.supportsPartialWrite = true
      q.prefersPropListEnumeration = false
      q.disableEventPump = false
      return q
    }(),
    storageInfo: [
      VirtualDeviceProfile.VirtualStorageInfo(
        storageID: 0x00010001,
        capacity: 64_000_000_000,
        freeSpace: 32_000_000_000,
        fileSystemType: "FAT32",
        accessCapability: 0x0003
      ),
      VirtualDeviceProfile.VirtualStorageInfo(
        storageID: 0x00010002,
        capacity: 64_000_000_000,
        freeSpace: 16_000_000_000,
        fileSystemType: "exFAT",
        accessCapability: 0x0003
      ),
    ]
  )

  public static let miNote2 = VirtualDeviceProfile(
    name: "mi-note2",
    vendorID: 0x2717,
    productID: 0xFF10,
    manufacturer: "Xiaomi",
    model: "Mi Note 2",
    serialNumber: "mi-note2-ff10",
    supportedOperations: [
      0x1001, 0x1002, 0x1003, 0x1004, 0x1005, 0x1006, 0x1007, 0x1008, 0x1009,
      0x100A, 0x100B, 0x100C, 0x100D, 0x100E, 0x100F, 0x1014, 0x1015, 0x1016,
      0x1017, 0x1018, 0x1019, 0x101A, 0x101B, 0x101C, 0x9801, 0x9802, 0x9803,
      0x9804, 0x95C1, 0x95C2, 0x95C3,
    ],
    supportedEvents: [
      0x4001, 0x4002, 0x4003, 0x4004,
    ],
    quirks: {
      var q = QuirkFlags()
      q.supportsPartialRead64 = false
      q.supportsPartialRead32 = false
      q.supportsPartialWrite = true
      q.prefersPropListEnumeration = true
      q.disableEventPump = true
      return q
    }(),
    storageInfo: [
      VirtualDeviceProfile.VirtualStorageInfo(
        storageID: 0x00010001,
        capacity: 128_000_000_000,
        freeSpace: 64_000_000_000,
        fileSystemType: "FAT32",
        accessCapability: 0x0003
      )
    ]
  )
}

// MARK: - Traffic Recording and Replay

/// Traffic recorder for regression testing
public actor TrafficRecorder {
  public private(set) var recordings: [RecordingSession] = []
  private var currentSessionData: RecordingSessionData?

  public struct RecordingSession: Sendable, Codable {
    public let id: UUID
    public let deviceProfile: String
    public let startTime: Date
    public let endTime: Date
    public let entries: [TrafficEntry]
    public let summary: SessionSummary
  }

  public struct TrafficEntry: Sendable, Codable {
    public let timestamp: Date
    public let direction: Direction
    public let opcode: UInt16?
    public let payload: Data
    public let responseTimeMs: Int

    public enum Direction: String, Sendable, Codable {
      case request = "REQ"
      case response = "RSP"
    }
  }

  public struct SessionSummary: Sendable, Codable {
    public let totalRequests: Int
    public let totalBytes: Int64
    public let averageResponseTimeMs: Double
    public let errorCount: Int
  }

  private struct RecordingSessionData {
    var entries: [TrafficEntry] = []
    let deviceProfile: String
    let startTime: Date
  }

  public init() {}

  public func startSession(profile: String) {
    currentSessionData = RecordingSessionData(
      deviceProfile: profile,
      startTime: Date()
    )
  }

  public func record(entry: TrafficEntry) {
    guard var session = currentSessionData else { return }
    session.entries.append(entry)
    currentSessionData = session
  }

  @discardableResult
  public func endSession() -> RecordingSession? {
    guard var session = currentSessionData else { return nil }

    let totalRequests = session.entries.filter { $0.direction == .request }.count
    let totalBytes = session.entries.reduce(0) { $0 + Int64($1.payload.count) }
    let responseTimes = session.entries.filter { $0.direction == .response }
      .map { Double($0.responseTimeMs) }
    let avgResponse =
      responseTimes.isEmpty ? 0 : responseTimes.reduce(0, +) / Double(responseTimes.count)

    let recording = RecordingSession(
      id: UUID(),
      deviceProfile: session.deviceProfile,
      startTime: session.startTime,
      endTime: Date(),
      entries: session.entries,
      summary: SessionSummary(
        totalRequests: totalRequests,
        totalBytes: totalBytes,
        averageResponseTimeMs: avgResponse,
        errorCount: 0
      )
    )

    recordings.append(recording)
    currentSessionData = nil
    return recording
  }

  public func getRecordings() -> [RecordingSession] {
    return recordings
  }
}

// MARK: - Result of a single capability test.

public struct CapabilityTestResult: Sendable, Codable {
  public let name: String
  public let opcode: String?
  public let supported: Bool
  public let durationMs: Int
  public let errorMessage: String?

  public init(
    name: String, opcode: String? = nil, supported: Bool, durationMs: Int,
    errorMessage: String? = nil
  ) {
    self.name = name
    self.opcode = opcode
    self.supported = supported
    self.durationMs = durationMs
    self.errorMessage = errorMessage
  }
}

// MARK: - Full report produced by the device lab harness.

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

  public init(maxChunkBytes: Int = 1 << 20, ioTimeoutMs: Int = 8000, handshakeTimeoutMs: Int = 6000)
  {
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
    // Prefer the real fingerprint from the probe receipt (carries actual USB descriptor data)
    let fingerprint: MTPDeviceFingerprint
    if let receipt = await device.probeReceipt {
      fingerprint = receipt.fingerprint
    } else {
      fingerprint = MTPDeviceFingerprint.fromUSB(
        vid: device.summary.vendorID ?? 0,
        pid: device.summary.productID ?? 0,
        interfaceClass: 0x06, interfaceSubclass: 0x01, interfaceProtocol: 0x01,
        epIn: 0x81, epOut: 0x01
      )
    }

    var tests: [CapabilityTestResult] = []

    // Test GetDeviceInfo
    tests.append(
      await testOperation(device: device, name: "GetDeviceInfo", opcode: 0x1001) {
        _ = try await device.devGetDeviceInfoUncached()
      })

    // Test GetStorageIDs
    tests.append(
      await testOperation(device: device, name: "GetStorageIDs", opcode: 0x1004) {
        _ = try await device.devGetStorageIDsUncached()
      })

    // Test storages enumeration
    let storages = try? await device.storages()
    if let firstStorage = storages?.first {
      tests.append(
        await testOperation(device: device, name: "GetObjectHandles", opcode: 0x1007) {
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
      let elapsed = Int(
        (DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000)
      return CapabilityTestResult(
        name: name, opcode: String(format: "0x%04X", opcode), supported: true, durationMs: elapsed)
    } catch {
      let elapsed = Int(
        (DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000)
      return CapabilityTestResult(
        name: name, opcode: String(format: "0x%04X", opcode), supported: false, durationMs: elapsed,
        errorMessage: "\(error)")
    }
  }
}
