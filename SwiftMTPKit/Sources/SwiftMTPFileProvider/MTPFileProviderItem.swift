// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import FileProvider
import UniformTypeIdentifiers

/// Represents an item (file or folder) in the MTP File Provider
public final class MTPFileProviderItem: NSObject, NSFileProviderItem {
    private let deviceId: String
    private let storageId: UInt32?
    private let objectHandle: UInt32?
    private let _parentHandle: UInt32?
    private let name: String
    private let size: UInt64?
    private let isDirectory: Bool
    private let modifiedDate: Date?

    public init(deviceId: String, storageId: UInt32?, objectHandle: UInt32?, parentHandle: UInt32? = nil, name: String, size: UInt64?, isDirectory: Bool, modifiedDate: Date?) {
        self.deviceId = deviceId
        self.storageId = storageId
        self.objectHandle = objectHandle
        self._parentHandle = parentHandle
        self.name = name
        self.size = size
        self.isDirectory = isDirectory
        self.modifiedDate = modifiedDate
        super.init()
    }

    public var itemIdentifier: NSFileProviderItemIdentifier {
        if let handle = objectHandle, let storageId = storageId {
            return NSFileProviderItemIdentifier("\(deviceId):\(storageId):\(handle)")
        } else if let storageId = storageId {
            return NSFileProviderItemIdentifier("\(deviceId):\(storageId)")
        } else {
            return NSFileProviderItemIdentifier(deviceId)
        }
    }

    public var parentItemIdentifier: NSFileProviderItemIdentifier {
        if let _ = objectHandle, let sid = storageId {
            if let ph = _parentHandle {
                // File/folder inside a subdirectory
                return NSFileProviderItemIdentifier("\(deviceId):\(sid):\(ph)")
            } else {
                // Object at storage root
                return NSFileProviderItemIdentifier("\(deviceId):\(sid)")
            }
        } else if let _ = storageId {
            // Storage item — parent is the device root
            return NSFileProviderItemIdentifier(deviceId)
        } else {
            // Device root — parent is the File Provider root
            return .rootContainer
        }
    }

    public var filename: String { name }

    public var contentType: UTType {
        if isDirectory {
            return .folder
        } else {
            let pathExtension = (name as NSString).pathExtension.lowercased()
            return UTType(filenameExtension: pathExtension) ?? .data
        }
    }

    public var documentSize: NSNumber? {
        size.map { NSNumber(value: $0) }
    }

    public var contentModificationDate: Date? {
        modifiedDate
    }

    // MARK: - Identifier Parsing

    public struct ItemComponents {
        public let deviceId: String
        public let storageId: UInt32?
        public let objectHandle: UInt32?
    }

    public static func parseItemIdentifier(_ identifier: NSFileProviderItemIdentifier) -> ItemComponents? {
        if identifier == .rootContainer { return nil }
        let parts = identifier.rawValue.split(separator: ":")
        if parts.count == 1 {
            return ItemComponents(deviceId: String(parts[0]), storageId: nil, objectHandle: nil)
        } else if parts.count == 2 {
            return ItemComponents(deviceId: String(parts[0]), storageId: UInt32(parts[1]), objectHandle: nil)
        } else if parts.count == 3 {
            return ItemComponents(deviceId: String(parts[0]), storageId: UInt32(parts[1]), objectHandle: UInt32(parts[2]))
        }
        return nil
    }
}
