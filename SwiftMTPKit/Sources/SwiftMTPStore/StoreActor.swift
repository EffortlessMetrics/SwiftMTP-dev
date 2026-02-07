// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import SwiftData
import SwiftMTPCore

@ModelActor
public actor StoreActor {
    public func upsertDevice(id: String, manufacturer: String?, model: String?) throws -> String {
        let predicate = #Predicate<DeviceEntity> { $0.id == id }
        let descriptor = FetchDescriptor<DeviceEntity>(predicate: predicate)
        let existing = try modelContext.fetch(descriptor)
        
        if let device = existing.first {
            if let manufacturer = manufacturer { device.manufacturer = manufacturer }
            if let model = model { device.model = model }
            device.lastSeenAt = Date()
            try modelContext.save()
            return device.id
        } else {
            let device = DeviceEntity(id: id, manufacturer: manufacturer, model: model)
            modelContext.insert(device)
            try modelContext.save()
            return device.id
        }
    }
    
    public func updateLearnedProfile(for fingerprintHash: String, deviceId: String, profile: LearnedProfile) throws {
        _ = try upsertDevice(id: deviceId, manufacturer: nil, model: nil)
        
        // Fetch device again to link it (must be in same context)
        let devicePredicate = #Predicate<DeviceEntity> { $0.id == deviceId }
        let device = try modelContext.fetch(FetchDescriptor<DeviceEntity>(predicate: devicePredicate)).first
        
        let predicate = #Predicate<LearnedProfileEntity> { $0.fingerprintHash == fingerprintHash }
        let descriptor = FetchDescriptor<LearnedProfileEntity>(predicate: predicate)
        let existing = try modelContext.fetch(descriptor)
        
        if let entity = existing.first {
            entity.lastUpdated = Date()
            entity.sampleCount = profile.sampleCount
            entity.optimalChunkSize = profile.optimalChunkSize
            entity.avgHandshakeMs = profile.avgHandshakeMs
            entity.optimalIoTimeoutMs = profile.optimalIoTimeoutMs
            entity.optimalInactivityTimeoutMs = profile.optimalInactivityTimeoutMs
            entity.p95ReadThroughputMBps = profile.p95ReadThroughputMBps
            entity.p95WriteThroughputMBps = profile.p95WriteThroughputMBps
            entity.successRate = profile.successRate
            entity.device = device
        } else {
            let entity = LearnedProfileEntity(
                fingerprintHash: fingerprintHash,
                created: profile.created,
                lastUpdated: profile.lastUpdated,
                sampleCount: profile.sampleCount,
                optimalChunkSize: profile.optimalChunkSize,
                avgHandshakeMs: profile.avgHandshakeMs,
                optimalIoTimeoutMs: profile.optimalIoTimeoutMs,
                optimalInactivityTimeoutMs: profile.optimalInactivityTimeoutMs,
                p95ReadThroughputMBps: profile.p95ReadThroughputMBps,
                p95WriteThroughputMBps: profile.p95WriteThroughputMBps,
                successRate: profile.successRate,
                hostEnvironment: profile.hostEnvironment
            )
            entity.device = device
            modelContext.insert(entity)
        }
        
        try modelContext.save()
    }
    
    public func fetchLearnedProfile(for fingerprintHash: String) throws -> LearnedProfile? {
        let predicate = #Predicate<LearnedProfileEntity> { $0.fingerprintHash == fingerprintHash }
        let descriptor = FetchDescriptor<LearnedProfileEntity>(predicate: predicate)
        guard let entity = try modelContext.fetch(descriptor).first else { return nil }
        
        // Return a plain struct to be Sendable
        // Note: We don't have the full MTPDeviceFingerprint here, so we return a "partial" profile
        // or the adapter will need to fill it in.
        // Actually, LearnedProfile needs MTPDeviceFingerprint.
        // I'll return the raw values and let the adapter reconstruct it.
        return nil // See below
    }
    
    // Better: return a simple DTO
    public struct LearnedProfileDTO: Sendable {
        public let fingerprintHash: String
        public let created: Date
        public let lastUpdated: Date
        public let sampleCount: Int
        public let optimalChunkSize: Int?
        public let avgHandshakeMs: Int?
        public let optimalIoTimeoutMs: Int?
        public let optimalInactivityTimeoutMs: Int?
        public let p95ReadThroughputMBps: Double?
        public let p95WriteThroughputMBps: Double?
        public let successRate: Double
        public let hostEnvironment: String
    }
    
    public func fetchLearnedProfileDTO(for fingerprintHash: String) throws -> LearnedProfileDTO? {
        let predicate = #Predicate<LearnedProfileEntity> { $0.fingerprintHash == fingerprintHash }
        let descriptor = FetchDescriptor<LearnedProfileEntity>(predicate: predicate)
        guard let entity = try modelContext.fetch(descriptor).first else { return nil }
        
        return LearnedProfileDTO(
            fingerprintHash: entity.fingerprintHash,
            created: entity.created,
            lastUpdated: entity.lastUpdated,
            sampleCount: entity.sampleCount,
            optimalChunkSize: entity.optimalChunkSize,
            avgHandshakeMs: entity.avgHandshakeMs,
            optimalIoTimeoutMs: entity.optimalIoTimeoutMs,
            optimalInactivityTimeoutMs: entity.optimalInactivityTimeoutMs,
            p95ReadThroughputMBps: entity.p95ReadThroughputMBps,
            p95WriteThroughputMBps: entity.p95WriteThroughputMBps,
            successRate: entity.successRate,
            hostEnvironment: entity.hostEnvironment
        )
    }

    public func recordProfilingRun(deviceId: String, profile: MTPDeviceProfile) throws {
        _ = try upsertDevice(id: deviceId, manufacturer: profile.deviceInfo.manufacturer, model: profile.deviceInfo.model)
        
        let devicePredicate = #Predicate<DeviceEntity> { $0.id == deviceId }
        let device = try modelContext.fetch(FetchDescriptor<DeviceEntity>(predicate: devicePredicate)).first

        let run = ProfilingRunEntity(timestamp: profile.timestamp)
        run.device = device
        modelContext.insert(run)
        
        for metric in profile.metrics {
            let metricEntity = ProfilingMetricEntity(
                operation: metric.operation,
                count: metric.count,
                minMs: metric.minMs,
                maxMs: metric.maxMs,
                avgMs: metric.avgMs,
                p95Ms: metric.p95Ms,
                throughputMBps: metric.throughputMBps
            )
            metricEntity.run = run
            modelContext.insert(metricEntity)
        }
        
                try modelContext.save()
        
            }
        
            
        
            public func recordSnapshot(deviceId: String, generation: Int, path: String?, hash: String?) throws {
        
                let device = try upsertDevice(id: deviceId, manufacturer: nil, model: nil)
        
                
        
                let devicePredicate = #Predicate<DeviceEntity> { $0.id == deviceId }
        
                let deviceRef = try modelContext.fetch(FetchDescriptor<DeviceEntity>(predicate: devicePredicate)).first
        
        
        
                let snapshot = SnapshotEntity(generation: generation, artifactPath: path, artifactHash: hash)
        
                snapshot.device = deviceRef
        
                modelContext.insert(snapshot)
        
                
        
                        try modelContext.save()
        
                
        
                    }
        
                
        
                    
        
                
        
                        public func recordSubmission(id: String, deviceId: String, path: String) throws {
        
                
        
                    
        
                
        
                            _ = try upsertDevice(id: deviceId, manufacturer: nil, model: nil)
        
                
        
                    
        
                
        
                            
        
                
        
                    
        
                
        
                            let submission = SubmissionEntity(id: id, deviceId: deviceId, path: path)
        
                
        
                    
        
                
        
                            modelContext.insert(submission)
        
                
        
                    
        
                
        
                            
        
                
        
                    
        
                
        
                            try modelContext.save()
        
                
        
                    
        
                
        
                        }
        
                
        
                    
        
                
        
                        
        
                
        
                    
        
                
        
                        // MARK: - Transfer Journal
        
                
        
                    
        
                
        
                        
        
                
        
                    
        
                
        
                        public func createTransfer(
        
                
        
                    
        
                
        
                            id: String,
        
                
        
                    
        
                
        
                            deviceId: String,
        
                
        
                    
        
                
        
                            kind: String,
        
                
        
                    
        
                
        
                            handle: UInt32?,
        
                
        
                    
        
                
        
                            parentHandle: UInt32?,
        
                
        
                    
        
                
        
                            name: String,
        
                
        
                    
        
                
        
                            totalBytes: UInt64?,
        
                
        
                    
        
                
        
                            supportsPartial: Bool,
        
                
        
                    
        
                
        
                            localTempURL: String,
        
                
        
                    
        
                
        
                            finalURL: String?,
        
                
        
                    
        
                
        
                            etagSize: UInt64?,
        
                
        
                    
        
                
        
                            etagMtime: Date?
        
                
        
                    
        
                
        
                        ) throws {
        
                
        
                    
        
                
        
                            let transfer = TransferEntity(
        
                
        
                    
        
                
        
                                id: id,
        
                
        
                    
        
                
        
                                deviceId: deviceId,
        
                
        
                    
        
                
        
                                kind: kind,
        
                
        
                    
        
                
        
                                handle: handle,
        
                
        
                    
        
                
        
                                parentHandle: parentHandle,
        
                
        
                    
        
                
        
                                name: name,
        
                
        
                    
        
                
        
                                totalBytes: totalBytes,
        
                
        
                    
        
                
        
                                supportsPartial: supportsPartial,
        
                
        
                    
        
                
        
                                localTempURL: localTempURL,
        
                
        
                    
        
                
        
                                finalURL: finalURL
        
                
        
                    
        
                
        
                            )
        
                
        
                    
        
                
        
                            transfer.etagSize = etagSize
        
                
        
                    
        
                
        
                            transfer.etagMtime = etagMtime
        
                
        
                    
        
                
        
                            
        
                
        
                    
        
                
        
                            modelContext.insert(transfer)
        
                
        
                    
        
                
        
                            try modelContext.save()
        
                
        
                    
        
                
        
                        }
        
                
        
                    
        
                
        
                        
        
                
        
                    
        
                
        
                        public func updateTransferProgress(id: String, committed: UInt64) throws {
        
                
        
                    
        
                
        
                            let predicate = #Predicate<TransferEntity> { $0.id == id }
        
                
        
                    
        
                
        
                            if let transfer = try modelContext.fetch(FetchDescriptor<TransferEntity>(predicate: predicate)).first {
        
                
        
                    
        
                
        
                                transfer.committedBytes = committed
        
                
        
                    
        
                
        
                                transfer.updatedAt = Date()
        
                
        
                    
        
                
        
                                try modelContext.save()
        
                
        
                    
        
                
        
                            }
        
                
        
                    
        
                
        
                        }
        
                
        
                    
        
                
        
                        
        
                
        
                    
        
                
        
                        public func updateTransferStatus(id: String, state: String, error: String? = nil) throws {
        
                
        
                    
        
                
        
                            let predicate = #Predicate<TransferEntity> { $0.id == id }
        
                
        
                    
        
                
        
                            if let transfer = try modelContext.fetch(FetchDescriptor<TransferEntity>(predicate: predicate)).first {
        
                
        
                    
        
                
        
                                transfer.state = state
        
                
        
                    
        
                
        
                                transfer.lastError = error
        
                
        
                    
        
                
        
                                transfer.updatedAt = Date()
        
                
        
                    
        
                
        
                                try modelContext.save()
        
                
        
                    
        
                
        
                            }
        
                
        
                    
        
                
        
                        }
        
                
        
                    
        
                
        
                        
        
                
        
                    
        
                
        
                        public func fetchResumableTransfers(for deviceId: String) throws -> [TransferRecord] {
        
                
        
                    
        
                
        
                            let predicate = #Predicate<TransferEntity> { $0.deviceId == deviceId && ($0.state == "active" || $0.state == "paused") }
        
                
        
                    
        
                
        
                            let descriptor = FetchDescriptor<TransferEntity>(predicate: predicate)
        
                
        
                    
        
                
        
                            let entities = try modelContext.fetch(descriptor)
        
                
        
                    
        
                
        
                            
        
                
        
                    
        
                
        
                                    return entities.map { entity in
        
                
        
                    
        
                
        
                            
        
                
        
                    
        
                
        
                                        TransferRecord(
        
                
        
                    
        
                
        
                            
        
                
        
                    
        
                
        
                                            id: entity.id,
        
                
        
                    
        
                
        
                            
        
                
        
                    
        
                
        
                                            deviceId: MTPDeviceID(raw: entity.deviceId),
        
                
        
                    
        
                
        
                            
        
                
        
                    
        
                
        
                                            kind: entity.kind,
        
                
        
                    
        
                
        
                            
        
                
        
                    
        
                
        
                                            handle: entity.handle,
        
                
        
                    
        
                
        
                            
        
                
        
                    
        
                
        
                                            parentHandle: entity.parentHandle,
        
                
        
                    
        
                
        
                            
        
                
        
                    
        
                
        
                                            name: entity.name,
        
                
        
                    
        
                
        
                            
        
                
        
                    
        
                
        
                                            totalBytes: entity.totalBytes,
        
                
        
                    
        
                
        
                            
        
                
        
                    
        
                
        
                                            committedBytes: entity.committedBytes,
        
                
        
                    
        
                
        
                            
        
                
        
                    
        
                
        
                                            supportsPartial: entity.supportsPartial,
        
                
        
                    
        
                
        
                            
        
                
        
                    
        
                
        
                                            localTempURL: URL(fileURLWithPath: entity.localTempURL),
        
                
        
                    
        
                
        
                            
        
                
        
                    
        
                
        
                                            finalURL: entity.finalURL.map { URL(fileURLWithPath: $0) },
        
                
        
                    
        
                
        
                            
        
                
        
                    
        
                
        
                                            state: entity.state,
        
                
        
                    
        
                
        
                            
        
                
        
                    
        
                
        
                                            updatedAt: entity.updatedAt
        
                
        
                    
        
                
        
                            
        
                
        
                    
        
                
        
                                        )
        
                
        
                    
        
                
        
                            
        
                
        
                    
        
                
        
                                    }
        
                
        
                    
        
                
        
                            
        
                
        
                    
        
                
        
                                }
        
                
        
                    
        
                
        
                            
        
                
        
                    
        
                
        
                                
        
                
        
                    
        
                
        
                            
        
                
        
                    
        
                
        
                                // MARK: - Object Catalog
        
                
        
                    
        
                
        
                            
        
                
        
                    
        
                
        
                                
        
                
        
                    
        
                
        
                            
        
                
        
                    
        
                
        
                                public func upsertStorage(
        
                
        
                    
        
                
        
                            
        
                
        
                    
        
                
        
                                    deviceId: String,
        
                
        
                    
        
                
        
                            
        
                
        
                    
        
                
        
                                    storageId: Int,
        
                
        
                    
        
                
        
                            
        
                
        
                    
        
                
        
                                    description: String,
        
                
        
                    
        
                
        
                            
        
                
        
                    
        
                
        
                                    capacity: Int64,
        
                
        
                    
        
                
        
                            
        
                
        
                    
        
                
        
                                    free: Int64,
        
                
        
                    
        
                
        
                            
        
                
        
                    
        
                
        
                                    readOnly: Bool
        
                
        
                    
        
                
        
                            
        
                
        
                    
        
                
        
                                ) throws {
        
                
        
                    
        
                
        
                            
        
                
        
                    
        
                
        
                                    let compoundId = "\(deviceId):\(storageId)"
        
                
        
                    
        
                
        
                            
        
                
        
                    
        
                
        
                                    let predicate = #Predicate<MTPStorageEntity> { $0.compoundId == compoundId }
        
                
        
                    
        
                
        
                            
        
                
        
                    
        
                
        
                                    let existing = try modelContext.fetch(FetchDescriptor<MTPStorageEntity>(predicate: predicate)).first
        
                
        
                    
        
                
        
                            
        
                
        
                    
        
                
        
                                    
        
                
        
                    
        
                
        
                            
        
                
        
                    
        
                
        
                                    if let storage = existing {
        
                
        
                    
        
                
        
                            
        
                
        
                    
        
                
        
                                        storage.storageDescription = description
        
                
        
                    
        
                
        
                            
        
                
        
                    
        
                
        
                                        storage.capacityBytes = capacity
        
                
        
                    
        
                
        
                            
        
                
        
                    
        
                
        
                                        storage.freeBytes = free
        
                
        
                    
        
                
        
                            
        
                
        
                    
        
                
        
                                        storage.isReadOnly = readOnly
        
                
        
                    
        
                
        
                            
        
                
        
                    
        
                
        
                                        storage.lastIndexedAt = Date()
        
                
        
                    
        
                
        
                            
        
                
        
                    
        
                
        
                                    } else {
        
                
        
                    
        
                
        
                            
        
                
        
                    
        
                
        
                                        let storage = MTPStorageEntity(
        
                
        
                    
        
                
        
                            
        
                
        
                    
        
                
        
                                            deviceId: deviceId,
        
                
        
                    
        
                
        
                            
        
                
        
                    
        
                
        
                                            storageId: storageId,
        
                
        
                    
        
                
        
                            
        
                
        
                    
        
                
        
                                            storageDescription: description,
        
                
        
                    
        
                
        
                            
        
                
        
                    
        
                
        
                                            capacityBytes: capacity,
        
                
        
                    
        
                
        
                            
        
                
        
                    
        
                
        
                                            freeBytes: free,
        
                
        
                    
        
                
        
                            
        
                
        
                    
        
                
        
                                            isReadOnly: readOnly
        
                
        
                    
        
                
        
                            
        
                
        
                    
        
                
        
                                        )
        
                
        
                    
        
                
        
                            
        
                
        
                    
        
                
        
                                        // Link to device
        
                
        
                    
        
                
        
                            
        
                
        
                    
        
                
        
                                        let devicePredicate = #Predicate<DeviceEntity> { $0.id == deviceId }
        
                
        
                    
        
                
        
                            
        
                
        
                    
        
                
        
                                        storage.device = try modelContext.fetch(FetchDescriptor<DeviceEntity>(predicate: devicePredicate)).first
        
                
        
                    
        
                
        
                            
        
                
        
                    
        
                
        
                                        modelContext.insert(storage)
        
                
        
                    
        
                
        
                            
        
                
        
                    
        
                
        
                                    }
        
                
        
                    
        
                
        
                            
        
                
        
                    
        
                
        
                                    try modelContext.save()
        
                
        
                    
        
                
        
                            
        
                
        
                    
        
                
        
                                }
        
                
        
                    
        
                
        
                            
        
                
        
                    
        
                
        
                                
        
                
        
                    
        
                
        
                            
        
                
        
                    
        
                
        
                                public func upsertObject(
        
                
        
                    
        
                
        
                            
        
                
        
                    
        
                
        
                                    deviceId: String,
        
                
        
                    
        
                
        
                            
        
                
        
                    
        
                
        
                                    storageId: Int,
        
                
        
                    
        
                
        
                            
        
                
        
                    
        
                
        
                                    handle: Int,
        
                
        
                    
        
                
        
                            
        
                
        
                    
        
                
        
                                    parentHandle: Int?,
        
                
        
                    
        
                
        
                            
        
                
        
                    
        
                
        
                                    name: String,
        
                
        
                    
        
                
        
                            
        
                
        
                    
        
                
        
                                    pathKey: String,
        
                
        
                    
        
                
        
                            
        
                
        
                    
        
                
        
                                    size: Int64?,
        
                
        
                    
        
                
        
                            
        
                
        
                    
        
                
        
                                    mtime: Date?,
        
                
        
                    
        
                
        
                            
        
                
        
                    
        
                
        
                                    format: Int,
        
                
        
                    
        
                
        
                            
        
                
        
                    
        
                
        
                                    generation: Int
        
                
        
                    
        
                
        
                            
        
                
        
                    
        
                
        
                                ) throws {
        
                
        
                    
        
                
        
                            
        
                
        
                    
        
                
        
                                    let compoundId = "\(deviceId):\(storageId):\(handle)"
        
                
        
                    
        
                
        
                            
        
                
        
                    
        
                
        
                                    let predicate = #Predicate<MTPObjectEntity> { $0.compoundId == compoundId }
        
                
        
                    
        
                
        
                            
        
                
        
                    
        
                
        
                                    let existing = try modelContext.fetch(FetchDescriptor<MTPObjectEntity>(predicate: predicate)).first
        
                
        
                    
        
                
        
                            
        
                
        
                    
        
                
        
                                    
        
                
        
                    
        
                
        
                            
        
                
        
                    
        
                
        
                                    if let object = existing {
        
                
        
                    
        
                
        
                            
        
                
        
                    
        
                
        
                                        object.parentHandle = parentHandle
        
                
        
                    
        
                
        
                            
        
                
        
                    
        
                
        
                                        object.name = name
        
                
        
                    
        
                
        
                            
        
                
        
                    
        
                
        
                                        object.pathKey = pathKey
        
                
        
                    
        
                
        
                            
        
                
        
                    
        
                
        
                                        object.sizeBytes = size
        
                
        
                    
        
                
        
                            
        
                
        
                    
        
                
        
                                        object.modifiedAt = mtime
        
                
        
                    
        
                
        
                            
        
                
        
                    
        
                
        
                                        object.formatCode = format
        
                
        
                    
        
                
        
                            
        
                
        
                    
        
                
        
                                        object.generation = generation
        
                
        
                    
        
                
        
                            
        
                
        
                    
        
                
        
                                        object.isTombstoned = false
        
                
        
                    
        
                
        
                            
        
                
        
                    
        
                
        
                                    } else {
        
                
        
                    
        
                
        
                            
        
                
        
                    
        
                
        
                                        let object = MTPObjectEntity(
        
                
        
                    
        
                
        
                            
        
                
        
                    
        
                
        
                                            deviceId: deviceId,
        
                
        
                    
        
                
        
                            
        
                
        
                    
        
                
        
                                            storageId: storageId,
        
                
        
                    
        
                
        
                            
        
                
        
                    
        
                
        
                                            handle: handle,
        
                
        
                    
        
                
        
                            
        
                
        
                    
        
                
        
                                            parentHandle: parentHandle,
        
                
        
                    
        
                
        
                            
        
                
        
                    
        
                
        
                                            name: name,
        
                
        
                    
        
                
        
                            
        
                
        
                    
        
                
        
                                            pathKey: pathKey,
        
                
        
                    
        
                
        
                            
        
                
        
                    
        
                
        
                                            sizeBytes: size,
        
                
        
                    
        
                
        
                            
        
                
        
                    
        
                
        
                                            modifiedAt: mtime,
        
                
        
                    
        
                
        
                            
        
                
        
                    
        
                
        
                                            formatCode: format,
        
                
        
                    
        
                
        
                            
        
                
        
                    
        
                
        
                                            generation: generation
        
                
        
                    
        
                
        
                            
        
                
        
                    
        
                
        
                                        )
        
                
        
                    
        
                
        
                            
        
                
        
                    
        
                
        
                                        // Link to storage
        
                
        
                    
        
                
        
                            
        
                
        
                    
        
                
        
                                        let storageCompoundId = "\(deviceId):\(storageId)"
        
                
        
                    
        
                
        
                            
        
                
        
                    
        
                
        
                                        let storagePredicate = #Predicate<MTPStorageEntity> { $0.compoundId == storageCompoundId }
        
                
        
                    
        
                
        
                            
        
                
        
                    
        
                
        
                                        object.storage = try modelContext.fetch(FetchDescriptor<MTPStorageEntity>(predicate: storagePredicate)).first
        
                
        
                    
        
                
        
                            
        
                
        
                    
        
                
        
                                        modelContext.insert(object)
        
                
        
                    
        
                
        
                            
        
                
        
                    
        
                
        
                                    }
        
                
        
                    
        
                
        
                            
        
                
        
                    
        
                
        
                                    // NOTE: We usually save in batches for performance during indexing
        
                
        
                    
        
                
        
                            
        
                
        
                    
        
                
        
                                }
        
                
        
                    
        
                
        
                            
        
                
        
                    
        
                
        
                                
        
                
        
                    
        
                
        
                            
        
                
        
                    
        
                
        
                                public func saveContext() throws {
        
                
        
                    
        
                
        
                            
        
                
        
                    
        
                
        
                                    try modelContext.save()
        
                
        
                    
        
                
        
                            
        
                
        
                    
        
                
        
                                }
        
                
        
                    
        
                
        
                            
        
                
        
                    
        
                
        
                                
        
                
        
                    
        
                
        
                            
        
                
        
                    
        
                
        
                                public func markPreviousGenerationTombstoned(deviceId: String, currentGen: Int) throws {
        
                
        
                    
        
                
        
                            
        
                
        
                    
        
                
        
                                    let predicate = #Predicate<MTPObjectEntity> { $0.deviceId == deviceId && $0.generation < currentGen && !$0.isTombstoned }
        
                
        
                    
        
                
        
                            
        
                
        
                    
        
                
        
                                    let descriptor = FetchDescriptor<MTPObjectEntity>(predicate: predicate)
        
                
        
                    
        
                
        
                            
        
                
        
                    
        
                
        
                                    let objects = try modelContext.fetch(descriptor)
        
                
        
                    
        
                
        
                            
        
                
        
                    
        
                
        
                                    for object in objects {
        
                
        
                    
        
                
        
                            
        
                
        
                    
        
                
        
                                        object.isTombstoned = true
        
                
        
                    
        
                
        
                            
        
                
        
                    
        
                
        
                                    }
        
                
        
                    
        
                
        
                            
        
                
        
                    
        
                
        
                                    try modelContext.save()
        
                
        
                    
        
                
        
                            
        
                
        
                    
        
                
        
                                }
        
                
        
                    
        
                
        
                            
        
                
        
                    
        
                
        
                            }
        
                
        
                    
        
                
        
                            
        
                
        
                    
        
                
        
                            
        
                
        
                    
        
                
        
                    
        
                
        
                
        
        