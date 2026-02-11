// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import SwiftData
import SwiftMTPCore

public final class SwiftMTPStore: Sendable {
    public static let shared = SwiftMTPStore()
    
    public let container: ModelContainer
    
    private init() {
        let useInMemory = ProcessInfo.processInfo.environment["SWIFTMTP_STORE_TYPE"] == "memory"

        let schema = Schema([
            DeviceEntity.self,
            LearnedProfileEntity.self,
            ProfilingRunEntity.self,
            ProfilingMetricEntity.self,
            SnapshotEntity.self,
            SubmissionEntity.self,
            TransferEntity.self,
            MTPStorageEntity.self,
            MTPObjectEntity.self
        ])
        let config = ModelConfiguration("SwiftMTP", schema: schema, isStoredInMemoryOnly: useInMemory)
        container = try! ModelContainer(for: schema, configurations: [config])
    }
    
    public func createActor() -> StoreActor {
        StoreActor(modelContainer: container)
    }
}
