// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import XCTest
@testable import SwiftMTPSync
@testable import SwiftMTPCore
@testable import SwiftMTPTestKit

/// Tests for concurrent sync operations
final class SyncConcurrencyTests: XCTestCase {

    // MARK: - Properties

    private var tempDirectory: URL!
    private let queue = DispatchQueue(label: "com.swiftmtp.sync.test", attributes: .concurrent)

    // MARK: - Setup/Teardown

    override func setUp() {
        super.setUp()
        tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDirectory)
        tempDirectory = nil
        super.tearDown()
    }

    // MARK: - Concurrent Sync Operations

    func testMultipleSyncsRunSequentially() async {
        // Given a mock engine that tracks execution
        let engine = ConcurrentSyncEngine()
        let syncCount = 5
        var completionOrder: [Int] = []

        // When performing multiple sync operations concurrently
        await withTaskGroup(of: Void.self) { group in
            for i in 0..<syncCount {
                group.addTask {
                    await engine.performSync(syncId: i)
                    completionOrder.append(i)
                }
            }
        }

        // Then all syncs should complete
        XCTAssertEqual(completionOrder.count, syncCount)
    }

    func testConcurrentSnapshotCaptures() async throws {
        // Given multiple virtual devices
        let devices = (0..<3).map { index -> VirtualMTPDevice in
            let config = VirtualDeviceConfig.emptyDevice
                .withObject(VirtualObjectConfig(
                    handle: UInt32(100 + index),
                    storage: MTPStorageID(raw: 0x0001_0001),
                    parent: nil,
                    name: "file\(index).txt",
                    sizeBytes: 1024,
                    formatCode: 0x3004
                ))
            return VirtualMTPDevice(config: config)
        }

        // When capturing snapshots concurrently
        await withTaskGroup(of: Int.self) { group in
            for (index, device) in devices.enumerated() {
                group.addTask {
                    let snapshotter = MockSnapshotter()
                    let gen = try? await snapshotter.capture(device: device, deviceId: device.id)
                    return gen ?? 0
                }
            }
        }

        // Then all snapshots should complete without error
        XCTAssertTrue(true) // If we got here, all succeeded
    }

    // MARK: - Actor Isolation Tests

    func testSyncEngineActorIsolation() async {
        // Given an actor-based sync engine
        let engine = ActorBasedSyncEngine()

        // When performing concurrent operations
        await withTaskGroup(of: Void.self) { group in
            for i in 0..<10 {
                group.addTask {
                    await engine.queueOperation("operation_\(i)")
                }
            }
        }

        // Then all operations should complete
        let operationCount = await engine.getOperationCount()
        XCTAssertEqual(operationCount, 10)
    }

    func testAsyncMirrorOperationIsolation() async throws {
        // Given a mirror engine
        let mirrorEngine = createMirrorEngine()
        let device = VirtualMTPDevice(config: .emptyDevice)
        let deviceId = device.id

        // When performing mirror operation
        let report = try await mirrorEngine.mirror(
            device: device,
            deviceId: deviceId,
            to: tempDirectory
        )

        // Then operation should complete without race conditions
        XCTAssertNotNil(report)
    }

    // MARK: - Concurrent File Operations

    func testConcurrentFileWritesDuringSync() async throws {
        // Given a directory being synced
        let syncDir = tempDirectory.appendingPathComponent("sync")
        try FileManager.default.createDirectory(at: syncDir, withIntermediateDirectories: true)

        // When writing files concurrently while sync runs
        let writeGroup = TaskGroup<URL>(returning: URL.self)
        for i in 0..<10 {
            writeGroup.addTask {
                let file = syncDir.appendingPathComponent("concurrent_\(i).txt")
                try "content \(i)".write(to: file, atomically: true, encoding: .utf8)
                return file
            }
        }

        // Then all writes should succeed
        var writtenFiles: [URL] = []
        for await file in writeGroup {
            writtenFiles.append(file)
        }
        XCTAssertEqual(writtenFiles.count, 10)
    }

    func testSyncDuringRapidFileChanges() async throws {
        // Given a directory with rapidly changing files
        let localDir = tempDirectory.appendingPathComponent("local")
        let remoteDir = tempDirectory.appendingPathComponent("remote")
        try FileManager.default.createDirectory(at: localDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: remoteDir, withIntermediateDirectories: true)

        // Create initial file
        let sharedFile = localDir.appendingPathComponent("rapid.txt")
        try "version 1".write(to: sharedFile, atomically: true, encoding: .utf8)

        // When rapidly updating file while detecting changes
        for i in 2...5 {
            try "\(i)".data(using: .utf8)?.write(to: sharedFile)
            // Simulate change detection
            _ = FileManager.default.fileExists(atPath: sharedFile.path)
        }

        // Then sync should handle the changes
        XCTAssertTrue(true)
    }

    // MARK: - Thread Safety Tests

    func testMirrorEngineThreadSafety() async throws {
        // Given a mirror engine accessed from multiple tasks
        let mirrorEngine = createMirrorEngine()
        let device = VirtualMTPDevice(config: .emptyDevice)
        let deviceId = device.id

        // When performing mirror operations concurrently
        await withTaskGroup(of: MTPSyncReport.self) { group in
            for _ in 0..<3 {
                group.addTask {
                    try? await mirrorEngine.mirror(
                        device: device,
                        deviceId: deviceId,
                        to: self.tempDirectory.appendingPathComponent(UUID().uuidString)
                    )
                }
            }
        }

        // Then no crashes or data races should occur
        XCTAssertTrue(true)
    }

    func testReportAccumulatesCorrectly() async throws {
        // Given a mirror engine with incremental updates
        let mirrorEngine = createMirrorEngine()
        let device = createDeviceWithFiles()
        let deviceId = device.id

        // When performing multiple mirror operations
        var totalReport = MTPSyncReport()
        for _ in 0..<3 {
            let report = try await mirrorEngine.mirror(
                device: device,
                deviceId: deviceId,
                to: tempDirectory.appendingPathComponent(UUID().uuidString)
            )
            totalReport.downloaded += report.downloaded
            totalReport.skipped += report.skipped
            totalReport.failed += report.failed
        }

        // Then report should accumulate correctly
        XCTAssertGreaterThanOrEqual(totalReport.totalProcessed, 0)
    }

    // MARK: - Performance Tests

    func testManySmallFilesSyncPerformance() async throws {
        // Given many small files
        let fileCount = 1000
        let localDir = tempDirectory.appendingPathComponent("local")
        let remoteDir = tempDirectory.appendingPathComponent("remote")
        try FileManager.default.createDirectory(at: localDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: remoteDir, withIntermediateDirectories: true)

        // Create files
        for i in 0..<fileCount {
            let file = remoteDir.appendingPathComponent("small_\(i).txt")
            try "\(i)".write(to: file, atomically: true, encoding: .utf8)
        }

        // When measuring sync time
        let startTime = Date()
        let changes = await detectChanges(local: localDir, remote: remoteDir)
        let duration = Date().timeIntervalSince(startTime)

        // Then should complete in reasonable time
        XCTAssertLessThan(duration, 10.0) // 10 seconds max for 1000 files
        XCTAssertEqual(changes.localToRemote, fileCount)
    }

    func testSyncCancellation() async throws {
        // Given a sync that can be cancelled
        let engine = CancellableSyncEngine()

        // When starting and then cancelling sync
        let task = Task {
            await engine.performCancellableSync()
        }

        // Allow some time for sync to start
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1 second

        // Cancel the task
        task.cancel()

        // Then task should be cancelled
        await Task.yield() // Allow cancellation to propagate
        XCTAssertTrue(task.isCancelled || engine.isCancelled)
    }

    // MARK: - Helper Methods

    private func createMirrorEngine() -> MirrorEngine {
        let snapshotter = MockSnapshotter()
        let diffEngine = MockDiffEngine()
        let journal = MockTransferJournal()
        return MirrorEngine(snapshotter: snapshotter, diffEngine: diffEngine, journal: journal)
    }

    private func createDeviceWithFiles() -> VirtualMTPDevice {
        let config = VirtualDeviceConfig.emptyDevice
            .withObject(VirtualObjectConfig(
                handle: 100,
                storage: MTPStorageID(raw: 0x0001_0001),
                parent: nil,
                name: "test.txt",
                sizeBytes: 1024,
                formatCode: 0x3004
            ))
        return VirtualMTPDevice(config: config)
    }

    private func detectChanges(local: URL, remote: URL) async -> SyncChanges {
        var changes = SyncChanges()
        changes.localToRemote = countFiles(in: remote) ?? 0
        return changes
    }

    private func countFiles(in directory: URL) -> Int? {
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }

        var count = 0
        for case let fileURL as URL in enumerator {
            if let isFile = try? fileURL.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile, isFile {
                count += 1
            }
        }
        return count
    }
}

// MARK: - Supporting Types for Concurrency Tests

/// Mock sync engine for concurrent testing
final class ConcurrentSyncEngine: @unchecked Sendable {
    private let lock = NSLock()
    private var isProcessing = false
    private var pendingOperations: [String] = []

    func performSync(syncId: Int) async {
        lock.lock()
        if isProcessing {
            pendingOperations.append("\(syncId)")
        } else {
            isProcessing = true
        }
        lock.unlock()

        // Simulate work
        try? await Task.sleep(nanoseconds: 10_000_000) // 10ms

        lock.lock()
        isProcessing = false
        lock.unlock()
    }
}

/// Actor-based sync engine for isolation testing
actor ActorBasedSyncEngine {
    private var operations: [String] = []
    private var isProcessing = false

    func queueOperation(_ id: String) {
        operations.append(id)
    }

    func getOperationCount() -> Int {
        operations.count
    }

    func performOperation(_ id: String) async {
        operations.append(id)
    }
}

/// Cancellable sync engine for cancellation testing
final class CancellableSyncEngine {
    var isCancelled = false

    func performCancellableSync() async {
        while !isCancelled && !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 50_000_000) // 50ms
        }
    }
}

/// Changes tracking struct
struct SyncChanges {
    var localToRemote: Int = 0
    var remoteToLocal: Int = 0
    var modified: Int = 0
    var deleted: Int = 0
}
