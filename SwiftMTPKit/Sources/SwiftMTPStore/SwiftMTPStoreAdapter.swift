// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import SwiftData
import SwiftMTPCore

public final class SwiftMTPStoreAdapter: MTPPersistenceProvider, LearnedProfileStore, ProfilingStore, SnapshotStore, SubmissionStore, TransferJournal, Sendable {
    private let store: SwiftMTPStore
    
    public init(store: SwiftMTPStore = .shared) {
        self.store = store
    }
    
    public var learnedProfiles: any LearnedProfileStore { self }
    public var profiling: any ProfilingStore { self }
    public var snapshots: any SnapshotStore { self }
    public var submissions: any SubmissionStore { self }
    public var transferJournal: any TransferJournal { self }
    
    // MARK: - LearnedProfileStore
    
    public func loadProfile(for fingerprint: MTPDeviceFingerprint) async throws -> LearnedProfile? {
        let actor = store.createActor()
        guard let dto = try await actor.fetchLearnedProfileDTO(for: fingerprint.hashString) else {
            return nil
        }
        
        return LearnedProfile(
            fingerprint: fingerprint,
            fingerprintHash: dto.fingerprintHash,
            created: dto.created,
            lastUpdated: dto.lastUpdated,
            sampleCount: dto.sampleCount,
            optimalChunkSize: dto.optimalChunkSize,
            avgHandshakeMs: dto.avgHandshakeMs,
            optimalIoTimeoutMs: dto.optimalIoTimeoutMs,
            optimalInactivityTimeoutMs: dto.optimalInactivityTimeoutMs,
            p95ReadThroughputMBps: dto.p95ReadThroughputMBps,
            p95WriteThroughputMBps: dto.p95WriteThroughputMBps,
            successRate: dto.successRate,
            hostEnvironment: dto.hostEnvironment
        )
    }
    
    public func saveProfile(_ profile: LearnedProfile, for deviceId: MTPDeviceID) async throws {
        let actor = store.createActor()
        try await actor.updateLearnedProfile(for: profile.fingerprintHash, deviceId: deviceId.raw, profile: profile)
    }
    
    // MARK: - ProfilingStore
    
    public func recordProfile(_ profile: MTPDeviceProfile, for deviceId: MTPDeviceID) async throws {
        let actor = store.createActor()
        try await actor.recordProfilingRun(deviceId: deviceId.raw, profile: profile)
    }
    
    // MARK: - SnapshotStore
    
    public func recordSnapshot(deviceId: MTPDeviceID, generation: Int, path: String?, hash: String?) async throws {
        let actor = store.createActor()
        try await actor.recordSnapshot(deviceId: deviceId.raw, generation: generation, path: path, hash: hash)
    }
    
    // MARK: - SubmissionStore
    
    public func recordSubmission(id: String, deviceId: MTPDeviceID, path: String) async throws {
        let actor = store.createActor()
        try await actor.recordSubmission(id: id, deviceId: deviceId.raw, path: path)
    }
    
    // MARK: - TransferJournal
    
    public func beginRead(device: MTPDeviceID, handle: UInt32, name: String, size: UInt64?, supportsPartial: Bool, tempURL: URL, finalURL: URL?, etag: (size: UInt64?, mtime: Date?)) throws -> String {
        let id = UUID().uuidString
        let actor = store.createActor()
        Task {
            try? await actor.createTransfer(
                id: id,
                deviceId: device.raw,
                kind: "read",
                handle: handle,
                parentHandle: nil,
                name: name,
                totalBytes: size,
                supportsPartial: supportsPartial,
                localTempURL: tempURL.path,
                finalURL: finalURL?.path,
                etagSize: etag.size,
                etagMtime: etag.mtime
            )
        }
        return id
    }
    
    public func beginWrite(device: MTPDeviceID, parent: UInt32, name: String, size: UInt64, supportsPartial: Bool, tempURL: URL, sourceURL: URL?) throws -> String {
        let id = UUID().uuidString
        let actor = store.createActor()
        Task {
            try? await actor.createTransfer(
                id: id,
                deviceId: device.raw,
                kind: "write",
                handle: nil,
                parentHandle: parent,
                name: name,
                totalBytes: size,
                supportsPartial: supportsPartial,
                localTempURL: tempURL.path,
                finalURL: sourceURL?.path,
                etagSize: nil,
                etagMtime: nil
            )
        }
        return id
    }
    
    public func updateProgress(id: String, committed: UInt64) throws {
        let actor = store.createActor()
        Task {
            try? await actor.updateTransferProgress(id: id, committed: committed)
        }
    }
    
    public func fail(id: String, error: Error) throws {
        let actor = store.createActor()
        Task {
            try? await actor.updateTransferStatus(id: id, state: "failed", error: error.localizedDescription)
        }
    }
    
    public func complete(id: String) throws {
        let actor = store.createActor()
        Task {
            try? await actor.updateTransferStatus(id: id, state: "done")
        }
    }
    
    public func loadResumables(for device: MTPDeviceID) throws -> [TransferRecord] {
        let actor = store.createActor()
        let semaphore = DispatchSemaphore(value: 0)
        var records: [TransferRecord] = []
        Task {
            records = (try? await actor.fetchResumableTransfers(for: device.raw)) ?? []
            semaphore.signal()
        }
        semaphore.wait()
        return records
    }
    
    public func clearStaleTemps(olderThan: TimeInterval) throws {
        // Implementation for clearing stale temp files
    }
}