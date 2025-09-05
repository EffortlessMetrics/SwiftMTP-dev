// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation

public protocol MTPTransport: Sendable {
    func open(_ summary: MTPDeviceSummary, config: SwiftMTPConfig) async throws -> MTPLink
}

public protocol MTPLink: Sendable {
    func openUSBIfNeeded() async throws
    func openSession(id: UInt32) async throws
    func closeSession() async throws
    func close() async

    func getDeviceInfo() async throws -> MTPDeviceInfo
    func getStorageIDs() async throws -> [MTPStorageID]
    func getStorageInfo(id: MTPStorageID) async throws -> MTPStorageInfo
    func getObjectHandles(storage: MTPStorageID, parent: MTPObjectHandle?) async throws -> [MTPObjectHandle]
    func getObjectInfos(_ handles: [MTPObjectHandle]) async throws -> [MTPObjectInfo]

    func deleteObject(handle: MTPObjectHandle) async throws
    func moveObject(handle: MTPObjectHandle, to storage: MTPStorageID, parent: MTPObjectHandle?) async throws

    func executeCommand(_ command: PTPContainer) throws -> Data?

    // Streaming data transfer methods for file operations
    func executeStreamingCommand(
        _ command: PTPContainer,
        dataInHandler: MTPDataIn?,
        dataOutHandler: MTPDataOut?
    ) async throws -> Data?
}

public protocol TransportFactory {
    static func createTransport() -> MTPTransport
}
