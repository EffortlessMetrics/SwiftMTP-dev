// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation

/// Codable request/response types for XPC communication
/// These are used by the File Provider extension to communicate with the host app

public struct ReadRequest: Codable, Sendable {
    public let deviceId: String
    public let objectHandle: UInt32
    public let bookmark: Data?

    public init(deviceId: String, objectHandle: UInt32, bookmark: Data? = nil) {
        self.deviceId = deviceId
        self.objectHandle = objectHandle
        self.bookmark = bookmark
    }
}

public struct ReadResponse: Codable, Sendable {
    public let success: Bool
    public let errorMessage: String?
    public let tempFileURL: URL?
    public let fileSize: UInt64?

    public init(success: Bool, errorMessage: String? = nil, tempFileURL: URL? = nil, fileSize: UInt64? = nil) {
        self.success = success
        self.errorMessage = errorMessage
        self.tempFileURL = tempFileURL
        self.fileSize = fileSize
    }
}

public struct StorageListRequest: Codable, Sendable {
    public let deviceId: String

    public init(deviceId: String) {
        self.deviceId = deviceId
    }
}

public struct StorageInfo: Codable, Sendable {
    public let storageId: UInt32
    public let description: String
    public let capacityBytes: UInt64
    public let freeBytes: UInt64

    public init(storageId: UInt32, description: String, capacityBytes: UInt64, freeBytes: UInt64) {
        self.storageId = storageId
        self.description = description
        self.capacityBytes = capacityBytes
        self.freeBytes = freeBytes
    }
}

public struct StorageListResponse: Codable, Sendable {
    public let success: Bool
    public let errorMessage: String?
    public let storages: [StorageInfo]?

    public init(success: Bool, errorMessage: String? = nil, storages: [StorageInfo]? = nil) {
        self.success = success
        self.errorMessage = errorMessage
        self.storages = storages
    }
}

public struct ObjectListRequest: Codable, Sendable {
    public let deviceId: String
    public let storageId: UInt32
    public let parentHandle: UInt32?

    public init(deviceId: String, storageId: UInt32, parentHandle: UInt32? = nil) {
        self.deviceId = deviceId
        self.storageId = storageId
        self.parentHandle = parentHandle
    }
}

public struct ObjectInfo: Codable, Sendable {
    public let handle: UInt32
    public let name: String
    public let sizeBytes: UInt64?
    public let isDirectory: Bool
    public let modifiedDate: Date?

    public init(handle: UInt32, name: String, sizeBytes: UInt64?, isDirectory: Bool, modifiedDate: Date?) {
        self.handle = handle
        self.name = name
        self.sizeBytes = sizeBytes
        self.isDirectory = isDirectory
        self.modifiedDate = modifiedDate
    }
}

public struct ObjectListResponse: Codable, Sendable {
    public let success: Bool
    public let errorMessage: String?
    public let objects: [ObjectInfo]?

    public init(success: Bool, errorMessage: String? = nil, objects: [ObjectInfo]? = nil) {
        self.success = success
        self.errorMessage = errorMessage
        self.objects = objects
    }
}

/// XPC service protocol that the File Provider extension calls
/// This is the main interface for Finder integration
@objc public protocol MTPXPCService {
    func ping(reply: @escaping (String) -> Void)

    func readObject(_ request: ReadRequest, withReply reply: @escaping (ReadResponse) -> Void)

    func listStorages(_ request: StorageListRequest, withReply reply: @escaping (StorageListResponse) -> Void)

    func listObjects(_ request: ObjectListRequest, withReply reply: @escaping (ObjectListResponse) -> Void)

    func getObjectInfo(deviceId: String, storageId: UInt32, objectHandle: UInt32, withReply reply: @escaping (ReadResponse) -> Void)
}

/// XPC service name for the host app
public let MTPXPCServiceName = "com.example.SwiftMTP.MTPXPCService"
