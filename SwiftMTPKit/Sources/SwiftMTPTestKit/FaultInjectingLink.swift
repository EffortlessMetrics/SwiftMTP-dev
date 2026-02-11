// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import SwiftMTPCore

/// A decorator that wraps any ``MTPLink`` and injects faults according to a ``FaultSchedule``.
///
/// Use this to simulate transport failures, timeouts, and protocol errors
/// when testing error-handling and retry logic.
///
/// ```swift
/// let realLink = VirtualMTPLink(config: .pixel7)
/// let schedule = FaultSchedule([.timeoutOnce(on: .getStorageIDs)])
/// let faultyLink = FaultInjectingLink(wrapping: realLink, schedule: schedule)
/// ```
public final class FaultInjectingLink: MTPLink, @unchecked Sendable {
    private let inner: any MTPLink
    private let schedule: FaultSchedule
    private var callCount = 0
    private let lock = NSLock()

    public var cachedDeviceInfo: MTPDeviceInfo? { inner.cachedDeviceInfo }
    public var linkDescriptor: MTPLinkDescriptor? { inner.linkDescriptor }

    public init(wrapping inner: any MTPLink, schedule: FaultSchedule) {
        self.inner = inner
        self.schedule = schedule
    }

    /// Dynamically add a fault to the schedule.
    public func scheduleFault(_ fault: ScheduledFault) {
        schedule.add(fault)
    }

    // MARK: - MTPLink Protocol

    public func openUSBIfNeeded() async throws {
        try checkFault(.openUSB)
        try await inner.openUSBIfNeeded()
    }

    public func openSession(id: UInt32) async throws {
        try checkFault(.openSession)
        try await inner.openSession(id: id)
    }

    public func closeSession() async throws {
        try checkFault(.closeSession)
        try await inner.closeSession()
    }

    public func close() async {
        await inner.close()
    }

    public func getDeviceInfo() async throws -> MTPDeviceInfo {
        try checkFault(.getDeviceInfo)
        return try await inner.getDeviceInfo()
    }

    public func getStorageIDs() async throws -> [MTPStorageID] {
        try checkFault(.getStorageIDs)
        return try await inner.getStorageIDs()
    }

    public func getStorageInfo(id: MTPStorageID) async throws -> MTPStorageInfo {
        try checkFault(.getStorageInfo)
        return try await inner.getStorageInfo(id: id)
    }

    public func getObjectHandles(storage: MTPStorageID, parent: MTPObjectHandle?) async throws -> [MTPObjectHandle] {
        try checkFault(.getObjectHandles)
        return try await inner.getObjectHandles(storage: storage, parent: parent)
    }

    public func getObjectInfos(_ handles: [MTPObjectHandle]) async throws -> [MTPObjectInfo] {
        try checkFault(.getObjectInfos)
        return try await inner.getObjectInfos(handles)
    }

    public func getObjectInfos(storage: MTPStorageID, parent: MTPObjectHandle?, format: UInt16?) async throws -> [MTPObjectInfo] {
        try checkFault(.getObjectInfos)
        return try await inner.getObjectInfos(storage: storage, parent: parent, format: format)
    }

    public func resetDevice() async throws {
        try await inner.resetDevice()
    }

    public func deleteObject(handle: MTPObjectHandle) async throws {
        try checkFault(.deleteObject)
        try await inner.deleteObject(handle: handle)
    }

    public func moveObject(handle: MTPObjectHandle, to storage: MTPStorageID, parent: MTPObjectHandle?) async throws {
        try checkFault(.moveObject)
        try await inner.moveObject(handle: handle, to: storage, parent: parent)
    }

    public func executeCommand(_ command: PTPContainer) async throws -> PTPResponseResult {
        try checkFault(.executeCommand)
        return try await inner.executeCommand(command)
    }

    public func executeStreamingCommand(
        _ command: PTPContainer,
        dataPhaseLength: UInt64?,
        dataInHandler: MTPDataIn?,
        dataOutHandler: MTPDataOut?
    ) async throws -> PTPResponseResult {
        try checkFault(.executeStreamingCommand)
        return try await inner.executeStreamingCommand(
            command,
            dataPhaseLength: dataPhaseLength,
            dataInHandler: dataInHandler,
            dataOutHandler: dataOutHandler
        )
    }

    // MARK: - Private

    private func checkFault(_ operation: LinkOperationType) throws {
        let index = lock.withLock { () -> Int in
            let idx = callCount
            callCount += 1
            return idx
        }
        if let error = schedule.check(operation: operation, callIndex: index, byteOffset: nil) {
            throw error.transportError
        }
    }
}
