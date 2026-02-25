// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import SwiftMTPCore

// MARK: - Transcript Types

/// A single entry in a PTP exchange transcript.
public struct TranscriptEntry: Codable, Sendable {
  public let timestamp: Date
  public let operation: String
  public let request: TranscriptData?
  public let response: TranscriptData?
  public let error: String?

  public init(
    timestamp: Date = Date(),
    operation: String,
    request: TranscriptData? = nil,
    response: TranscriptData? = nil,
    error: String? = nil
  ) {
    self.timestamp = timestamp
    self.operation = operation
    self.request = request
    self.response = response
    self.error = error
  }
}

/// Data associated with a PTP request or response.
public struct TranscriptData: Codable, Sendable {
  public let code: UInt16?
  public let params: [UInt32]?
  public let dataSize: Int?

  public init(code: UInt16? = nil, params: [UInt32]? = nil, dataSize: Int? = nil) {
    self.code = code
    self.params = params
    self.dataSize = dataSize
  }
}

// MARK: - TranscriptRecorder

/// A decorator that wraps any ``MTPLink`` and records every PTP exchange
/// for later inspection or serialisation to JSON.
///
/// ```swift
/// let link = VirtualMTPLink(config: .pixel7)
/// let recorder = TranscriptRecorder(wrapping: link)
/// let info = try await recorder.getDeviceInfo()
/// let entries = recorder.transcript()
/// ```
public final class TranscriptRecorder: MTPLink, @unchecked Sendable {
  private let inner: any MTPLink
  private var entries: [TranscriptEntry] = []
  private let lock = NSLock()

  public var cachedDeviceInfo: MTPDeviceInfo? { inner.cachedDeviceInfo }

  public init(wrapping inner: any MTPLink) {
    self.inner = inner
  }

  // MARK: - Transcript Access

  /// Returns a snapshot of all recorded entries.
  public func transcript() -> [TranscriptEntry] {
    lock.withLock { entries }
  }

  /// Exports the transcript as pretty-printed JSON.
  public func exportJSON() throws -> Data {
    let snapshot = lock.withLock { entries }
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    return try encoder.encode(snapshot)
  }

  // MARK: - MTPLink Protocol

  public func openUSBIfNeeded() async throws {
    try await record("openUSBIfNeeded") {
      try await inner.openUSBIfNeeded()
      return nil
    }
  }

  public func openSession(id: UInt32) async throws {
    try await record("openSession", request: TranscriptData(params: [id])) {
      try await inner.openSession(id: id)
      return nil
    }
  }

  public func closeSession() async throws {
    try await record("closeSession") {
      try await inner.closeSession()
      return nil
    }
  }

  public func close() async {
    await inner.close()
    appendEntry(TranscriptEntry(operation: "close"))
  }

  public func getDeviceInfo() async throws -> MTPDeviceInfo {
    var result: MTPDeviceInfo!
    try await record("getDeviceInfo") {
      result = try await inner.getDeviceInfo()
      return nil
    }
    return result
  }

  public func getStorageIDs() async throws -> [MTPStorageID] {
    var result: [MTPStorageID]!
    try await record("getStorageIDs") {
      result = try await inner.getStorageIDs()
      return TranscriptData(dataSize: result.count)
    }
    return result
  }

  public func getStorageInfo(id: MTPStorageID) async throws -> MTPStorageInfo {
    var result: MTPStorageInfo!
    try await record("getStorageInfo", request: TranscriptData(params: [id.raw])) {
      result = try await inner.getStorageInfo(id: id)
      return nil
    }
    return result
  }

  public func getObjectHandles(storage: MTPStorageID, parent: MTPObjectHandle?) async throws
    -> [MTPObjectHandle]
  {
    var result: [MTPObjectHandle]!
    let params: [UInt32] = [storage.raw] + (parent.map { [$0] } ?? [])
    try await record("getObjectHandles", request: TranscriptData(params: params)) {
      result = try await inner.getObjectHandles(storage: storage, parent: parent)
      return TranscriptData(dataSize: result.count)
    }
    return result
  }

  public func getObjectInfos(_ handles: [MTPObjectHandle]) async throws -> [MTPObjectInfo] {
    var result: [MTPObjectInfo]!
    try await record("getObjectInfos", request: TranscriptData(dataSize: handles.count)) {
      result = try await inner.getObjectInfos(handles)
      return TranscriptData(dataSize: result.count)
    }
    return result
  }

  public func getObjectInfos(storage: MTPStorageID, parent: MTPObjectHandle?, format: UInt16?)
    async throws -> [MTPObjectInfo]
  {
    var result: [MTPObjectInfo]!
    let params: [UInt32] = [storage.raw] + (parent.map { [$0] } ?? [])
    try await record("getObjectInfos", request: TranscriptData(code: format, params: params)) {
      result = try await inner.getObjectInfos(storage: storage, parent: parent, format: format)
      return TranscriptData(dataSize: result.count)
    }
    return result
  }

  public func resetDevice() async throws {
    try await record("resetDevice") {
      try await inner.resetDevice()
      return nil
    }
  }

  public func deleteObject(handle: MTPObjectHandle) async throws {
    try await record("deleteObject", request: TranscriptData(params: [handle])) {
      try await inner.deleteObject(handle: handle)
      return nil
    }
  }

  public func moveObject(
    handle: MTPObjectHandle, to storage: MTPStorageID, parent: MTPObjectHandle?
  ) async throws {
    let params: [UInt32] = [handle, storage.raw] + (parent.map { [$0] } ?? [])
    try await record("moveObject", request: TranscriptData(params: params)) {
      try await inner.moveObject(handle: handle, to: storage, parent: parent)
      return nil
    }
  }

  public func executeCommand(_ command: PTPContainer) async throws -> PTPResponseResult {
    var result: PTPResponseResult!
    try await record(
      "executeCommand", request: TranscriptData(code: command.code, params: command.params)
    ) {
      result = try await inner.executeCommand(command)
      return TranscriptData(code: result.code, params: result.params, dataSize: result.data?.count)
    }
    return result
  }

  public func executeStreamingCommand(
    _ command: PTPContainer,
    dataPhaseLength: UInt64?,
    dataInHandler: MTPDataIn?,
    dataOutHandler: MTPDataOut?
  ) async throws -> PTPResponseResult {
    var result: PTPResponseResult!
    try await record(
      "executeStreamingCommand",
      request: TranscriptData(
        code: command.code, params: command.params, dataSize: dataPhaseLength.map { Int($0) })
    ) {
      result = try await inner.executeStreamingCommand(
        command,
        dataPhaseLength: dataPhaseLength,
        dataInHandler: dataInHandler,
        dataOutHandler: dataOutHandler
      )
      return TranscriptData(code: result.code, params: result.params, dataSize: result.data?.count)
    }
    return result
  }

  // MARK: - Private

  private func record(
    _ operation: String,
    request: TranscriptData? = nil,
    body: () async throws -> TranscriptData?
  ) async rethrows {
    do {
      let response = try await body()
      appendEntry(
        TranscriptEntry(
          operation: operation,
          request: request,
          response: response
        ))
    } catch {
      appendEntry(
        TranscriptEntry(
          operation: operation,
          request: request,
          error: "\(error)"
        ))
      throw error
    }
  }

  private func appendEntry(_ entry: TranscriptEntry) {
    lock.withLock { entries.append(entry) }
  }
}
