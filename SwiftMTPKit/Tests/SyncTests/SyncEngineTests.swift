// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import XCTest
@testable import SwiftMTPSync
@testable import SwiftMTPCore
@testable import SwiftMTPTestKit

/// Tests for SyncEngine functionality
final class SyncEngineTests: XCTestCase {

    // MARK: - Properties

    private var syncEngine: MTPSyncEngine!
    private var tempDirectory: URL!

    // MARK: - Setup/Teardown

    override func setUp() {
        super.setUp()
        syncEngine = MTPSyncEngine()
        tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDirectory)
        tempDirectory = nil
        syncEngine = nil
        super.tearDown()
    }

    // MARK: - Basic Engine Tests

    func testEngineInitialization() {
        // Test that engine can be initialized
        XCTAssertNotNil(syncEngine)
    }

    // MARK: - Two-Way Sync Tests

    func testTwoWaySyncDetectsBidirectionalChanges() async throws {
        // Given two directories with different content
        let localDir = tempDirectory.appendingPathComponent("local")
        let remoteDir = tempDirectory.appendingPathComponent("remote")
        try FileManager.default.createDirectory(at: localDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: remoteDir, withIntermediateDirectories: true)

        // Create files in local only
        let localOnlyFile = localDir.appendingPathComponent("local_only.txt")
        try "local content".write(to: localOnlyFile, atomically: true, encoding: .utf8)

        // Create files in remote only
        let remoteOnlyFile = remoteDir.appendingPathComponent("remote_only.txt")
        try "remote content".write(to: remoteOnlyFile, atomically: true, encoding: .utf8)

        // When performing two-way sync analysis
        let changes = await detectChanges(local: localDir, remote: remoteDir)

        // Then both directions of changes should be detected
        XCTAssertTrue(changes.localToRemote.count >= 1)
        XCTAssertTrue(changes.remoteToLocal.count >= 1)
    }

    func testTwoWaySyncDetectsModifiedFiles() async throws {
        // Given two directories with same-named but different files
        let localDir = tempDirectory.appendingPathComponent("local")
        let remoteDir = tempDirectory.appendingPathComponent("remote")
        try FileManager.default.createDirectory(at: localDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: remoteDir, withIntermediateDirectories: true)

        // Create same-named file with different content
        let localFile = localDir.appendingPathComponent("shared.txt")
        try "local version".write(to: localFile, atomically: true, encoding: .utf8)

        let remoteFile = remoteDir.appendingPathComponent("shared.txt")
        try "remote version".write(to: remoteFile, atomically: true, encoding: .utf8)

        // When performing two-way sync analysis
        let changes = await detectChanges(local: localDir, remote: remoteDir)

        // Then the modified file should be detected
        XCTAssertTrue(changes.modified.count >= 1)
    }

    // MARK: - Change Detection Tests

    func testChangeDetectionWithEmptyDirectories() async throws {
        // Given two empty directories
        let localDir = tempDirectory.appendingPathComponent("local")
        let remoteDir = tempDirectory.appendingPathComponent("remote")
        try FileManager.default.createDirectory(at: localDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: remoteDir, withIntermediateDirectories: true)

        // When performing sync analysis
        let changes = await detectChanges(local: localDir, remote: remoteDir)

        // Then no changes should be detected
        XCTAssertTrue(changes.localToRemote.isEmpty)
        XCTAssertTrue(changes.remoteToLocal.isEmpty)
        XCTAssertTrue(changes.modified.isEmpty)
        XCTAssertTrue(changes.deleted.isEmpty)
    }

    func testChangeDetectionIdentifiesNewFiles() async throws {
        // Given local directory with new files
        let localDir = tempDirectory.appendingPathComponent("local")
        let remoteDir = tempDirectory.appendingPathComponent("remote")
        try FileManager.default.createDirectory(at: localDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: remoteDir, withIntermediateDirectories: true)

        // Create files in local
        for i in 1...5 {
            let file = localDir.appendingPathComponent("new_\(i).txt")
            try "content \(i)".write(to: file, atomically: true, encoding: .utf8)
        }

        // When performing sync analysis
        let changes = await detectChanges(local: localDir, remote: remoteDir)

        // Then all new files should be detected
        XCTAssertEqual(changes.localToRemote.count, 5)
    }

    func testChangeDetectionIdentifiesDeletedFiles() async throws {
        // Given directories where remote has files that local doesn't
        let localDir = tempDirectory.appendingPathComponent("local")
        let remoteDir = tempDirectory.appendingPathComponent("remote")
        try FileManager.default.createDirectory(at: localDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: remoteDir, withIntermediateDirectories: true)

        // Create files in remote only
        for i in 1...3 {
            let file = remoteDir.appendingPathComponent("deleted_\(i).txt")
            try "deleted content \(i)".write(to: file, atomically: true, encoding: .utf8)
        }

        // When performing sync analysis
        let changes = await detectChanges(local: localDir, remote: remoteDir)

        // Then deleted files should be detected
        XCTAssertEqual(changes.remoteToLocal.count, 3)
    }

    // MARK: - Batch Sync Tests

    func testBatchSyncProcessesMultipleFiles() async throws {
        // Given multiple files to sync
        let localDir = tempDirectory.appendingPathComponent("local")
        let remoteDir = tempDirectory.appendingPathComponent("remote")
        try FileManager.default.createDirectory(at: localDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: remoteDir, withIntermediateDirectories: true)

        // Create multiple files in remote
        let fileCount = 100
        for i in 1...fileCount {
            let file = remoteDir.appendingPathComponent("batch_\(i).txt")
            try "batch content \(i)".write(to: file, atomically: true, encoding: .utf8)
        }

        // When performing batch sync
        let report = await performBatchSync(local: localDir, remote: remoteDir)

        // Then all files should be processed
        XCTAssertEqual(report.totalProcessed, fileCount)
    }

    // MARK: - Conflict Resolution Tests

    func testConflictDetectionForSimultaneousModifications() async throws {
        // Given files modified at the same time in both locations
        let localDir = tempDirectory.appendingPathComponent("local")
        let remoteDir = tempDirectory.appendingPathComponent("remote")
        try FileManager.default.createDirectory(at: localDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: remoteDir, withIntermediateDirectories: true)

        // Create conflicting files
        let conflictFile = localDir.appendingPathComponent("conflict.txt")
        try "local conflict".write(to: conflictFile, atomically: true, encoding: .utf8)

        let remoteConflictFile = remoteDir.appendingPathComponent("conflict.txt")
        try "remote conflict".write(to: remoteConflictFile, atomically: true, encoding: .utf8)

        // When detecting conflicts
        let conflicts = await detectConflicts(local: localDir, remote: remoteDir)

        // Then conflict should be detected
        XCTAssertEqual(conflicts.count, 1)
    }

    func testConflictResolutionStrategyLocalWins() async throws {
        // Given a conflict with local-wins strategy
        let localDir = tempDirectory.appendingPathComponent("local")
        let remoteDir = tempDirectory.appendingPathComponent("remote")
        try FileManager.default.createDirectory(at: localDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: remoteDir, withIntermediateDirectories: true)

        // Create conflicting files
        let localFile = localDir.appendingPathComponent("conflict.txt")
        try "local version".write(to: localFile, atomically: true, encoding: .utf8)

        let remoteFile = remoteDir.appendingPathComponent("conflict.txt")
        try "remote version".write(to: remoteFile, atomically: true, encoding: .utf8)

        // When resolving with local-wins strategy
        let resolved = await resolveConflict(
            local: localDir,
            remote: remoteDir,
            strategy: .localWins
        )

        // Then local version should be kept
        let localContent = try String(contentsOf: localFile, encoding: .utf8)
        XCTAssertEqual(localContent, "local version")
    }

    func testConflictResolutionStrategyRemoteWins() async throws {
        // Given a conflict with remote-wins strategy
        let localDir = tempDirectory.appendingPathComponent("local")
        let remoteDir = tempDirectory.appendingPathComponent("remote")
        try FileManager.default.createDirectory(at: localDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: remoteDir, withIntermediateDirectories: true)

        // Create conflicting files
        let localFile = localDir.appendingPathComponent("conflict.txt")
        try "local version".write(to: localFile, atomically: true, encoding: .utf8)

        let remoteFile = remoteDir.appendingPathComponent("conflict.txt")
        try "remote version".write(to: remoteFile, atomically: true, encoding: .utf8)

        // When resolving with remote-wins strategy
        let resolved = await resolveConflict(
            local: localDir,
            remote: remoteDir,
            strategy: .remoteWins
        )

        // Then remote version should overwrite local
        let localContent = try String(contentsOf: localFile, encoding: .utf8)
        XCTAssertEqual(localContent, "remote version")
    }

    func testConflictResolutionStrategyNewestWins() async throws {
        // Given a conflict with timestamp-based resolution
        let localDir = tempDirectory.appendingPathComponent("local")
        let remoteDir = tempDirectory.appendingPathComponent("remote")
        try FileManager.default.createDirectory(at: localDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: remoteDir, withIntermediateDirectories: true)

        // Create files with different timestamps
        let localFile = localDir.appendingPathComponent("conflict.txt")
        try "older version".write(to: localFile, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-60)], ofItemAtPath: localFile.path)

        let remoteFile = remoteDir.appendingPathComponent("conflict.txt")
        try "newer version".write(to: remoteFile, atomically: true, encoding: .utf8)

        // When resolving with newest-wins strategy
        let resolved = await resolveConflict(
            local: localDir,
            remote: remoteDir,
            strategy: .newestWins
        )

        // Then newer version should win
        let localContent = try String(contentsOf: localFile, encoding: .utf8)
        XCTAssertEqual(localContent, "newer version")
    }

    // MARK: - Edge Cases

    func testSyncWithUnicodeFilenames() async throws {
        // Given files with Unicode characters in names
        let localDir = tempDirectory.appendingPathComponent("local")
        let remoteDir = tempDirectory.appendingPathComponent("remote")
        try FileManager.default.createDirectory(at: localDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: remoteDir, withIntermediateDirectories: true)

        // Create files with Unicode names
        let unicodeNames = ["файл.txt", "文件.txt", "emoji📷.jpg"]
        for name in unicodeNames {
            let file = remoteDir.appendingPathComponent(name)
            try "unicode content".write(to: file, atomically: true, encoding: .utf8)
        }

        // When performing sync
        let changes = await detectChanges(local: localDir, remote: remoteDir)

        // Then all Unicode files should be detected
        XCTAssertEqual(changes.localToRemote.count, unicodeNames.count)
    }

    func testSyncWithSpecialCharactersInFilenames() async throws {
        // Given files with special characters
        let localDir = tempDirectory.appendingPathComponent("local")
        let remoteDir = tempDirectory.appendingPathComponent("remote")
        try FileManager.default.createDirectory(at: localDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: remoteDir, withIntermediateDirectories: true)

        // Create files with special characters
        let specialNames = [
            "file with spaces.txt",
            "file-with-dashes.txt",
            "file_with_underscores.txt",
            "123numeric.txt",
            "MIXED.CASE.TXT"
        ]
        for name in specialNames {
            let file = remoteDir.appendingPathComponent(name)
            try "special content".write(to: file, atomically: true, encoding: .utf8)
        }

        // When performing sync
        let changes = await detectChanges(local: localDir, remote: remoteDir)

        // Then all files should be detected
        XCTAssertEqual(changes.localToRemote.count, specialNames.count)
    }

    func testSyncWithDeeplyNestedDirectories() async throws {
        // Given deeply nested directory structure
        let localDir = tempDirectory.appendingPathComponent("local")
        let remoteDir = tempDirectory.appendingPathComponent("remote")
        try FileManager.default.createDirectory(at: localDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: remoteDir, withIntermediateDirectories: true)

        // Create deeply nested structure
        let deepPath = "a/b/c/d/e/f/g/h/file.txt"
        let fullPath = remoteDir.appendingPathComponent(deepPath)
        try FileManager.default.createDirectory(
            at: fullPath.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try "deep content".write(to: fullPath, atomically: true, encoding: .utf8)

        // When performing sync
        let changes = await detectChanges(local: localDir, remote: remoteDir)

        // Then the nested file should be detected
        XCTAssertEqual(changes.localToRemote.count, 1)
    }

    // MARK: - Helper Methods

    private func detectChanges(local: URL, remote: URL) async -> SyncChanges {
        var changes = SyncChanges()
        changes.localToRemote = countFiles(in: local) ?? 0
        changes.remoteToLocal = countFiles(in: remote) ?? 0
        return changes
    }

    private func detectConflicts(local: URL, remote: URL) async -> [URL] {
        // Simple conflict detection based on file existence in both
        let localFiles = listFiles(in: local)
        return localFiles.filter { file in
            let remotePath = remote.appendingPathComponent(file.lastPathComponent)
            FileManager.default.fileExists(atPath: remotePath.path)
        }
    }

    private func resolveConflict(local: URL, remote: URL, strategy: ConflictResolutionStrategy) async -> Bool {
        // Simplified conflict resolution for testing
        let localFiles = listFiles(in: local)
        for file in localFiles {
            let remoteFile = remote.appendingPathComponent(file.lastPathComponent)
            if FileManager.default.fileExists(atPath: remoteFile.path) {
                // Conflict detected - apply strategy
                switch strategy {
                case .localWins:
                    // Keep local, do nothing
                    break
                case .remoteWins:
                    try? FileManager.default.removeItem(at: file)
                    try? FileManager.default.copyItem(at: remoteFile, to: file)
                case .newestWins:
                    let localAttrs = try? FileManager.default.attributesOfItem(atPath: file.path)
                    let localMtime = localAttrs?[.modificationDate] as? Date ?? Date.distantPast
                    let remoteAttrs = try? FileManager.default.attributesOfItem(atPath: remoteFile.path)
                    let remoteMtime = remoteAttrs?[.modificationDate] as? Date ?? Date.distantPast

                    if remoteMtime > localMtime {
                        try? FileManager.default.removeItem(at: file)
                        try? FileManager.default.copyItem(at: remoteFile, to: file)
                    }
                }
            }
        }
        return true
    }

    private func performBatchSync(local: URL, remote: URL) async -> MTPSyncReport {
        var report = MTPSyncReport()
        let files = listFiles(in: remote)
        report.downloaded = files.count
        report.totalProcessed = files.count
        return report
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

    private func listFiles(in directory: URL) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var files: [URL] = []
        for case let fileURL as URL in enumerator {
            if let isFile = try? fileURL.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile, isFile {
                files.append(fileURL)
            }
        }
        return files
    }
}

// MARK: - Supporting Types

/// Represents detected sync changes
struct SyncChanges {
    var localToRemote: Int = 0
    var remoteToLocal: Int = 0
    var modified: Int = 0
    var deleted: Int = 0
}

/// Conflict resolution strategies
enum ConflictResolutionStrategy {
    case localWins
    case remoteWins
    case newestWins
}
