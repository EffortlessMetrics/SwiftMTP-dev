// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import FileProvider

/// File Provider item representing an MTP object (file or directory)
public final class MTPFileProviderItem: NSObject, NSFileProviderItem {
    public let deviceId: String
    public let storageId: UInt32?
    public let objectHandle: UInt32?
    public let name: String
    public let size: UInt64?
    public let isDirectory: Bool
    public let modifiedDate: Date?

    public init(deviceId: String, storageId: UInt32?, objectHandle: UInt32?, name: String, size: UInt64?, isDirectory: Bool, modifiedDate: Date?) {
        self.deviceId = deviceId
        self.storageId = storageId
        self.objectHandle = objectHandle
        self.name = name
        self.size = size
        self.isDirectory = isDirectory
        self.modifiedDate = modifiedDate
        super.init()
    }

    // MARK: - NSFileProviderItem Protocol

    public var itemIdentifier: NSFileProviderItemIdentifier {
        if let objectHandle = objectHandle {
            return NSFileProviderItemIdentifier("\(deviceId):\(storageId ?? 0):\(objectHandle)")
        } else if let storageId = storageId {
            return NSFileProviderItemIdentifier("\(deviceId):\(storageId)")
        } else {
            return NSFileProviderItemIdentifier(deviceId)
        }
    }

    public var parentItemIdentifier: NSFileProviderItemIdentifier {
        if let objectHandle = objectHandle, let storageId = storageId {
            // File item - parent is the directory containing it
            // For simplicity, assume root directory for now
            return NSFileProviderItemIdentifier("\(deviceId):\(storageId)")
        } else if let storageId = storageId {
            // Storage item - parent is the device
            return NSFileProviderItemIdentifier(deviceId)
        } else {
            // Device item - root
            return NSFileProviderItemIdentifier.rootContainer
        }
    }

    public var filename: String {
        return name
    }

    public var contentType: UTType {
        if isDirectory {
            return .folder
        } else {
            // Basic content type detection - would need enhancement for better type detection
            let pathExtension = (name as NSString).pathExtension.lowercased()
            switch pathExtension {
            case "jpg", "jpeg", "png", "gif", "bmp":
                return .image
            case "mp4", "mov", "avi", "mkv":
                return .movie
            case "mp3", "aac", "wav", "flac":
                return .audio
            case "txt", "md", "rtf":
                return .text
            default:
                return .data
            }
        }
    }

    public var capabilities: NSFileProviderItemCapabilities {
        var caps: NSFileProviderItemCapabilities = []

        if isDirectory {
            caps.insert(.allowsReading)
            caps.insert(.allowsContentEnumerating)
            // Note: No writing capabilities for tech preview
        } else {
            caps.insert(.allowsReading)
            // Note: No writing capabilities for tech preview
        }

        return caps
    }

    public var documentSize: NSNumber? {
        guard let size = size else { return nil }
        return NSNumber(value: size)
    }

    public var creationDate: Date? {
        // MTP doesn't always provide creation date, use modified date as fallback
        return modifiedDate
    }

    public var contentModificationDate: Date? {
        return modifiedDate
    }

    public var childItemCount: NSNumber? {
        // Only return count for directories
        guard isDirectory else { return nil }
        // For tech preview, return nil (unknown count)
        // In full implementation, you'd query the device for child count
        return nil
    }

    public var isDownloaded: Bool {
        // For MTP devices, content is only "downloaded" when explicitly requested
        // Since we use on-demand hydration, most items appear as not downloaded
        return false
    }

    public var isDownloading: Bool {
        // Not currently downloading
        return false
    }

    public var downloadingError: Error? {
        // No download error
        return nil
    }

    public var isUploaded: Bool {
        // Read-only for tech preview
        return true
    }

    public var isUploading: Bool {
        // Read-only for tech preview
        return false
    }

    public var uploadingError: Error? {
        // No upload error
        return nil
    }

    // MARK: - Helper Methods

    /// Create an item identifier from an MTP object path
    public static func itemIdentifier(forDevice deviceId: String, storageId: UInt32? = nil, objectHandle: UInt32? = nil) -> NSFileProviderItemIdentifier {
        if let objectHandle = objectHandle {
            return NSFileProviderItemIdentifier("\(deviceId):\(storageId ?? 0):\(objectHandle)")
        } else if let storageId = storageId {
            return NSFileProviderItemIdentifier("\(deviceId):\(storageId)")
        } else {
            return NSFileProviderItemIdentifier(deviceId)
        }
    }

    /// Parse an item identifier back to components
    public static func parseItemIdentifier(_ identifier: NSFileProviderItemIdentifier) -> (deviceId: String, storageId: UInt32?, objectHandle: UInt32?)? {
        let components = identifier.rawValue.components(separatedBy: ":")

        guard components.count >= 1 else { return nil }

        let deviceId = components[0]

        if components.count >= 2, let storageId = UInt32(components[1]) {
            if components.count >= 3, let objectHandle = UInt32(components[2]) {
                return (deviceId, storageId, objectHandle)
            } else {
                return (deviceId, storageId, nil)
            }
        } else {
            return (deviceId, nil, nil)
        }
    }
}
