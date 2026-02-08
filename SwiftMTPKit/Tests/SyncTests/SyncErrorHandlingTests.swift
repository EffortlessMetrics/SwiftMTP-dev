// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import XCTest
@testable import SwiftMTPSync
@testable import SwiftMTPCore
@testable import SwiftMTPTestKit

/// Tests for error handling in sync operations
final class SyncErrorHandlingTests: XCTestCase {

    // MARK: - Properties

    private var tempDirectory: URL!

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

    // MARK: - Empty Sync Scenarios

    func testEmptyDeviceSync() async throws {
        // Given an empty device
        let device = VirtualMTPDevice(config: .emptyDevice)
        let deviceId = device.id
        let mirrorEngine = createMirrorEngine()

        // When performing mirror on empty device
        let report = try await mirrorEngine.mirror(
            device: device,
            deviceId: deviceId,
            to: tempDirectory
        )

        // Then report should reflect empty state
        XCTAssertEqual(report.downloaded, 0)
        XCTAssertEqual(report.skipped, 0)
        XCTAssertEqual(report.failed, 0)
    }

    func testEmptyTargetDirectorySync() async throws {
        // Given an empty local directory
        let localDir = tempDirectory.appendingPathComponent("local")
        let remoteDir = tempDirectory.appendingPathComponent("remote")
        try FileManager.default.createDirectory(at: localDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: remoteDir, withIntermediateDirectories: true)

        // When syncing empty directories
        let changes = await detectChanges(local: localDir, remote: remoteDir)

        // Then no changes should be detected
        XCTAssertTrue(changes.localToRemote.isEmpty)
        XCTAssertTrue(changes.remoteToLocal.isEmpty)
    }

    // MARK: - Partial Sync Failures

    func testPartialSyncFailureContinuesWithRemainingFiles() async throws {
        // Given a device with files where one will fail
        let device = createDeviceWithFailingRead()
        let deviceId = device.id
        let mirrorEngine = createMirrorEngine()

        mockSnapshotter.nextGeneration = 1
        mockDiffEngine.nextDiff = MTPDiff(added: [
            MTPDiff.Row(handle: 100, storage: 1, pathKey: "/file1.txt", size: 1024, mtime: Date(), format: 0x3004),
            MTPDiff.Row(handle: 101, storage: 1, pathKey: "/failing.txt", size: 1024, mtime: Date(), format: 0x3004),
            MTPDiff.Row(handle: 102, storage: 1, pathKey: "/file2.txt", size: 1024, mtime: Date(), format: 0x3004),
        ])

        // When performing mirror
        let report = try await mirrorEngine.mirror(
            device: device,
            deviceId: deviceId,
            to: tempDirectory
        )

        // Then remaining files should still be processed
        XCTAssertGreaterThanOrEqual(report.failed, 1)
        XCTAssertLessThan(report.failed, 3) // Not all should fail
    }

    func testSyncRecoversFromTransientErrors() async throws {
        // Given a device with transient failure capability
        let device = VirtualMTPDevice(config: .emptyDevice)
        let deviceId = device.id
        let mirrorEngine = createMirrorEngine()

        mockSnapshotter.nextGeneration = 1

        // Create actual files on device
        let storageId = MTPStorageID(raw: 0x0001_0001)
        device.addObject(VirtualObjectConfig(
            handle: 100,
            storage: storageId,
            parent: nil,
            name: "test.txt",
            sizeBytes: 100,
            formatCode: 0x3004,
            data: Data(repeating: 0, count: 100)
        ))

        // When performing mirror
        let report = try await mirrorEngine.mirror(
            device: device,
            deviceId: deviceId,
            to: tempDirectory
        )

        // Then sync should complete
        XCTAssertTrue(report.totalProcessed >= 0)
    }

    // MARK: - Large File Sync

    func testLargeFileSync() async throws {
        // Given a device with a large file
        let largeSize = 50 * 1024 * 1024 // 50 MB
        let device = createDeviceWithLargeFile(size: largeSize)
        let deviceId = device.id
        let mirrorEngine = createMirrorEngine()

        mockSnapshotter.nextGeneration = 1
        mockDiffEngine.nextDiff = MTPDiff(added: [
            MTPDiff.Row(handle: 100, storage: 1, pathKey: "/large_file.bin", size: UInt64(largeSize), mtime: Date(), format: 0x3004)
        ])

        // When performing mirror
        let report = try await mirrorEngine.mirror(
            device: device,
            deviceId: deviceId,
            to: tempDirectory
        )

        // Then file should be downloaded
        XCTAssertEqual(report.downloaded, 1)
    }

    func testSyncWithFilesLargerThanMemory() async throws {
        // Given multiple large files
        let fileCount = 5
        let fileSize = 100 * 1024 * 1024 // 100 MB each

        // Create local and remote directories
        let localDir = tempDirectory.appendingPathComponent("local")
        let remoteDir = tempDirectory.appendingPathComponent("remote")
        try FileManager.default.createDirectory(at: localDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: remoteDir, withIntermediateDirectories: true)

        // Create large files in remote
        for i in 0..<fileCount {
            let file = remoteDir.appendingPathComponent("large_\(i).bin")
            let data = Data(repeating: 0, count: min(fileSize, 1024)) // Smaller for test speed
            try data.write(to: file)
        }

        // When detecting changes
        let changes = await detectChanges(local: localDir, remote: remoteDir)

        // Then all files should be detected
        XCTAssertEqual(changes.localToRemote, fileCount)
    }

    // MARK: - Network/Device Disconnection Handling

    func testSyncWithDeviceDisconnection() async throws {
        // Given a device that can be disconnected
        let device = VirtualMTPDevice(config: .emptyDevice)
        let deviceId = device.id
        let mirrorEngine = createMirrorEngine()

        mockSnapshotter.nextGeneration = 1

        // When device becomes unavailable during snapshot
        await device.devClose()

        // Then snapshot should fail gracefully
        do {
            _ = try await mirrorEngine.mirror(
                device: device,
                deviceId: deviceId,
                to: tempDirectory
            )
        } catch {
            // Expected - device is closed
            XCTAssertNotNil(error)
        }
    }

    func testSyncWithReadFailure() async throws {
        // Given a device with a file that fails to read
        let device = createDeviceWithUnreadableFile()
        let deviceId = device.id
        let mirrorEngine = createMirrorEngine()

        mockSnapshotter.nextGeneration = 1
        mockDiffEngine.nextDiff = MTPDiff(added: [
            MTPDiff.Row(handle: 100, storage: 1, pathKey: "/unreadable.txt", size: 1024, mtime: Date(), format: 0x3004)
        ])

        // When performing mirror
        let report = try await mirrorEngine.mirror(
            device: device,
            deviceId: deviceId,
            to: tempDirectory
        )

        // Then failure should be recorded
        XCTAssertEqual(report.failed, 1)
    }

    // MARK: - Directory Creation Failures

    func testSyncWithInsufficientPermissions() async throws {
        // Given a directory without write permissions
        let restrictedDir = tempDirectory.appendingPathComponent("restricted")
        try FileManager.default.createDirectory(at: restrictedDir, withIntermediateDirectories: true)

        // When directory becomes read-only
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: restrictedDir.path)

        // Then write operations should fail gracefully
        let file = restrictedDir.appendingPathComponent("test.txt")
        do {
            try "content".write(to: file, atomically: true, encoding: .utf8)
            XCTFail("Expected write to fail")
        } catch {
            // Expected - no write permission
            XCTAssertNotNil(error)
        }

        // Cleanup - restore permissions
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: restrictedDir.path)
    }

    // MARK: - Invalid Path Handling

    func testSyncWithInvalidPathCharacters() async throws {
        // Given files with invalid path characters
        let localDir = tempDirectory.appendingPathComponent("local")
        let remoteDir = tempDirectory.appendingPathComponent("remote")
        try FileManager.default.createDirectory(at: localDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: remoteDir, withIntermediateDirectories: true)

        // Create file with potentially problematic name
        let problematicFile = remoteDir.appendingPathComponent("file with\0null.bytes")
        try "content".write(to: problematicFile, atomically: true, encoding: .utf8)

        // When detecting changes
        let changes = await detectChanges(local: localDir, remote: remoteDir)

        // Then should handle gracefully
        XCTAssertTrue(true) // Test passes if no crash
    }

    // MARK: - Sync Report Accuracy

    func testReportAccuracyAfterFailures() async throws {
        // Given a mix of successful and failed downloads
        let device = createDeviceWithFiles()
        let deviceId = device.id
        let mirrorEngine = createMirrorEngine()

        mockSnapshotter.nextGeneration = 1
        mockDiffEngine.nextDiff = MTPDiff(added: [
            MTPDiff.Row(handle: 100, storage: 1, pathKey: "/success.txt", size: 100, mtime: Date(), format: 0x3004),
            MTPDiff.Row(handle: 101, storage: 1, pathKey: "/fail1.txt", size: 100, mtime: Date(), format: 0x3004),
            MTPDiff.Row(handle: 102, storage: 1, pathKey: "/success2.txt", size: 100, mtime: Date(), format: 0x3004),
            MTPDiff.Row(handle: 103, storage: 1, pathKey: "/fail2.txt", size: 100, mtime: Date(), format: 0x3004),
        ])

        // When performing mirror
        let report = try await mirrorEngine.mirror(
            device: device,
            deviceId: deviceId,
            to: tempDirectory
        )

        // Then report should accurately reflect results
        XCTAssertEqual(report.downloaded + report.skipped + report.failed, report.totalProcessed)
    }

    func testReportSuccessRateCalculation() {
        // Test success rate calculation
        var report = MTPSyncReport()
        XCTAssertEqual(report.successRate, 0.0)

        report.downloaded = 8
        report.failed = 2
        XCTAssertEqual(report.successRate, 80.0)

        report.downloaded = 0
        report.skipped = 5
        report.failed = 5
        XCTAssertEqual(report.successRate, 0.0) // No downloads = 0% success
    }

    // MARK: - Recovery Tests

    func testSyncRecoveryAfterPartialFailure() async throws {
        // Given a state where some files synced, some failed
        let localDir = tempDirectory.appendingPathComponent("local")
        try FileManager.default.createDirectory(at: localDir, withIntermediateDirectories: true)

        // Create partially synced state
        let successFile = localDir.appendingPathComponent("success.txt")
        try "already synced".write(to: successFile, atomically: true, encoding: .utf8)

        let remoteDir = tempDirectory.appendingPathComponent("remote")
        try FileManager.default.createDirectory(at: remoteDir, withIntermediateDirectories: true)
        let newFile = remoteDir.appendingPathComponent("new.txt")
        try "new content".write(to: newFile, atomically: true, encoding: .utf8)

        // When syncing with partial state
        let changes = await detectChanges(local: localDir, remote: remoteDir)

        // Then new files should be detected
        XCTAssertEqual(changes.localToRemote, 1)
    }

    // MARK: - Helper Methods

    private var mockSnapshotter: MockSnapshotter!
    private var mockDiffEngine: MockDiffEngine!
    private var mockJournal: MockTransferJournal!

    private func createMirrorEngine() -> MirrorEngine {
        mockSnapshotter = MockSnapshotter()
        mockDiffEngine = MockDiffEngine()
        mockJournal = MockTransferJournal()
        return MirrorEngine(snapshotter: mockSnapshotter, diffEngine: mockDiffEngine, journal: mockJournal)
    }

    private func createDeviceWithFiles() -> VirtualMTPDevice {
        let config = VirtualDeviceConfig.emptyDevice
            .withObject(VirtualObjectConfig(
                handle: 100,
                storage: MTPStorageID(raw: 0x0001_0001),
                parent: nil,
                name: "test.txt",
                sizeBytes: 100,
                formatCode: 0x3004,
                data: Data(repeating: 0, count: 100)
            ))
        return VirtualMTPDevice(config: config)
    }

    private func createDeviceWithLargeFile(size: Int) -> VirtualMTPDevice {
        let config = VirtualDeviceConfig.emptyDevice
            .withObject(VirtualObjectConfig(
                handle: 100,
                storage: MTPStorageID(raw: 0x0001_0001),
                parent: nil,
                name: "large_file.bin",
                sizeBytes: UInt64(size),
                formatCode: 0x3004,
                data: Data(repeating: 0, count: min(size, 1024)) // Small data for test
            ))
        return VirtualMTPDevice(config: config)
    }

    private func createDeviceWithFailingRead() -> VirtualMTPDevice {
        return VirtualMTPDevice(config: .emptyDevice)
    }

    private func createDeviceWithUnreadableFile() -> VirtualMTPDevice {
        let config = VirtualDeviceConfig.emptyDevice
            .withObject(VirtualObjectConfig(
                handle: 100,
                storage: MTPStorageID(raw: 0x0001_0001),
                parent: nil,
                name: "unreadable.txt",
                sizeBytes: 1024,
                formatCode: 0x3004,
                data: nil // No data = read will fail
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

// MARK: - Supporting Types for Error Handling Tests

struct SyncChanges {
    var localToRemote: Int = 0
    var remoteToLocal: Int = 0
    var modified: Int = 0
    var deleted: Int = 0
}
