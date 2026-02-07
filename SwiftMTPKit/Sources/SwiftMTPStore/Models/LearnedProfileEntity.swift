// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import SwiftData
import SwiftMTPCore

@Model
public final class LearnedProfileEntity {
    @Attribute(.unique) public var fingerprintHash: String
    public var created: Date
    public var lastUpdated: Date
    public var sampleCount: Int
    public var optimalChunkSize: Int?
    public var avgHandshakeMs: Int?
    public var optimalIoTimeoutMs: Int?
    public var optimalInactivityTimeoutMs: Int?
    public var p95ReadThroughputMBps: Double?
    public var p95WriteThroughputMBps: Double?
    public var successRate: Double
    public var hostEnvironment: String
    
    public var device: DeviceEntity?

    public init(
        fingerprintHash: String,
        created: Date = Date(),
        lastUpdated: Date = Date(),
        sampleCount: Int = 1,
        optimalChunkSize: Int? = nil,
        avgHandshakeMs: Int? = nil,
        optimalIoTimeoutMs: Int? = nil,
        optimalInactivityTimeoutMs: Int? = nil,
        p95ReadThroughputMBps: Double? = nil,
        p95WriteThroughputMBps: Double? = nil,
        successRate: Double = 1.0,
        hostEnvironment: String = ProcessInfo.processInfo.operatingSystemVersionString
    ) {
        self.fingerprintHash = fingerprintHash
        self.created = created
        self.lastUpdated = lastUpdated
        self.sampleCount = sampleCount
        self.optimalChunkSize = optimalChunkSize
        self.avgHandshakeMs = avgHandshakeMs
        self.optimalIoTimeoutMs = optimalIoTimeoutMs
        self.optimalInactivityTimeoutMs = optimalInactivityTimeoutMs
        self.p95ReadThroughputMBps = p95ReadThroughputMBps
        self.p95WriteThroughputMBps = p95WriteThroughputMBps
        self.successRate = successRate
        self.hostEnvironment = hostEnvironment
    }
}
