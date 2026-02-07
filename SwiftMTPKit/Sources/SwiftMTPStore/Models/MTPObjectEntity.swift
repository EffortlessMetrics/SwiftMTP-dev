// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import SwiftData

@Model
public final class MTPObjectEntity {
    @Attribute(.unique) public var compoundId: String // "deviceId:storageId:handle"
    public var deviceId: String
    public var storageId: Int
    public var handle: Int
    public var parentHandle: Int?
    public var name: String
    public var pathKey: String
    public var sizeBytes: Int64?
    public var modifiedAt: Date?
    public var formatCode: Int
    public var generation: Int
    public var isTombstoned: Bool
    
    public var storage: MTPStorageEntity?

    public init(
        deviceId: String,
        storageId: Int,
        handle: Int,
        parentHandle: Int? = nil,
        name: String,
        pathKey: String,
        sizeBytes: Int64? = nil,
        modifiedAt: Date? = nil,
        formatCode: Int,
        generation: Int,
        isTombstoned: Bool = false
    ) {
        self.compoundId = "\(deviceId):\(storageId):\(handle)"
        self.deviceId = deviceId
        self.storageId = storageId
        self.handle = handle
        self.parentHandle = parentHandle
        self.name = name
        self.pathKey = pathKey
        self.sizeBytes = sizeBytes
        self.modifiedAt = modifiedAt
        self.formatCode = formatCode
        self.generation = generation
        self.isTombstoned = isTombstoned
    }
}
