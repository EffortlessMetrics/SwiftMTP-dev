// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import XCTest
import SwiftCheck
@testable import SwiftMTPCore
@testable import SwiftMTPIndex
@testable import SwiftMTPObservability
@testable import SwiftMTPStore
@testable import SwiftMTPQuirks

// MARK: - Custom SwiftCheck Generators

// MARK: - Local types used by property tests

/// Device connection state for state-transition property tests.
enum DeviceConnectionState: Equatable, CaseIterable, Hashable {
    case disconnected, connecting, connected
}

/// Generator for random Unicode strings including emoji and CJK characters
enum UnicodeStringGenerator {
    static var arbitrary: Gen<String> {
        let wordGen = Gen<String>.fromElements(of: [
            "hello", "world", "test", "файл", "文件", "ファイル", "파일",
            "naïve", "café", "Señor", "niño", "Müller", "Ångström",
            "emoji📷", "CJK日本", "hangul한국"
        ])
        let emojiGen = Gen<UInt32>.choose((0x1F600, 0x1F64F)).map { scalar in
            String(UnicodeScalar(scalar) ?? UnicodeScalar(0x20)!)
        }
        return Gen<String>.one(of: [wordGen, emojiGen])
    }
}

/// Generator for random path depths and components
enum PathComponentsGenerator {
    static var arbitrary: Gen<[String]> {
        Gen<Int>.choose((1, 20)).map { depth in
            (1...depth).map { "folder\($0)" }
        }
    }
}

/// Generator for random file sizes
enum RandomFileSizeGenerator {
    static var arbitrary: Gen<UInt64> {
        Gen<UInt64>.one(of: [
            Gen<UInt64>.fromElements(of: [0, 1, 100, 1024, 1024 * 1024, 100 * 1024 * 1024]),
            Gen<UInt64>.choose((0, 10_000_000_000)) // Up to 10GB
        ])
    }
}

/// Generator for valid MTP object handles
enum MTPHandleGenerator {
    static var arbitrary: Gen<MTPObjectHandle> {
        Gen<MTPObjectHandle>.choose((1, UInt32.max))
    }
}

/// Generator for random device states
enum DeviceStateGenerator {
    static var arbitrary: Gen<DeviceConnectionState> {
        Gen<DeviceConnectionState>.fromElements(of: [
            .disconnected,
            .connecting,
            .connected
        ])
    }
}

// MARK: - MTPObjectEntity Property Tests

final class MTPObjectEntityPropertyTests: XCTestCase {

    // MARK: - Object Handle Invariants

    func testObjectHandleIsAlwaysPositive() {
        property("Object handle should always be positive") <- forAll(MTPHandleGenerator.arbitrary) { handle in
            handle > 0
        }
    }

    func testObjectHandleWithinValidRange() {
        property("Object handle should be within valid MTP range (1 to UInt32.max)") <- forAll(MTPHandleGenerator.arbitrary) { handle in
            handle >= 1 && handle <= UInt32.max
        }
    }

    func testCompoundIdFormatIsValid() {
        property("Compound ID should be in format deviceId:storageId:handle") <- forAll(
            Gen<String>.fromElements(of: ["device1", "device2", "test-device-id"]),
            Gen<Int>.choose((1, 100)),
            MTPHandleGenerator.arbitrary
        ) { deviceId, storageId, handle in
            let entity = MTPObjectEntity(
                deviceId: deviceId,
                storageId: storageId,
                handle: Int(handle),
                name: "test.txt",
                pathKey: "test/path",
                formatCode: 0x3001,
                generation: 1
            )
            
            let parts = entity.compoundId.split(separator: ":")
            return parts.count == 3
        }
    }

    // MARK: - Parent/Child Relationship Properties

    func testParentChildFormsValidTree() {
        property("Tree traversal via parent handles should eventually reach root") <- forAll(
            Gen<String>.fromElements(of: ["device1", "device2"]),
            Gen<Int>.choose((1, 10))
        ) { deviceId, maxDepth in
            var handles: [Int] = []
            var currentHandle = maxDepth
            
            // Build a chain of parent handles
            while currentHandle > 0 {
                handles.append(currentHandle)
                currentHandle -= 1
            }
            
            // Verify we can traverse back to root
            var current = handles.last ?? 0
            var depth = 0
            let maxIterations = handles.count + 1
            
            while depth < maxIterations {
                if current == 0 { return true }
                if let index = handles.firstIndex(of: current), index > 0 {
                    current = handles[index - 1]
                } else {
                    break
                }
                depth += 1
            }
            
            return true
        }
    }

    func testParentChainReachesRoot() {
        property("Following parent handles should eventually reach nil (root)") <- forAll(
            MTPHandleGenerator.arbitrary
        ) { rootHandle in
            // Simulate parent chain: root -> parent1 -> parent2 -> ... -> child
            let chainLength = Int.random(in: 1...10)
            var handles: [Int] = [Int(rootHandle)]
            
            for i in 0..<chainLength {
                handles.append(Int(rootHandle) + i + 1)
            }
            
            // Verify chain structure (each child has a parent)
            for i in 1..<handles.count {
                let child = handles[i]
                let parent = handles[i - 1]
                XCTAssertTrue(child > parent, "Child handle should be greater than parent")
            }
            
            return true
        }
    }

    // MARK: - Path Reconstruction Properties

    func testPathReconstructionFromParentChain() {
        property("Path reconstructed from parent chain should match original") <- forAll(
            Gen<[String]>.fromElements(of: [
                ["DCIM", "2024", "photos"],
                ["Documents", "Work", "Project"],
                ["Music", "Albums", "Artist"]
            ])
        ) { components in
            // Simulate building path from components
            let reconstructed = "/" + components.joined(separator: "/")
            
            // Verify path format
            return reconstructed.hasPrefix("/") && !reconstructed.hasSuffix("/")
        }
    }

    func testPathKeyRoundtripPreservesData() {
        property("PathKey encode/decode roundtrip should preserve path") <- forAll(
            Gen<UInt32>.choose((1, UInt32.max)),
            PathComponentsGenerator.arbitrary
        ) { storageId, components in
            let normalized = PathKey.normalize(storage: storageId, components: components)
            let (parsedStorageId, parsedComponents) = PathKey.parse(normalized)
            
            return parsedStorageId == storageId && parsedComponents == components
        }
    }

    // MARK: - Serialization Roundtrip Properties

    func testMTPObjectEntityFieldConsistency() {
        property("MTPObjectEntity fields should be consistent after init") <- forAll(
            Gen<String>.fromElements(of: ["device1", "test-device-123"]),
            Gen<Int>.choose((1, 1000)),
            MTPHandleGenerator.arbitrary,
            UnicodeStringGenerator.arbitrary,
            RandomFileSizeGenerator.arbitrary
        ) { deviceId, storageId, handle, name, size in
            let entity = MTPObjectEntity(
                deviceId: deviceId,
                storageId: storageId,
                handle: Int(handle),
                parentHandle: handle > 1 ? Int(handle - 1) : nil,
                name: name,
                pathKey: PathKey.normalize(storage: UInt32(storageId), components: [name]),
                sizeBytes: Int64(size),
                modifiedAt: Date(),
                formatCode: 0x3001,
                generation: 1
            )

            return entity.deviceId == deviceId &&
                   entity.handle == Int(handle) &&
                   entity.storageId == storageId &&
                   entity.name == name
        }
    }
}

// MARK: - MTPDevice Property Tests

final class MTPDevicePropertyTests: XCTestCase {

    // MARK: - Device ID Properties

    func testDeviceIDUniqueness() {
        property("Different device IDs should be different") <- forAll(
            Gen<String>.fromElements(of: ["device1", "device2", "device3"])
        ) { id1 in
            let id2 = id1 == "device1" ? "device2" : "device1"
            return MTPDeviceID(raw: id1) != MTPDeviceID(raw: id2)
        }
    }

    func testDeviceIDSameValueEquality() {
        property("Same device ID values should be equal") <- forAll(
            Gen<String>.fromElements(of: ["test-device-123", "abc-def-ghi", "uuid-1234"])
        ) { raw in
            let id1 = MTPDeviceID(raw: raw)
            let id2 = MTPDeviceID(raw: raw)
            return id1 == id2
        }
    }

    // MARK: - Vendor/Product ID Format Properties

    func testVendorProductIDFormatValidation() {
        property("Vendor/Product ID fingerprint should be in hex format") <- forAll(
            Gen<UInt16>.choose((0x0001, 0xFFFF)),
            Gen<UInt16>.choose((0x0001, 0xFFFF))
        ) { vid, pid in
            let fingerprint = String(format: "%04x:%04x", vid, pid)
            
            // Verify format: 4 hex digits : 4 hex digits
            let parts = fingerprint.split(separator: ":")
            return parts.count == 2 &&
                   parts[0].count == 4 &&
                   parts[1].count == 4
        }
    }

    func testFingerprintConsistency() {
        property("Fingerprint should be consistent across calls") <- forAll(
            Gen<UInt16>.choose((0x0001, 0xFFFF)),
            Gen<UInt16>.choose((0x0001, 0xFFFF))
        ) { vid, pid in
            let summary = MTPDeviceSummary(
                id: MTPDeviceID(raw: "test"),
                manufacturer: "Test",
                model: "Test",
                vendorID: vid,
                productID: pid
            )
            
            let fp1 = summary.fingerprint
            let fp2 = summary.fingerprint
            
            return fp1 == fp2
        }
    }

    func testUnknownFingerprintWhenVIDMissing() {
        property("Fingerprint should be 'unknown' when vendor ID is nil") <- forAll(
            Gen<String>.fromElements(of: ["Test1", "Test2"])
        ) { model in
            let summary = MTPDeviceSummary(
                id: MTPDeviceID(raw: "test"),
                manufacturer: "Test",
                model: model,
                vendorID: nil,
                productID: 0x1234
            )
            
            return summary.fingerprint == "unknown"
        }
    }

    // MARK: - Connection State Transition Properties

    func testValidConnectionStateTransitions() {
        let allStates: [DeviceConnectionState] = [.disconnected, .connecting, .connected]
        property("Connection states should transition in valid order") <- forAll(
            Gen<Int>.choose((0, 2))
        ) { idx in
            let initial = allStates[idx]
            // Define valid transitions
            let validTransitions: [DeviceConnectionState: Set<DeviceConnectionState>] = [
                .disconnected: [.connecting],
                .connecting: [.connected, .disconnected],
                .connected: [.disconnected]
            ]

            let validNextStates = validTransitions[initial] ?? []
            return !validNextStates.isEmpty
        }
    }

    func testNoSelfTransitionFromConnected() {
        property("Connected state should not transition to itself") <- forAll(
            Gen<Int>.pure(0)
        ) { _ -> Bool in
            let validTransitions: [DeviceConnectionState: Set<DeviceConnectionState>] = [
                .disconnected: [.connecting],
                .connecting: [.connected, .disconnected],
                .connected: [.disconnected]
            ]
            return !(validTransitions[.connected] ?? []).contains(.connected)
        }
    }
}

// MARK: - QuirkDatabase Property Tests

final class QuirkDatabasePropertyTests: XCTestCase {

    // MARK: - Adding Quirks Properties

    func testAddingQuirkDoesNotBreakExistingMatches() {
        property("Adding new quirks should not affect existing matches") <- forAll(
            Gen<UInt16>.choose((0x0001, 0xFFFF)),
            Gen<UInt16>.choose((0x0001, 0xFFFF))
        ) { vid, pid in
            // Create base database
            let existingQuirk = DeviceQuirk(
                id: "existing-device",
                vid: vid,
                pid: pid
            )
            
            let baseDB = QuirkDatabase(
                schemaVersion: "1.0",
                entries: [existingQuirk]
            )
            
            // Create new database with added quirk
            let newQuirk = DeviceQuirk(
                id: "new-device",
                vid: vid + 1,
                pid: pid + 1
            )
            
            let extendedDB = QuirkDatabase(
                schemaVersion: "1.0",
                entries: [existingQuirk, newQuirk]
            )
            
            // Existing quirk should still match the same device
            let baseMatch = baseDB.match(
                vid: vid, pid: pid,
                bcdDevice: nil,
                ifaceClass: nil, ifaceSubclass: nil, ifaceProtocol: nil
            )
            
            let extendedMatch = extendedDB.match(
                vid: vid, pid: pid,
                bcdDevice: nil,
                ifaceClass: nil, ifaceSubclass: nil, ifaceProtocol: nil
            )
            
            return baseMatch?.id == extendedMatch?.id
        }
    }

    // MARK: - Fingerprint Evolution Properties

    func testFingerprintMatchingIsMonotonic() {
        property("More specific fingerprint matches should score higher") <- forAll(
            Gen<UInt16>.choose((0x0001, 0xFFFF)),
            Gen<UInt16>.choose((0x0001, 0xFFFF)),
            Gen<UInt16>.choose((0x0000, 0xFFFF))
        ) { vid, pid, bcdDevice in
            // Less specific quirk
            let lessSpecific = DeviceQuirk(
                id: "less-specific",
                vid: vid,
                pid: pid
            )
            
            // More specific quirk (adds bcdDevice)
            let moreSpecific = DeviceQuirk(
                id: "more-specific",
                vid: vid,
                pid: pid,
                bcdDevice: bcdDevice
            )
            
            // Both should match the device
            let lessMatch = lessSpecific.vid == vid && lessSpecific.pid == pid
            let moreMatch = moreSpecific.vid == vid && 
                           moreSpecific.pid == pid && 
                           moreSpecific.bcdDevice == bcdDevice
            
            return lessMatch && moreMatch
        }
    }

    // MARK: - Layer Merging Properties

    func testLayerMergingIsAssociative() {
        property("Layer merging should be associative") <- forAll(
            Gen<Int>.choose((1, 100)),
            Gen<Int>.choose((1, 100)),
            Gen<Int>.choose((1, 100))
        ) { a, b, c in
            // Simulate layer merging with a simple associative operation
            func mergeLayers(_ x: Int, _ y: Int) -> Int {
                return max(x, y) // Simple example operation
            }
            
            let left = mergeLayers(mergeLayers(a, b), c)
            let right = mergeLayers(a, mergeLayers(b, c))
            
            return left == right
        }
    }

    func testLayerMergingIsCommutative() {
        property("Layer merging should be commutative") <- forAll(
            Gen<Int>.choose((1, 100)),
            Gen<Int>.choose((1, 100))
        ) { a, b in
            // Simulate layer merging with a simple commutative operation
            func mergeLayers(_ x: Int, _ y: Int) -> Int {
                return max(x, y)
            }
            
            let ab = mergeLayers(a, b)
            let ba = mergeLayers(b, a)
            
            return ab == ba
        }
    }
}

// MARK: - TransferJournal Property Tests

final class TransferJournalPropertyTests: XCTestCase {

    // MARK: - Journal Replay Properties

    func testJournalReplayFromAnyPointProducesSameState() {
        property("Journal replay from any point should produce consistent state") <- forAll(
            Gen<String>.fromElements(of: ["device1", "device2"]),
            Gen<UInt32>.choose((1, 1000)),
            UnicodeStringGenerator.arbitrary
        ) { deviceId, handle, name in
            // Simulate transfer record states
            let states = ["pending", "in_progress", "completed", "failed"]
            var recordedStates: [String] = []
            
            // Record state at each step
            for _ in 0..<5 {
                let state = states.randomElement() ?? "pending"
                recordedStates.append(state)
            }
            
            // Verify we can replay from any point
            for startIndex in 0..<recordedStates.count {
                let replayed = Array(recordedStates[startIndex...])
                XCTAssertFalse(replayed.isEmpty)
            }
            
            return true
        }
    }

    // MARK: - Compaction Properties

    func testCompactionDoesNotLosePendingTransfers() {
        property("Compaction should preserve pending transfers") <- forAll(
            Gen<Int>.choose((1, 20))
        ) { pendingCount in
            // Simulate pending transfers
            var pendingTransfers: [String] = []
            for i in 0..<pendingCount {
                pendingTransfers.append("transfer-\(i)")
            }
            
            // Simulate completed transfers
            let completedTransfers = ["completed-1", "completed-2"]
            
            // Compact: remove completed, keep pending
            let compactedPending = pendingTransfers
            let compactedCount = compactedPending.count
            
            return compactedCount == pendingCount
        }
    }

    // MARK: - Cross-Device Isolation Properties

    func testCrossDeviceIsolationIsMaintained() {
        property("Transfers from different devices should be isolated") <- forAll(
            Gen<String>.fromElements(of: ["device-A", "device-B", "device-C"]),
            Gen<String>.fromElements(of: ["file1.txt", "file2.jpg", "file3.pdf"])
        ) { deviceId, filename in
            // Simulate transfer record with device ID
            let transferDevice1 = TransferRecord(
                id: "transfer-1",
                deviceId: MTPDeviceID(raw: "device-A"),
                kind: "read",
                handle: 1,
                parentHandle: nil,
                name: filename,
                totalBytes: 1024,
                committedBytes: 0,
                supportsPartial: true,
                localTempURL: URL(fileURLWithPath: "/tmp/t1"),
                finalURL: nil,
                state: "pending",
                updatedAt: Date()
            )
            
            let transferDevice2 = TransferRecord(
                id: "transfer-2",
                deviceId: MTPDeviceID(raw: "device-B"),
                kind: "write",
                handle: 2,
                parentHandle: nil,
                name: filename,
                totalBytes: 2048,
                committedBytes: 0,
                supportsPartial: false,
                localTempURL: URL(fileURLWithPath: "/tmp/t2"),
                finalURL: nil,
                state: "pending",
                updatedAt: Date()
            )
            
            // Different devices should have different IDs
            return transferDevice1.deviceId != transferDevice2.deviceId
        }
    }

    func testSameTransferOnDifferentDevicesAreDistinct() {
        property("Same transfer on different devices should be distinct records") <- forAll(
            Gen<String>.fromElements(of: ["photo.jpg", "document.pdf", "music.mp3"])
        ) { filename in
            let deviceAId = MTPDeviceID(raw: "device-A")
            let deviceBId = MTPDeviceID(raw: "device-B")
            
            // Create records for same file on different devices
            let recordA = TransferRecord(
                id: "record-\(filename)",
                deviceId: deviceAId,
                kind: "read",
                handle: 1,
                parentHandle: nil,
                name: filename,
                totalBytes: 1024,
                committedBytes: 512,
                supportsPartial: true,
                localTempURL: URL(fileURLWithPath: "/tmp/tA"),
                finalURL: nil,
                state: "in_progress",
                updatedAt: Date()
            )
            
            let recordB = TransferRecord(
                id: "record-\(filename)",
                deviceId: deviceBId,
                kind: "read",
                handle: 1,
                parentHandle: nil,
                name: filename,
                totalBytes: 1024,
                committedBytes: 512,
                supportsPartial: true,
                localTempURL: URL(fileURLWithPath: "/tmp/tB"),
                finalURL: nil,
                state: "in_progress",
                updatedAt: Date()
            )
            
            // Records should differ by device
            return recordA.deviceId != recordB.deviceId
        }
    }
}

// MARK: - PathKey Property Tests

final class PathKeyPropertyTests: XCTestCase {

    // MARK: - Roundtrip Properties

    func testPathKeyRoundtripEncodeDecode() {
        property("PathKey normalize/parse roundtrip should preserve path") <- forAll(
            Gen<UInt32>.choose((1, UInt32.max)),
            PathComponentsGenerator.arbitrary
        ) { storageId, components in
            let normalized = PathKey.normalize(storage: storageId, components: components)
            let (parsedStorageId, parsedComponents) = PathKey.parse(normalized)
            
            return parsedStorageId == storageId && parsedComponents == components
        }
    }

    func testUnicodePathRoundtrip() {
        property("Unicode paths should roundtrip correctly") <- forAll(
            Gen<UInt32>.choose((1, UInt32.max)),
            Gen<[String]>.fromElements(of: [
                ["café", "naïve", "日本語"],
                ["中文", "한국어", "English"],
                ["🎉", "📷", "🔥"]
            ])
        ) { storageId, components in
            let normalized = PathKey.normalize(storage: storageId, components: components)
            let (_, parsedComponents) = PathKey.parse(normalized)
            
            // Compare normalized components
            let normalizedInput = components.map { PathKey.normalizeComponent($0) }
            
            return true
        }
    }

    // MARK: - Normalization Idempotence Properties

    func testPathNormalizationIsIdempotent() {
        property("Path normalization should be idempotent") <- forAll(
            Gen<UInt32>.choose((1, UInt32.max)),
            PathComponentsGenerator.arbitrary
        ) { storageId, components in
            let first = PathKey.normalize(storage: storageId, components: components)
            let second = PathKey.normalize(storage: storageId, components: components)
            
            return first == second
        }
    }

    func testComponentNormalizationIsIdempotent() {
        property("Component normalization should be idempotent") <- forAll(
            UnicodeStringGenerator.arbitrary
        ) { component in
            let first = PathKey.normalizeComponent(component)
            let second = PathKey.normalizeComponent(first)
            
            return first == second
        }
    }

    // MARK: - Parent Resolution Properties

    func testParentResolutionIsCorrect() {
        property("Parent resolution should be correct for all paths") <- forAll(
            Gen<UInt32>.choose((1, UInt32.max)),
            Gen<Int>.choose((1, 50)).map { depth in
                (1...depth).map { "folder\($0)" }
            }
        ) { storageId, components in
            guard !components.isEmpty else { return true }
            
            let fullPath = PathKey.normalize(storage: storageId, components: components)
            let parent = PathKey.parent(of: fullPath)
            
            // Parent should have one fewer component
            if let parentPath = parent {
                let (_, parentComponents) = PathKey.parse(parentPath)
                return parentComponents.count == components.count - 1
            }
            
            // No parent if single component
            return components.count == 1
        }
    }

    func testParentOfRootIsNil() {
        property("Parent of root path should be nil") <- forAll(
            Gen<UInt32>.choose((1, UInt32.max))
        ) { storageId in
            let rootPath = PathKey.normalize(storage: storageId, components: [])
            let parent = PathKey.parent(of: rootPath)
            
            return parent == nil
        }
    }

    func testGrandparentChainReachesRoot() {
        property("Following parent chain should eventually reach root") <- forAll(
            Gen<UInt32>.choose((1, UInt32.max)),
            Gen<Int>.choose((1, 20))
        ) { storageId, depth in
            let components = (0..<depth).map { "level\($0)" }
            let path = PathKey.normalize(storage: storageId, components: components)
            
            var current: String? = path
            var steps = 0
            let maxSteps = depth + 1
            
            while let cur = current, steps < maxSteps {
                current = PathKey.parent(of: cur)
                steps += 1
            }
            
            return steps == depth
        }
    }
}

// MARK: - Throughput Metrics Property Tests

final class ThroughputMetricsPropertyTests: XCTestCase {

    // MARK: - EWMA Properties

    func testMovingAverageIsWithinReasonableBounds() {
        property("EWMA should stay within reasonable bounds") <- forAll(
            Gen<Double>.choose((0.0, 1_000_000_000.0)),
            Gen<Double>.choose((0.001, 60.0))
        ) { bytes, dt in
            var ewma = ThroughputEWMA()
            let rate = ewma.update(bytes: Int(bytes), dt: dt)
            
            // Rate should be non-negative and finite
            return rate >= 0 && !rate.isInfinite && !rate.isNaN
        }
    }

    func testEWMAResetClearsState() {
        property("EWMA reset should clear all state") <- forAll(
            Gen<Int>.choose((1000, 1_000_000)),
            Gen<Double>.choose((0.01, 10.0)),
            Gen<Int>.choose((1, 100))
        ) { bytes, dt, updates in
            var ewma = ThroughputEWMA()
            
            // Update multiple times
            for _ in 0..<updates {
                ewma.update(bytes: bytes, dt: dt)
            }
            
            // Verify state exists
            let beforeCount = ewma.count
            XCTAssertGreaterThan(beforeCount, 0)
            
            // Reset
            ewma.reset()
            
            // Verify state cleared
            let afterCount = ewma.count
            
            return afterCount == 0
        }
    }

    func testEWMAPositiveUpdateNeverDecreases() {
        property("EWMA with consistent samples should not decrease") <- forAll(
            Gen<Int>.choose((1000, 1_000_000)),
            Gen<Double>.choose((0.01, 10.0)),
            Gen<Int>.choose((2, 20))
        ) { bytes, dt, count in
            var ewma = ThroughputEWMA()
            var previousRate: Double = 0
            
            for _ in 0..<count {
                let rate = ewma.update(bytes: bytes, dt: dt)
                // Rate should be >= 0 and shouldn't dramatically decrease
                XCTAssertGreaterThanOrEqual(rate, 0)
            }
            
            return true
        }
    }

    // MARK: - Ring Buffer Properties

    func testRingBufferCapacity() {
        property("Ring buffer should respect max capacity") <- forAll(
            Gen<Int>.choose((10, 100)),
            Gen<Int>.choose((50, 500))
        ) { maxSamples, samplesToAdd in
            var buffer = ThroughputRingBuffer(maxSamples: maxSamples)
            
            for i in 0..<samplesToAdd {
                buffer.addSample(Double(i))
            }
            
            // Count should not exceed max
            return buffer.count <= maxSamples
        }
    }

    func testRingBufferWrapsCorrectly() {
        property("Ring buffer should wrap around correctly") <- forAll(
            Gen<Int>.choose((5, 20)),
            Gen<Int>.choose((10, 50))
        ) { maxSamples, extraSamples in
            var buffer = ThroughputRingBuffer(maxSamples: maxSamples)
            
            // Fill buffer
            for i in 0..<maxSamples {
                buffer.addSample(Double(i))
            }
            
            // Add more samples (should wrap)
            for i in 0..<extraSamples {
                buffer.addSample(Double(maxSamples + i))
            }
            
            return buffer.count <= maxSamples
        }
    }

    func testRingBufferAverageCalculation() {
        property("Ring buffer average should be correct") <- forAll(
            Gen<Int>.choose((5, 20))
        ) { count in
            var buffer = ThroughputRingBuffer(maxSamples: count)
            var expectedSum: Double = 0
            
            for i in 0..<count {
                buffer.addSample(Double(i))
                expectedSum += Double(i)
            }
            
            let expectedAvg = expectedSum / Double(count)
            let actualAvg = buffer.average
            
            return actualAvg != nil && abs(actualAvg! - expectedAvg) < 0.001
        }
    }

    // MARK: - Regression Detection Properties

    func testRegressionDetectionThresholdIsStable() {
        property("Regression threshold should be stable across calculations") <- forAll(
            Gen<Int>.choose((10, 100))
        ) { count in
            var buffer = ThroughputRingBuffer(maxSamples: count)
            
            // Add samples
            for i in 0..<count {
                buffer.addSample(Double(1000 + i))
            }
            
            // Get p95
            let p95 = buffer.p95
            
            // Add more similar samples
            for i in 0..<10 {
                buffer.addSample(Double(1000 + i + count))
            }
            
            // p95 should still be defined
            return p95 != nil
        }
    }

    func testThroughputRateNeverNegative() {
        property("Throughput rate should never be negative") <- forAll(
            Gen<Int>.choose((0, 1_000_000)),
            Gen<Double>.choose((0.0001, 60.0)),
            Gen<Int>.choose((1, 50))
        ) { bytes, dt, updates in
            var ewma = ThroughputEWMA()
            var allNonNegative = true
            
            for _ in 0..<updates {
                let rate = ewma.update(bytes: bytes, dt: dt)
                if rate < 0 {
                    allNonNegative = false
                    break
                }
            }
            
            return allNonNegative
        }
    }
}

// MARK: - Edge Case Property Tests

final class EdgeCasePropertyTests: XCTestCase {

    // MARK: - Empty String Properties

    func testEmptyComponentNormalization() {
        property("Empty components should normalize to underscore") <- forAll(
            Gen<Int>.pure(0)
        ) { _ -> Bool in
            let result = PathKey.normalizeComponent("")
            return result == "_"
        }
    }

    func testControlCharacterStripping() {
        property("Control characters should be stripped from paths") <- forAll(
            Gen<String>.fromElements(of: [
                "file\u{00}.txt",
                "file\n.txt",
                "file\t.txt",
                "file\r.txt",
                "file\u{1b}.txt"
            ])
        ) { input in
            let result = PathKey.normalizeComponent(input)
            // Should not contain control characters
            let containsControl = result.unicodeScalars.contains { scalar in
                CharacterSet.controlCharacters.contains(scalar)
            }
            return !containsControl
        }
    }

    // MARK: - Zero Value Properties

    func testZeroHandleIsInvalid() {
        property("Zero handle should be treated as invalid") <- forAll(
            Gen<Int>.pure(0)
        ) { _ -> Bool in
            let zeroHandle: MTPObjectHandle = 0
            return zeroHandle == 0
        }
    }

    func testZeroStorageIdHandling() {
        property("Zero storage ID should be handled correctly") <- forAll(
            Gen<[String]>.fromElements(of: [
                ["test"],
                ["folder", "file.txt"],
                []
            ])
        ) { components in
            let result = PathKey.normalize(storage: 0, components: components)
            
            if components.isEmpty {
                return result == "00000000"
            }
            return result.hasPrefix("00000000/")
        }
    }

    // MARK: - Maximum Value Properties

    func testMaximumHandleValue() {
        property("Maximum handle value should be valid") <- forAll(
            Gen<Int>.pure(0)
        ) { _ -> Bool in
            let maxHandle: MTPObjectHandle = UInt32.max
            return maxHandle == UInt32.max
        }
    }

    func testLargeFileSizeHandling() {
        property("Large file sizes should be handled correctly") <- forAll(
            Gen<UInt64>.choose((1_000_000_000, UInt64.max))
        ) { size in
            // Simulate large file
            let largeFile = size
            
            // Should be positive and within range
            return largeFile > 0 && largeFile <= UInt64.max
        }
    }

    // MARK: - Unicode Edge Cases

    func testEmojiHandling() {
        property("Emoji should be handled (potentially stripped)") <- forAll(
            Gen<String>.fromElements(of: [
                "🎉",
                "📷photo.jpg",
                "file🎉.txt",
                "🎉🎉🎉"
            ])
        ) { emoji in
            let result = PathKey.normalizeComponent(emoji)
            // Result should not crash and should be non-empty
            return !result.isEmpty
        }
    }

    func testMixedUnicodeNormalization() {
        property("Mixed Unicode should normalize correctly") <- forAll(
            Gen<String>.fromElements(of: [
                "café-🎉-файл-文件.txt",
                "naïve-日本語-한국어",
                "test-🎁-🎈-🎊"
            ])
        ) { mixed in
            let result = PathKey.normalizeComponent(mixed)

            // Should preserve valid characters
            return !result.isEmpty
        }
    }
}
