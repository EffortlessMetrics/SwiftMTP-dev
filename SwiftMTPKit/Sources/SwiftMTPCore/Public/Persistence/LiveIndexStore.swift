// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation

// MARK: - DTOs

/// A cached MTP object from the live index.
public struct IndexedObject: Sendable, Equatable {
    public let deviceId: String
    public let storageId: UInt32
    public let handle: MTPObjectHandle
    public let parentHandle: MTPObjectHandle?
    public let name: String
    public let pathKey: String
    public let sizeBytes: UInt64?
    public let mtime: Date?
    public let formatCode: UInt16
    public let isDirectory: Bool
    public let changeCounter: Int64

    public init(
        deviceId: String, storageId: UInt32, handle: MTPObjectHandle,
        parentHandle: MTPObjectHandle?, name: String, pathKey: String,
        sizeBytes: UInt64?, mtime: Date?, formatCode: UInt16,
        isDirectory: Bool, changeCounter: Int64
    ) {
        self.deviceId = deviceId; self.storageId = storageId; self.handle = handle
        self.parentHandle = parentHandle; self.name = name; self.pathKey = pathKey
        self.sizeBytes = sizeBytes; self.mtime = mtime; self.formatCode = formatCode
        self.isDirectory = isDirectory; self.changeCounter = changeCounter
    }
}

/// A cached MTP storage from the live index.
public struct IndexedStorage: Sendable, Equatable {
    public let deviceId: String
    public let storageId: UInt32
    public let description: String
    public let capacity: UInt64?
    public let free: UInt64?
    public let readOnly: Bool

    public init(deviceId: String, storageId: UInt32, description: String, capacity: UInt64?, free: UInt64?, readOnly: Bool) {
        self.deviceId = deviceId; self.storageId = storageId; self.description = description
        self.capacity = capacity; self.free = free; self.readOnly = readOnly
    }
}

/// Represents a change to an object in the live index.
public struct IndexedObjectChange: Sendable {
    public enum ChangeKind: Sendable { case upserted, deleted }

    public let kind: ChangeKind
    public let object: IndexedObject

    public init(kind: ChangeKind, object: IndexedObject) {
        self.kind = kind; self.object = object
    }
}

// MARK: - Reader Protocol

/// Read-only access to the live object index.
/// Used by the File Provider extension (running in a separate process).
public protocol LiveIndexReader: Sendable {
    /// List children of a parent directory.
    func children(deviceId: String, storageId: UInt32, parentHandle: MTPObjectHandle?) async throws -> [IndexedObject]

    /// Fetch a single object by handle.
    func object(deviceId: String, handle: MTPObjectHandle) async throws -> IndexedObject?

    /// List all storages for a device.
    func storages(deviceId: String) async throws -> [IndexedStorage]

    /// Current change counter for a device (used as sync anchor).
    func currentChangeCounter(deviceId: String) async throws -> Int64

    /// Objects changed since a given change counter (for enumerateChanges).
    func changesSince(deviceId: String, anchor: Int64) async throws -> [IndexedObjectChange]
}

// MARK: - Writer Protocol

/// Write access to the live object index.
/// Used by the crawler running in the host app.
public protocol LiveIndexWriter: Sendable {
    /// Upsert a batch of objects from a crawl. Increments change counter.
    func upsertObjects(_ objects: [IndexedObject], deviceId: String) async throws

    /// Mark all children of a parent as stale (before re-crawl).
    func markStaleChildren(deviceId: String, storageId: UInt32, parentHandle: MTPObjectHandle?) async throws

    /// Remove a specific object (e.g., from objectRemoved event).
    func removeObject(deviceId: String, storageId: UInt32, handle: MTPObjectHandle) async throws

    /// Insert a single newly-discovered object.
    func insertObject(_ object: IndexedObject, deviceId: String) async throws

    /// Upsert storage metadata.
    func upsertStorage(_ storage: IndexedStorage) async throws

    /// Atomically increment and return the next change counter.
    func nextChangeCounter(deviceId: String) async throws -> Int64

    /// Purge stale objects (those marked stale but not refreshed by latest crawl).
    func purgeStale(deviceId: String, storageId: UInt32, parentHandle: MTPObjectHandle?) async throws
}
