// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import OSLog

/// Ladder for resolving a safe write target folder on MTP devices.
/// Some devices (Xiaomi, OnePlus) return InvalidParameter (0x201D) when writing to storage root.
public struct WriteTargetLadder {
  /// Fallback preferred folder names in priority order (used when no quirk preference is set)
  public static let fallbackPreferredFolders = [
    "Download", "Downloads", "DCIM", "Camera", "Pictures", "Documents",
  ]

  /// Resolve a safe parent handle for writing.
  /// - Parameters:
  ///   - device: The MTP device actor.
  ///   - storage: The target storage ID.
  ///   - explicitParent: Optional explicit parent handle (if provided, used directly).
  ///   - requiresSubfolder: Whether the device requires a subfolder (not root).
  ///   - preferredWriteFolder: Optional device-specific preferred folder from quirks.
  ///   - excludingParent: Optional parent handle to skip when selecting fallback folders.
  /// - Returns: A tuple of (storageID, parentHandle) where the file should be written.
  public static func resolveTarget(
    device: any MTPDevice,
    storage: MTPStorageID,
    explicitParent: MTPObjectHandle?,
    requiresSubfolder: Bool,
    preferredWriteFolder: String?,
    excludingParent: MTPObjectHandle? = nil
  ) async throws -> (MTPStorageID, MTPObjectHandle) {
    // If explicit parent provided, use it directly
    if let parent = explicitParent {
      return (storage, parent)
    }

    // If no subfolder required, write to root
    if !requiresSubfolder {
      return (storage, 0xFFFFFFFF)
    }

    // List root objects to find available folders
    let rootStream = device.list(parent: nil, in: storage)
    var rootItems: [MTPObjectInfo] = []
    for try await batch in rootStream {
      rootItems.append(contentsOf: batch)
    }

    // Find folders (format code 0x3001 = Association)
    let folders = rootItems.filter { $0.formatCode == 0x3001 }

    // Try device-specific preferred folder first if specified
    if let preferred = preferredWriteFolder {
      if let match = folders.first(where: {
        $0.name.caseInsensitiveCompare(preferred) == .orderedSame
          && $0.handle != excludingParent
      }) {
        Logger(subsystem: "SwiftMTP", category: "write")
          .info("Using device-preferred folder: \(match.name)")
        return (storage, match.handle)
      }
    }

    // Try fallback preferred folder names
    for name in Self.fallbackPreferredFolders {
      if let match = folders.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame })
      {
        if match.handle == excludingParent { continue }
        Logger(subsystem: "SwiftMTP", category: "write")
          .info("Using fallback preferred folder: \(match.name)")
        return (storage, match.handle)
      }
    }

    // Fall back to first available folder
    if let firstFolder = folders.first(where: { $0.handle != excludingParent }) {
      Logger(subsystem: "SwiftMTP", category: "write")
        .info("Using first available folder: \(firstFolder.name)")
      return (storage, firstFolder.handle)
    }

    // No folders found - create SwiftMTP at root as fallback
    Logger(subsystem: "SwiftMTP", category: "write")
      .info("No folders found, creating SwiftMTP at root")
    let swiftMTPFolder = try await device.createFolder(parent: nil, name: "SwiftMTP", storage: storage)
    return (storage, swiftMTPFolder)
  }
}
