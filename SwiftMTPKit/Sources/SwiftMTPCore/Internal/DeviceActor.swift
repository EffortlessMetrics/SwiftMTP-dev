// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import SwiftMTPObservability
import OSLog

public actor MTPDeviceActor: MTPDevice {
    public let id: MTPDeviceID
    private let transport: any MTPTransport
    private let summary: MTPDeviceSummary
    private let config: SwiftMTPConfig
    private var deviceInfo: MTPDeviceInfo?
    private var mtpLink: (any MTPLink)?
    private var sessionOpen = false
    let transferJournal: (any TransferJournal)?

    public init(id: MTPDeviceID, summary: MTPDeviceSummary, transport: MTPTransport, config: SwiftMTPConfig = .init(), transferJournal: (any TransferJournal)? = nil) {
        self.id = id
        self.summary = summary
        self.transport = transport
        self.config = config
        self.transferJournal = transferJournal
    }

    public var info: MTPDeviceInfo {
        get async throws {
            if let deviceInfo {
                return deviceInfo
            }

            // For mock devices, return the mock device info
            // For real devices, this would parse the actual MTP DeviceInfo response
            let mtpDeviceInfo = MTPDeviceInfo(
                manufacturer: summary.manufacturer,
                model: summary.model,
                version: "Mock Version 1.0",
                serialNumber: "MOCK123456",
                operationsSupported: Set([0x1001, 0x1002, 0x1004, 0x1005]), // Basic operations
                eventsSupported: Set([0x4002, 0x4003]) // Basic events
            )

            self.deviceInfo = mtpDeviceInfo
            return mtpDeviceInfo
        }
    }

    public func storages() async throws -> [MTPStorageInfo] {
        try await openIfNeeded()

        // Wrap storage operations with DEVICE_BUSY backoff
        return try await performStorageOperationsWithBackoff()
    }

    private nonisolated func performStorageOperationsWithBackoff() async throws -> [MTPStorageInfo] {
        // For now, implement without backoff to get basic functionality working
        // TODO: Re-implement with proper backoff once concurrency issues are resolved
        let link = try await getMTPLink()

        // First get storage IDs
        let storageIDs = try await getStorageIDs(using: link)

        // Then get storage info for each storage
        var storages = [MTPStorageInfo]()
        for storageID in storageIDs {
            let storageInfo = try await getStorageInfo(storageID, using: link)
            storages.append(storageInfo)
        }

        return storages
    }

    private nonisolated func performObjectEnumerationWithBackoff(parent: MTPObjectHandle?, storage: MTPStorageID) async throws -> [MTPObjectInfo] {
        // For now, implement without backoff to get basic functionality working
        // TODO: Re-implement with proper backoff once concurrency issues are resolved
        let link = try await getMTPLink()

        // Performance logging: begin enumeration
        MTPLog.perf.info("Enumeration begin: storage=\(storage.raw) parent=\(parent ?? 0)")

        // Get object handles for this parent/storage
        let objectHandles = try await getObjectHandles(parent: parent, storage: storage, using: link)

        // Get object info for each handle
        var objectInfos = [MTPObjectInfo]()
        for handle in objectHandles {
            let objectInfo = try await getObjectInfo(handle, using: link)
            objectInfos.append(objectInfo)
        }

        return objectInfos
    }

    public nonisolated func list(parent: MTPObjectHandle?, in storage: MTPStorageID) -> AsyncThrowingStream<[MTPObjectInfo], Error> {
        AsyncThrowingStream { continuation in
            Task {
                let enumStartTime = Date()
                do {
                    try await openIfNeeded()

                    // Wrap object enumeration with DEVICE_BUSY backoff
                    let objectInfos = try await performObjectEnumerationWithBackoff(parent: parent, storage: storage)

                    // Performance logging: end enumeration (success)
                    let enumDuration = Date().timeIntervalSince(enumStartTime)
                    MTPLog.perf.info("Enumeration completed: \(objectInfos.count) objects in \(String(format: "%.2f", enumDuration))s")

                    // Yield the results
                    continuation.yield(objectInfos)
                    continuation.finish()
                } catch {
                    // Performance logging: end enumeration (failure)
                    let enumDuration = Date().timeIntervalSince(enumStartTime)
                    MTPLog.perf.error("Enumeration failed: after \(String(format: "%.2f", enumDuration))s - \(error.localizedDescription)")

                    continuation.finish(throwing: error)
                }
            }
        }
    }

    public func getInfo(handle: MTPObjectHandle) async throws -> MTPObjectInfo {
        try await openIfNeeded()
        let link = try await getMTPLink()
        return try await getObjectInfo(handle, using: link)
    }

    // Note: read/write methods are implemented in DeviceActor+Transfer.swift

    public func delete(_ handle: MTPObjectHandle, recursive: Bool) async throws {
        // TODO: Implement object deletion
        throw MTPError.notSupported("Object deletion not implemented")
    }

    public func move(_ handle: MTPObjectHandle, to newParent: MTPObjectHandle?) async throws {
        // TODO: Implement object moving
        throw MTPError.notSupported("Object moving not implemented")
    }

    public nonisolated var events: AsyncStream<MTPEvent> {
        // TODO: Implement event stream
        return AsyncStream { _ in }
    }

    // MARK: - Session Management

    /// Open device session if not already open, with optional stabilization delay.
    internal func openIfNeeded() async throws {
        if sessionOpen { return }

        let link = try await getMTPLink()

        // Open MTP session using PTP OpenSession command
        let openSessionCommand = PTPContainer(
            length: 16,
            type: PTPContainer.Kind.command.rawValue,
            code: PTPOp.openSession.rawValue,
            txid: 1,
            params: [1] // Session ID = 1
        )

        guard let response = try link.executeCommand(openSessionCommand) else {
            throw MTPError.protocolError(code: 0, message: "OpenSession command failed")
        }

        // Check response code (should be 0x2001 for OK)
        guard response.count >= 12 else {
            throw MTPError.protocolError(code: 0, message: "OpenSession response too short")
        }

        let responseCode = response.withUnsafeBytes {
            $0.load(fromByteOffset: 6, as: UInt16.self).littleEndian
        }

        guard responseCode == 0x2001 else {
            throw MTPError.protocolError(code: responseCode, message: "OpenSession failed")
        }

        sessionOpen = true

        // Apply stabilization delay if configured (e.g., for Xiaomi devices)
        if config.stabilizeMs > 0 {
            try? await Task.sleep(nanoseconds: UInt64(config.stabilizeMs) * 1_000_000)
        }
    }

    // MARK: - Helper Methods

    internal func getMTPLink() async throws -> any MTPLink {
        if let link = mtpLink {
            return link
        }

        let link = try await transport.open(summary, config: config)
        self.mtpLink = link
        return link
    }

    private func getStorageIDs(using link: any MTPLink) async throws -> [MTPStorageID] {
        let command = PTPContainer(
            length: 12,
            type: PTPContainer.Kind.command.rawValue,
            code: PTPOp.getStorageIDs.rawValue,
            txid: 1,
            params: []
        )

        guard let responseData = try link.executeCommand(command) else {
            return []
        }

        // Parse response: [count: UInt32, storageIDs: [UInt32]]
        guard responseData.count >= 4 else { return [] }

        let count = responseData.withUnsafeBytes { ptr in
            ptr.load(fromByteOffset: 0, as: UInt32.self).littleEndian
        }

        guard responseData.count >= 4 + Int(count) * 4 else { return [] }

        var storageIDs = [MTPStorageID]()
        for i in 0..<Int(count) {
            let offset = 4 + i * 4
            let storageIDRaw = responseData.withUnsafeBytes { ptr in
                ptr.load(fromByteOffset: offset, as: UInt32.self).littleEndian
            }
            storageIDs.append(MTPStorageID(raw: storageIDRaw))
        }

        return storageIDs
    }

    private func getStorageInfo(_ storageID: MTPStorageID, using link: any MTPLink) async throws -> MTPStorageInfo {
        let command = PTPContainer(
            length: 16,
            type: PTPContainer.Kind.command.rawValue,
            code: PTPOp.getStorageInfo.rawValue,
            txid: 2,
            params: [storageID.raw]
        )

        guard let responseData = try link.executeCommand(command) else {
            throw MTPError.protocolError(code: 0, message: "No storage info response")
        }

        // Parse StorageInfo dataset
        // Format: StorageType(2), FilesystemType(2), AccessCapability(2), MaxCapacity(8), FreeSpace(8), FreeSpaceInObjects(4), StorageDescription(string), VolumeLabel(string)
        var offset = 0

        func read16() -> UInt16 {
            let value = responseData.withUnsafeBytes { ptr in
                // Read byte by byte to avoid alignment issues
                let b0 = UInt16(ptr[offset])
                let b1 = UInt16(ptr[offset + 1]) << 8
                return b0 | b1
            }
            offset += 2
            return value
        }

        func read32() -> UInt32 {
            let value = responseData.withUnsafeBytes { ptr in
                // Read byte by byte to avoid alignment issues
                let b0 = UInt32(ptr[offset])
                let b1 = UInt32(ptr[offset + 1]) << 8
                let b2 = UInt32(ptr[offset + 2]) << 16
                let b3 = UInt32(ptr[offset + 3]) << 24
                return b0 | b1 | b2 | b3
            }
            offset += 4
            return value
        }

        func read64() -> UInt64 {
            let value = responseData.withUnsafeBytes { ptr in
                // Read byte by byte to avoid alignment issues
                let b0 = UInt64(ptr[offset])
                let b1 = UInt64(ptr[offset + 1]) << 8
                let b2 = UInt64(ptr[offset + 2]) << 16
                let b3 = UInt64(ptr[offset + 3]) << 24
                let b4 = UInt64(ptr[offset + 4]) << 32
                let b5 = UInt64(ptr[offset + 5]) << 40
                let b6 = UInt64(ptr[offset + 6]) << 48
                let b7 = UInt64(ptr[offset + 7]) << 56
                return b0 | b1 | b2 | b3 | b4 | b5 | b6 | b7
            }
            offset += 8
            return value
        }

        func readString() -> String {
            guard let string = PTPString.parse(from: responseData, at: &offset) else {
                return "Unknown"
            }
            return string
        }

        guard responseData.count >= 22 else { // Minimum size for fixed fields
            throw MTPError.protocolError(code: 0, message: "Storage info response too short")
        }

        let _ = read16() // StorageType
        let _ = read16() // FilesystemType
        let accessCapability = read16()
        let maxCapacity = read64()
        let freeSpace = read64()
        let _ = read32() // FreeSpaceInObjects
        let description = readString()
        let _ = readString() // VolumeLabel

        let isReadOnly = accessCapability == 0x0001

        return MTPStorageInfo(
            id: storageID,
            description: description,
            capacityBytes: maxCapacity,
            freeBytes: freeSpace,
            isReadOnly: isReadOnly
        )
    }

    private func getObjectHandles(parent: MTPObjectHandle?, storage: MTPStorageID, using link: any MTPLink) async throws -> [MTPObjectHandle] {
        let parentHandle = parent ?? 0xFFFFFFFF // 0xFFFFFFFF means root level

        let command = PTPContainer(
            length: 20,
            type: PTPContainer.Kind.command.rawValue,
            code: PTPOp.getObjectHandles.rawValue,
            txid: 3,
            params: [storage.raw, parentHandle]
        )

        guard let responseData = try link.executeCommand(command) else {
            return []
        }

        // Parse response: [count: UInt32, objectHandles: [UInt32]]
        guard responseData.count >= 4 else { return [] }

        let count = responseData.withUnsafeBytes { ptr in
            ptr.load(fromByteOffset: 0, as: UInt32.self).littleEndian
        }

        guard responseData.count >= 4 + Int(count) * 4 else { return [] }

        var objectHandles = [MTPObjectHandle]()
        for i in 0..<Int(count) {
            let offset = 4 + i * 4
            let handle = responseData.withUnsafeBytes { ptr in
                ptr.load(fromByteOffset: offset, as: UInt32.self).littleEndian
            }
            objectHandles.append(handle)
        }

        return objectHandles
    }

    internal func getObjectInfo(_ handle: MTPObjectHandle, using link: any MTPLink) async throws -> MTPObjectInfo {
        let command = PTPContainer(
            length: 16,
            type: PTPContainer.Kind.command.rawValue,
            code: PTPOp.getObjectInfo.rawValue,
            txid: 4,
            params: [handle]
        )

        guard let responseData = try link.executeCommand(command) else {
            throw MTPError.protocolError(code: 0, message: "No object info response")
        }

        // Parse ObjectInfo dataset
        var offset = 0

        func read16() -> UInt16 {
            let value = responseData.withUnsafeBytes { ptr in
                // Read byte by byte to avoid alignment issues
                let b0 = UInt16(ptr[offset])
                let b1 = UInt16(ptr[offset + 1]) << 8
                return b0 | b1
            }
            offset += 2
            return value
        }

        func read32() -> UInt32 {
            let value = responseData.withUnsafeBytes { ptr in
                // Read byte by byte to avoid alignment issues
                let b0 = UInt32(ptr[offset])
                let b1 = UInt32(ptr[offset + 1]) << 8
                let b2 = UInt32(ptr[offset + 2]) << 16
                let b3 = UInt32(ptr[offset + 3]) << 24
                return b0 | b1 | b2 | b3
            }
            offset += 4
            return value
        }

        func read64() -> UInt64 {
            let value = responseData.withUnsafeBytes { ptr in
                // Read byte by byte to avoid alignment issues
                let b0 = UInt64(ptr[offset])
                let b1 = UInt64(ptr[offset + 1]) << 8
                let b2 = UInt64(ptr[offset + 2]) << 16
                let b3 = UInt64(ptr[offset + 3]) << 24
                let b4 = UInt64(ptr[offset + 4]) << 32
                let b5 = UInt64(ptr[offset + 5]) << 40
                let b6 = UInt64(ptr[offset + 6]) << 48
                let b7 = UInt64(ptr[offset + 7]) << 56
                return b0 | b1 | b2 | b3 | b4 | b5 | b6 | b7
            }
            offset += 8
            return value
        }

        func readString() -> String {
            guard let string = PTPString.parse(from: responseData, at: &offset) else {
                return "Unknown"
            }
            return string
        }

        guard responseData.count >= 52 else { // Minimum size for fixed fields
            throw MTPError.protocolError(code: 0, message: "Object info response too short")
        }

        let storageIDRaw = read32()
        let formatCode = read16()
        let _ = read16() // ProtectionStatus
        let compressedSize = read32()
        let _ = read16() // ThumbFormat
        let _ = read32() // ThumbCompressedSize
        let _ = read32() // ThumbWidth
        let _ = read32() // ThumbHeight
        let _ = read32() // ImageWidth
        let _ = read32() // ImageHeight
        let _ = read32() // ImageBitDepth
        let parentObject = read32()
        let _ = read16() // AssociationType
        let _ = read32() // AssociationDesc
        let _ = read32() // SequenceNumber
        let filename = readString()
        let _ = readString() // CaptureDate
        let _ = readString() // ModificationDate
        let _ = readString() // Keywords

        let storage = MTPStorageID(raw: storageIDRaw)
        let parent = parentObject == 0 ? nil : parentObject
        let size = compressedSize == 0xFFFFFFFF ? nil : UInt64(compressedSize)

        return MTPObjectInfo(
            handle: handle,
            storage: storage,
            parent: parent,
            name: filename,
            sizeBytes: size,
            modified: nil, // TODO: Parse modification date
            formatCode: formatCode,
            properties: [:] // TODO: Parse additional properties
        )
    }
}
