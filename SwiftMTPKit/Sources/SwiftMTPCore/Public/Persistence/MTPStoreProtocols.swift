// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation

public protocol LearnedProfileStore: Sendable {
    func loadProfile(for fingerprint: MTPDeviceFingerprint) async throws -> LearnedProfile?
    func saveProfile(_ profile: LearnedProfile, for deviceId: MTPDeviceID) async throws
}

public protocol ProfilingStore: Sendable {
    func recordProfile(_ profile: MTPDeviceProfile, for deviceId: MTPDeviceID) async throws
}

public protocol SnapshotStore: Sendable {
    func recordSnapshot(deviceId: MTPDeviceID, generation: Int, path: String?, hash: String?) async throws
}

public protocol SubmissionStore: Sendable {
    func recordSubmission(id: String, deviceId: MTPDeviceID, path: String) async throws
}

public protocol ObjectCatalogStore: Sendable {
    func recordStorage(deviceId: MTPDeviceID, storage: MTPStorageInfo) async throws
    func recordObject(deviceId: MTPDeviceID, object: MTPObjectInfo, pathKey: String, generation: Int) async throws
    func recordObjects(deviceId: MTPDeviceID, objects: [(object: MTPObjectInfo, pathKey: String)], generation: Int) async throws
    func finalizeIndexing(deviceId: MTPDeviceID, generation: Int) async throws
    func fetchObjects(deviceId: MTPDeviceID, generation: Int) async throws -> [MTPObjectRecord]
}

public struct MTPObjectRecord: Sendable {
    public let handle: UInt32
    public let storage: UInt32
    public let pathKey: String
    public let size: UInt64?
    public let mtime: Date?
    public let format: UInt16
    
    public init(handle: UInt32, storage: UInt32, pathKey: String, size: UInt64?, mtime: Date?, format: UInt16) {
        self.handle = handle
        self.storage = storage
        self.pathKey = pathKey
        self.size = size
        self.mtime = mtime
        self.format = format
    }
}

public protocol MTPPersistenceProvider: Sendable {
    var learnedProfiles: any LearnedProfileStore { get }
    var profiling: any ProfilingStore { get }
    var snapshots: any SnapshotStore { get }
    var submissions: any SubmissionStore { get }
    var transferJournal: any TransferJournal { get }
    var objectCatalog: any ObjectCatalogStore { get }
}

public final class NullPersistenceProvider: MTPPersistenceProvider, LearnedProfileStore, ProfilingStore, SnapshotStore, SubmissionStore, TransferJournal, ObjectCatalogStore {
    public init() {}
    public var learnedProfiles: any LearnedProfileStore { self }
    public var profiling: any ProfilingStore { self }
    public var snapshots: any SnapshotStore { self }
    public var submissions: any SubmissionStore { self }
    public var transferJournal: any TransferJournal { self }
    public var objectCatalog: any ObjectCatalogStore { self }
    
    public func loadProfile(for fingerprint: MTPDeviceFingerprint) async throws -> LearnedProfile? { nil }
    public func saveProfile(_ profile: LearnedProfile, for deviceId: MTPDeviceID) async throws {}
    public func recordProfile(_ profile: MTPDeviceProfile, for deviceId: MTPDeviceID) async throws {}
    public func recordSnapshot(deviceId: MTPDeviceID, generation: Int, path: String?, hash: String?) async throws {}
    public func recordSubmission(id: String, deviceId: MTPDeviceID, path: String) async throws {}

    // TransferJournal (Null)
    public func beginRead(device: MTPDeviceID, handle: UInt32, name: String, size: UInt64?, supportsPartial: Bool, tempURL: URL, finalURL: URL?, etag: (size: UInt64?, mtime: Date?)) async throws -> String { UUID().uuidString }
    public func beginWrite(device: MTPDeviceID, parent: UInt32, name: String, size: UInt64, supportsPartial: Bool, tempURL: URL, sourceURL: URL?) async throws -> String { UUID().uuidString }
    public func updateProgress(id: String, committed: UInt64) async throws {}
    public func fail(id: String, error: Error) async throws {}
    public func complete(id: String) async throws {}
    public func loadResumables(for device: MTPDeviceID) async throws -> [TransferRecord] { [] }
    public func clearStaleTemps(olderThan: TimeInterval) async throws {}

    // ObjectCatalogStore (Null)
    public func recordStorage(deviceId: MTPDeviceID, storage: MTPStorageInfo) async throws {}
    public func recordObject(deviceId: MTPDeviceID, object: MTPObjectInfo, pathKey: String, generation: Int) async throws {}
    public func recordObjects(deviceId: MTPDeviceID, objects: [(object: MTPObjectInfo, pathKey: String)], generation: Int) async throws {}
    public func finalizeIndexing(deviceId: MTPDeviceID, generation: Int) async throws {}
    public func fetchObjects(deviceId: MTPDeviceID, generation: Int) async throws -> [MTPObjectRecord] { [] }
}
