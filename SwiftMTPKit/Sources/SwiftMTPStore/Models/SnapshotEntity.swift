// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import SwiftData

@Model
public final class SnapshotEntity {
    public var generation: Int
    public var createdAt: Date
    public var artifactPath: String?
    public var artifactHash: String?
    
    public var device: DeviceEntity?

    public init(generation: Int, createdAt: Date = Date(), artifactPath: String? = nil, artifactHash: String? = nil) {
        self.generation = generation
        self.createdAt = createdAt
        self.artifactPath = artifactPath
        self.artifactHash = artifactHash
    }
}
