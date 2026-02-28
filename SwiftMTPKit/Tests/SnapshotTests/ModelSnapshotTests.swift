// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import XCTest
import SnapshotTesting
@testable import SwiftMTPCore
@testable import SwiftMTPIndex
import SwiftMTPQuirks

/// Comprehensive snapshot tests for SwiftMTP data types using swift-snapshot-testing (1.10.0+).
///
/// Snapshot directories:
/// - __Snapshots__/ProbeReceiptSnapshots/ - Device probe output snapshots
/// - __Snapshots__/QuirkSnapshots/ - Device quirks and policy snapshots
/// - __Snapshots__/ProfileSnapshots/ - Learned profile snapshots
/// - __Snapshots__/IndexSnapshots/ - Device index snapshots
/// - __Snapshots__/JournalSnapshots/ - Transfer journal snapshots
/// - __Snapshots__/ErrorSnapshots/ - Error state snapshots
final class ModelSnapshotTests: XCTestCase {

  // MARK: - Test Configuration

  override func setUpWithError() throws {
    try super.setUpWithError()
    SnapshotTesting.diffTool = "ksdiff"
    try XCTSkipUnless(
      ProcessInfo.processInfo.environment["SWIFTMTP_SNAPSHOT_TESTS"] == "1",
      "Set SWIFTMTP_SNAPSHOT_TESTS=1 to run snapshot reference assertions (run-all-tests.sh enables this by default)."
    )
  }

  // MARK: - ProbeReceipt Snapshots

  /// Pixel 7 probe output snapshot - realistic device probe data
  func testProbeReceiptPixel7() throws {
    let fingerprint = MTPDeviceFingerprint(
      vid: "18d1",
      pid: "4ee1",
      bcdDevice: "0528",
      interfaceTriple: InterfaceTriple(class: "06", subclass: "01", protocol: "01"),
      endpointAddresses: EndpointAddresses(input: "81", output: "01", event: "82"),
      deviceInfoHash: "google-pixel-7-4ee1-hash"
    )

    let summary = MTPDeviceSummary(
      id: MTPDeviceID(raw: "pixel7-4ee1-TESTSERIAL001"),
      manufacturer: "Google",
      model: "Pixel 7",
      vendorID: 0x18D1,
      productID: 0x4EE1,
      usbSerial: "TESTSERIAL001"
    )

    let receipt = ProbeReceipt(
      timestamp: ISO8601DateFormatter().date(from: "2026-02-08T10:00:00Z")!,
      deviceSummary: ReceiptDeviceSummary(from: summary),
      fingerprint: fingerprint
    )

    // Configure interface probe results
    var interfaceProbe = InterfaceProbeResult()
    interfaceProbe.candidatesEvaluated = 2
    interfaceProbe.selectedInterface = 0
    interfaceProbe.selectedScore = 10
    interfaceProbe.deviceInfoCached = false
    interfaceProbe.attempts = [
      InterfaceAttemptResult(interfaceNumber: 0, score: 10, succeeded: true, durationMs: 45),
      InterfaceAttemptResult(
        interfaceNumber: 1, score: 8, succeeded: false, durationMs: 120,
        error: "LIBUSB_ERROR_ACCESS"),
    ]

    // Configure session probe
    var sessionProbe = SessionProbeResult()
    sessionProbe.succeeded = true
    sessionProbe.requiredRetry = false
    sessionProbe.durationMs = 89
    sessionProbe.error = nil

    // Configure capabilities
    let capabilities: [String: Bool] = [
      "supportsGetPartialObject64": true,
      "supportsSendPartialObject": true,
      "supportsEvents": true,
      "supportsObjectPropList": true,
    ]

    // Configure fallback results
    let fallbackResults: [String: String] = [
      "enumeration": "propList5",
      "read": "partial64",
      "write": "partial",
    ]

    // Configure resolved policy
    let policy = DevicePolicy(
      tuning: EffectiveTuning(
        maxChunkBytes: 2097152,
        ioTimeoutMs: 30000,
        handshakeTimeoutMs: 20000,
        inactivityTimeoutMs: 10000,
        overallDeadlineMs: 180000,
        stabilizeMs: 3000,
        postClaimStabilizeMs: 500,
        postProbeStabilizeMs: 0,
        resetOnOpen: false,
        disableEventPump: false,
        operations: capabilities,
        hooks: []
      ),
      flags: QuirkFlags()
    )
    var testReceipt = receipt
    testReceipt.interfaceProbe = interfaceProbe
    testReceipt.sessionEstablishment = sessionProbe
    testReceipt.capabilities = capabilities
    testReceipt.fallbackResults = fallbackResults
    testReceipt.resolvedPolicy = PolicySummary(from: policy)
    testReceipt.totalProbeTimeMs = 245

    assertSnapshot(of: testReceipt, as: .json, named: "pixel7-probe")
  }

  /// OnePlus 3T probe output snapshot - Android device with mass storage interface
  func testProbeReceiptOnePlus3T() throws {
    let fingerprint = MTPDeviceFingerprint(
      vid: "2a70",
      pid: "f003",
      bcdDevice: "0200",
      interfaceTriple: InterfaceTriple(class: "06", subclass: "01", protocol: "01"),
      endpointAddresses: EndpointAddresses(input: "81", output: "01", event: "82"),
      deviceInfoHash: "oneplus-3t-f003-hash"
    )

    let summary = MTPDeviceSummary(
      id: MTPDeviceID(raw: "oneplus3t-f003-TESTSERIAL002"),
      manufacturer: "OnePlus",
      model: "ONEPLUS A3010",
      vendorID: 0x2A70,
      productID: 0xF003,
      usbSerial: "TESTSERIAL002"
    )

    let receipt = ProbeReceipt(
      timestamp: ISO8601DateFormatter().date(from: "2026-02-08T10:01:00Z")!,
      deviceSummary: ReceiptDeviceSummary(from: summary),
      fingerprint: fingerprint
    )

    var interfaceProbe = InterfaceProbeResult()
    interfaceProbe.candidatesEvaluated = 2
    interfaceProbe.selectedInterface = 0
    interfaceProbe.selectedScore = 12
    interfaceProbe.deviceInfoCached = false
    interfaceProbe.attempts = [
      InterfaceAttemptResult(interfaceNumber: 0, score: 12, succeeded: true, durationMs: 115),
      InterfaceAttemptResult(
        interfaceNumber: 1, score: 0, succeeded: false, durationMs: 5,
        error: "Mass Storage interface - ignored"),
    ]

    var sessionProbe = SessionProbeResult()
    sessionProbe.succeeded = true
    sessionProbe.requiredRetry = false
    sessionProbe.durationMs = 0
    sessionProbe.error = nil

    let capabilities: [String: Bool] = [
      "supportsGetPartialObject64": true,
      "supportsSendPartialObject": true,
      "supportsEvents": true,
      "preferGetObjectPropList": true,
      "skipPTPReset": true,
    ]

    let fallbackResults: [String: String] = [
      "enumeration": "propList5",
      "read": "partial64",
      "write": "partial",
    ]

    var testReceipt = receipt
    testReceipt.interfaceProbe = interfaceProbe
    testReceipt.sessionEstablishment = sessionProbe
    testReceipt.capabilities = capabilities
    testReceipt.fallbackResults = fallbackResults
    testReceipt.totalProbeTimeMs = 156

    assertSnapshot(of: testReceipt, as: .json, named: "oneplus-3t-probe")
  }

  /// Xiaomi Mi-Note 2 probe output snapshot - device requiring stabilization
  func testProbeReceiptXiaomiMiNote2() throws {
    let fingerprint = MTPDeviceFingerprint(
      vid: "2717",
      pid: "ff10",
      bcdDevice: "0100",
      interfaceTriple: InterfaceTriple(class: "06", subclass: "01", protocol: "01"),
      endpointAddresses: EndpointAddresses(input: "81", output: "01", event: "82"),
      deviceInfoHash: "xiaomi-mi-note-2-ff10-hash"
    )

    let summary = MTPDeviceSummary(
      id: MTPDeviceID(raw: "mi-note2-ff10-abc123"),
      manufacturer: "Xiaomi",
      model: "Mi Note 2",
      vendorID: 0x2717,
      productID: 0xFF10,
      usbSerial: "abc123"
    )

    let receipt = ProbeReceipt(
      timestamp: ISO8601DateFormatter().date(from: "2026-02-08T10:02:00Z")!,
      deviceSummary: ReceiptDeviceSummary(from: summary),
      fingerprint: fingerprint
    )

    var interfaceProbe = InterfaceProbeResult()
    interfaceProbe.candidatesEvaluated = 1
    interfaceProbe.selectedInterface = 0
    interfaceProbe.selectedScore = 10
    interfaceProbe.deviceInfoCached = false
    interfaceProbe.attempts = [
      InterfaceAttemptResult(interfaceNumber: 0, score: 10, succeeded: true, durationMs: 250)
    ]

    var sessionProbe = SessionProbeResult()
    sessionProbe.succeeded = true
    sessionProbe.requiredRetry = true
    sessionProbe.durationMs = 450
    sessionProbe.error = nil

    let capabilities: [String: Bool] = [
      "supportsGetPartialObject64": true,
      "supportsSendPartialObject": true,
      "requiresStabilization": true,
    ]

    let fallbackResults: [String: String] = [
      "enumeration": "propList5",
      "read": "partial64",
      "write": "partial",
    ]

    var quirkFlags = QuirkFlags()
    quirkFlags.requireStabilization = true
    let hook = QuirkHook(phase: .postOpenSession, delayMs: 400)
    var policy = EffectiveTuningBuilder.build(
      capabilities: capabilities,
      learned: nil,
      quirk: DeviceQuirk(
        id: "xiaomi-mi-note-2-ff10",
        vid: 0x2717,
        pid: 0xff10,
        stabilizeMs: 400,
        resetOnOpen: false
      ),
      overrides: nil
    )
    policy.hooks = [hook]

    var testReceipt = receipt
    testReceipt.interfaceProbe = interfaceProbe
    testReceipt.sessionEstablishment = sessionProbe
    testReceipt.capabilities = capabilities
    testReceipt.fallbackResults = fallbackResults
    testReceipt.resolvedPolicy = PolicySummary(
      from: DevicePolicy(tuning: policy, flags: quirkFlags))
    testReceipt.totalProbeTimeMs = 850

    assertSnapshot(of: testReceipt, as: .json, named: "xiaomi-mi-note-2-probe")
  }

  /// Mock device probe output snapshot - for testing without real hardware
  func testProbeReceiptMockDevice() throws {
    let fingerprint = MTPDeviceFingerprint(
      vid: "1234",
      pid: "5678",
      bcdDevice: "0100",
      interfaceTriple: InterfaceTriple(class: "06", subclass: "01", protocol: "01"),
      endpointAddresses: EndpointAddresses(input: "81", output: "01", event: "82"),
      deviceInfoHash: "mock-device-1234-hash"
    )

    let summary = MTPDeviceSummary(
      id: MTPDeviceID(raw: "mock-device-12345678"),
      manufacturer: "MockMfg",
      model: "MockDevice",
      vendorID: 0x1234,
      productID: 0x5678,
      usbSerial: "12345678"
    )

    let receipt = ProbeReceipt(
      timestamp: ISO8601DateFormatter().date(from: "2026-02-08T10:03:00Z")!,
      deviceSummary: ReceiptDeviceSummary(from: summary),
      fingerprint: fingerprint
    )

    var interfaceProbe = InterfaceProbeResult()
    interfaceProbe.candidatesEvaluated = 1
    interfaceProbe.selectedInterface = 0
    interfaceProbe.selectedScore = 10
    interfaceProbe.deviceInfoCached = false
    interfaceProbe.attempts = [
      InterfaceAttemptResult(interfaceNumber: 0, score: 10, succeeded: true, durationMs: 10)
    ]

    var sessionProbe = SessionProbeResult()
    sessionProbe.succeeded = true
    sessionProbe.requiredRetry = false
    sessionProbe.durationMs = 5
    sessionProbe.error = nil

    let capabilities: [String: Bool] = [
      "supportsGetPartialObject64": true,
      "supportsSendPartialObject": true,
      "supportsEvents": false,
    ]

    let fallbackResults: [String: String] = [
      "enumeration": "propList5",
      "read": "partial64",
      "write": "wholeObject",
    ]

    var testReceipt = receipt
    testReceipt.interfaceProbe = interfaceProbe
    testReceipt.sessionEstablishment = sessionProbe
    testReceipt.capabilities = capabilities
    testReceipt.fallbackResults = fallbackResults
    testReceipt.totalProbeTimeMs = 25

    assertSnapshot(of: testReceipt, as: .json, named: "mock-device-probe")
  }

  // MARK: - Device Quirks Snapshots

  /// Quirks database with multiple devices
  func testQuirksDatabase() throws {
    let database = try QuirkDatabase.load()
    assertSnapshot(of: database, as: .json, named: "quirks-database")
  }

  /// Fallback strategy selections for different device types
  func testFallbackSelections() {
    // Unknown device (needs probing)
    var unknownFallbacks = FallbackSelections()
    unknownFallbacks.enumeration = .unknown
    unknownFallbacks.read = .unknown
    unknownFallbacks.write = .unknown

    // Pixel 7 - successful probe results
    var pixel7Fallbacks = FallbackSelections()
    pixel7Fallbacks.enumeration = .propList5
    pixel7Fallbacks.read = .partial64
    pixel7Fallbacks.write = .partial

    // OnePlus 3T - prefers prop list enumeration
    var onePlus3TFallbacks = FallbackSelections()
    onePlus3TFallbacks.enumeration = .propList5
    onePlus3TFallbacks.read = .partial64
    onePlus3TFallbacks.write = .partial

    // Legacy device - only supports whole object operations
    var legacyFallbacks = FallbackSelections()
    legacyFallbacks.enumeration = .handlesThenInfo
    legacyFallbacks.read = .wholeObject
    legacyFallbacks.write = .wholeObject

    let selections: [String: AnyEncodable] = [
      "unknown": AnyEncodable(unknownFallbacks),
      "pixel7": AnyEncodable(pixel7Fallbacks),
      "oneplus3t": AnyEncodable(onePlus3TFallbacks),
      "legacy": AnyEncodable(legacyFallbacks),
    ]

    assertSnapshot(of: selections, as: .json, named: "fallback-selections")
  }

  // MARK: - Category Distribution Snapshot

  /// Verify category distribution across the quirks database
  func testCategoryDistribution() throws {
    let database = try QuirkDatabase.load()
    var distribution: [String: Int] = [:]
    for entry in database.entries {
      let cat = entry.category ?? "unknown"
      distribution[cat, default: 0] += 1
    }
    // Verify we have enough categories and the expected shape
    XCTAssertGreaterThanOrEqual(distribution.count, 25, "Expected at least 25 device categories")
    XCTAssertGreaterThanOrEqual(distribution["phone"] ?? 0, 2000)
    XCTAssertGreaterThanOrEqual(distribution["camera"] ?? 0, 800)
    XCTAssertGreaterThanOrEqual(distribution["media-player"] ?? 0, 300)
    XCTAssertGreaterThanOrEqual(distribution["e-reader"] ?? 0, 100)
    XCTAssertGreaterThanOrEqual(distribution["gps-navigator"] ?? 0, 100)
  }

  // MARK: - LearnedProfile Snapshots

  /// Empty profile (new device, no session data yet)
  func testLearnedProfileEmpty() {
    let fingerprint = MTPDeviceFingerprint(
      vid: "18d1",
      pid: "4ee1",
      bcdDevice: "0528",
      interfaceTriple: InterfaceTriple(class: "06", subclass: "01", protocol: "01"),
      endpointAddresses: EndpointAddresses(input: "81", output: "01", event: "82"),
      deviceInfoHash: nil
    )

    let profile = LearnedProfile(
      fingerprint: fingerprint,
      fingerprintHash: fingerprint.hashString,
      created: ISO8601DateFormatter().date(from: "2025-01-01T00:00:00Z")!,
      lastUpdated: ISO8601DateFormatter().date(from: "2025-01-01T00:00:00Z")!,
      sampleCount: 1,
      hostEnvironment: "macOS 15.0"
    )

    assertSnapshot(of: profile, as: .json, named: "empty-profile")
  }

  /// Partial profile (some metrics learned from a few sessions)
  func testLearnedProfilePartial() {
    let fingerprint = MTPDeviceFingerprint(
      vid: "2a70",
      pid: "f003",
      bcdDevice: "0200",
      interfaceTriple: InterfaceTriple(class: "06", subclass: "01", protocol: "01"),
      endpointAddresses: EndpointAddresses(input: "81", output: "01", event: "82"),
      deviceInfoHash: nil
    )

    let profile = LearnedProfile(
      fingerprint: fingerprint,
      fingerprintHash: fingerprint.hashString,
      created: ISO8601DateFormatter().date(from: "2025-01-02T00:00:00Z")!,
      lastUpdated: ISO8601DateFormatter().date(from: "2025-01-02T00:00:00Z")!,
      sampleCount: 5,
      optimalChunkSize: 1_048_576,
      avgHandshakeMs: 150,
      optimalIoTimeoutMs: 25_000,
      p95ReadThroughputMBps: 28.5,
      p95WriteThroughputMBps: 15.2,
      successRate: 0.95,
      hostEnvironment: "macOS 15.0"
    )

    assertSnapshot(of: profile, as: .json, named: "partial-profile")
  }

  /// Full profile (all metrics learned from many sessions)
  func testLearnedProfileFull() {
    let fingerprint = MTPDeviceFingerprint(
      vid: "2717",
      pid: "ff10",
      bcdDevice: "0100",
      interfaceTriple: InterfaceTriple(class: "06", subclass: "01", protocol: "01"),
      endpointAddresses: EndpointAddresses(input: "81", output: "01", event: "82"),
      deviceInfoHash: "xiaomi-mi-note-2-full-hash"
    )

    let createdDate = ISO8601DateFormatter().date(from: "2025-01-01T00:00:00Z")!
    let lastUpdatedDate = ISO8601DateFormatter().date(from: "2025-02-01T00:00:00Z")!
    let profile = LearnedProfile(
      fingerprint: fingerprint,
      fingerprintHash: fingerprint.hashString,
      created: createdDate,
      lastUpdated: lastUpdatedDate,
      sampleCount: 50,
      optimalChunkSize: 2_097_152,
      avgHandshakeMs: 350,
      optimalIoTimeoutMs: 20_000,
      optimalInactivityTimeoutMs: 15_000,
      p95ReadThroughputMBps: 42.8,
      p95WriteThroughputMBps: 22.4,
      successRate: 0.98,
      hostEnvironment: "macOS 15.0"
    )

    assertSnapshot(of: profile, as: .json, named: "full-profile")
  }

  /// Profile merge operation snapshot
  func testLearnedProfileMerge() {
    let fingerprint = MTPDeviceFingerprint(
      vid: "18d1",
      pid: "4ee1",
      bcdDevice: "0528",
      interfaceTriple: InterfaceTriple(class: "06", subclass: "01", protocol: "01"),
      endpointAddresses: EndpointAddresses(input: "81", output: "01", event: "82"),
      deviceInfoHash: nil
    )

    let existingProfile = LearnedProfile(
      fingerprint: fingerprint,
      fingerprintHash: fingerprint.hashString,
      created: ISO8601DateFormatter().date(from: "2025-01-03T00:00:00Z")!,
      lastUpdated: ISO8601DateFormatter().date(from: "2025-01-03T00:00:00Z")!,
      sampleCount: 10,
      optimalChunkSize: 1_500_000,
      avgHandshakeMs: 200,
      p95ReadThroughputMBps: 30.0,
      successRate: 0.90,
      hostEnvironment: "macOS 15.0"
    )

    let newSessionData = SessionData(
      actualChunkSize: 2_000_000,
      handshakeTimeMs: 180,
      effectiveIoTimeoutMs: 25_000,
      readThroughputMBps: 35.0,
      writeThroughputMBps: 18.0,
      wasSuccessful: true
    )

    let mergedRaw = existingProfile.merged(with: newSessionData)
    let mergedProfile = LearnedProfile(
      fingerprint: mergedRaw.fingerprint,
      fingerprintHash: mergedRaw.fingerprintHash,
      created: mergedRaw.created,
      lastUpdated: ISO8601DateFormatter().date(from: "2025-01-04T00:00:00Z")!,
      sampleCount: mergedRaw.sampleCount,
      optimalChunkSize: mergedRaw.optimalChunkSize,
      avgHandshakeMs: mergedRaw.avgHandshakeMs,
      optimalIoTimeoutMs: mergedRaw.optimalIoTimeoutMs,
      optimalInactivityTimeoutMs: mergedRaw.optimalInactivityTimeoutMs,
      p95ReadThroughputMBps: mergedRaw.p95ReadThroughputMBps,
      p95WriteThroughputMBps: mergedRaw.p95WriteThroughputMBps,
      successRate: mergedRaw.successRate,
      hostEnvironment: mergedRaw.hostEnvironment
    )

    assertSnapshot(of: mergedProfile, as: .json, named: "merged-profile")
  }

  // MARK: - Index Snapshots

  /// Empty index state (no devices indexed)
  func testIndexEmptyState() {
    let emptyIndex: [String: Any] = [
      "devices": [],
      "storages": [],
      "objects": [],
      "changeCounter": 0,
    ]

    assertSnapshot(of: emptyIndex, as: .json, named: "empty-index")
  }

  /// Single file snapshot (indexed object)
  func testIndexSingleFile() {
    let fileObject = IndexedObject(
      deviceId: "pixel7-4ee1",
      storageId: 0x00010001,
      handle: 0x00000001,
      parentHandle: nil,
      name: "test.txt",
      pathKey: "/test.txt",
      sizeBytes: 1024,
      mtime: ISO8601DateFormatter().date(from: "2026-02-07T12:00:00Z"),
      formatCode: 0x3001,
      isDirectory: false,
      changeCounter: 1
    )

    let snapshot: [String: Any] = [
      "deviceId": fileObject.deviceId,
      "storageId": fileObject.storageId,
      "handle": fileObject.handle,
      "parentHandle": fileObject.parentHandle as Any,
      "name": fileObject.name,
      "pathKey": fileObject.pathKey,
      "sizeBytes": fileObject.sizeBytes as Any,
      "mtime": fileObject.mtime.map { ISO8601DateFormatter().string(from: $0) } as Any,
      "formatCode": fileObject.formatCode,
      "isDirectory": fileObject.isDirectory,
      "changeCounter": fileObject.changeCounter,
    ]

    assertSnapshot(of: snapshot, as: .json, named: "single-file")
  }

  /// Device disconnect state (cleanup after detach)
  func testIndexDeviceDisconnect() {
    let disconnectState: [String: Any] = [
      "event": "deviceDetached",
      "deviceId": "pixel7-4ee1",
      "timestamp": "2026-02-08T10:00:00Z",
      "cleanupActions": [
        "stopCrawler": true,
        "stopEventBridge": true,
        "closeDeviceHandle": true,
        "purgeCache": true,
      ],
      "indexState": [
        "preserved": true,
        "reason": "offline-browsing",
      ],
    ]

    assertSnapshot(of: disconnectState, as: .json, named: "device-disconnect")
  }

  // MARK: - Error Snapshots

  /// MTP protocol errors
  func testMTPProtocolErrors() {
    let protocolErrors: [String: Any] = [
      "errors": [
        [
          "code": 0x2009,
          "name": "InvalidParameter",
          "description": "MTP device rejected command due to invalid parameter",
        ],
        [
          "code": 0x2019,
          "name": "InvalidObjectHandle",
          "description": "Object handle does not exist on device",
        ],
        [
          "code": 0x201D,
          "name": "ObjectTooLarge",
          "description": "Object exceeds device's maximum file size",
        ],
        [
          "code": 0x2020,
          "name": "SessionAlreadyOpen",
          "description": "MTP session is already open",
        ],
      ],
      "recoveryStrategies": [
        "retryWithDifferentParams": true,
        "refreshDeviceIndex": true,
        "reconnectDevice": false,
      ],
    ]

    assertSnapshot(of: protocolErrors, as: .json, named: "mtp-protocol-errors")
  }

  /// USB transport errors
  func testUSBTransportErrors() {
    let transportErrors: [String: Any] = [
      "errors": [
        [
          "code": -1,
          "libusbError": "LIBUSB_ERROR_IO",
          "name": "InputOutputError",
          "description": "Input/output error during USB transfer",
        ],
        [
          "code": -4,
          "libusbError": "LIBUSB_ERROR_INTERRUPTED",
          "name": "TransferInterrupted",
          "description": "Transfer was interrupted by system",
        ],
        [
          "code": -7,
          "libusbError": "LIBUSB_ERROR_TIMEOUT",
          "name": "TransferTimeout",
          "description": "USB transfer timed out",
        ],
        [
          "code": -9,
          "libusbError": "LIBUSB_ERROR_PIPE",
          "name": "PipeError",
          "description": "Endpoint pipe stalled or control request not supported",
        ],
        [
          "code": -12,
          "libusbError": "LIBUSB_ERROR_NO_DEVICE",
          "name": "NoDevice",
          "description": "Device was disconnected during transfer",
        ],
      ],
      "recoveryStrategies": [
        "retry": true,
        "reconfigureDevice": true,
        "resetUSBPort": true,
      ],
    ]

    assertSnapshot(of: transportErrors, as: .json, named: "usb-transport-errors")
  }

  /// Device timeout errors
  func testDeviceTimeoutErrors() {
    let timeoutErrors: [String: Any] = [
      "errors": [
        [
          "type": "handshakeTimeout",
          "description": "Device failed to respond to OpenSession within timeout",
          "thresholdMs": 20000,
          "observedMs": 25000,
          "action": "retryWithBackoff",
        ],
        [
          "type": "ioTimeout",
          "description": "Data transfer exceeded I/O timeout",
          "thresholdMs": 30000,
          "observedMs": 35000,
          "action": "retryWithShorterChunks",
        ],
        [
          "type": "inactivityTimeout",
          "description": "Device went idle beyond allowed inactivity period",
          "thresholdMs": 10000,
          "observedMs": 15000,
          "action": "reopenSession",
        ],
      ],
      "mitigation": [
        "adaptiveTimeout": true,
        "sessionKeepalive": true,
      ],
    ]

    assertSnapshot(of: timeoutErrors, as: .json, named: "device-timeout-errors")
  }

  /// Storage full errors
  func testStorageFullErrors() {
    let storageFullErrors: [String: Any] = [
      "errors": [
        [
          "mtpCode": 0x200C,
          "name": "StorageFull",
          "description": "Device storage is full",
          "storageId": 0x00010001,
          "capacityBytes": 128_000_000_000,
          "freeBytes": 0,
          "recovery": "userActionRequired",
        ],
        [
          "mtpCode": 0x200D,
          "name": "ReadOnly",
          "description": "Storage is read-only",
          "storageId": 0x00010002,
          "recovery": "useDifferentStorage",
        ],
      ],
      "userNotification": [
        "title": "Device Storage Full",
        "message": "Free up space on your device to continue transfers",
        "actions": ["openDeviceSettings", "eject"],
      ],
    ]

    assertSnapshot(of: storageFullErrors, as: .json, named: "storage-full-errors")
  }
}

// MARK: - Helper Types

/// Type erapper for Encodable types to allow mixing in dictionaries
struct AnyEncodable: Encodable {
  private let _encode: (Encoder) throws -> Void

  init<T: Encodable>(_ value: T) {
    _encode = value.encode
  }

  func encode(to encoder: Encoder) throws {
    try _encode(encoder)
  }
}

// MARK: - Helper Extensions

extension Encodable {
  /// Convert any encodable type to a dictionary for snapshot testing
  func asDictionary() -> [String: Any] {
    let data = (try? JSONEncoder().encode(self)) ?? Data()
    let jsonObject = (try? JSONSerialization.jsonObject(with: data)) ?? [:]
    return jsonObject as? [String: Any] ?? [:]
  }
}
