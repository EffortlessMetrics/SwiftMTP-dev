// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import CLibusb
import Foundation
import OSLog
import SwiftMTPCore
import SwiftMTPObservability

private let log = MTPLog.transport

// MARK: - MTP Operations

extension MTPUSBLink {

  private var isPixel7PreflightTarget: Bool {
    vendorID == 0x18D1 && productID == 0x4EE1
  }

  /// Pre-OpenSession preflight for Pixel 7 devices.
  ///
  /// Resets interface alt-setting, clears endpoint HALT states, and optionally sends
  /// a PTP class reset (0x66) to ensure the device is in a clean state before the
  /// first OpenSession command. This compensates for macOS host controller quirks
  /// where endpoint pipes retain stale state across close/reopen cycles.
  ///
  /// 2000ms class reset timeout: sufficient for the lightweight control transfer;
  /// the device typically responds in <100ms but we allow headroom for busy devices.
  /// 200ms settle delay: allows the host controller to complete pipe reconfiguration
  /// after alt-setting change.
  private func runPixelPreOpenSessionPreflightIfNeeded() {
    guard isPixel7PreflightTarget, !didRunPixelPreOpenSessionPreflight else { return }
    didRunPixelPreOpenSessionPreflight = true

    let debug = ProcessInfo.processInfo.environment["SWIFTMTP_DEBUG"] == "1"
    setConfigurationIfNeeded(handle: h, device: dev, force: true, debug: debug)
    let setAltRC = libusb_set_interface_alt_setting(h, Int32(iface), 0)
    let clearOutRC = libusb_clear_halt(h, outEP)
    let clearInRC = libusb_clear_halt(h, inEP)
    let clearEventRC: Int32 =
      evtEP != 0 ? libusb_clear_halt(h, evtEP) : Int32(LIBUSB_SUCCESS.rawValue)
    let skipClassReset = skipPixelClassResetControlTransfer
    let classResetRC: Int32 =
      skipClassReset
      ? Int32(LIBUSB_SUCCESS.rawValue)
      : libusb_control_transfer(h, 0x21, 0x66, 0, UInt16(iface), nil, 0, 2000)
    usleep(200_000)

    if debug {
      print(
        String(
          format:
            "   [USB][Preflight][Pixel] setAlt0=%d clear(out=%d in=%d evt=%d) classReset=%d skipClassReset=%@ settleMs=200",
          setAltRC,
          clearOutRC,
          clearInRC,
          clearEventRC,
          classResetRC,
          skipClassReset ? "true" : "false"
        )
      )
    }
  }

  public func openSession(id: UInt32) async throws {
    runPixelPreOpenSessionPreflightIfNeeded()
    try await executeStreamingCommand(
      PTPContainer(type: 1, code: 0x1002, txid: 0, params: [id]), dataPhaseLength: nil,
      dataInHandler: nil, dataOutHandler: nil
    )
    .checkOK()
    nextTx = 1
  }

  public func closeSession() async throws {
    try await executeStreamingCommand(
      PTPContainer(type: 1, code: 0x1003, txid: 0, params: []), dataPhaseLength: nil,
      dataInHandler: nil, dataOutHandler: nil
    )
    .checkOK()
    nextTx = 0
  }

  public func getDeviceInfo() async throws -> MTPDeviceInfo {
    // Use cached probe data if available (avoids redundant USB round-trip)
    if let cached = cachedDeviceInfoData, let info = PTPDeviceInfo.parse(from: cached) {
      return MTPDeviceInfo(
        manufacturer: info.manufacturer, model: info.model, version: info.deviceVersion,
        serialNumber: info.serialNumber, operationsSupported: Set(info.operationsSupported),
        eventsSupported: Set(info.eventsSupported))
    }
    let collector = SimpleCollector()
    let res = try await executeStreamingCommand(
      PTPContainer(type: 1, code: 0x1001, txid: 0, params: []), dataPhaseLength: nil,
      dataInHandler: {
        collector.append($0)
        return $0.count
      }, dataOutHandler: nil)
    if res.isOK, let info = PTPDeviceInfo.parse(from: collector.data) {
      return MTPDeviceInfo(
        manufacturer: info.manufacturer, model: info.model, version: info.deviceVersion,
        serialNumber: info.serialNumber, operationsSupported: Set(info.operationsSupported),
        eventsSupported: Set(info.eventsSupported))
    }
    return MTPDeviceInfo(
      manufacturer: manufacturer, model: model, version: "1.0", serialNumber: "Unknown",
      operationsSupported: [], eventsSupported: [])
  }

  public func getStorageIDs() async throws -> [MTPStorageID] {
    let collector = SimpleCollector()
    let res = try await executeStreamingCommand(
      PTPContainer(type: 1, code: 0x1004, txid: 0, params: []), dataPhaseLength: nil,
      dataInHandler: {
        collector.append($0)
        return $0.count
      }, dataOutHandler: nil)
    if !res.isOK || collector.data.count < 4 { return [] }
    var reader = PTPReader(data: collector.data)
    guard let count = reader.u32() else { return [] }
    let payloadCount = (collector.data.count - 4) / 4
    let total = min(Int(count), payloadCount)
    var ids = [MTPStorageID]()
    ids.reserveCapacity(total)
    for _ in 0..<total {
      guard let raw = reader.u32() else { break }
      ids.append(MTPStorageID(raw: raw))
    }
    return ids
  }

  public func getStorageInfo(id: MTPStorageID) async throws -> MTPStorageInfo {
    let collector = SimpleCollector()
    let res = try await executeStreamingCommand(
      PTPContainer(type: 1, code: 0x1005, txid: 0, params: [id.raw]), dataPhaseLength: nil,
      dataInHandler: {
        collector.append($0)
        return $0.count
      }, dataOutHandler: nil)
    try res.checkOK()
    var r = PTPReader(data: collector.data)
    _ = r.u16()
    _ = r.u16()
    let cap = r.u16(), max = r.u64(), free = r.u64()
    _ = r.u32()
    let desc = r.string() ?? ""
    return MTPStorageInfo(
      id: id, description: desc, capacityBytes: max ?? 0, freeBytes: free ?? 0,
      isReadOnly: cap == 0x0001)
  }

  public func getObjectHandles(storage: MTPStorageID, parent: MTPObjectHandle?) async throws
    -> [MTPObjectHandle]
  {
    let collector = SimpleCollector()
    let res = try await executeStreamingCommand(
      PTPContainer(type: 1, code: 0x1007, txid: 0, params: [storage.raw, 0, parent ?? 0x00000000]),
      dataPhaseLength: nil,
      dataInHandler: {
        collector.append($0)
        return $0.count
      }, dataOutHandler: nil)
    try res.checkOK()
    if collector.data.count < 4 { return [] }
    var reader = PTPReader(data: collector.data)
    guard let count = reader.u32() else { return [] }
    let payloadCount = (collector.data.count - 4) / 4
    let total = min(Int(count), payloadCount)
    var handles = [MTPObjectHandle]()
    handles.reserveCapacity(total)
    for _ in 0..<total {
      guard let raw = reader.u32() else { break }
      handles.append(raw)
    }
    return handles
  }

  public func getObjectInfos(_ handles: [MTPObjectHandle]) async throws -> [MTPObjectInfo] {
    var out = [MTPObjectInfo]()
    for h in handles {
      let collector = SimpleCollector()
      let res = try await executeStreamingCommand(
        PTPContainer(type: 1, code: 0x1008, txid: 0, params: [h]), dataPhaseLength: nil,
        dataInHandler: {
          collector.append($0)
          return $0.count
        }, dataOutHandler: nil)
      if !res.isOK { continue }
      let responseData = collector.data
      var r = PTPReader(data: responseData)
      guard let sid = r.u32(), let fmt = r.u16() else {
        continue
      }
      _ = r.u16()  // ProtectionStatus
      let size = r.u32()
      _ = r.u16()  // ThumbFormat
      _ = r.u32()  // ThumbCompressedSize
      _ = r.u32()  // ThumbPixWidth
      _ = r.u32()  // ThumbPixHeight
      _ = r.u32()  // ImagePixWidth
      _ = r.u32()  // ImagePixHeight
      _ = r.u32()  // ImageBitDepth
      let par = r.u32()
      _ = r.u16()  // AssociationType
      _ = r.u32()  // AssociationDesc
      _ = r.u32()  // SequenceNumber
      let name = r.string() ?? "Unknown"
      out.append(
        MTPObjectInfo(
          handle: h, storage: MTPStorageID(raw: sid), parent: par == 0 ? nil : par, name: name,
          sizeBytes: (size == nil || size == 0xFFFFFFFF) ? nil : UInt64(size!),
          modified: nil as Date?, formatCode: fmt, properties: [:]))
    }
    return out
  }

  public func getObjectInfos(storage: MTPStorageID, parent: MTPObjectHandle?, format: UInt16?)
    async throws -> [MTPObjectInfo]
  {
    let parentHandle = parent ?? 0x00000000, formatCode = format ?? 0x00000000

    func tryPropList(params: [UInt32]) async throws -> [MTPObjectInfo]? {
      let collector = SimpleCollector()
      let res = try await executeStreamingCommand(
        PTPContainer(type: 1, code: 0x9805, txid: 0, params: params), dataPhaseLength: nil,
        dataInHandler: {
          collector.append($0)
          return $0.count
        }, dataOutHandler: nil)
      if !res.isOK { return nil }
      guard let pl = PTPPropList.parse(from: collector.data) else { return nil }
      var grouped = [UInt32: [UInt16: PTPValue]]()
      for e in pl.entries {
        if grouped[e.handle] == nil { grouped[e.handle] = [:] }
        if let v = e.value { grouped[e.handle]![e.propertyCode] = v }
      }
      return grouped.map { h, p in
        var name = "Unknown"
        if case .string(let s) = p[0xDC07] { name = s }
        var size: UInt64? = nil
        if let v = p[0xDC04] {
          if case .uint64(let u) = v {
            size = u
          } else if case .uint32(let u) = v {
            size = UInt64(u)
          }
        }
        var fmt: UInt16 = 0
        if case .uint16(let u) = p[0xDC02] { fmt = u }
        var par: UInt32? = nil
        if case .uint32(let u) = p[0xDC0B] { par = u }
        return MTPObjectInfo(
          handle: h, storage: storage, parent: par == 0 ? nil : par, name: name, sizeBytes: size,
          modified: nil, formatCode: fmt, properties: [:])
      }
    }

    if MTPFeatureFlags.shared.isEnabled(.propListFastPath) {
      if let res = try? await tryPropList(params: [
        parentHandle, 0xFFFFFFFF, UInt32(formatCode), storage.raw, 1,
      ]) {
        return res
      }
      if let res = try? await tryPropList(params: [parentHandle, 0x00000000, UInt32(formatCode)]) {
        return res
      }
    }

    let handles = try await getObjectHandles(storage: storage, parent: parent)
    return try await getObjectInfos(handles)
  }

  public func deleteObject(handle: MTPObjectHandle) async throws {
    try await executeStreamingCommand(
      PTPContainer(type: 1, code: 0x100B, txid: 0, params: [handle, 0]), dataPhaseLength: nil,
      dataInHandler: nil, dataOutHandler: nil
    )
    .checkOK()
  }

  public func moveObject(
    handle: MTPObjectHandle, to storage: MTPStorageID, parent: MTPObjectHandle?
  ) async throws {
    try await executeStreamingCommand(
      PTPContainer(
        type: 1, code: 0x100E, txid: 0, params: [handle, storage.raw, parent ?? 0xFFFFFFFF]),
      dataPhaseLength: nil, dataInHandler: nil, dataOutHandler: nil
    )
    .checkOK()
  }

  public func copyObject(
    handle: MTPObjectHandle, toStorage storage: MTPStorageID, parent: MTPObjectHandle?
  ) async throws -> MTPObjectHandle {
    let result = try await executeStreamingCommand(
      PTPContainer(
        type: 1, code: PTPOp.copyObject.rawValue, txid: 0,
        params: [handle, storage.raw, parent ?? 0xFFFFFFFF]),
      dataPhaseLength: nil, dataInHandler: nil, dataOutHandler: nil
    )
    try result.checkOK()
    return result.params.first ?? 0
  }
}
