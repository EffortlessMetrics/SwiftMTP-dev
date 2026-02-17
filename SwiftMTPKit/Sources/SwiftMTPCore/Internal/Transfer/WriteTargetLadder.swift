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
  private static let mediaFirstPreferredPaths = ["DCIM/Camera", "Pictures", "Download", "SwiftMTP"]

  private static func isMediaFirstTargetDevice(_ summary: MTPDeviceSummary) -> Bool {
    guard let vid = summary.vendorID, let pid = summary.productID else { return false }
    return (vid == 0x2717 && pid == 0xFF40) || (vid == 0x2A70 && pid == 0xF003)
  }

  private static func preferredFolderPaths(
    device: any MTPDevice,
    preferredWriteFolder: String?
  ) -> [String] {
    if isMediaFirstTargetDevice(device.summary) {
      return mediaFirstPreferredPaths
    }

    var ordered: [String] = []
    if let preferredWriteFolder, !preferredWriteFolder.isEmpty {
      ordered.append(preferredWriteFolder)
    }
    for name in fallbackPreferredFolders where !ordered.contains(where: {
      $0.caseInsensitiveCompare(name) == .orderedSame
    }) {
      ordered.append(name)
    }
    return ordered
  }

  /// Resolve a folder handle by name in root or first-level subfolders.
  /// Used when some devices invalidate handles between retries.
  public static func resolveFolderHandleByName(
    device: any MTPDevice,
    storage: MTPStorageID,
    folderName: String
  ) async throws -> MTPObjectHandle? {
    let rootFolders = try await listFolders(device: device, storage: storage, parent: nil)
    if let rootMatch = rootFolders.first(where: {
      $0.name.caseInsensitiveCompare(folderName) == .orderedSame
    }) {
      return rootMatch.handle
    }

    for parent in rootFolders {
      let children = try await listFolders(device: device, storage: storage, parent: parent.handle)
      if let childMatch = children.first(where: {
        $0.name.caseInsensitiveCompare(folderName) == .orderedSame
      }) {
        return childMatch.handle
      }
    }
    return nil
  }

  /// Resolve a safe parent handle for writing.
  /// - Parameters:
  ///   - device: The MTP device actor.
  ///   - storage: The target storage ID.
  ///   - explicitParent: Optional explicit parent handle (if provided, used directly).
  ///   - requiresSubfolder: Whether the device requires a subfolder (not root).
  ///   - preferredWriteFolder: Optional device-specific preferred folder from quirks.
  ///   - excludingParent: Optional parent handle to skip when selecting fallback folders.
  ///   - excludingParents: Optional parent handles to skip when selecting fallback folders.
  /// - Returns: A tuple of (storageID, parentHandle) where the file should be written.
  public static func resolveTarget(
    device: any MTPDevice,
    storage: MTPStorageID,
    explicitParent: MTPObjectHandle?,
    requiresSubfolder: Bool,
    preferredWriteFolder: String?,
    excludingParent: MTPObjectHandle? = nil,
    excludingParents: Set<MTPObjectHandle> = []
  ) async throws -> (MTPStorageID, MTPObjectHandle) {
    var excluded = excludingParents
    if let excludingParent {
      excluded.insert(excludingParent)
    }

    // If explicit parent provided, use it directly
    if let parent = explicitParent {
      return (storage, parent)
    }

    // If no subfolder required, write to root
    if !requiresSubfolder {
      return (storage, 0xFFFFFFFF)
    }

    let rootFolders = try await listFolders(device: device, storage: storage, parent: nil)
    let preferredPaths = preferredFolderPaths(device: device, preferredWriteFolder: preferredWriteFolder)

    for preferredPath in preferredPaths {
      if preferredPath.caseInsensitiveCompare("SwiftMTP") == .orderedSame {
        if let swiftMTPHandle = try await ensureSwiftMTPFolder(
          device: device,
          storage: storage,
          rootFolders: rootFolders,
          preferredPaths: preferredPaths,
          excluded: excluded
        ) {
          Logger(subsystem: "SwiftMTP", category: "write")
            .info("Using preferred folder path: SwiftMTP")
          return (storage, swiftMTPHandle)
        }
        continue
      }

      if let resolved = try await resolveFolderPath(
        device: device,
        storage: storage,
        path: preferredPath,
        rootFolders: rootFolders
      ) {
        if excluded.contains(resolved.handle) { continue }
        Logger(subsystem: "SwiftMTP", category: "write")
          .info("Using preferred folder path: \(resolved.label)")
        return (storage, resolved.handle)
      }
    }

    // Fall back to first available folder
    if let firstFolder = rootFolders.first(where: { !excluded.contains($0.handle) }) {
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

  private static func listFolders(
    device: any MTPDevice,
    storage: MTPStorageID,
    parent: MTPObjectHandle?
  ) async throws -> [MTPObjectInfo] {
    let stream = device.list(parent: parent, in: storage)
    var items: [MTPObjectInfo] = []
    for try await batch in stream {
      items.append(contentsOf: batch)
    }
    return items.filter { $0.formatCode == 0x3001 }
  }

  private static func resolveFolderPath(
    device: any MTPDevice,
    storage: MTPStorageID,
    path: String,
    rootFolders: [MTPObjectInfo]
  ) async throws -> (handle: MTPObjectHandle, label: String)? {
    let components = path.split(separator: "/").map(String.init).filter { !$0.isEmpty }
    guard !components.isEmpty else { return nil }

    var currentParent: MTPObjectHandle?
    var currentFolders = rootFolders
    var resolvedLabel: [String] = []

    for component in components {
      guard
        let match = currentFolders.first(where: {
          $0.name.caseInsensitiveCompare(component) == .orderedSame
        })
      else {
        return nil
      }
      currentParent = match.handle
      resolvedLabel.append(match.name)
      currentFolders = try await listFolders(device: device, storage: storage, parent: match.handle)
    }

    guard let handle = currentParent else { return nil }
    return (handle: handle, label: resolvedLabel.joined(separator: "/"))
  }

  private static func ensureSwiftMTPFolder(
    device: any MTPDevice,
    storage: MTPStorageID,
    rootFolders: [MTPObjectInfo],
    preferredPaths: [String],
    excluded: Set<MTPObjectHandle>
  ) async throws -> MTPObjectHandle? {
    if let existingRootSwiftMTP = rootFolders.first(where: {
      $0.name.caseInsensitiveCompare("SwiftMTP") == .orderedSame
    }), !excluded.contains(existingRootSwiftMTP.handle) {
      return existingRootSwiftMTP.handle
    }

    var checkedParents = Set<MTPObjectHandle>()
    for preferredPath in preferredPaths where preferredPath.caseInsensitiveCompare("SwiftMTP") != .orderedSame {
      guard let resolved = try await resolveFolderPath(
        device: device,
        storage: storage,
        path: preferredPath,
        rootFolders: rootFolders
      ) else {
        continue
      }
      if !checkedParents.insert(resolved.handle).inserted || excluded.contains(resolved.handle) {
        continue
      }

      let childFolders = try await listFolders(device: device, storage: storage, parent: resolved.handle)
      if let existingChild = childFolders.first(where: {
        $0.name.caseInsensitiveCompare("SwiftMTP") == .orderedSame
      }), !excluded.contains(existingChild.handle) {
        return existingChild.handle
      }

      do {
        let created = try await device.createFolder(parent: resolved.handle, name: "SwiftMTP", storage: storage)
        if !excluded.contains(created) { return created }
      } catch {
        continue
      }
    }

    let createdRoot = try await device.createFolder(parent: nil, name: "SwiftMTP", storage: storage)
    if excluded.contains(createdRoot) { return nil }
    return createdRoot
  }
}
