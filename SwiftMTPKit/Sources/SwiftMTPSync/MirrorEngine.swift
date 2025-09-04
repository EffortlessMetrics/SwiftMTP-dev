// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import SwiftMTPCore
import SwiftMTPIndex
import SwiftMTPObservability

/// Result of a mirror operation
public struct MTPSyncReport: Sendable {
    /// Number of files successfully downloaded
    public var downloaded: Int = 0
    /// Number of files skipped (due to filtering or already existing)
    public var skipped: Int = 0
    /// Number of files that failed to download
    public var failed: Int = 0

    /// Total number of files processed
    public var totalProcessed: Int {
        downloaded + skipped + failed
    }

    /// Success rate as a percentage
    public var successRate: Double {
        guard totalProcessed > 0 else { return 0 }
        return Double(downloaded) / Double(totalProcessed) * 100
    }
}

/// Engine for mirroring device contents to local filesystem
public final class MirrorEngine {
    private let snapshotter: Snapshotter
    private let diffEngine: DiffEngine
    private let journal: TransferJournal
    private let log = MTPLog.sync

    public init(snapshotter: Snapshotter, diffEngine: DiffEngine, journal: TransferJournal) {
        self.snapshotter = snapshotter
        self.diffEngine = diffEngine
        self.journal = journal
    }

    /// Mirror device contents to local directory
    /// - Parameters:
    ///   - device: The MTP device to mirror
    ///   - deviceId: Unique identifier for the device
    ///   - root: Local directory to mirror into
    ///   - include: Optional filter function to include/exclude objects
    /// - Returns: Report of the mirror operation
    public func mirror(device: any MTPDevice, deviceId: MTPDeviceID, to root: URL,
                       include: ((MTPDiff.Row) -> Bool)? = nil) async throws -> MTPSyncReport {
        log.info("Starting mirror operation for device \(deviceId.raw) to \(root.path)")

        let startTime = Date()
        var report = MTPSyncReport()

        // Take a new snapshot
        let newGen = try await snapshotter.capture(device: device, deviceId: deviceId)

        // Get previous generation for diff
        let prevGen = try snapshotter.previousGeneration(for: deviceId, before: newGen)

        // Compute differences
        let delta = try diffEngine.diff(deviceId: deviceId, oldGen: prevGen, newGen: newGen)

        log.info("Mirror diff computed for device \(deviceId.raw): +\(delta.added.count) -\(delta.removed.count) ~\(delta.modified.count)")

        // Process added and modified files
        let filesToDownload = delta.added + delta.modified

        for file in filesToDownload {
            if let include = include, !include(file) {
                report.skipped += 1
                continue
            }

            do {
                try await downloadFile(file, from: device, to: root)
                report.downloaded += 1
            } catch {
                log.error("Failed to download file \(file.pathKey): \(error.localizedDescription)")
                report.failed += 1
            }
        }

        // Handle removed files (optional - one-way mirror typically keeps them)
        // In a future version, we could add a flag to remove local files that were deleted on device

        let duration = Date().timeIntervalSince(startTime)
        log.info("Mirror operation completed for device \(deviceId.raw): downloaded \(report.downloaded), skipped \(report.skipped), failed \(report.failed) in \(duration)s")

        return report
    }

    /// Download a single file from device to local mirror directory
    private func downloadFile(_ file: MTPDiff.Row, from device: any MTPDevice, to root: URL) async throws {
        // Convert path key to local file URL
        let localURL = pathKeyToLocalURL(file.pathKey, root: root)

        // Ensure parent directory exists
        let parentDir = localURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true)

        // Check if file already exists and is up to date
        if try shouldSkipDownload(of: localURL, file: file) {
            log.debug("Skipping download - file \(file.pathKey) already exists and is current at \(localURL.path)")
            return
        }

        // Download the file (this will use resumable transfers automatically via the device actor)
        let progress = try await device.read(handle: file.handle, range: nil, to: localURL)

        // Wait for completion
        _ = progress.completedUnitCount

        log.debug("Downloaded file \(file.pathKey) to \(localURL.path) (\(progress.completedUnitCount) bytes)")
    }

    /// Convert a path key to a local file URL
    internal func pathKeyToLocalURL(_ pathKey: String, root: URL) -> URL {
        let (_, components) = PathKey.parse(pathKey)
        let relativePath = components.joined(separator: "/")
        return root.appendingPathComponent(relativePath)
    }

    /// Check if we should skip downloading a file that already exists locally
    internal func shouldSkipDownload(of localURL: URL, file: MTPDiff.Row) throws -> Bool {
        // Check if local file exists
        guard FileManager.default.fileExists(atPath: localURL.path) else {
            return false
        }

        // Get local file attributes
        let attributes = try FileManager.default.attributesOfItem(atPath: localURL.path)
        guard let localSize = attributes[.size] as? UInt64 else {
            return false
        }

        // Compare sizes
        if let remoteSize = file.size, localSize != remoteSize {
            return false
        }

        // Compare modification times (with tolerance)
        if let remoteMtime = file.mtime {
            let localMtime = attributes[.modificationDate] as? Date ?? Date.distantPast
            let timeDiff = abs(localMtime.timeIntervalSince1970 - remoteMtime.timeIntervalSince1970)
            if timeDiff > 300 { // 5 minute tolerance
                return false
            }
        }

        return true
    }

    /// Mirror with glob pattern filtering
    /// - Parameters:
    ///   - device: The MTP device to mirror
    ///   - deviceId: Unique identifier for the device
    ///   - root: Local directory to mirror into
    ///   - includePattern: Glob pattern to match files (e.g., "DCIM/**", "*.jpg")
    /// - Returns: Report of the mirror operation
    public func mirror(device: any MTPDevice, deviceId: MTPDeviceID, to root: URL,
                       includePattern: String) async throws -> MTPSyncReport {
        let filter: (MTPDiff.Row) -> Bool = { [self] row in
            return self.matchesPattern(row.pathKey, pattern: includePattern)
        }

        return try await mirror(device: device, deviceId: deviceId, to: root, include: filter)
    }

    /// Check if a path matches a glob pattern
    internal func matchesPattern(_ path: String, pattern: String) -> Bool {
        // Simple glob matching - could be enhanced with a proper glob library
        if pattern == "**" { return true }

        // Convert glob to regex
        let regexPattern = pattern
            .replacingOccurrences(of: "**", with: ".*")
            .replacingOccurrences(of: "*", with: "[^/]*")

        do {
            let regex = try NSRegularExpression(pattern: "^\(regexPattern)$", options: [])
            let range = NSRange(location: 0, length: path.utf8.count)
            return regex.firstMatch(in: path, options: [], range: range) != nil
        } catch {
            log.warning("Invalid glob pattern '\(pattern)': \(error.localizedDescription)")
            return false
        }
    }
}
