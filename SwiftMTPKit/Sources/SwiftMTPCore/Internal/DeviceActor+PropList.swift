// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation

extension MTPDeviceActor {

  // MARK: - GetObjectPropList fast-path

  /// Fetch all object properties for the children of `parentHandle` in a single round-trip.
  ///
  /// When the device quirk `supportsGetObjectPropList` is `true`, sends opcode `0x9805`
  /// (GetObjectPropList) to retrieve all properties in one call. Otherwise falls back to
  /// per-handle `GetObjectInfo` calls.
  ///
  /// - Parameters:
  ///   - parentHandle: Parent directory handle whose children to enumerate.
  ///   - depth: Recursion depth (0 = immediate children only).
  /// - Returns: Array of `MTPObjectInfo` for all enumerated children.
  public func getObjectPropList(
    parentHandle: MTPObjectHandle, depth: UInt32 = 0
  ) async throws -> [MTPObjectInfo] {
    try await openIfNeeded()
    let link = try await getMTPLink()

    guard currentPolicy?.flags.supportsGetObjectPropList == true else {
      // Fallback: enumerate handles then fetch per-handle object info
      let handles = try await link.getObjectHandles(
        storage: MTPStorageID(raw: 0xFFFFFFFF), parent: parentHandle)
      guard !handles.isEmpty else { return [] }
      return try await link.getObjectInfos(handles)
    }

    // Fast path: GetObjectPropList (0x9805)
    // params: [parentHandle, 0 (all props), 0 (all formats), depth, 0]
    let buffer = LockedDataBuffer()
    do {
      let result = try await link.executeStreamingCommand(
        PTPContainer(
          type: PTPContainer.Kind.command.rawValue,
          code: MTPOp.getObjectPropList.rawValue,
          txid: 0,
          params: [parentHandle, 0x00000000, 0x00000000, depth, 0]
        ),
        dataPhaseLength: nil,
        dataInHandler: { raw in
          buffer.append(raw)
          return raw.count
        },
        dataOutHandler: nil
      )
      try result.checkOK()
      return try parsePropListDataset(buffer.snapshot())
    } catch MTPError.notSupported {
      // Device doesn't support GetObjectPropList despite heuristic — disable and fallback
      if currentPolicy != nil {
        currentPolicy!.flags.supportsGetObjectPropList = false
      }
      let handles = try await link.getObjectHandles(
        storage: MTPStorageID(raw: 0xFFFFFFFF), parent: parentHandle)
      guard !handles.isEmpty else { return [] }
      return try await link.getObjectInfos(handles)
    }
  }

  /// Parse a GetObjectPropList (0x9805) response dataset into `[MTPObjectInfo]`.
  ///
  /// Dataset layout: `UInt32` object-count, then repeated
  /// `(UInt32 handle, UInt16 propCode, UInt16 dataType, <value>)` tuples.
  nonisolated func parsePropListDataset(_ data: Data) throws -> [MTPObjectInfo] {
    var r = PTPReader(data: data)

    guard let rawCount = r.u32() else {
      throw MTPError.protocolError(
        code: 0x2006, message: "GetObjectPropList: missing object count")
    }
    try PTPReader.validateCount(rawCount)

    // Accumulate property values keyed by object handle
    struct Accum {
      var storageID: UInt32?
      var sizeBytes: UInt64?
      var name: String?
      var dateCreated: Date?
      var dateModified: Date?
      var parent: UInt32?
    }

    var accum: [MTPObjectHandle: Accum] = [:]
    accum.reserveCapacity(Int(min(rawCount, 1024)))

    for _ in 0..<rawCount {
      guard let handle = r.u32(), let propCode = r.u16(), let dataType = r.u16() else {
        break
      }
      guard let val = r.value(dt: dataType) else {
        break
      }

      var a = accum[handle] ?? Accum()
      switch propCode {
      case MTPObjectPropCode.storageID:
        if case .uint32(let v) = val { a.storageID = v }
      case MTPObjectPropCode.objectSize:
        switch val {
        case .uint64(let v): a.sizeBytes = v
        case .uint32(let v): a.sizeBytes = UInt64(v)
        default: break
        }
      case MTPObjectPropCode.objectFileName:
        if case .string(let s) = val, a.name == nil { a.name = s }
      case MTPObjectPropCode.name:
        if case .string(let s) = val, a.name == nil { a.name = s }
      case MTPObjectPropCode.dateCreated:
        if case .string(let s) = val { a.dateCreated = MTPDateString.decode(s) }
      case MTPObjectPropCode.dateModified:
        if case .string(let s) = val { a.dateModified = MTPDateString.decode(s) }
      case MTPObjectPropCode.parentObject:
        if case .uint32(let v) = val { a.parent = v }
      default:
        break
      }
      accum[handle] = a
    }

    return accum.map { handle, a in
      MTPObjectInfo(
        handle: handle,
        storage: MTPStorageID(raw: a.storageID ?? 0),
        parent: (a.parent == nil || a.parent == 0 || a.parent == 0xFFFFFFFF) ? nil : a.parent,
        name: a.name ?? "(unknown)",
        sizeBytes: a.sizeBytes,
        modified: a.dateModified,
        formatCode: 0x3000,  // UNDEFINED — not provided by GetObjectPropList
        properties: [:]
      )
    }
  }

  // MARK: - GetPartialObject resume read

  /// Resume a partial download using `GetPartialObject` (opcode `0x101B`).
  ///
  /// Requests `length` bytes starting at `offset` within the object identified by `handle`.
  /// Gate this behind the `supportsGetPartialObject` device quirk.
  ///
  /// - Parameters:
  ///   - handle: Object handle to read from.
  ///   - offset: Byte offset to start reading from.
  ///   - length: Number of bytes to read.
  /// - Returns: The partial data blob.
  @discardableResult
  public func resumeRead(
    handle: MTPObjectHandle, offset: UInt64, length: UInt64
  ) async throws -> Data {
    let link = try await getMTPLink()
    let buffer = LockedDataBuffer()
    let result = try await link.executeStreamingCommand(
      PTPContainer(
        type: PTPContainer.Kind.command.rawValue,
        code: PTPOp.getPartialObject.rawValue,
        txid: 0,
        params: [
          handle,
          UInt32(offset & 0xFFFF_FFFF),
          UInt32(offset >> 32),
          UInt32(min(length, UInt64(UInt32.max))),
        ]
      ),
      dataPhaseLength: nil,
      dataInHandler: { raw in
        buffer.append(raw)
        return raw.count
      },
      dataOutHandler: nil
    )
    try result.checkOK()
    return buffer.snapshot()
  }
}
