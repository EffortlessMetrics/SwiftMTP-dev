// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import MTPEndianCodec
import SwiftMTPCore

/// An in-memory ``MTPLink`` implementation backed by a ``VirtualDeviceConfig``.
///
/// Useful for testing protocol-level code without a USB transport.
/// Optionally injects faults via a ``FaultSchedule``.
public final class VirtualMTPLink: MTPLink, @unchecked Sendable {
  private let config: VirtualDeviceConfig
  private var sessionOpen = false
  private var callCount = 0
  private let faultSchedule: FaultSchedule?
  private let lock = NSLock()

  public var cachedDeviceInfo: MTPDeviceInfo? { nil }

  public init(config: VirtualDeviceConfig, faultSchedule: FaultSchedule? = nil) {
    self.config = config
    self.faultSchedule = faultSchedule
  }

  // MARK: - MTPLink Protocol

  public func openUSBIfNeeded() async throws {
    try checkFault(.openUSB)
  }

  public func openSession(id: UInt32) async throws {
    try checkFault(.openSession)
    lock.withLock { sessionOpen = true }
  }

  public func closeSession() async throws {
    try checkFault(.closeSession)
    lock.withLock { sessionOpen = false }
  }

  public func close() async {
    lock.withLock { sessionOpen = false }
  }

  public func getDeviceInfo() async throws -> MTPDeviceInfo {
    try checkFault(.getDeviceInfo)
    try await applyLatency(.getDeviceInfo)
    return config.info
  }

  public func getStorageIDs() async throws -> [MTPStorageID] {
    try checkFault(.getStorageIDs)
    try await applyLatency(.getStorageIDs)
    return config.storages.map(\.id)
  }

  public func getStorageInfo(id: MTPStorageID) async throws -> MTPStorageInfo {
    try checkFault(.getStorageInfo)
    try await applyLatency(.getStorageInfo)
    guard let storage = config.storages.first(where: { $0.id.raw == id.raw }) else {
      throw TransportError.io("Storage \(id.raw) not found")
    }
    return storage.toStorageInfo()
  }

  public func getObjectHandles(storage: MTPStorageID, parent: MTPObjectHandle?) async throws
    -> [MTPObjectHandle]
  {
    try checkFault(.getObjectHandles)
    try await applyLatency(.getObjectHandles)
    return config.objects
      .filter { $0.storage.raw == storage.raw && $0.parent == parent }
      .map(\.handle)
  }

  public func getObjectInfos(_ handles: [MTPObjectHandle]) async throws -> [MTPObjectInfo] {
    try checkFault(.getObjectInfos)
    try await applyLatency(.getObjectInfos)
    let handleSet = Set(handles)
    return config.objects
      .filter { handleSet.contains($0.handle) }
      .map { $0.toObjectInfo() }
  }

  public func getObjectInfos(storage: MTPStorageID, parent: MTPObjectHandle?, format: UInt16?)
    async throws -> [MTPObjectInfo]
  {
    try checkFault(.getObjectInfos)
    try await applyLatency(.getObjectInfos)
    return config.objects
      .filter { obj in
        obj.storage.raw == storage.raw
          && obj.parent == parent
          && (format == nil || obj.formatCode == format)
      }
      .map { $0.toObjectInfo() }
  }

  public func resetDevice() async throws {
    // no-op for virtual link
  }

  public func deleteObject(handle: MTPObjectHandle) async throws {
    try checkFault(.deleteObject)
    guard config.objects.contains(where: { $0.handle == handle }) else {
      throw TransportError.io("Object \(handle) not found")
    }
  }

  public func moveObject(
    handle: MTPObjectHandle, to storage: MTPStorageID, parent: MTPObjectHandle?
  ) async throws {
    try checkFault(.moveObject)
    guard config.objects.contains(where: { $0.handle == handle }) else {
      throw TransportError.io("Object \(handle) not found")
    }
  }

  public func executeCommand(_ command: PTPContainer) async throws -> PTPResponseResult {
    try checkFault(.executeCommand)
    try await applyLatency(.executeCommand)
    return PTPResponseResult(code: 0x2001, txid: command.txid)
  }

  public func executeStreamingCommand(
    _ command: PTPContainer,
    dataPhaseLength: UInt64?,
    dataInHandler: MTPDataIn?,
    dataOutHandler: MTPDataOut?
  ) async throws -> PTPResponseResult {
    try checkFault(.executeStreamingCommand)
    try await applyLatency(.executeStreamingCommand)
    return PTPResponseResult(code: 0x2001, txid: command.txid)
  }

  public func getObjectPropValue(handle: MTPObjectHandle, property: UInt16) async throws -> Data {
    try checkFault(.executeCommand)
    guard let obj = config.objects.first(where: { $0.handle == handle }) else {
      throw TransportError.io("Object \(handle) not found")
    }
    switch property {
    case MTPObjectPropCode.objectFileName:
      return PTPString.encode(obj.name)
    case MTPObjectPropCode.objectSize:
      var enc = MTPDataEncoder()
      enc.append(UInt64(obj.sizeBytes ?? 0))
      return enc.encodedData
    case MTPObjectPropCode.storageID:
      var enc = MTPDataEncoder()
      enc.append(obj.storage.raw)
      return enc.encodedData
    case MTPObjectPropCode.parentObject:
      var enc = MTPDataEncoder()
      enc.append(obj.parent ?? 0xFFFFFFFF)
      return enc.encodedData
    case MTPObjectPropCode.dateModified, MTPObjectPropCode.dateCreated:
      return PTPString.encode("20250101T000000")
    default:
      throw MTPError.notSupported(
        "Property 0x\(String(property, radix: 16)) not supported by VirtualMTPLink")
    }
  }

  public func setObjectPropValue(handle: MTPObjectHandle, property: UInt16, value: Data)
    async throws
  {
    try checkFault(.executeCommand)
    guard config.objects.contains(where: { $0.handle == handle }) else {
      throw TransportError.io("Object \(handle) not found")
    }
    // VirtualMTPLink accepts all set-prop operations without persisting them
  }

  // MARK: - Private

  private func checkFault(_ operation: LinkOperationType) throws {
    let index = lock.withLock { () -> Int in
      let idx = callCount
      callCount += 1
      return idx
    }
    if let error = faultSchedule?.check(operation: operation, callIndex: index, byteOffset: nil) {
      throw error.transportError
    }
  }

  private func applyLatency(_ operation: LinkOperationType) async throws {
    if let duration = config.latencyPerOp[operation] {
      try await Task.sleep(for: duration)
    }
  }
}
