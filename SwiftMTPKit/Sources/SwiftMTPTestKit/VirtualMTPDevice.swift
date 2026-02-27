// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
@_spi(Dev) import SwiftMTPCore
import SwiftMTPQuirks

// MARK: - Operation Record

/// A recorded operation on a virtual MTP device for test assertions.
public struct OperationRecord: Sendable {
  public let operation: String
  public let timestamp: Date
  public let parameters: [String: String]

  public init(operation: String, timestamp: Date = Date(), parameters: [String: String] = [:]) {
    self.operation = operation
    self.timestamp = timestamp
    self.parameters = parameters
  }
}

// MARK: - VirtualMTPDevice

/// An in-memory MTP device for testing that implements the full ``MTPDevice`` protocol.
///
/// All data lives in memory -- no USB transport or real device is needed.
/// Use ``injectEvent(_:)`` to simulate device-side changes and inspect
/// ``operations`` to verify the sequence of calls your code makes.
public actor VirtualMTPDevice: MTPDevice {
  public let id: MTPDeviceID
  public let summary: MTPDeviceSummary

  private var deviceInfo: MTPDeviceInfo
  private var storageConfigs: [VirtualStorageConfig]
  private var objectTree: [MTPObjectHandle: VirtualObjectConfig]
  private var nextHandle: MTPObjectHandle
  private var operationLog: [OperationRecord] = []

  private var eventContinuation: AsyncStream<MTPEvent>.Continuation?
  private let _events: AsyncStream<MTPEvent>

  // MARK: - Initialisation

  public init(config: VirtualDeviceConfig) {
    self.id = config.deviceId
    self.summary = config.summary
    self.deviceInfo = config.info
    self.storageConfigs = config.storages
    self.objectTree = Dictionary(
      uniqueKeysWithValues: config.objects.map { ($0.handle, $0) }
    )
    self.nextHandle = (config.objects.map(\.handle).max() ?? 0) + 1

    let (stream, continuation) = AsyncStream<MTPEvent>.makeStream()
    self._events = stream
    self.eventContinuation = continuation
  }

  // MARK: - MTPDevice Protocol

  public var info: MTPDeviceInfo {
    get async throws { deviceInfo }
  }

  public func storages() async throws -> [MTPStorageInfo] {
    record("storages")
    return storageConfigs.map { $0.toStorageInfo() }
  }

  public nonisolated func list(parent: MTPObjectHandle?, in storage: MTPStorageID)
    -> AsyncThrowingStream<[MTPObjectInfo], Error>
  {
    AsyncThrowingStream { continuation in
      Task {
        let matching = await self.objectsMatching(storage: storage, parent: parent)
        let batch = matching.map { $0.toObjectInfo() }
        if !batch.isEmpty {
          continuation.yield(batch)
        }
        continuation.finish()
      }
    }
  }

  /// Actor-isolated helper for fetching matching objects.
  private func objectsMatching(storage: MTPStorageID, parent: MTPObjectHandle?)
    -> [VirtualObjectConfig]
  {
    objectTree.values.filter { obj in
      obj.storage.raw == storage.raw && obj.parent == parent
    }
  }

  public func getInfo(handle: MTPObjectHandle) async throws -> MTPObjectInfo {
    record("getInfo", parameters: ["handle": "\(handle)"])
    guard let obj = objectTree[handle] else {
      throw MTPError.objectNotFound
    }
    return obj.toObjectInfo()
  }

  public func read(handle: MTPObjectHandle, range: Range<UInt64>?, to url: URL) async throws
    -> Progress
  {
    record("read", parameters: ["handle": "\(handle)", "url": url.lastPathComponent])
    guard let obj = objectTree[handle] else {
      throw MTPError.objectNotFound
    }
    let data = obj.data ?? Data()
    let slice: Data
    if let range {
      let lower = Int(range.lowerBound)
      let upper = min(Int(range.upperBound), data.count)
      slice = data.subdata(in: lower..<upper)
    } else {
      slice = data
    }
    try slice.write(to: url)
    let progress = Progress(totalUnitCount: Int64(slice.count))
    progress.completedUnitCount = Int64(slice.count)
    return progress
  }

  public func createFolder(parent: MTPObjectHandle?, name: String, storage: MTPStorageID)
    async throws -> MTPObjectHandle
  {
    record(
      "createFolder",
      parameters: ["parent": "\(parent ?? 0)", "name": name, "storage": "\(storage.raw)"])
    let handle = nextHandle
    nextHandle += 1

    let storageId: MTPStorageID
    if let parent, let parentObj = objectTree[parent] {
      storageId = parentObj.storage
    } else {
      storageId = storage
    }

    let obj = VirtualObjectConfig(
      handle: handle,
      storage: storageId,
      parent: parent,
      name: name,
      sizeBytes: 0,
      formatCode: 0x3001  // Association
    )
    objectTree[handle] = obj
    return handle
  }

  public func write(parent: MTPObjectHandle?, name: String, size: UInt64, from url: URL)
    async throws -> Progress
  {
    record("write", parameters: ["parent": "\(parent ?? 0)", "name": name, "size": "\(size)"])
    let fileData = try Data(contentsOf: url)

    // Determine the storage from the parent, or use the first storage.
    let storageId: MTPStorageID
    if let parent, let parentObj = objectTree[parent] {
      storageId = parentObj.storage
    } else {
      guard let first = storageConfigs.first else {
        throw MTPError.preconditionFailed("No storages configured on virtual device")
      }
      storageId = first.id
    }

    let handle = nextHandle
    nextHandle += 1

    let obj = VirtualObjectConfig(
      handle: handle,
      storage: storageId,
      parent: parent,
      name: name,
      sizeBytes: UInt64(fileData.count),
      formatCode: PTPObjectFormat.forFilename(name),
      data: fileData
    )
    objectTree[handle] = obj

    let progress = Progress(totalUnitCount: Int64(fileData.count))
    progress.completedUnitCount = Int64(fileData.count)
    return progress
  }

  public func delete(_ handle: MTPObjectHandle, recursive: Bool) async throws {
    record("delete", parameters: ["handle": "\(handle)", "recursive": "\(recursive)"])
    guard objectTree[handle] != nil else {
      throw MTPError.objectNotFound
    }
    if recursive {
      removeSubtree(handle)
    } else {
      objectTree.removeValue(forKey: handle)
    }
  }

  public func rename(_ handle: MTPObjectHandle, to newName: String) async throws {
    record("rename", parameters: ["handle": "\(handle)", "newName": newName])
    guard let existing = objectTree[handle] else {
      throw MTPError.objectNotFound
    }
    let renamed = VirtualObjectConfig(
      handle: existing.handle, storage: existing.storage, parent: existing.parent,
      name: newName, sizeBytes: existing.sizeBytes, formatCode: existing.formatCode,
      data: existing.data)
    objectTree[handle] = renamed
  }

  public func move(_ handle: MTPObjectHandle, to newParent: MTPObjectHandle?) async throws {
    record("move", parameters: ["handle": "\(handle)", "newParent": "\(newParent ?? 0)"])
    guard let existing = objectTree[handle] else {
      throw MTPError.objectNotFound
    }
    let moved = VirtualObjectConfig(
      handle: existing.handle,
      storage: existing.storage,
      parent: newParent,
      name: existing.name,
      sizeBytes: existing.sizeBytes,
      formatCode: existing.formatCode,
      data: existing.data
    )
    objectTree[handle] = moved
  }

  public var probedCapabilities: [String: Bool] {
    get async { [:] }
  }

  public var effectiveTuning: EffectiveTuning {
    get async { EffectiveTuning.defaults() }
  }

  public var devicePolicy: DevicePolicy? {
    get async { nil }
  }

  public var probeReceipt: ProbeReceipt? {
    get async { nil }
  }

  public func openIfNeeded() async throws {
    record("openIfNeeded")
  }

  public nonisolated var events: AsyncStream<MTPEvent> {
    _events
  }

  // MARK: - @_spi(Dev) Protocol Methods

  public func devClose() async throws {
    record("devClose")
    eventContinuation?.finish()
    eventContinuation = nil
  }

  public func devGetDeviceInfoUncached() async throws -> MTPDeviceInfo {
    record("devGetDeviceInfoUncached")
    return deviceInfo
  }

  public func devGetStorageIDsUncached() async throws -> [MTPStorageID] {
    record("devGetStorageIDsUncached")
    return storageConfigs.map(\.id)
  }

  public func devGetRootHandlesUncached(storage: MTPStorageID) async throws -> [MTPObjectHandle] {
    record("devGetRootHandlesUncached", parameters: ["storage": "\(storage.raw)"])
    return objectTree.values
      .filter { $0.storage.raw == storage.raw && $0.parent == nil }
      .map(\.handle)
  }

  public func devGetObjectInfoUncached(handle: MTPObjectHandle) async throws -> MTPObjectInfo {
    record("devGetObjectInfoUncached", parameters: ["handle": "\(handle)"])
    guard let obj = objectTree[handle] else {
      throw MTPError.objectNotFound
    }
    return obj.toObjectInfo()
  }

  // MARK: - Runtime Mutation

  /// Add an object to the in-memory tree at runtime.
  public func addObject(_ obj: VirtualObjectConfig) {
    objectTree[obj.handle] = obj
    if obj.handle >= nextHandle {
      nextHandle = obj.handle + 1
    }
  }

  /// Remove an object from the in-memory tree.
  public func removeObject(handle: MTPObjectHandle) {
    objectTree.removeValue(forKey: handle)
  }

  /// Inject an event into the device's event stream.
  public func injectEvent(_ event: MTPEvent) {
    eventContinuation?.yield(event)
  }

  // MARK: - Inspection

  /// All operations recorded so far.
  public var operations: [OperationRecord] { operationLog }

  /// Clear the operation log.
  public func clearOperations() {
    operationLog.removeAll()
  }

  // MARK: - Private Helpers

  private func record(_ operation: String, parameters: [String: String] = [:]) {
    operationLog.append(
      OperationRecord(
        operation: operation,
        timestamp: Date(),
        parameters: parameters
      ))
  }

  private func removeSubtree(_ handle: MTPObjectHandle) {
    // Find children first
    let children = objectTree.values.filter { $0.parent == handle }.map(\.handle)
    for child in children {
      removeSubtree(child)
    }
    objectTree.removeValue(forKey: handle)
  }
}
