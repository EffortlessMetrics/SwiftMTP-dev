// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import SwiftMTPCore

/// An ``MTPLink`` that replays a previously recorded transcript.
///
/// Each call to any protocol method consumes the next ``TranscriptEntry``.
/// If the entry contains an error, the call throws; otherwise an appropriate
/// default result is returned.
///
/// ```swift
/// let recorder = TranscriptRecorder(wrapping: someLink)
/// // ... use recorder ...
/// let json = try recorder.exportJSON()
///
/// let replay = try TranscriptReplayLink(json: json)
/// let info = try await replay.getDeviceInfo()
/// ```
public final class TranscriptReplayLink: MTPLink, @unchecked Sendable {
    private var entries: [TranscriptEntry]
    private var cursor = 0
    private let lock = NSLock()

    public var cachedDeviceInfo: MTPDeviceInfo? { nil }

    /// Create a replay link from transcript entries.
    public init(transcript: [TranscriptEntry]) {
        self.entries = transcript
    }

    /// Create a replay link from JSON data exported by ``TranscriptRecorder``.
    public init(json: Data) throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.entries = try decoder.decode([TranscriptEntry].self, from: json)
    }

    // MARK: - MTPLink Protocol

    public func openUSBIfNeeded() async throws {
        try consumeNext("openUSBIfNeeded")
    }

    public func openSession(id: UInt32) async throws {
        try consumeNext("openSession")
    }

    public func closeSession() async throws {
        try consumeNext("closeSession")
    }

    public func close() async {
        _ = try? consumeNext("close")
    }

    public func getDeviceInfo() async throws -> MTPDeviceInfo {
        let entry = try consumeNext("getDeviceInfo")
        // Return a minimal device info; the replay is primarily for
        // verifying call sequences rather than data fidelity.
        _ = entry
        return MTPDeviceInfo(
            manufacturer: "Replay",
            model: "Replay Device",
            version: "1.0",
            serialNumber: nil,
            operationsSupported: [],
            eventsSupported: []
        )
    }

    public func getStorageIDs() async throws -> [MTPStorageID] {
        let entry = try consumeNext("getStorageIDs")
        let count = entry.response?.dataSize ?? 0
        return (0..<count).map { MTPStorageID(raw: UInt32($0 + 1)) }
    }

    public func getStorageInfo(id: MTPStorageID) async throws -> MTPStorageInfo {
        try consumeNext("getStorageInfo")
        return MTPStorageInfo(
            id: id,
            description: "Replay Storage",
            capacityBytes: 0,
            freeBytes: 0,
            isReadOnly: false
        )
    }

    public func getObjectHandles(storage: MTPStorageID, parent: MTPObjectHandle?) async throws -> [MTPObjectHandle] {
        let entry = try consumeNext("getObjectHandles")
        let count = entry.response?.dataSize ?? 0
        return (0..<count).map { MTPObjectHandle($0 + 1) }
    }

    public func getObjectInfos(_ handles: [MTPObjectHandle]) async throws -> [MTPObjectInfo] {
        let entry = try consumeNext("getObjectInfos")
        let count = entry.response?.dataSize ?? 0
        return (0..<count).map { idx in
            let handle = idx < handles.count ? handles[idx] : MTPObjectHandle(idx + 1)
            return MTPObjectInfo(
                handle: handle,
                storage: MTPStorageID(raw: 1),
                parent: nil,
                name: "replay_\(handle)",
                sizeBytes: nil,
                modified: nil,
                formatCode: 0x3000,
                properties: [:]
            )
        }
    }

    public func getObjectInfos(storage: MTPStorageID, parent: MTPObjectHandle?, format: UInt16?) async throws -> [MTPObjectInfo] {
        let entry = try consumeNext("getObjectInfos")
        let count = entry.response?.dataSize ?? 0
        return (0..<count).map { idx in
            MTPObjectInfo(
                handle: MTPObjectHandle(idx + 1),
                storage: storage,
                parent: parent,
                name: "replay_\(idx + 1)",
                sizeBytes: nil,
                modified: nil,
                formatCode: format ?? 0x3000,
                properties: [:]
            )
        }
    }

    public func resetDevice() async throws {
        try consumeNext("resetDevice")
    }

    public func deleteObject(handle: MTPObjectHandle) async throws {
        try consumeNext("deleteObject")
    }

    public func moveObject(handle: MTPObjectHandle, to storage: MTPStorageID, parent: MTPObjectHandle?) async throws {
        try consumeNext("moveObject")
    }

    public func executeCommand(_ command: PTPContainer) async throws -> PTPResponseResult {
        let entry = try consumeNext("executeCommand")
        return PTPResponseResult(
            code: entry.response?.code ?? 0x2001,
            txid: command.txid,
            params: entry.response?.params ?? []
        )
    }

    public func executeStreamingCommand(
        _ command: PTPContainer,
        dataPhaseLength: UInt64?,
        dataInHandler: MTPDataIn?,
        dataOutHandler: MTPDataOut?
    ) async throws -> PTPResponseResult {
        let entry = try consumeNext("executeStreamingCommand")
        return PTPResponseResult(
            code: entry.response?.code ?? 0x2001,
            txid: command.txid,
            params: entry.response?.params ?? []
        )
    }

    // MARK: - Private

    @discardableResult
    private func consumeNext(_ expectedOperation: String) throws -> TranscriptEntry {
        let entry: TranscriptEntry = try lock.withLock {
            guard cursor < entries.count else {
                throw TransportError.io("Transcript exhausted: no more entries (expected \(expectedOperation))")
            }
            let e = entries[cursor]
            cursor += 1
            return e
        }

        if let errorMessage = entry.error {
            throw TransportError.io("Replayed error for \(entry.operation): \(errorMessage)")
        }

        return entry
    }
}
