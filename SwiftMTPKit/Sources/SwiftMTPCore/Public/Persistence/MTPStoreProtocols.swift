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

public protocol MTPPersistenceProvider: Sendable {
    var learnedProfiles: any LearnedProfileStore { get }
    var profiling: any ProfilingStore { get }
    var snapshots: any SnapshotStore { get }
    var submissions: any SubmissionStore { get }
    var transferJournal: any TransferJournal { get }
}

public final class NullPersistenceProvider: MTPPersistenceProvider, LearnedProfileStore, ProfilingStore, SnapshotStore, SubmissionStore, TransferJournal {
    public init() {}
    public var learnedProfiles: any LearnedProfileStore { self }
    public var profiling: any ProfilingStore { self }
    public var snapshots: any SnapshotStore { self }
    public var submissions: any SubmissionStore { self }
    public var transferJournal: any TransferJournal { self }
    
    public func loadProfile(for fingerprint: MTPDeviceFingerprint) async throws -> LearnedProfile? { nil }
    public func saveProfile(_ profile: LearnedProfile, for deviceId: MTPDeviceID) async throws {}
    public func recordProfile(_ profile: MTPDeviceProfile, for deviceId: MTPDeviceID) async throws {}
    public func recordSnapshot(deviceId: MTPDeviceID, generation: Int, path: String?, hash: String?) async throws {}
    public func recordSubmission(id: String, deviceId: MTPDeviceID, path: String) async throws {}

    // TransferJournal (Null)
    public func beginRead(device: MTPDeviceID, handle: UInt32, name: String, size: UInt64?, supportsPartial: Bool, tempURL: URL, finalURL: URL?, etag: (size: UInt64?, mtime: Date?)) throws -> String { UUID().uuidString }
    public func beginWrite(device: MTPDeviceID, parent: UInt32, name: String, size: UInt64, supportsPartial: Bool, tempURL: URL, sourceURL: URL?) throws -> String { UUID().uuidString }
    public func updateProgress(id: String, committed: UInt64) throws {}
    public func fail(id: String, error: Error) throws {}
    public func complete(id: String) throws {}
    public func loadResumables(for device: MTPDeviceID) throws -> [TransferRecord] { [] }
    public func clearStaleTemps(olderThan: TimeInterval) throws {}
}
