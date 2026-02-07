// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation

// MARK: - Profiling Models

public struct MTPProfileMetric: Codable, Sendable {
    public let operation: String
    public let count: Int
    public let minMs: Double
    public let maxMs: Double
    public let avgMs: Double
    public let p95Ms: Double
    public let throughputMBps: Double?
}

public struct MTPDeviceProfile: Codable, Sendable {
    public let timestamp: Date
    public let deviceInfo: MTPDeviceInfo
    public let metrics: [MTPProfileMetric]
}

// MARK: - Profiling Tool

public actor ProfilingManager {
    private var results: [String: [Double]] = [:]
    private var throughputs: [String: [Double]] = [:]
    
    public init() {}
    
    // Actor-isolated state update
    private func record(_ name: String, ms: Double, bytes: Int?) {
        results[name, default: []].append(ms)
        if let b = bytes {
            let mbps = (Double(b) / 1_000_000.0) / (ms / 1000.0)
            throughputs[name, default: []].append(mbps)
        }
    }
    
    /// Measures an async operation in the caller's context, then hops into the actor to record metrics.
    @discardableResult
    public nonisolated func measure<T>(
        _ name: String,
        bytes: Int? = nil,
        body: () async throws -> T
    ) async rethrows -> T {
        let start = DispatchTime.now()
        let value = try await body()
        let end = DispatchTime.now()
        
        let ns = end.uptimeNanoseconds - start.uptimeNanoseconds
        let ms = Double(ns) / 1_000_000.0
        
        await self.record(name, ms: ms, bytes: bytes)
        return value
    }
    
    public func report(info: MTPDeviceInfo) -> MTPDeviceProfile {
        let metrics = results.map { name, values -> MTPProfileMetric in
            let sorted = values.sorted()
            let count = sorted.count
            let minVal = sorted.first ?? 0
            let maxVal = sorted.last ?? 0
            let avg = count > 0 ? (sorted.reduce(0, +) / Double(count)) : 0
            let p95Index = max(0, min(count - 1, Int(Double(count) * 0.95)))
            let p95 = count > 0 ? sorted[p95Index] : 0
            
            let tp = throughputs[name]
            let avgTp = tp.map { $0.reduce(0, +) / Double($0.count) }
            
            return MTPProfileMetric(
                operation: name,
                count: count,
                minMs: minVal,
                maxMs: maxVal,
                avgMs: avg,
                p95Ms: p95,
                throughputMBps: avgTp
            )
        }
        
        return MTPDeviceProfile(
            timestamp: Date(),
            deviceInfo: info,
            metrics: metrics.sorted { $0.operation < $1.operation }
        )
    }
    
    public func saveReport(info: MTPDeviceInfo, deviceId: MTPDeviceID) async throws {
        let profile = report(info: info)
        let persistence = await MTPDeviceManager.shared.persistence
        try await persistence.profiling.recordProfile(profile, for: deviceId)
    }
}