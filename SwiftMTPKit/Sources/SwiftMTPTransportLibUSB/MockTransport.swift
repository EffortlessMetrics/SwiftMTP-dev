// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import MTPEndianCodec
import SwiftMTPCore

/// Mock transport that simulates libusb operations without physical hardware
public final class MockTransport: @unchecked Sendable, MTPTransport {
  private let deviceData: MockDeviceData
  private var isConnected = false

  public init(deviceData: MockDeviceData) {
    self.deviceData = deviceData
  }

  public func open(_ summary: MTPDeviceSummary, config: SwiftMTPConfig) async throws -> MTPLink {
    try await Task.sleep(nanoseconds: 100_000_000)
    guard summary.id.raw == deviceData.deviceSummary.id.raw else {
      throw MTPError.notSupported("Mock device ID mismatch")
    }
    if let failureMode = deviceData.failureMode {
      switch failureMode {
      case .timeout: throw TransportError.timeout
      case .busy: throw TransportError.busy
      case .accessDenied: throw TransportError.accessDenied
      case .deviceDisconnected: throw MTPError.deviceDisconnected
      case .protocolError: throw MTPError.protocolError(code: 0, message: "Mock protocol error")
      }
    }
    isConnected = true
    return MockMTPLink(deviceData: deviceData, transport: self)
  }

  public func close() async throws {
    isConnected = false
  }
}

/// Mock MTP link that simulates USB bulk transfers
public final class MockMTPLink: @unchecked Sendable, MTPLink {
  private let deviceData: MockDeviceData
  private weak var transport: MockTransport?
  private var sessionID: UInt32?
  private var eventContinuation: AsyncStream<Data>.Continuation?
  public let eventStream: AsyncStream<Data>

  init(deviceData: MockDeviceData, transport: MockTransport) {
    self.deviceData = deviceData
    self.transport = transport
    var cont: AsyncStream<Data>.Continuation!
    self.eventStream = AsyncStream(Data.self, bufferingPolicy: .bufferingNewest(16)) { cont = $0 }
    self.eventContinuation = cont
  }

  public func close() async {
    eventContinuation?.finish()
    transport = nil
  }

  public func startEventPump() {}

  /// Internal helper to simulate an MTP event
  public func simulateEvent(_ data: Data) {
    eventContinuation?.yield(data)
  }

  public func resetDevice() async throws {}
  public func openUSBIfNeeded() async throws {}
  public func openSession(id: UInt32) async throws { sessionID = id }
  public func closeSession() async throws { sessionID = nil }

  public func getDeviceInfo() async throws -> MTPDeviceInfo {
    return MTPDeviceInfo(
      manufacturer: deviceData.deviceSummary.manufacturer, model: deviceData.deviceSummary.model,
      version: "Mock 1.0", serialNumber: "MOCK123", operationsSupported: Set(),
      eventsSupported: Set())
  }

  public func getStorageIDs() async throws -> [MTPStorageID] {
    return deviceData.storages.map { $0.id }
  }

  public func getStorageInfo(id: MTPStorageID) async throws -> MTPStorageInfo {
    guard let storage = deviceData.storages.first(where: { $0.id == id }) else {
      throw MTPError.objectNotFound
    }
    return storage
  }

  public func getObjectHandles(storage: MTPStorageID, parent: MTPObjectHandle?) async throws
    -> [MTPObjectHandle]
  {
    return deviceData.objects.filter { $0.storage == storage && $0.parent == parent }
      .map { $0.handle }
  }

  public func getObjectInfos(_ handles: [MTPObjectHandle]) async throws -> [MTPObjectInfo] {
    return handles.compactMap { h in
      deviceData.objects.first { $0.handle == h }
        .map {
          MTPObjectInfo(
            handle: $0.handle, storage: $0.storage, parent: $0.parent, name: $0.name,
            sizeBytes: $0.size, modified: nil, formatCode: $0.formatCode, properties: [:])
        }
    }
  }

  public func getObjectInfos(storage: MTPStorageID, parent: MTPObjectHandle?, format: UInt16?)
    async throws -> [MTPObjectInfo]
  {
    let handles = try await getObjectHandles(storage: storage, parent: parent)
    return try await getObjectInfos(handles)
  }

  public func deleteObject(handle: MTPObjectHandle) async throws {
    try await Task.sleep(nanoseconds: 10_000_000)
  }

  public func moveObject(
    handle: MTPObjectHandle, to storage: MTPStorageID, parent: MTPObjectHandle?
  ) async throws {
    try await Task.sleep(nanoseconds: 10_000_000)
  }

  public func executeCommand(_ command: PTPContainer) async throws -> PTPResponseResult {
    return try await executeStreamingCommand(
      command, dataPhaseLength: nil, dataInHandler: nil, dataOutHandler: nil)
  }

  public func executeStreamingCommand(
    _ command: PTPContainer, dataPhaseLength: UInt64?, dataInHandler: MTPDataIn?,
    dataOutHandler: MTPDataOut?
  ) async throws -> PTPResponseResult {
    switch command.code {
    case 0x1001:  // GetDeviceInfo
      let info = handleGetDeviceInfo()
      _ = dataInHandler?(info.withUnsafeBytes { $0 })
      return PTPResponseResult(code: 0x2001, txid: command.txid)
    case 0x1002:  // OpenSession
      sessionID = command.params.first
      return PTPResponseResult(code: 0x2001, txid: command.txid)
    case 0x1004:  // GetStorageIDs
      var enc = MTPDataEncoder()
      let ids = deviceData.storages.map { $0.id.raw }
      enc.append(UInt32(ids.count))
      for id in ids { enc.append(id) }
      _ = dataInHandler?(enc.encodedData.withUnsafeBytes { $0 })
      return PTPResponseResult(code: 0x2001, txid: command.txid)
    case 0x1005:  // GetStorageInfo
      let id = MTPStorageID(raw: command.params.first ?? 0)
      guard let s = deviceData.storages.first(where: { $0.id == id }) else {
        return PTPResponseResult(code: 0x2009, txid: command.txid)
      }
      var enc = MTPDataEncoder()
      enc.append(UInt16(0x0003))
      enc.append(UInt16(0x0002))
      enc.append(UInt16(s.isReadOnly ? 0x0001 : 0x0000))
      enc.append(s.capacityBytes)
      enc.append(s.freeBytes)
      enc.append(UInt32(0xFFFFFFFF))
      enc.append(PTPString.encode(s.description))
      enc.append(PTPString.encode("Mock"))
      _ = dataInHandler?(enc.encodedData.withUnsafeBytes { $0 })
      return PTPResponseResult(code: 0x2001, txid: command.txid)
    case 0x100C:  // SendObjectInfo
      let newHandle: UInt32 = 0x00010001
      return PTPResponseResult(code: 0x2001, txid: command.txid, params: [newHandle])
    case 0x100D:  // SendObject
      if let out = dataOutHandler {
        var buf = [UInt8](repeating: 0, count: 8192)
        while true {
          let n = buf.withUnsafeMutableBytes { out($0) }
          if n == 0 { break }
        }
      }
      return PTPResponseResult(code: 0x2001, txid: command.txid)
    default:
      return PTPResponseResult(code: 0x2005, txid: command.txid)
    }
  }

  private func handleGetDeviceInfo() -> Data {
    var enc = MTPDataEncoder()
    enc.append(UInt16(100))
    enc.append(UInt32(0x00000006))
    enc.append(UInt16(100))
    enc.append(PTPString.encode("Mock Vendor"))
    enc.append(UInt16(0))
    enc.append(UInt32(0))
    enc.append(UInt32(0))
    enc.append(UInt32(0))
    enc.append(UInt32(0))
    enc.append(UInt32(0))
    enc.append(PTPString.encode(deviceData.deviceInfo.manufacturer))
    enc.append(PTPString.encode(deviceData.deviceInfo.model))
    enc.append(PTPString.encode(deviceData.deviceInfo.version))
    enc.append(PTPString.encode(deviceData.deviceInfo.serialNumber ?? ""))
    return enc.encodedData
  }
}
