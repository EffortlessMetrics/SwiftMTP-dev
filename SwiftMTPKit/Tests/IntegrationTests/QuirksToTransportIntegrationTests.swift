// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import XCTest
import SwiftMTPCore
import SwiftMTPQuirks
import SwiftMTPTestKit

/// Integration tests for Quirks → Transport interactions:
/// quirk lookup, transport configuration, device-specific tuning.
final class QuirksToTransportIntegrationTests: XCTestCase {

  // MARK: - 1. Quirk lookup → transport configuration

  func testQuirkLookupConfiguresTransportChunkSize() {
    let quirk = DeviceQuirk(
      id: "test-android-phone",
      vid: 0x04E8, pid: 0x6860,
      maxChunkBytes: 512 * 1024,
      ioTimeoutMs: 10000)

    let db = QuirkDatabase(schemaVersion: "1.0", entries: [quirk])
    let fingerprint = MTPDeviceFingerprint.fromUSB(
      vid: 0x04E8, pid: 0x6860,
      interfaceClass: 0xFF, interfaceSubclass: 0x01, interfaceProtocol: 0x01,
      epIn: 0x81, epOut: 0x02)

    let policy = QuirkResolver.resolve(fingerprint: fingerprint, database: db)
    XCTAssertEqual(policy.tuning.maxChunkBytes, 512 * 1024)
    XCTAssertEqual(policy.tuning.ioTimeoutMs, 10000)
  }

  func testQuirkLookupPreservesDefaultsForUnsetFields() {
    let quirk = DeviceQuirk(
      id: "partial-quirk",
      vid: 0x1234, pid: 0x5678,
      maxChunkBytes: 256 * 1024)

    let db = QuirkDatabase(schemaVersion: "1.0", entries: [quirk])
    let fingerprint = MTPDeviceFingerprint.fromUSB(
      vid: 0x1234, pid: 0x5678,
      interfaceClass: 0xFF, interfaceSubclass: 0x01, interfaceProtocol: 0x01,
      epIn: 0x81, epOut: 0x02)

    let policy = QuirkResolver.resolve(fingerprint: fingerprint, database: db)
    let defaults = EffectiveTuning.defaults()

    XCTAssertEqual(policy.tuning.maxChunkBytes, 256 * 1024,
      "Quirk should override chunk size")
    XCTAssertEqual(policy.tuning.handshakeTimeoutMs, defaults.handshakeTimeoutMs,
      "Unset fields should retain defaults")
  }

  func testMultipleQuirksOnlyMatchingVIDPIDApplied() {
    let samsungQuirk = DeviceQuirk(
      id: "samsung-phone", vid: 0x04E8, pid: 0x6860,
      maxChunkBytes: 512 * 1024, ioTimeoutMs: 8000)
    let xiaomiQuirk = DeviceQuirk(
      id: "xiaomi-phone", vid: 0x2717, pid: 0xFF10,
      maxChunkBytes: 128 * 1024, ioTimeoutMs: 20000)

    let db = QuirkDatabase(schemaVersion: "1.0", entries: [samsungQuirk, xiaomiQuirk])

    let samsungFP = MTPDeviceFingerprint.fromUSB(
      vid: 0x04E8, pid: 0x6860,
      interfaceClass: 0xFF, interfaceSubclass: 0x01, interfaceProtocol: 0x01,
      epIn: 0x81, epOut: 0x02)

    let policy = QuirkResolver.resolve(fingerprint: samsungFP, database: db)
    XCTAssertEqual(policy.tuning.maxChunkBytes, 512 * 1024,
      "Samsung quirk should be selected, not Xiaomi")
    XCTAssertEqual(policy.tuning.ioTimeoutMs, 8000)
  }

  // MARK: - 2. Samsung quirk → correct chunk size

  func testSamsungGalaxyQuirkSetsExpectedChunkSize() {
    let quirk = DeviceQuirk(
      id: "samsung-galaxy-s7",
      deviceName: "Samsung Galaxy S7",
      category: "phone",
      vid: 0x04E8, pid: 0x6860,
      maxChunkBytes: 512 * 1024,
      ioTimeoutMs: 10000,
      flags: QuirkFlags())

    let db = QuirkDatabase(schemaVersion: "1.0", entries: [quirk])
    let fingerprint = MTPDeviceFingerprint.fromUSB(
      vid: 0x04E8, pid: 0x6860,
      interfaceClass: 0xFF, interfaceSubclass: 0x01, interfaceProtocol: 0x01,
      epIn: 0x81, epOut: 0x02)

    let policy = QuirkResolver.resolve(fingerprint: fingerprint, database: db)
    XCTAssertEqual(policy.tuning.maxChunkBytes, 512 * 1024,
      "Samsung Galaxy quirk should set 512KB chunk size")
    XCTAssertEqual(policy.sources.chunkSizeSource, .quirk,
      "Chunk size source should be .quirk")
  }

  func testSamsungQuirkFlagsApplied() {
    var flags = QuirkFlags()
    flags.requiresKernelDetach = true
    flags.writeToSubfolderOnly = true
    flags.preferredWriteFolder = "Download"

    let quirk = DeviceQuirk(
      id: "samsung-android-subfolder",
      vid: 0x04E8, pid: 0x6860,
      flags: flags)

    let db = QuirkDatabase(schemaVersion: "1.0", entries: [quirk])
    let fingerprint = MTPDeviceFingerprint.fromUSB(
      vid: 0x04E8, pid: 0x6860,
      interfaceClass: 0xFF, interfaceSubclass: 0x01, interfaceProtocol: 0x01,
      epIn: 0x81, epOut: 0x02)

    let policy = QuirkResolver.resolve(fingerprint: fingerprint, database: db)
    XCTAssertTrue(policy.flags.requiresKernelDetach)
    XCTAssertTrue(policy.flags.writeToSubfolderOnly)
    XCTAssertEqual(policy.flags.preferredWriteFolder, "Download")
  }

  func testSamsungQuirkWithLargeTimeout() {
    let quirk = DeviceQuirk(
      id: "samsung-slow-usb",
      vid: 0x04E8, pid: 0x6860,
      ioTimeoutMs: 30000,
      handshakeTimeoutMs: 15000)

    let db = QuirkDatabase(schemaVersion: "1.0", entries: [quirk])
    let fingerprint = MTPDeviceFingerprint.fromUSB(
      vid: 0x04E8, pid: 0x6860,
      interfaceClass: 0xFF, interfaceSubclass: 0x01, interfaceProtocol: 0x01,
      epIn: 0x81, epOut: 0x02)

    let policy = QuirkResolver.resolve(fingerprint: fingerprint, database: db)
    XCTAssertEqual(policy.tuning.ioTimeoutMs, 30000)
    XCTAssertEqual(policy.tuning.handshakeTimeoutMs, 15000)
  }

  // MARK: - 3. Camera quirk → PTP mode selection

  func testCameraQuirkEnablesPTPFlags() {
    let fingerprint = MTPDeviceFingerprint.fromUSB(
      vid: 0x04A9, pid: 0x3139,
      interfaceClass: 0x06, interfaceSubclass: 0x01, interfaceProtocol: 0x01,
      epIn: 0x81, epOut: 0x02)

    let db = QuirkDatabase(schemaVersion: "1.0", entries: [])
    let policy = QuirkResolver.resolve(fingerprint: fingerprint, database: db)

    XCTAssertTrue(policy.flags.supportsGetObjectPropList,
      "PTP camera should enable proplist")
    XCTAssertFalse(policy.flags.requiresKernelDetach,
      "PTP camera should not require kernel detach")
    XCTAssertTrue(policy.flags.prefersPropListEnumeration,
      "PTP camera should prefer proplist enumeration")
  }

  func testCameraQuirkWithExplicitOverride() {
    var cameraFlags = QuirkFlags()
    cameraFlags.supportsGetObjectPropList = true
    cameraFlags.cameraClass = true
    cameraFlags.requiresKernelDetach = false
    cameraFlags.needsShortReads = true

    let quirk = DeviceQuirk(
      id: "canon-eos-special",
      vid: 0x04A9, pid: 0x3139,
      maxChunkBytes: 1_048_576,
      flags: cameraFlags)

    let db = QuirkDatabase(schemaVersion: "1.0", entries: [quirk])
    let fingerprint = MTPDeviceFingerprint.fromUSB(
      vid: 0x04A9, pid: 0x3139,
      interfaceClass: 0x06, interfaceSubclass: 0x01, interfaceProtocol: 0x01,
      epIn: 0x81, epOut: 0x02)

    let policy = QuirkResolver.resolve(fingerprint: fingerprint, database: db)
    XCTAssertTrue(policy.flags.supportsGetObjectPropList)
    XCTAssertTrue(policy.flags.cameraClass)
    XCTAssertTrue(policy.flags.needsShortReads,
      "Explicit quirk flag should override defaults")
    XCTAssertEqual(policy.tuning.maxChunkBytes, 1_048_576)
  }

  func testNikonCameraDefaultsViaPTPClass() {
    let fingerprint = MTPDeviceFingerprint.fromUSB(
      vid: 0x04B0, pid: 0x0410,
      interfaceClass: 0x06, interfaceSubclass: 0x01, interfaceProtocol: 0x01,
      epIn: 0x81, epOut: 0x02)

    let emptyDB = QuirkDatabase(schemaVersion: "1.0", entries: [])
    let policy = QuirkResolver.resolve(fingerprint: fingerprint, database: emptyDB)

    XCTAssertTrue(policy.flags.supportsGetObjectPropList,
      "Nikon (PTP class) should get proplist support via heuristic")
    XCTAssertTrue(policy.flags.supportsPartialRead32)
    XCTAssertFalse(policy.flags.requiresKernelDetach)
  }

  func testCameraVsPhoneFlagDifferences() {
    let cameraFP = MTPDeviceFingerprint.fromUSB(
      vid: 0x04A9, pid: 0x3139,
      interfaceClass: 0x06, interfaceSubclass: 0x01, interfaceProtocol: 0x01,
      epIn: 0x81, epOut: 0x02)

    let phoneFP = MTPDeviceFingerprint.fromUSB(
      vid: 0x04E8, pid: 0x6860,
      interfaceClass: 0xFF, interfaceSubclass: 0x01, interfaceProtocol: 0x01,
      epIn: 0x81, epOut: 0x02)

    let emptyDB = QuirkDatabase(schemaVersion: "1.0", entries: [])
    let cameraPolicy = QuirkResolver.resolve(fingerprint: cameraFP, database: emptyDB)
    let phonePolicy = QuirkResolver.resolve(fingerprint: phoneFP, database: emptyDB)

    XCTAssertTrue(cameraPolicy.flags.supportsGetObjectPropList)
    XCTAssertFalse(phonePolicy.flags.supportsGetObjectPropList,
      "Phone (vendor class) should not get proplist by default")
    XCTAssertNotEqual(cameraPolicy.flags.requiresKernelDetach,
      phonePolicy.flags.requiresKernelDetach,
      "Camera and phone should have different kernel detach defaults")
  }

  // MARK: - 4. Unknown device → default tuning

  func testUnknownDeviceGetsDefaultTuning() {
    let fingerprint = MTPDeviceFingerprint.fromUSB(
      vid: 0xDEAD, pid: 0xBEEF,
      interfaceClass: 0xFF, interfaceSubclass: 0x01, interfaceProtocol: 0x01,
      epIn: 0x81, epOut: 0x02)

    let emptyDB = QuirkDatabase(schemaVersion: "1.0", entries: [])
    let policy = QuirkResolver.resolve(fingerprint: fingerprint, database: emptyDB)
    let defaults = EffectiveTuning.defaults()

    XCTAssertEqual(policy.tuning.maxChunkBytes, defaults.maxChunkBytes)
    XCTAssertEqual(policy.tuning.ioTimeoutMs, defaults.ioTimeoutMs)
    XCTAssertEqual(policy.tuning.handshakeTimeoutMs, defaults.handshakeTimeoutMs)
    XCTAssertEqual(policy.sources.chunkSizeSource, .defaults,
      "Unknown device should use default sources")
  }

  func testUnknownDeviceDefaultFlagsAreConservative() {
    let fingerprint = MTPDeviceFingerprint.fromUSB(
      vid: 0x9999, pid: 0x8888,
      interfaceClass: 0xFF, interfaceSubclass: 0x01, interfaceProtocol: 0x01,
      epIn: 0x81, epOut: 0x02)

    let emptyDB = QuirkDatabase(schemaVersion: "1.0", entries: [])
    let policy = QuirkResolver.resolve(fingerprint: fingerprint, database: emptyDB)

    XCTAssertTrue(policy.flags.requiresKernelDetach,
      "Unknown device should conservatively require kernel detach")
    XCTAssertFalse(policy.flags.supportsGetObjectPropList,
      "Unknown device should not assume proplist support")
    XCTAssertFalse(policy.flags.resetOnOpen,
      "Unknown device should not reset on open by default")
  }

  func testUnknownDeviceWithNilInterfaceClass() {
    let policy = EffectiveTuningBuilder.buildPolicy(
      capabilities: [:], learned: nil, quirk: nil, overrides: nil, ifaceClass: nil)

    let defaults = EffectiveTuning.defaults()
    XCTAssertEqual(policy.tuning.maxChunkBytes, defaults.maxChunkBytes)
    XCTAssertFalse(policy.flags.supportsGetObjectPropList)
    XCTAssertTrue(policy.flags.requiresKernelDetach)
  }

  func testUserOverridesTrumpQuirkAndDefaults() {
    let quirk = DeviceQuirk(
      id: "overrideable-device",
      vid: 0x1111, pid: 0x2222,
      maxChunkBytes: 256 * 1024,
      ioTimeoutMs: 5000)

    let overrides = ["maxChunkBytes": "8388608", "ioTimeoutMs": "60000"]
    let policy = EffectiveTuningBuilder.buildPolicy(
      capabilities: [:], learned: nil, quirk: quirk, overrides: overrides)

    XCTAssertEqual(policy.tuning.maxChunkBytes, 8_388_608,
      "User override should trump quirk")
    XCTAssertEqual(policy.tuning.ioTimeoutMs, 60000)
    XCTAssertEqual(policy.sources.chunkSizeSource, .userOverride)
  }

  // MARK: - 5. Learned profile integration

  func testLearnedProfileMergedWithQuirk() {
    let quirk = DeviceQuirk(
      id: "learned-quirk-merge",
      vid: 0x3333, pid: 0x4444,
      maxChunkBytes: 512 * 1024)

    var learnedTuning = EffectiveTuning.defaults()
    learnedTuning.maxChunkBytes = 1_048_576
    learnedTuning.ioTimeoutMs = 12000

    let policy = EffectiveTuningBuilder.buildPolicy(
      capabilities: [:], learned: learnedTuning, quirk: quirk, overrides: nil)

    // Quirk should take precedence over learned for chunk size
    XCTAssertEqual(policy.tuning.maxChunkBytes, 512 * 1024,
      "Quirk should override learned profile for chunk size")
  }

  func testLearnedProfileAppliedWhenNoQuirk() {
    var learnedTuning = EffectiveTuning.defaults()
    learnedTuning.maxChunkBytes = 2_097_152
    learnedTuning.ioTimeoutMs = 15000

    let policy = EffectiveTuningBuilder.buildPolicy(
      capabilities: [:], learned: learnedTuning, quirk: nil, overrides: nil)

    XCTAssertEqual(policy.tuning.maxChunkBytes, 2_097_152,
      "Learned tuning should apply when no quirk exists")
    XCTAssertEqual(policy.sources.chunkSizeSource, .learned)
  }

  // MARK: - 6. Fingerprint-based resolution

  func testFingerprintHashDeterminesQuirkMatch() {
    let fp1 = MTPDeviceFingerprint.fromUSB(
      vid: 0x04E8, pid: 0x6860,
      interfaceClass: 0xFF, interfaceSubclass: 0x01, interfaceProtocol: 0x01,
      epIn: 0x81, epOut: 0x02)

    let fp2 = MTPDeviceFingerprint.fromUSB(
      vid: 0x04E8, pid: 0x6860,
      interfaceClass: 0xFF, interfaceSubclass: 0x01, interfaceProtocol: 0x01,
      epIn: 0x81, epOut: 0x02)

    let fp3 = MTPDeviceFingerprint.fromUSB(
      vid: 0x04E8, pid: 0x6861,
      interfaceClass: 0xFF, interfaceSubclass: 0x01, interfaceProtocol: 0x01,
      epIn: 0x81, epOut: 0x02)

    XCTAssertEqual(fp1.hashString, fp2.hashString,
      "Same VID/PID should produce identical hash")
    XCTAssertNotEqual(fp1.hashString, fp3.hashString,
      "Different PID should produce different hash")
  }

  func testLearnedProfileSessionDataMerge() {
    let fingerprint = MTPDeviceFingerprint.fromUSB(
      vid: 0x5555, pid: 0x6666,
      interfaceClass: 0xFF, interfaceSubclass: 0x01, interfaceProtocol: 0x01,
      epIn: 0x81, epOut: 0x02)

    let initial = LearnedProfile(
      fingerprint: fingerprint,
      fingerprintHash: fingerprint.hashString,
      created: Date(),
      lastUpdated: Date(),
      sampleCount: 5,
      optimalChunkSize: 1_048_576,
      avgHandshakeMs: 45,
      optimalIoTimeoutMs: 8000,
      optimalInactivityTimeoutMs: 8000,
      p95ReadThroughputMBps: 20.0,
      p95WriteThroughputMBps: 10.0,
      successRate: 0.95,
      hostEnvironment: "macOS-test")

    let session = SessionData(
      actualChunkSize: 2_097_152,
      handshakeTimeMs: 35,
      readThroughputMBps: 35.0,
      wasSuccessful: true)

    let merged = initial.merged(with: session)
    XCTAssertEqual(merged.sampleCount, 6)
    XCTAssertGreaterThan(merged.p95ReadThroughputMBps ?? 0, initial.p95ReadThroughputMBps ?? 0,
      "Merged profile should reflect higher throughput sample")
  }

  // MARK: - 7. Quirk flag combinations

  func testQuirkWithResetOnOpenFlag() {
    var flags = QuirkFlags()
    flags.resetOnOpen = true
    flags.requireStabilization = true

    let quirk = DeviceQuirk(
      id: "reset-device", vid: 0x7777, pid: 0x8888, flags: flags)
    let db = QuirkDatabase(schemaVersion: "1.0", entries: [quirk])

    let fp = MTPDeviceFingerprint.fromUSB(
      vid: 0x7777, pid: 0x8888,
      interfaceClass: 0xFF, interfaceSubclass: 0x01, interfaceProtocol: 0x01,
      epIn: 0x81, epOut: 0x02)

    let policy = QuirkResolver.resolve(fingerprint: fp, database: db)
    XCTAssertTrue(policy.flags.resetOnOpen)
    XCTAssertTrue(policy.flags.requireStabilization)
  }

  func testQuirkWithDisabledEventPump() {
    var flags = QuirkFlags()
    flags.disableEventPump = true

    let quirk = DeviceQuirk(
      id: "no-events", vid: 0xAAAA, pid: 0xBBBB, flags: flags)
    let db = QuirkDatabase(schemaVersion: "1.0", entries: [quirk])

    let fp = MTPDeviceFingerprint.fromUSB(
      vid: 0xAAAA, pid: 0xBBBB,
      interfaceClass: 0xFF, interfaceSubclass: 0x01, interfaceProtocol: 0x01,
      epIn: 0x81, epOut: 0x02)

    let policy = QuirkResolver.resolve(fingerprint: fp, database: db)
    XCTAssertTrue(policy.flags.disableEventPump)
  }

  func testQuirkDatabaseWithEmptyEntries() {
    let emptyDB = QuirkDatabase(schemaVersion: "1.0", entries: [])

    let fp = MTPDeviceFingerprint.fromUSB(
      vid: 0x0001, pid: 0x0002,
      interfaceClass: 0xFF, interfaceSubclass: 0x01, interfaceProtocol: 0x01,
      epIn: 0x81, epOut: 0x02)

    let policy = QuirkResolver.resolve(fingerprint: fp, database: emptyDB)
    let defaults = EffectiveTuning.defaults()
    XCTAssertEqual(policy.tuning.maxChunkBytes, defaults.maxChunkBytes,
      "Empty DB should yield default tuning")
    XCTAssertEqual(policy.sources.chunkSizeSource, .defaults)
  }

  func testQuirkWithWriteRestrictions() {
    var flags = QuirkFlags()
    flags.writeToSubfolderOnly = true
    flags.preferredWriteFolder = "Pictures"
    flags.emptyDatesInSendObject = true
    flags.forceFFFFFFFForSendObject = true

    let quirk = DeviceQuirk(
      id: "write-restricted", vid: 0xCCCC, pid: 0xDDDD, flags: flags)
    let db = QuirkDatabase(schemaVersion: "1.0", entries: [quirk])

    let fp = MTPDeviceFingerprint.fromUSB(
      vid: 0xCCCC, pid: 0xDDDD,
      interfaceClass: 0xFF, interfaceSubclass: 0x01, interfaceProtocol: 0x01,
      epIn: 0x81, epOut: 0x02)

    let policy = QuirkResolver.resolve(fingerprint: fp, database: db)
    XCTAssertTrue(policy.flags.writeToSubfolderOnly)
    XCTAssertEqual(policy.flags.preferredWriteFolder, "Pictures")
    XCTAssertTrue(policy.flags.emptyDatesInSendObject)
    XCTAssertTrue(policy.flags.forceFFFFFFFForSendObject)
  }
}
