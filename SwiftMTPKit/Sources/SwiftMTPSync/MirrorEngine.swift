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
  /// Number of conflicts detected during the mirror
  public var conflictsDetected: Int = 0
  /// Records of how each conflict was resolved
  public var conflictResolutions: [ConflictResolutionRecord] = []

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
public final class MirrorEngine: Sendable {
  private let snapshotter: Snapshotter
  private let diffEngine: DiffEngine
  private let journal: any TransferJournal
  private let log = MTPLog.sync
  /// Strategy applied when both sides have changed since last sync.
  public let conflictStrategy: ConflictResolutionStrategy
  /// Optional resolver callback used when `conflictStrategy == .ask`.
  private let conflictResolver: ConflictResolver?

  public init(
    snapshotter: Snapshotter, diffEngine: DiffEngine, journal: any TransferJournal,
    conflictStrategy: ConflictResolutionStrategy = .newerWins,
    conflictResolver: ConflictResolver? = nil
  ) {
    self.snapshotter = snapshotter
    self.diffEngine = diffEngine
    self.journal = journal
    self.conflictStrategy = conflictStrategy
    self.conflictResolver = conflictResolver
  }

  /// Mirror device contents to local directory
  /// - Parameters:
  ///   - device: The MTP device to mirror
  ///   - deviceId: Unique identifier for the device
  ///   - root: Local directory to mirror into
  ///   - include: Optional filter function to include/exclude objects
  /// - Returns: Report of the mirror operation
  public func mirror(
    device: any MTPDevice, deviceId: MTPDeviceID, to root: URL,
    include: (@Sendable (MTPDiff.Row) -> Bool)? = nil
  ) async throws -> MTPSyncReport {
    log.info("Starting mirror operation for device \(deviceId.raw) to \(root.path)")

    let startTime = Date()
    var report = MTPSyncReport()

    // Take a new snapshot
    let newGen = try await snapshotter.capture(device: device, deviceId: deviceId)

    // Get previous generation for diff
    let prevGen = try snapshotter.previousGeneration(for: deviceId, before: newGen)

    // Compute differences
    let delta = try await diffEngine.diff(deviceId: deviceId, oldGen: prevGen, newGen: newGen)

    log.info(
      "Mirror diff computed for device \(deviceId.raw): +\(delta.added.count) -\(delta.removed.count) ~\(delta.modified.count)"
    )

    // Process added and modified files
    let filesToDownload = delta.added + delta.modified

    for file in filesToDownload {
      if let include = include, !include(file) {
        report.skipped += 1
        continue
      }

      let localURL = pathKeyToLocalURL(file.pathKey, root: root)

      // Conflict detection: if the file is in "modified" and a local copy exists
      // with different content (size or mtime), we have a conflict.
      if delta.modified.contains(where: { $0.pathKey == file.pathKey }),
        FileManager.default.fileExists(atPath: localURL.path)
      {
        let conflict = try detectConflict(file: file, localURL: localURL)
        if let conflict = conflict {
          report.conflictsDetected += 1
          let resolution = try await resolveConflict(
            conflict: conflict, file: file, localURL: localURL, device: device, root: root)
          report.conflictResolutions.append(resolution)
          try? await journal.recordConflictResolution(
            pathKey: file.pathKey, strategy: conflictStrategy.rawValue,
            outcome: resolution.outcome.rawValue)
          switch resolution.outcome {
          case .skipped, .pending:
            report.skipped += 1
          case .keptLocal:
            report.skipped += 1
          case .keptDevice:
            do {
              try await downloadFile(file, from: device, to: root)
              report.downloaded += 1
            } catch {
              log.error("Failed to download conflicted file \(file.pathKey): \(error.localizedDescription)")
              report.failed += 1
            }
          case .keptBoth:
            do {
              try await downloadFile(file, from: device, to: root, suffix: "-device")
              report.downloaded += 1
            } catch {
              log.error("Failed to download conflicted file \(file.pathKey): \(error.localizedDescription)")
              report.failed += 1
            }
          }
          continue
        }
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
    log.info(
      "Mirror operation completed for device \(deviceId.raw): downloaded \(report.downloaded), skipped \(report.skipped), failed \(report.failed) in \(duration)s"
    )

    return report
  }

  /// Download a single file from device to local mirror directory
  private func downloadFile(
    _ file: MTPDiff.Row, from device: any MTPDevice, to root: URL, suffix: String? = nil
  ) async throws {
    var localURL = pathKeyToLocalURL(file.pathKey, root: root)

    // Apply suffix for keep-both conflict resolution (e.g. "photo-device.jpg")
    if let suffix = suffix {
      let ext = localURL.pathExtension
      let base = localURL.deletingPathExtension().lastPathComponent
      let newName = ext.isEmpty ? "\(base)\(suffix)" : "\(base)\(suffix).\(ext)"
      localURL = localURL.deletingLastPathComponent().appendingPathComponent(newName)
    }

    // Ensure parent directory exists
    let parentDir = localURL.deletingLastPathComponent()
    try FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true)

    // Check if file already exists and is up to date
    if try shouldSkipDownload(of: localURL, file: file) {
      log.debug("Skipping download - file already exists and is current")
      return
    }

    // Write to a temp file first, then atomically move on success
    let tempURL = localURL.appendingPathExtension("swiftmtp-partial")

    // Register with journal so the transfer is resumable
    let transferId = try await journal.beginRead(
      device: await device.id,
      handle: file.handle,
      name: localURL.lastPathComponent,
      size: file.size,
      supportsPartial: false,
      tempURL: tempURL,
      finalURL: localURL,
      etag: (size: file.size, mtime: file.mtime)
    )

    do {
      let progress = try await device.read(handle: file.handle, range: nil, to: tempURL)
      // Atomic move from temp to final destination
      do {
        try FileManager.default.moveItem(at: tempURL, to: localURL)
      } catch CocoaError.fileWriteFileExists {
        try FileManager.default.removeItem(at: localURL)
        try FileManager.default.moveItem(at: tempURL, to: localURL)
      }
      try await journal.complete(id: transferId)
      log.debug("Downloaded file successfully")
    } catch {
      // Clean up partial temp file on failure
      try? FileManager.default.removeItem(at: tempURL)
      try? await journal.fail(id: transferId, error: error)
      throw error
    }
  }

  /// Convert a path key to a local file URL
  internal func pathKeyToLocalURL(_ pathKey: String, root: URL) -> URL {
    let (_, components) = PathKey.parse(pathKey)
    // Sanitize each component to guard against path traversal from device-supplied names.
    let safeComponents = components.compactMap { PathSanitizer.sanitize($0) }
    let relativePath = safeComponents.joined(separator: "/")
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

    // Compare sizes (guard against missing attribute)
    if let remoteSize = file.size {
      guard let localSizeVal = attributes[.size] as? NSNumber else { return false }
      if localSizeVal.uint64Value != remoteSize { return false }
    }

    // Compare modification times (with tolerance)
    if let remoteMtime = file.mtime {
      guard let localMtime = attributes[.modificationDate] as? Date else { return false }
      let timeDiff = abs(localMtime.timeIntervalSince1970 - remoteMtime.timeIntervalSince1970)
      if timeDiff > 300 {  // 5 minute tolerance
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
  public func mirror(
    device: any MTPDevice, deviceId: MTPDeviceID, to root: URL,
    includePattern: String
  ) async throws -> MTPSyncReport {
    let filter: @Sendable (MTPDiff.Row) -> Bool = { [self] row in
      return self.matchesPattern(row.pathKey, pattern: includePattern)
    }

    return try await mirror(device: device, deviceId: deviceId, to: root, include: filter)
  }

  /// Mirror with format-based filtering
  /// - Parameters:
  ///   - device: The MTP device to mirror
  ///   - deviceId: Unique identifier for the device
  ///   - root: Local directory to mirror into
  ///   - formatFilter: Format filter controlling which object types to include/exclude
  /// - Returns: Report of the mirror operation
  public func mirror(
    device: any MTPDevice, deviceId: MTPDeviceID, to root: URL,
    formatFilter: MTPFormatFilter
  ) async throws -> MTPSyncReport {
    let filter: @Sendable (MTPDiff.Row) -> Bool = { row in
      return formatFilter.matches(format: row.format)
    }

    return try await mirror(device: device, deviceId: deviceId, to: root, include: filter)
  }

  /// Check if a path matches a glob pattern
  internal func matchesPattern(_ pathKey: String, pattern: String) -> Bool {
    // 1. Strip storage ID and get components
    let (_, pathComponents) = PathKey.parse(pathKey)

    // 2. Normalize pattern and split into components
    let cleanPattern = pattern.hasPrefix("/") ? String(pattern.dropFirst()) : pattern
    let patternComponents = cleanPattern.split(separator: "/", omittingEmptySubsequences: false)
      .map(String.init)

    if pattern == "**" || pattern == "/**" { return true }

    // Recursive matching function
    func match(pIdx: Int, cIdx: Int) -> Bool {
      // Base case: both pattern and path exhausted
      if pIdx == patternComponents.count {
        return cIdx == pathComponents.count
      }

      let pComp = patternComponents[pIdx]

      guard pComp == "**" else {
        // Regular component match (including *)
        if cIdx >= pathComponents.count { return false }

        let cComp = pathComponents[cIdx]
        if matchComponent(pComp, with: cComp) {
          return match(pIdx: pIdx + 1, cIdx: cIdx + 1)
        }
        return false
      }
      // ** matches zero or more components
      // Try matching 0, 1, 2... path components with the rest of the pattern
      for i in 0...(pathComponents.count - cIdx) {
        if match(pIdx: pIdx + 1, cIdx: cIdx + i) {
          return true
        }
      }
      return false
    }

    func matchComponent(_ pattern: String, with component: String) -> Bool {
      // Escape regex special characters except *
      let specials = ["\\", ".", "+", "(", ")", "[", "]", "{", "}", "^", "$", "|"]
      var regexPattern = pattern
      for char in specials {
        regexPattern = regexPattern.replacingOccurrences(of: char, with: "\\" + char)
      }

      // Convert * to [^/]*
      regexPattern = regexPattern.replacingOccurrences(of: "*", with: ".*")

      let regex = try! NSRegularExpression(
        pattern: "^\(regexPattern)$", options: [.caseInsensitive])
      let range = NSRange(location: 0, length: component.utf16.count)
      return regex.firstMatch(in: component, options: [], range: range) != nil
    }

    return match(pIdx: 0, cIdx: 0)
  }

  // MARK: - Conflict Detection & Resolution

  /// Detect whether a modified device file conflicts with its local counterpart.
  /// A conflict exists when the local file differs in size or modification time
  /// from the device version — meaning both sides changed since the last sync.
  internal func detectConflict(file: MTPDiff.Row, localURL: URL) throws -> MTPConflictInfo? {
    guard FileManager.default.fileExists(atPath: localURL.path) else { return nil }

    let attrs = try FileManager.default.attributesOfItem(atPath: localURL.path)
    let localSize = (attrs[.size] as? NSNumber)?.uint64Value
    let localMtime = attrs[.modificationDate] as? Date

    let sizeDiffers: Bool
    if let ls = localSize, let ds = file.size {
      sizeDiffers = ls != ds
    } else {
      sizeDiffers = false
    }

    let timeDiffers: Bool
    if let lm = localMtime, let dm = file.mtime {
      timeDiffers = abs(lm.timeIntervalSince1970 - dm.timeIntervalSince1970) > 300
    } else {
      timeDiffers = false
    }

    guard sizeDiffers || timeDiffers else { return nil }

    return MTPConflictInfo(
      pathKey: file.pathKey, handle: file.handle,
      deviceSize: file.size, deviceMtime: file.mtime,
      localSize: localSize, localMtime: localMtime)
  }

  /// Apply the configured conflict resolution strategy to a detected conflict.
  internal func resolveConflict(
    conflict: MTPConflictInfo, file: MTPDiff.Row, localURL: URL,
    device: any MTPDevice, root: URL
  ) async throws -> ConflictResolutionRecord {
    let outcome: ConflictOutcome

    switch conflictStrategy {
    case .newerWins:
      let localMtime = conflict.localMtime ?? .distantPast
      let deviceMtime = conflict.deviceMtime ?? .distantPast
      outcome = deviceMtime > localMtime ? .keptDevice : .keptLocal
      log.info("Conflict on \(conflict.pathKey): newer-wins → \(outcome.rawValue)")

    case .localWins:
      outcome = .keptLocal
      log.info("Conflict on \(conflict.pathKey): local-wins → kept local")

    case .deviceWins:
      outcome = .keptDevice
      log.info("Conflict on \(conflict.pathKey): device-wins → kept device")

    case .keepBoth:
      outcome = .keptBoth
      // Rename local file with "-local" suffix to preserve it
      let ext = localURL.pathExtension
      let base = localURL.deletingPathExtension().lastPathComponent
      let localRename = ext.isEmpty ? "\(base)-local" : "\(base)-local.\(ext)"
      let renamedURL = localURL.deletingLastPathComponent().appendingPathComponent(localRename)
      try? FileManager.default.moveItem(at: localURL, to: renamedURL)
      log.info("Conflict on \(conflict.pathKey): keep-both → renamed local, downloading device")

    case .skip:
      outcome = .skipped
      log.info("Conflict on \(conflict.pathKey): skip → skipped")

    case .ask:
      if let resolver = conflictResolver {
        outcome = await resolver(conflict)
        log.info("Conflict on \(conflict.pathKey): ask → user chose \(outcome.rawValue)")
      } else {
        outcome = .pending
        log.warning("Conflict on \(conflict.pathKey): ask strategy but no resolver — marking pending")
      }
    }

    return ConflictResolutionRecord(
      pathKey: conflict.pathKey, strategy: conflictStrategy, outcome: outcome)
  }
}
