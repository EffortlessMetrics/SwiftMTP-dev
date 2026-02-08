// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import XCTest
@testable import SwiftMTPSync
@testable import SwiftMTPCore
@testable import SwiftMTPTestKit

/// Tests for MirrorEngine functionality
final class MirrorEngineTests: XCTestCase {

    // MARK: - Properties

    private var mirrorEngine: MirrorEngine!
    private var mockSnapshotter: MockSnapshotter!
    private var mockDiffEngine: MockDiffEngine!
    private var mockJournal: MockTransferJournal!
    private var tempDirectory: URL!

    // MARK: - Setup/Teardown

    override func setUp() {
        super.setUp()
        mockSnapshotter = MockSnapshotter()
        mockDiffEngine = MockDiffEngine()
        mockJournal = MockTransferJournal()
        mirrorEngine = MirrorEngine(
            snapshotter: mockSnapshotter,
            diffEngine: mockDiffEngine,
            journal: mockJournal
        )

        // Create a temporary directory for mirror operations
        tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDown() {
        // Clean up temporary directory
        try? FileManager.default.removeItem(at: tempDirectory)
        tempDirectory = nil
        mirrorEngine = nil
        mockSnapshotter = nil
        mockDiffEngine = nil
        mockJournal = nil
        super.tearDown()
    }

    // MARK: - Initial Sync Tests

    func testInitialSyncWithNoChanges() async throws {
        // Given an empty diff
        let device = VirtualMTPDevice(config: .emptyDevice)
        let deviceId = device.id

        mockSnapshotter.nextGeneration = 1
        mockDiffEngine.nextDiff = MTPDiff()

        // When performing mirror operation
        let report = try await mirrorEngine.mirror(
            device: device,
            deviceId: deviceId,
            to: tempDirectory
        )

        // Then no files should be downloaded
        XCTAssertEqual(report.downloaded, 0)
        XCTAssertEqual(report.skipped, 0)
        XCTAssertEqual(report.failed, 0)
        XCTAssertEqual(report.totalProcessed, 0)
    }

    func testInitialSyncWithAddedFiles() async throws {
        // Given a device with files to add
        let device = createDeviceWithFiles()
        let deviceId = device.id

        mockSnapshotter.nextGeneration = 1
        mockDiffEngine.nextDiff = MTPDiff(added: [
            MTPDiff.Row(
                handle: 100,
                storage: 1,
                pathKey: "/DCIM/Camera/photo.jpg",
                size: 1024,
                mtime: Date(),
                format: 0x3801
            )
        ])

        // When performing mirror operation
        let report = try await mirrorEngine.mirror(
            device: device,
            deviceId: deviceId,
            to: tempDirectory
        )

        // Then the file should be downloaded
        XCTAssertEqual(report.downloaded, 1)
        XCTAssertEqual(report.failed, 0)
    }

    func testInitialSyncWithModifiedFiles() async throws {
        // Given a device with modified files
        let device = createDeviceWithFiles()
        let deviceId = device.id

        mockSnapshotter.nextGeneration = 2
        mockSnapshotter.previousGenerationForDevice = 1
        mockDiffEngine.nextDiff = MTPDiff(modified: [
            MTPDiff.Row(
                handle: 100,
                storage: 1,
                pathKey: "/DCIM/Camera/photo.jpg",
                size: 2048,  // Size changed
                mtime: Date(),
                format: 0x3801
            )
        ])

        // When performing mirror operation
        let report = try await mirrorEngine.mirror(
            device: device,
            deviceId: deviceId,
            to: tempDirectory
        )

        // Then the file should be re-downloaded
        XCTAssertEqual(report.downloaded, 1)
        XCTAssertEqual(report.failed, 0)
    }

    // MARK: - Filter Tests

    func testMirrorWithIncludeFilter() async throws {
        // Given a device with mixed file types
        let device = createDeviceWithMixedFiles()
        let deviceId = device.id

        mockSnapshotter.nextGeneration = 1
        mockDiffEngine.nextDiff = MTPDiff(added: [
            MTPDiff.Row(handle: 100, storage: 1, pathKey: "/DCIM/photo.jpg", size: 1024, mtime: Date(), format: 0x3801),
            MTPDiff.Row(handle: 101, storage: 1, pathKey: "/DCIM/video.mp4", size: 2048, mtime: Date(), format: 0x3802),
            MTPDiff.Row(handle: 102, storage: 1, pathKey: "/Music/song.mp3", size: 512, mtime: Date(), format: 0x3803),
        ])

        // When filtering to only JPG files
        let report = try await mirrorEngine.mirror(
            device: device,
            deviceId: deviceId,
            to: tempDirectory
        ) { row in
            row.pathKey.hasSuffix(".jpg")
        }

        // Then only matching files should be processed
        XCTAssertEqual(report.downloaded, 1)
        XCTAssertEqual(report.skipped, 2)
    }

    func testMirrorWithGlobPattern() async throws {
        // Given a device with files in different directories
        let device = createDeviceWithNestedFiles()
        let deviceId = device.id

        mockSnapshotter.nextGeneration = 1
        mockDiffEngine.nextDiff = MTPDiff(added: [
            MTPDiff.Row(handle: 100, storage: 1, pathKey: "/DCIM/Camera/photo1.jpg", size: 1024, mtime: Date(), format: 0x3801),
            MTPDiff.Row(handle: 101, storage: 1, pathKey: "/DCIM/Camera/photo2.jpg", size: 1024, mtime: Date(), format: 0x3801),
            MTPDiff.Row(handle: 102, storage: 1, pathKey: "/Screenshots/screenshot.png", size: 2048, mtime: Date(), format: 0x3801),
        ])

        // When using glob pattern for Camera folder
        let report = try await mirrorEngine.mirror(
            device: device,
            deviceId: deviceId,
            to: tempDirectory,
            includePattern: "DCIM/Camera/**"
        )

        // Then only files in Camera folder should be mirrored
        XCTAssertEqual(report.downloaded, 2)
        XCTAssertEqual(report.skipped, 1)
    }

    // MARK: - Deletion Handling Tests

    func testMirrorDoesNotDeleteLocalFiles() async throws {
        // Given a file that was removed from device but exists locally
        let device = createDeviceWithFiles()
        let deviceId = device.id

        // Create a local file that doesn't exist on device
        let localFile = tempDirectory.appendingPathComponent("orphaned.txt")
        try "orphaned content".write(to: localFile, atomically: true, encoding: .utf8)

        mockSnapshotter.nextGeneration = 2
        mockSnapshotter.previousGenerationForDevice = 1
        mockDiffEngine.nextDiff = MTPDiff(removed: [
            MTPDiff.Row(handle: 999, storage: 1, pathKey: "/orphaned.txt", size: 1024, mtime: Date(), format: 0x3004)
        ])

        // When performing mirror operation
        let report = try await mirrorEngine.mirror(
            device: device,
            deviceId: deviceId,
            to: tempDirectory
        )

        // Then the local file should still exist (mirror is one-way)
        XCTAssertTrue(FileManager.default.fileExists(atPath: localFile.path))
    }

    // MARK: - Pattern Matching Tests

    func testMatchesPatternWithDoubleAsterisk() {
        // Test ** pattern matching
        XCTAssertTrue(mirrorEngine.matchesPattern("DCIM/file.jpg", pattern: "**"))
        XCTAssertTrue(mirrorEngine.matchesPattern("/DCIM/file.jpg", pattern: "/**"))
        XCTAssertTrue(mirrorEngine.matchesPattern("DCIM/Camera/file.jpg", pattern: "**"))
    }

    func testMatchesPatternWithWildcard() {
        // Test single wildcard *
        XCTAssertTrue(mirrorEngine.matchesPattern("photo.jpg", pattern: "*.jpg"))
        XCTAssertTrue(mirrorEngine.matchesPattern("IMG_001.jpg", pattern: "IMG_*.jpg"))
        XCTAssertFalse(mirrorEngine.matchesPattern("photo.png", pattern: "*.jpg"))
    }

    func testMatchesPatternWithDirectory() {
        // Test directory patterns
        XCTAssertTrue(mirrorEngine.matchesPattern("DCIM/Camera/photo.jpg", pattern: "DCIM/**"))
        XCTAssertTrue(mirrorEngine.matchesPattern("DCIM/Camera/Nested/photo.jpg", pattern: "DCIM/**"))
        XCTAssertFalse(mirrorEngine.matchesPattern("Music/photo.jpg", pattern: "DCIM/**"))
    }

    // MARK: - Path Conversion Tests

    func testPathKeyToLocalURL() {
        // Test path key conversion
        let pathKey = "/DCIM/Camera/photo.jpg"
        let localURL = mirrorEngine.pathKeyToLocalURL(pathKey, root: tempDirectory)

        XCTAssertEqual(localURL.path, tempDirectory.path + "/DCIM/Camera/photo.jpg")
    }

    func testPathKeyToLocalURLWithStoragePrefix() {
        // Test path key with storage ID prefix (if applicable)
        let pathKey = "0x00010001/DCIM/photo.jpg"
        let localURL = mirrorEngine.pathKeyToLocalURL(pathKey, root: tempDirectory)

        // Should strip storage ID prefix
        XCTAssertTrue(localURL.path.hasSuffix("/DCIM/photo.jpg"))
    }

    // MARK: - Skip Download Tests

    func testShouldSkipDownloadWhenFileExistsWithSameSizeAndMtime() throws {
        // Given an existing file with matching attributes
        let fileURL = tempDirectory.appendingPathComponent("test.txt")
        let content = "test content"
        try content.write(to: fileURL, atomically: true, encoding: .utf8)

        let fileRow = MTPDiff.Row(
            handle: 100,
            storage: 1,
            pathKey: "/test.txt",
            size: UInt64(content.utf8.count),
            mtime: Date(timeIntervalSinceNow: -60), // 1 minute ago
            format: 0x3004
        )

        // When checking if download should be skipped
        let shouldSkip = try mirrorEngine.shouldSkipDownload(of: fileURL, file: fileRow)

        // Then it should be skipped
        XCTAssertTrue(shouldSkip)
    }

    func testShouldNotSkipDownloadWhenFileSizeDiffers() throws {
        // Given an existing file with different size
        let fileURL = tempDirectory.appendingPathComponent("test.txt")
        try "original content".write(to: fileURL, atomically: true, encoding: .utf8)

        let fileRow = MTPDiff.Row(
            handle: 100,
            storage: 1,
            pathKey: "/test.txt",
            size: 9999,  // Different size
            mtime: Date(),
            format: 0x3004
        )

        // When checking if download should be skipped
        let shouldSkip = try mirrorEngine.shouldSkipDownload(of: fileURL, file: fileRow)

        // Then it should not be skipped
        XCTAssertFalse(shouldSkip)
    }

    func testShouldNotSkipDownloadWhenFileDoesNotExist() {
        // Given a non-existent file
        let fileURL = tempDirectory.appendingPathComponent("nonexistent.txt")

        let fileRow = MTPDiff.Row(
            handle: 100,
            storage: 1,
            pathKey: "/nonexistent.txt",
            size: 1024,
            mtime: Date(),
            format: 0x3004
        )

        // When checking if download should be skipped
        let shouldSkip = try? mirrorEngine.shouldSkipDownload(of: fileURL, file: fileRow)

        // Then it should not be skipped
        XCTAssertFalse(shouldSkip ?? false)
    }

    // MARK: - Directory Structure Sync Tests

    func testMirrorCreatesDirectoryStructure() async throws {
        // Given a device with nested directories
        let device = VirtualMTPDevice(config: .emptyDevice)
        let deviceId = device.id

        mockSnapshotter.nextGeneration = 1
        mockDiffEngine.nextDiff = MTPDiff(added: [
            MTPDiff.Row(handle: 1, storage: 1, pathKey: "/DCIM", size: nil, mtime: nil, format: 0x3001),
            MTPDiff.Row(handle: 2, storage: 1, pathKey: "/DCIM/Camera", size: nil, mtime: nil, format: 0x3001),
            MTPDiff.Row(handle: 3, storage: 1, pathKey: "/DCIM/Camera/photo.jpg", size: 1024, mtime: Date(), format: 0x3801),
        ])

        // When performing mirror operation
        let report = try await mirrorEngine.mirror(
            device: device,
            deviceId: deviceId,
            to: tempDirectory
        )

        // Then directories should be created
        let cameraDir = tempDirectory.appendingPathComponent("DCIM/Camera")
        XCTAssertTrue(FileManager.default.fileExists(atPath: cameraDir.path))
    }

    // MARK: - Helper Methods

    private func createDeviceWithFiles() -> VirtualMTPDevice {
        let config = VirtualDeviceConfig.emptyDevice
            .withObject(VirtualObjectConfig(
                handle: 1,
                storage: MTPStorageID(raw: 0x0001_0001),
                parent: nil,
                name: "DCIM",
                formatCode: 0x3001
            ))
            .withObject(VirtualObjectConfig(
                handle: 2,
                storage: MTPStorageID(raw: 0x0001_0001),
                parent: 1,
                name: "Camera",
                formatCode: 0x3001
            ))
            .withObject(VirtualObjectConfig(
                handle: 100,
                storage: MTPStorageID(raw: 0x0001_0001),
                parent: 2,
                name: "photo.jpg",
                sizeBytes: 1024,
                formatCode: 0x3801,
                data: Data(repeating: 0, count: 1024)
            ))
        return VirtualMTPDevice(config: config)
    }

    private func createDeviceWithMixedFiles() -> VirtualMTPDevice {
        var config = VirtualDeviceConfig.emptyDevice
        let storageId = MTPStorageID(raw: 0x0001_0001)

        // DCIM folder
        config = config.withObject(VirtualObjectConfig(
            handle: 1, storage: storageId, parent: nil, name: "DCIM", formatCode: 0x3001
        ))
        // Music folder
        config = config.withObject(VirtualObjectConfig(
            handle: 10, storage: storageId, parent: nil, name: "Music", formatCode: 0x3001
        ))

        return VirtualMTPDevice(config: config)
    }

    private func createDeviceWithNestedFiles() -> VirtualMTPDevice {
        var config = VirtualDeviceConfig.emptyDevice
        let storageId = MTPStorageID(raw: 0x0001_0001)

        config = config.withObject(VirtualObjectConfig(handle: 1, storage: storageId, parent: nil, name: "DCIM", formatCode: 0x3001))
        config = config.withObject(VirtualObjectConfig(handle: 2, storage: storageId, parent: 1, name: "Camera", formatCode: 0x3001))
        config = config.withObject(VirtualObjectConfig(handle: 3, storage: storageId, parent: 1, name: "Screenshots", formatCode: 0x3001))

        return VirtualMTPDevice(config: config)
    }
}

// MARK: - Mock Dependencies

/// Mock Snapshotter for testing
final class MockSnapshotter: @unchecked Sendable {
    var nextGeneration: Int = 1
    var previousGenerationForDevice: Int? = nil
    var captureDeviceId: MTPDeviceID?
    var captureCallCount = 0

    func capture(device: any MTPDevice, deviceId: MTPDeviceID) async throws -> Int {
        captureCallCount += 1
        captureDeviceId = deviceId
        return nextGeneration
    }

    func previousGeneration(for deviceId: MTPDeviceID, before currentGen: Int) throws -> Int? {
        return previousGenerationForDevice
    }
}

/// Mock DiffEngine for testing
final class MockDiffEngine: @unchecked Sendable {
    var nextDiff = MTPDiff()
    var diffCallCount = 0

    func diff(deviceId: MTPDeviceID, oldGen: Int?, newGen: Int) async throws -> MTPDiff {
        diffCallCount += 1
        return nextDiff
    }
}

/// Mock TransferJournal for testing
final class MockTransferJournal: TransferJournal {
    var beginReadCalls: [(device: MTPDeviceID, handle: UInt32, name: String)] = []
    var beginWriteCalls: [(device: MTPDeviceID, parent: UInt32, name: String)] = []

    func beginRead(device: MTPDeviceID, handle: UInt32, name: String, size: UInt64?, supportsPartial: Bool, tempURL: URL, finalURL: URL?, etag: (size: UInt64?, mtime: Date?)) async throws -> String {
        beginReadCalls.append((device, handle, name))
        return "read-\(UUID().uuidString)"
    }

    func beginWrite(device: MTPDeviceID, parent: UInt32, name: String, size: UInt64, supportsPartial: Bool, tempURL: URL, sourceURL: URL?) async throws -> String {
        beginWriteCalls.append((device, parent, name))
        return "write-\(UUID().uuidString)"
    }

    func updateProgress(id: String, committed: UInt64) async throws {}
    func fail(id: String, error: Error) async throws {}
    func complete(id: String) async throws {}
    func loadResumables(for device: MTPDeviceID) async throws -> [TransferRecord] { [] }
    func clearStaleTemps(olderThan: TimeInterval) async throws {}
}

// MARK: - MTPSyncReport Tests

extension MirrorEngineTests {

    func testSyncReportCalculations() {
        // Test report metrics calculations
        var report = MTPSyncReport()
        XCTAssertEqual(report.totalProcessed, 0)
        XCTAssertEqual(report.successRate, 0.0)

        report.downloaded = 5
        report.skipped = 2
        report.failed = 1

        XCTAssertEqual(report.totalProcessed, 8)
        XCTAssertEqual(report.successRate, 62.5) // 5/8 * 100
    }

    func testSyncReportWithZeroTotal() {
        // Test edge case: zero total processed
        var report = MTPSyncReport()
        XCTAssertEqual(report.successRate, 0.0)
    }
}
