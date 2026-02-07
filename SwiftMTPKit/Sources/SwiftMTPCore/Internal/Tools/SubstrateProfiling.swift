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
    
    public func measure<T>(_ name: String, bytes: Int? = nil, body: () async throws -> T) async throws -> T {
        let start = DispatchTime.now()
        let result = try await body()
        let end = DispatchTime.now()
        
        let nanoseconds = end.uptimeNanoseconds - start.uptimeNanoseconds
        let milliseconds = Double(nanoseconds) / 1_000_000.0
        
        results[name, default: []].append(milliseconds)
        if let b = bytes {
            let mbps = (Double(b) / 1_000_000.0) / (milliseconds / 1000.0)
            throughputs[name, default: []].append(mbps)
        }
        
        return result
    }
    
    public func report(info: MTPDeviceInfo) async -> MTPDeviceProfile {
        let metrics = results.map { name, values -> MTPProfileMetric in
            let sorted = values.sorted()
            let count = sorted.count
            let minVal = sorted.first ?? 0
            let maxVal = sorted.last ?? 0
            let avg = sorted.reduce(0, +) / Double(count)
            let p95Index = Int(Double(count) * 0.95)
            let p95 = sorted[min(p95Index, count - 1)]
            
            let tp = throughputs[name]?.sorted()
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
}