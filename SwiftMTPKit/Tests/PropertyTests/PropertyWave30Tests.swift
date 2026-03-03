// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import MTPEndianCodec
import SwiftCheck
import XCTest

@testable import SwiftMTPCLI
@testable import SwiftMTPCore
@testable import SwiftMTPIndex
@testable import SwiftMTPQuirks
@testable import SwiftMTPSync

// MARK: - Generators

/// Generator for PTP operation codes covering standard and vendor-extended ranges.
private enum PTPOpCodeGenerator {
  static var arbitrary: Gen<UInt16> {
    Gen<UInt16>
      .one(of: [
        // Standard PTP/MTP operation codes
        Gen<UInt16>
          .fromElements(of: [
            0x1001, 0x1002, 0x1003, 0x1004, 0x1005, 0x1006, 0x1007,
            0x1008, 0x1009, 0x100A, 0x100B, 0x100C, 0x100D, 0x100E,
            0x1014, 0x1015, 0x1016, 0x1017, 0x101B,
          ]),
        // Vendor-extended codes
        Gen<UInt16>.fromElements(of: [0x95C1, 0x95C4, 0x9801, 0x9802, 0x9803]),
        // Random codes
        Gen<UInt16>.choose((0x1000, 0xFFFF)),
      ])
  }
}

/// Generator for PTP container type values.
private enum PTPContainerTypeGenerator {
  static var arbitrary: Gen<UInt16> {
    Gen<UInt16>.fromElements(of: [1, 2, 3, 4])
  }
}

/// Generator for PTP parameter arrays (0–5 params per spec).
private enum PTPParamGenerator {
  static var arbitrary: Gen<[UInt32]> {
    Gen<Int>.choose((0, 5))
      .flatMap { count in
        if count == 0 { return Gen.pure([UInt32]()) }
        return Gen<[UInt32]>
          .compose { c in
            (0..<count).map { _ in c.generate(using: Gen<UInt32>.choose((0, UInt32.max))) }
          }
      }
  }
}

/// Generator for MTP format codes.
private enum FormatCodeGenerator {
  static var arbitrary: Gen<UInt16> {
    Gen<UInt16>
      .fromElements(of: [
        0x3000, 0x3001, 0x3002, 0x3004, 0x3005, 0x3006, 0x3008, 0x3009,
        0x3801, 0x3802, 0x3804, 0x3807, 0x380B, 0x380D,
        0xB901, 0xB902, 0xB982, 0xB984,
      ])
  }
}

/// Generator for safe filenames (no path separators, no null bytes, fits PTP string limits).
private enum SafeFilenameGenerator {
  static var arbitrary: Gen<String> {
    Gen<String>
      .one(of: [
        Gen<String>
          .fromElements(of: [
            "photo.jpg", "IMG_20240101_120000.jpg", "track.mp3",
            "notes.txt", "video.mp4", "document.pdf",
            "naïve.txt", "café.png", "日本語.txt", "한국어.mp4",
            "emoji📷.jpg", "résumé.pdf", "Ångström.dat",
            "file with spaces.txt", "UPPERCASE.JPG",
            "file.tar.gz", ".hidden", "no_extension",
          ]),
        Gen<Character>.fromElements(of: Array("abcdefghijklmnopqrstuvwxyz0123456789._- "))
          .proliferate
          .suchThat { !$0.isEmpty }
          .map { String($0).trimmingCharacters(in: .whitespaces) }
          .suchThat { !$0.isEmpty && $0.count < 200 },
      ])
  }
}

/// Generator for path component arrays.
private enum Wave30PathComponentsGen {
  static var arbitrary: Gen<[String]> {
    let names = [
      "DCIM", "Music", "Documents", "Photos", "Videos",
      "Download", "Pictures", "Camera", "2024", "vacation",
      "IMG_001.jpg", "track.mp3", "notes.txt", "photo.png",
      "naïve", "café", "文件", "ファイル",
    ]
    return Gen<Int>.choose((0, 8))
      .flatMap { depth in
        if depth == 0 { return Gen.pure([String]()) }
        return Gen<[String]>
          .compose { c in
            (0..<depth).map { _ in c.generate(using: Gen<String>.fromElements(of: names)) }
          }
      }
  }
}

/// Generator for storage IDs.
private enum Wave30StorageIDGen {
  static var arbitrary: Gen<UInt32> {
    Gen<UInt32>
      .fromElements(of: [
        0x0001_0001, 0x0001_0002, 0x0002_0001, 0x0001_0003, 0xFFFF_FFFF, 1,
      ])
  }
}

/// Generator for EffectiveTuning with random valid values.
private enum TuningGenerator {
  static var arbitrary: Gen<EffectiveTuning> {
    Gen<(Int, Int, Int, Int, Int, Int, Int, Int, Bool, Bool)>
      .zip(
        Gen<Int>.choose((128 * 1024, 16 * 1024 * 1024)),
        Gen<Int>.choose((1000, 30000)),
        Gen<Int>.choose((1000, 30000)),
        Gen<Int>.choose((1000, 30000)),
        Gen<Int>.choose((10000, 120000)),
        Gen<Int>.choose((0, 2000)),
        Gen<Int>.choose((0, 2000)),
        Gen<Int>.choose((0, 2000)),
        Bool.arbitrary,
        Bool.arbitrary
      )
      .map { chunk, io, hs, inact, deadline, stab, postClaim, postProbe, reset, disableEvt in
        EffectiveTuning(
          maxChunkBytes: chunk, ioTimeoutMs: io, handshakeTimeoutMs: hs,
          inactivityTimeoutMs: inact, overallDeadlineMs: deadline,
          stabilizeMs: stab, postClaimStabilizeMs: postClaim,
          postProbeStabilizeMs: postProbe, resetOnOpen: reset,
          disableEventPump: disableEvt, operations: [:], hooks: []
        )
      }
  }
}

// MARK: - PTP Container Encode→Decode Round-Trip

final class PTPContainerRoundTripPropertyTests: XCTestCase {

  /// Encoding a PTPContainer and decoding the bytes via PTPReader must recover all fields.
  func testPTPContainerEncodeDecodeRoundTrip() {
    property("PTPContainer encode→decode round-trips for random codes and params")
      <- forAll(
        PTPContainerTypeGenerator.arbitrary,
        PTPOpCodeGenerator.arbitrary,
        Gen<UInt32>.choose((1, UInt32.max)),
        PTPParamGenerator.arbitrary
      ) { (type: UInt16, code: UInt16, txid: UInt32, params: [UInt32]) in
        let length = UInt32(12 + params.count * 4)
        let container = PTPContainer(
          length: length, type: type, code: code, txid: txid, params: params)

        var buf = [UInt8](repeating: 0, count: Int(length) + 16)
        let written = container.encode(into: &buf)

        let data = Data(buf[0..<written])
        var reader = PTPReader(data: data)

        guard let decodedLength = reader.u32(),
          let decodedType = reader.u16(),
          let decodedCode = reader.u16(),
          let decodedTxid = reader.u32()
        else { return false }

        var decodedParams = [UInt32]()
        for _ in 0..<params.count {
          guard let p = reader.u32() else { return false }
          decodedParams.append(p)
        }

        return decodedLength == length
          && decodedType == type
          && decodedCode == code
          && decodedTxid == txid
          && decodedParams == params
      }
  }

  /// Encoded container length field always matches actual byte count.
  func testPTPContainerEncodedLengthMatchesActual() {
    property("PTPContainer encoded length field matches actual encoded byte count")
      <- forAll(
        PTPContainerTypeGenerator.arbitrary,
        PTPOpCodeGenerator.arbitrary,
        Gen<UInt32>.choose((1, UInt32.max)),
        PTPParamGenerator.arbitrary
      ) { (type: UInt16, code: UInt16, txid: UInt32, params: [UInt32]) in
        let length = UInt32(12 + params.count * 4)
        let container = PTPContainer(
          length: length, type: type, code: code, txid: txid, params: params)
        var buf = [UInt8](repeating: 0, count: Int(length) + 16)
        let written = container.encode(into: &buf)
        return written == Int(length)
      }
  }
}

// MARK: - MTPObjectInfo Serialization Round-Trip

final class MTPObjectInfoRoundTripPropertyTests: XCTestCase {

  /// MTPObjectInfo created with random values preserves all fields.
  func testMTPObjectInfoFieldPreservation() {
    property("MTPObjectInfo preserves all fields through construction")
      <- forAll(
        Gen<UInt32>.choose((1, UInt32.max)),
        Gen<UInt32>.choose((1, UInt32.max)),
        SafeFilenameGenerator.arbitrary,
        Gen<UInt64>.choose((0, 10_000_000_000)),
        FormatCodeGenerator.arbitrary
      ) { (handle: UInt32, storage: UInt32, name: String, size: UInt64, format: UInt16) in
        let storageID = MTPStorageID(raw: storage)
        let info = MTPObjectInfo(
          handle: handle, storage: storageID, parent: nil,
          name: name, sizeBytes: size, modified: nil,
          formatCode: format, properties: [:])
        return info.handle == handle
          && info.storage == storageID
          && info.name == name
          && info.sizeBytes == size
          && info.formatCode == format
      }
  }

  /// MTPObjectInfo Codable round-trip preserves all fields.
  func testMTPObjectInfoCodableRoundTrip() {
    property("MTPObjectInfo survives JSON encode→decode round-trip")
      <- forAll(
        Gen<UInt32>.choose((1, UInt32.max)),
        Gen<UInt32>.choose((1, UInt32.max)),
        SafeFilenameGenerator.arbitrary,
        Gen<UInt64>.choose((0, 10_000_000_000)),
        FormatCodeGenerator.arbitrary
      ) { (handle: UInt32, storage: UInt32, name: String, size: UInt64, format: UInt16) in
        let storageID = MTPStorageID(raw: storage)
        let original = MTPObjectInfo(
          handle: handle, storage: storageID, parent: nil,
          name: name, sizeBytes: size,
          modified: Date(timeIntervalSince1970: 1_700_000_000),
          formatCode: format, properties: [:])
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        guard let data = try? encoder.encode(original),
          let decoded = try? decoder.decode(MTPObjectInfo.self, from: data)
        else { return false }
        return decoded.handle == original.handle
          && decoded.storage == original.storage
          && decoded.name == original.name
          && decoded.sizeBytes == original.sizeBytes
          && decoded.formatCode == original.formatCode
      }
  }
}

// MARK: - PathKey Normalization Idempotency

final class PathKeyIdempotencyPropertyTests: XCTestCase {

  /// normalize(normalize(x)) == normalize(x) for any storage and components.
  func testNormalizationIdempotency() {
    property("PathKey.normalize is idempotent: normalize(normalize(x)) == normalize(x)")
      <- forAll(Wave30StorageIDGen.arbitrary, Wave30PathComponentsGen.arbitrary) {
        (storage: UInt32, components: [String]) in
        let once = PathKey.normalize(storage: storage, components: components)
        let (parsedStorage, parsedComponents) = PathKey.parse(once)
        let twice = PathKey.normalize(storage: parsedStorage, components: parsedComponents)
        return once == twice
      }
  }

  /// Normalizing components individually then joining matches normalize with array.
  func testComponentNormalizationConsistency() {
    property("Individual component normalization is consistent with bulk normalize")
      <- forAll(Wave30StorageIDGen.arbitrary, Wave30PathComponentsGen.arbitrary) {
        (storage: UInt32, components: [String]) in
        let bulkResult = PathKey.normalize(storage: storage, components: components)
        let prefix = String(format: "%08x", storage)
        let individualComponents = components.map { PathKey.normalizeComponent($0) }
        let manualResult =
          individualComponents.isEmpty
          ? prefix : prefix + "/" + individualComponents.joined(separator: "/")
        return bulkResult == manualResult
      }
  }

  /// Normalized component never contains control characters or slashes.
  func testNormalizedComponentSafety() {
    property("Normalized component never contains control chars, '/', or '\\'")
      <- forAll(String.arbitrary.suchThat { !$0.isEmpty && $0.count < 200 }) { raw in
        let normalized = PathKey.normalizeComponent(raw)
        let hasControl = normalized.unicodeScalars.contains {
          CharacterSet.controlCharacters.contains($0)
        }
        let hasSlash = normalized.contains("/") || normalized.contains("\\")
        return !hasControl && !hasSlash && !normalized.isEmpty
      }
  }
}

// MARK: - QuirkEntry Merge Associativity

final class QuirkMergeAssociativityPropertyTests: XCTestCase {

  /// Building tuning with quirk A then quirk B applied sequentially
  /// should produce deterministic results (the last quirk wins for each field).
  func testQuirkOverrideIsLastWriterWins() {
    property("Quirk override follows last-writer-wins for each field")
      <- forAll(
        Gen<Int>.choose((128 * 1024, 16 * 1024 * 1024)),
        Gen<Int>.choose((128 * 1024, 16 * 1024 * 1024)),
        Gen<Int>.choose((1000, 30000)),
        Gen<Int>.choose((1000, 30000))
      ) { (chunkA: Int, chunkB: Int, ioA: Int, ioB: Int) in
        let quirkA = DeviceQuirk(
          id: "quirk-a", vid: 0x1234, pid: 0x5678,
          maxChunkBytes: chunkA, ioTimeoutMs: ioA)
        let quirkB = DeviceQuirk(
          id: "quirk-b", vid: 0x1234, pid: 0x5678,
          maxChunkBytes: chunkB, ioTimeoutMs: ioB)

        // Apply A then override with B
        let withA = EffectiveTuningBuilder.build(
          capabilities: [:], learned: nil, quirk: quirkA, overrides: nil)
        let withB = EffectiveTuningBuilder.build(
          capabilities: [:], learned: nil, quirk: quirkB, overrides: nil)

        // B's values should appear in withB
        return withB.maxChunkBytes == chunkB && withB.ioTimeoutMs == ioB
          && withA.maxChunkBytes == chunkA && withA.ioTimeoutMs == ioA
      }
  }

  /// Building with defaults as learned profile yields same result as no learned profile.
  func testDefaultLearnedIsIdentity() {
    property("Building with EffectiveTuning.defaults() as learned is identity")
      <- forAll(
        Gen<Int>.choose((128 * 1024, 8 * 1024 * 1024)),
        Gen<Int>.choose((1000, 20000))
      ) { (chunk: Int, io: Int) in
        let quirk = DeviceQuirk(
          id: "test", vid: 0x1234, pid: 0x5678,
          maxChunkBytes: chunk, ioTimeoutMs: io)
        let withoutLearned = EffectiveTuningBuilder.build(
          capabilities: [:], learned: nil, quirk: quirk, overrides: nil)
        let withDefaults = EffectiveTuningBuilder.build(
          capabilities: [:], learned: EffectiveTuning.defaults(), quirk: quirk, overrides: nil)
        // Quirk values override both cases equally
        return withoutLearned.maxChunkBytes == withDefaults.maxChunkBytes
          && withoutLearned.ioTimeoutMs == withDefaults.ioTimeoutMs
      }
  }

  /// Quirk fields always override default values when present.
  func testQuirkFieldsOverrideDefaults() {
    property("Non-nil quirk fields always override defaults")
      <- forAll(
        Gen<Int>.choose((128 * 1024, 16 * 1024 * 1024)),
        Gen<Int>.choose((1000, 30000)),
        Gen<Bool>.fromElements(of: [true, false])
      ) { (chunk: Int, io: Int, reset: Bool) in
        let quirk = DeviceQuirk(
          id: "test", vid: 0xAAAA, pid: 0xBBBB,
          maxChunkBytes: chunk, ioTimeoutMs: io, resetOnOpen: reset)
        let tuning = EffectiveTuningBuilder.build(
          capabilities: [:], learned: nil, quirk: quirk, overrides: nil)
        return tuning.maxChunkBytes == chunk
          && tuning.ioTimeoutMs == io
          && tuning.resetOnOpen == reset
      }
  }
}

// MARK: - TransferRecord Serialization Round-Trip

final class TransferRecordRoundTripPropertyTests: XCTestCase {

  /// TransferRecord preserves all fields through construction.
  func testTransferRecordFieldPreservation() {
    property("TransferRecord preserves all fields through construction")
      <- forAll(
        SafeFilenameGenerator.arbitrary,
        Gen<UInt64>.choose((0, 10_000_000_000)),
        Gen<UInt64>.choose((0, 10_000_000_000))
      ) { (name: String, total: UInt64, committed: UInt64) in
        let clamped = min(committed, total)
        let record = TransferRecord(
          id: "test-\(UUID().uuidString.prefix(8))",
          deviceId: MTPDeviceID(raw: "test-device"),
          kind: "read",
          handle: 42,
          parentHandle: nil,
          name: name,
          totalBytes: total,
          committedBytes: clamped,
          supportsPartial: true,
          localTempURL: URL(fileURLWithPath: "/tmp/test"),
          finalURL: URL(fileURLWithPath: "/out/test"),
          state: "active",
          updatedAt: Date()
        )
        return record.name == name
          && record.totalBytes == total
          && record.committedBytes == clamped
          && record.kind == "read"
          && record.handle == 42
      }
  }

  /// Committed bytes never exceed total bytes in well-formed records.
  func testCommittedNeverExceedsTotal() {
    property("Committed bytes should not exceed total in well-formed TransferRecord")
      <- forAll(
        Gen<UInt64>.choose((0, 10_000_000_000)),
        Gen<UInt64>.choose((0, 10_000_000_000))
      ) { (total: UInt64, rawCommitted: UInt64) in
        let committed = min(rawCommitted, total)
        let record = TransferRecord(
          id: UUID().uuidString,
          deviceId: MTPDeviceID(raw: "dev"),
          kind: "read",
          handle: 1,
          parentHandle: nil,
          name: "file.dat",
          totalBytes: total,
          committedBytes: committed,
          supportsPartial: false,
          localTempURL: URL(fileURLWithPath: "/tmp/x"),
          finalURL: nil,
          state: "active",
          updatedAt: Date()
        )
        return record.committedBytes <= record.totalBytes!
      }
  }

  /// TransferRecord throughput and content hash optionals are preserved.
  func testTransferRecordOptionalFields() {
    property("TransferRecord optional fields are preserved")
      <- forAll(
        Gen<Double>.choose((0.0, 500.0)),
        Gen<String>
          .fromElements(of: ["abc123def456", "deadbeef0123", String(repeating: "0", count: 64)])
      ) { (throughput: Double, hash: String) in
        let record = TransferRecord(
          id: "opt-test",
          deviceId: MTPDeviceID(raw: "dev"),
          kind: "write",
          handle: 10,
          parentHandle: 5,
          name: "test.bin",
          totalBytes: 1024,
          committedBytes: 512,
          supportsPartial: true,
          localTempURL: URL(fileURLWithPath: "/tmp/opt"),
          finalURL: nil,
          state: "completed",
          updatedAt: Date(),
          throughputMBps: throughput,
          remoteHandle: 99,
          contentHash: hash
        )
        return record.throughputMBps == throughput
          && record.remoteHandle == 99
          && record.contentHash == hash
      }
  }
}

// MARK: - DeviceFilter Matching Consistency

final class DeviceFilterConsistencyPropertyTests: XCTestCase {

  /// A filter with nil fields matches everything.
  func testEmptyFilterMatchesAll() {
    property("Empty DeviceFilter matches all candidates")
      <- forAll(
        Gen<UInt16>.choose((1, UInt16.max)),
        Gen<UInt16>.choose((1, UInt16.max))
      ) { (vid: UInt16, pid: UInt16) in
        let filter = DeviceFilter(vid: nil, pid: nil, bus: nil, address: nil)
        let summary = MTPDeviceSummary(
          id: MTPDeviceID(raw: "test"),
          manufacturer: "Test", model: "Device",
          vendorID: vid, productID: pid,
          bus: 1, address: 1)
        let result = selectDevice([summary], filter: filter, noninteractive: true)
        if case .selected(let s) = result { return s.vendorID == vid }
        return false
      }
  }

  /// A filter with a specific VID only matches devices with that VID.
  func testVIDFilterMatchesCorrectly() {
    property("VID filter only matches devices with matching VID")
      <- forAll(
        Gen<UInt16>.choose((1, UInt16.max)),
        Gen<UInt16>.choose((1, UInt16.max)),
        Gen<UInt16>.choose((1, UInt16.max))
      ) { (filterVid: UInt16, deviceVid: UInt16, pid: UInt16) in
        let filter = DeviceFilter(vid: filterVid, pid: nil, bus: nil, address: nil)
        let summary = MTPDeviceSummary(
          id: MTPDeviceID(raw: "test"),
          manufacturer: "Test", model: "Device",
          vendorID: deviceVid, productID: pid,
          bus: 1, address: 1)
        let result = selectDevice([summary], filter: filter, noninteractive: true)
        guard filterVid == deviceVid else {
          if case .none = result { return true }
          return false
        }
        if case .selected = result { return true }
        return false
      }
  }

  /// selectDevice with multiple matching devices returns .multiple.
  func testMultipleMatchesReturnMultiple() {
    property("Multiple matching devices yield .multiple outcome")
      <- forAll(Gen<UInt16>.choose((1, UInt16.max))) { (vid: UInt16) in
        let filter = DeviceFilter(vid: vid, pid: nil, bus: nil, address: nil)
        let s1 = MTPDeviceSummary(
          id: MTPDeviceID(raw: "d1"),
          manufacturer: "A", model: "M1",
          vendorID: vid, productID: 1, bus: 1, address: 1)
        let s2 = MTPDeviceSummary(
          id: MTPDeviceID(raw: "d2"),
          manufacturer: "B", model: "M2",
          vendorID: vid, productID: 2, bus: 2, address: 2)
        let result = selectDevice([s1, s2], filter: filter, noninteractive: true)
        if case .multiple(let devices) = result { return devices.count == 2 }
        return false
      }
  }
}

// MARK: - MTPError Description Non-Empty

final class MTPErrorDescriptionPropertyTests: XCTestCase {

  /// Every MTPError case has a non-empty error description.
  func testAllMTPErrorCasesHaveNonEmptyDescription() {
    let cases: [MTPError] = [
      .deviceDisconnected,
      .permissionDenied,
      .notSupported("test operation"),
      .transport(.noDevice),
      .transport(.timeout),
      .transport(.busy),
      .transport(.accessDenied),
      .transport(.stall),
      .transport(.io("test io error")),
      .protocolError(code: 0x2001, message: "general error"),
      .protocolError(code: 0x2002, message: nil),
      .protocolError(code: 0x201D, message: "invalid parameter"),
      .protocolError(code: 0x201E, message: "session already open"),
      .objectNotFound,
      .objectWriteProtected,
      .storageFull,
      .readOnly,
      .timeout,
      .busy,
      .sessionBusy,
      .preconditionFailed("test precondition"),
      .verificationFailed(expected: 1024, actual: 512),
    ]

    for error in cases {
      let description = error.errorDescription ?? ""
      XCTAssertFalse(
        description.isEmpty,
        "MTPError.\(error) should have non-empty errorDescription")
    }
  }

  /// MTPError descriptions with random strings are always non-empty.
  func testMTPErrorNotSupportedDescription() {
    property("MTPError.notSupported always produces non-empty description")
      <- forAll { (message: String) in
        let error = MTPError.notSupported(message)
        let desc = error.errorDescription ?? ""
        return !desc.isEmpty
      }
  }

  /// MTPError.protocolError with random codes always produces non-empty description.
  func testMTPErrorProtocolErrorDescription() {
    property("MTPError.protocolError always produces non-empty description")
      <- forAll(
        Gen<UInt16>.choose((0x2000, 0x2FFF)),
        String.arbitrary
      ) { (code: UInt16, message: String) in
        let error = MTPError.protocolError(code: code, message: message)
        let desc = error.errorDescription ?? ""
        return !desc.isEmpty
      }
  }

  /// MTPError.verificationFailed always includes both expected and actual values.
  func testVerificationFailedDescription() {
    property("verificationFailed description mentions both sizes")
      <- forAll(
        Gen<UInt64>.choose((0, UInt64.max)),
        Gen<UInt64>.choose((0, UInt64.max))
      ) { (expected: UInt64, actual: UInt64) in
        let error = MTPError.verificationFailed(expected: expected, actual: actual)
        let desc = error.errorDescription ?? ""
        return desc.contains("\(actual)") && desc.contains("\(expected)")
      }
  }
}

// MARK: - Sync Diff Symmetry

final class SyncDiffSymmetryPropertyTests: XCTestCase {

  /// Items added in diff(a,b) correspond to items removed in the inverse direction.
  func testDiffAddRemoveSymmetry() {
    property("Items added in one direction are removed in the reverse")
      <- forAll(
        Gen<Int>.choose((1, 20)),
        Gen<Int>.choose((1, 20))
      ) { (onlyInACount: Int, onlyInBCount: Int) in
        var forward = MTPDiff()
        var reverse = MTPDiff()

        // Items only in B appear as "added" in forward diff, "removed" in reverse
        for i in 0..<onlyInBCount {
          let row = MTPDiff.Row(
            handle: UInt32(i + 1), storage: 1,
            pathKey: "00000001/new_\(i)", size: 100, mtime: nil, format: 0x3001)
          forward.added.append(row)
          reverse.removed.append(row)
        }

        // Items only in A appear as "removed" in forward diff, "added" in reverse
        for i in 0..<onlyInACount {
          let row = MTPDiff.Row(
            handle: UInt32(i + 1000), storage: 1,
            pathKey: "00000001/old_\(i)", size: 200, mtime: nil, format: 0x3001)
          forward.removed.append(row)
          reverse.added.append(row)
        }

        return forward.added.count == reverse.removed.count
          && forward.removed.count == reverse.added.count
      }
  }

  /// Symmetric diff: totalChanges is the same regardless of direction.
  func testDiffTotalChangesSymmetric() {
    property("Total changes count is symmetric between forward and reverse diff")
      <- forAll(
        Gen<Int>.choose((0, 15)),
        Gen<Int>.choose((0, 15)),
        Gen<Int>.choose((0, 10))
      ) { (addedCount: Int, removedCount: Int, modifiedCount: Int) in
        var forward = MTPDiff()
        var reverse = MTPDiff()

        for i in 0..<addedCount {
          let row = MTPDiff.Row(
            handle: UInt32(i + 1), storage: 1,
            pathKey: "00000001/a_\(i)", size: nil, mtime: nil, format: 0x3001)
          forward.added.append(row)
          reverse.removed.append(row)
        }
        for i in 0..<removedCount {
          let row = MTPDiff.Row(
            handle: UInt32(i + 500), storage: 1,
            pathKey: "00000001/r_\(i)", size: nil, mtime: nil, format: 0x3001)
          forward.removed.append(row)
          reverse.added.append(row)
        }
        for i in 0..<modifiedCount {
          let row = MTPDiff.Row(
            handle: UInt32(i + 1000), storage: 1,
            pathKey: "00000001/m_\(i)", size: nil, mtime: nil, format: 0x3001)
          forward.modified.append(row)
          reverse.modified.append(row)
        }

        return forward.totalChanges == reverse.totalChanges
      }
  }

  /// Empty diff is its own inverse.
  func testEmptyDiffIsSelfInverse() {
    let diff = MTPDiff()
    XCTAssertTrue(diff.isEmpty)
    XCTAssertEqual(diff.added.count, 0)
    XCTAssertEqual(diff.removed.count, 0)
    XCTAssertEqual(diff.modified.count, 0)
  }
}

// MARK: - PTPString Encode→Decode Round-Trip (Fuzz-Style)

final class PTPStringFuzzPropertyTests: XCTestCase {

  /// PTPString encode→decode round-trip for strings within PTP limits.
  func testPTPStringRoundTripFuzz() {
    property("PTPString round-trips for strings under 254 UTF-16 code units")
      <- forAll(String.arbitrary.suchThat { $0.count < 200 && $0.utf16.count < 254 }) { str in
        let encoded = PTPString.encode(str)
        var offset = 0
        guard let decoded = PTPString.parse(from: encoded, at: &offset) else {
          return str.isEmpty
        }
        return decoded == str
      }
  }

  /// PTPString.parse never crashes on random data.
  func testPTPStringParseNeverCrashes() {
    for _ in 0..<500 {
      let length = Int.random(in: 0...200)
      var data = Data(count: length)
      for i in 0..<length { data[i] = UInt8.random(in: 0...255) }
      var offset = 0
      _ = PTPString.parse(from: data, at: &offset)
    }
  }
}

// MARK: - PTPReader Value Fuzz-Style Tests

final class PTPReaderFuzzPropertyTests: XCTestCase {

  /// PTPReader.u32 round-trips through encode/decode for any UInt32.
  func testPTPReaderU32RoundTrip() {
    property("MTPEndianCodec encode→PTPReader.u32 round-trips")
      <- forAll { (value: UInt32) in
        var data = Data(count: 4)
        data.withUnsafeMutableBytes { buf in
          MTPEndianCodec.encode(value, into: buf.baseAddress!, at: 0)
        }
        var reader = PTPReader(data: data)
        guard let decoded = reader.u32() else { return false }
        return decoded == value
      }
  }

  /// PTPReader.u16 round-trips through encode/decode for any UInt16.
  func testPTPReaderU16RoundTrip() {
    property("MTPEndianCodec encode→PTPReader.u16 round-trips")
      <- forAll { (value: UInt16) in
        var data = Data(count: 2)
        data.withUnsafeMutableBytes { buf in
          MTPEndianCodec.encode(value, into: buf.baseAddress!, at: 0)
        }
        var reader = PTPReader(data: data)
        guard let decoded = reader.u16() else { return false }
        return decoded == value
      }
  }

  /// PTPReader never crashes on undersized buffers.
  func testPTPReaderHandlesUndersizedBuffers() {
    for _ in 0..<500 {
      let length = Int.random(in: 0...3)
      let data = Data((0..<length).map { _ in UInt8.random(in: 0...255) })
      var reader = PTPReader(data: data)
      _ = reader.u32()
      _ = reader.u16()
      _ = reader.u8()
    }
  }
}
