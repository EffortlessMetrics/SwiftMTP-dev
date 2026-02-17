// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation

enum TransferMode { case whole, partial }

final class BoxedOffset: @unchecked Sendable {
  var value: Int = 0
  private let lock = NSLock()
  func getAndAdd(_ n: Int) -> Int {
    lock.lock()
    defer { lock.unlock() }
    let old = value
    value += n
    return old
  }
  func get() -> Int {
    lock.lock()
    defer { lock.unlock() }
    return value
  }
}

public enum ProtoTransfer {
  /// Whole-object read: GetObject, stream data-in into a sink.
  public static func readWholeObject(
    handle: UInt32, on link: MTPLink,
    dataHandler: @escaping MTPDataIn,
    ioTimeoutMs: Int
  ) async throws {
    let command = PTPContainer(
      length: 16,
      type: PTPContainer.Kind.command.rawValue,
      code: PTPOp.getObject.rawValue,
      txid: 1,
      params: [handle]
    )
    try await link.executeStreamingCommand(
      command, dataPhaseLength: nil, dataInHandler: dataHandler, dataOutHandler: nil
    )
    .checkOK()
  }

  /// Whole-object write: SendObjectInfo → SendObject (single pass).
  public static func writeWholeObject(
    storageID: UInt32, parent: UInt32?, name: String, size: UInt64,
    dataHandler: @escaping MTPDataOut,
    on link: MTPLink,
    ioTimeoutMs: Int,
    useEmptyDates: Bool = false,
    useUndefinedObjectFormat: Bool = false,
    useUnknownObjectInfoSize: Bool = false,
    omitOptionalObjectInfoFields: Bool = false,
    zeroObjectInfoParentHandle: Bool = false
  ) async throws {
    // PTP Spec: SendObjectInfo command parameters are [StorageID, ParentHandle]
    // Use a concrete storage ID; wildcard storage (0xFFFFFFFF) triggers
    // InvalidStorageID (0x2008) on multiple Android stacks.
    let parentParam = parent ?? 0xFFFFFFFF
    guard storageID != 0 && storageID != 0xFFFFFFFF else {
      throw MTPError.preconditionFailed(
        "SendObjectInfo requires a concrete storage ID (got \(String(format: "0x%08x", storageID))).")
    }
    let targetStorage = storageID
    let formatCode = useUndefinedObjectFormat ? 0x3000 : PTPObjectFormat.forFilename(name)
    let objectInfoParentHandle = zeroObjectInfoParentHandle ? UInt32(0) : parentParam

    let sendObjectInfoCommand = PTPContainer(
      length: 20,  // 12 + 2 * 4
      type: PTPContainer.Kind.command.rawValue,
      code: PTPOp.sendObjectInfo.rawValue,
      txid: 0,
      params: [targetStorage, parentParam]
    )

    let dataset = PTPObjectInfoDataset.encode(
      storageID: targetStorage, parentHandle: parentParam, format: formatCode, size: size,
      name: name, useEmptyDates: useEmptyDates,
      objectCompressedSizeOverride: useUnknownObjectInfoSize ? 0xFFFFFFFF : nil,
      omitOptionalStringFields: omitOptionalObjectInfoFields,
      objectInfoParentHandleOverride: objectInfoParentHandle
    )

    if ProcessInfo.processInfo.environment["SWIFTMTP_DEBUG"] == "1" {
      print(
        "   [USB] SendObjectInfo: storage=\(String(format: "0x%08x", targetStorage)) parent=\(String(format: "0x%08x", parentParam)) format=\(String(format: "0x%04x", formatCode)) size=\(size) name=\(name)"
      )
      let formatSource = useUndefinedObjectFormat ? "forced-undefined" : "filename"
      print(
        "   [USB] SendObjectInfo fields: emptyDates=\(useEmptyDates) unknownSize=\(useUnknownObjectInfoSize) formatSource=\(formatSource) omitOptionalObjectInfoFields=\(omitOptionalObjectInfoFields) zeroObjectInfoParentHandle=\(zeroObjectInfoParentHandle) nameUTF16Units=\(name.utf16.count)"
      )
      print("   [USB] SendObjectInfo dataset length: \(dataset.count) bytes")
      let hex = dataset.map { String(format: "%02x", $0) }.joined(separator: " ")
      print("   [USB] Dataset hex: \(hex.prefix(128))\(dataset.count > 64 ? "..." : "")")
    }

    let infoOffset = BoxedOffset()
    let infoRes = try await link.executeStreamingCommand(
      sendObjectInfoCommand, dataPhaseLength: UInt64(dataset.count), dataInHandler: nil,
      dataOutHandler: { buf in
        let off = infoOffset.get()
        let remaining = dataset.count - off
        guard remaining > 0 else { return 0 }
        let toCopy = min(buf.count, remaining)
        dataset.copyBytes(to: buf, from: off..<off + toCopy)
        _ = infoOffset.getAndAdd(toCopy)
        return toCopy
      })
    try infoRes.checkOK()

    try await Task.sleep(nanoseconds: 100_000_000)

    let sendObjectCommand = PTPContainer(
      length: 12,
      type: PTPContainer.Kind.command.rawValue,
      code: PTPOp.sendObject.rawValue,
      txid: 0,
      params: []
    )
    try await link.executeStreamingCommand(
      sendObjectCommand, dataPhaseLength: size, dataInHandler: nil, dataOutHandler: dataHandler
    )
    .checkOK()
  }
}

// MARK: - Folder Creation

extension ProtoTransfer {
  /// Create a folder on the device using SendObjectInfo + zero-length SendObject.
  ///
  /// - Parameters:
  ///   - storageID: Target storage ID
  ///   - parent: Parent handle (0xFFFFFFFF for root)
  ///   - name: Folder name
  ///   - link: MTP link
  /// - Returns: The handle of the newly created folder
  public static func createFolder(
    storageID: UInt32, parent: UInt32, name: String,
    on link: MTPLink, ioTimeoutMs: Int
  ) async throws -> MTPObjectHandle {
    guard storageID != 0 && storageID != 0xFFFFFFFF else {
      throw MTPError.preconditionFailed(
        "SendObjectInfo requires a concrete storage ID (got \(String(format: "0x%08x", storageID))).")
    }

    // Build ObjectInfoDataset for an Association (folder)
    // format=0x3001 (Association), associationType=0x0001 (GenericFolder), size=0
    let dataset = PTPObjectInfoDataset.encode(
      storageID: storageID, parentHandle: parent,
      format: 0x3001, size: 0, name: name,
      associationType: 0x0001, associationDesc: 0
    )

    if ProcessInfo.processInfo.environment["SWIFTMTP_DEBUG"] == "1" {
      print(
        "   [USB] SendObjectInfo: storage=\(String(format: "0x%08x", storageID)) parent=\(String(format: "0x%08x", parent)) format=0x3001 size=0 name=\(name)"
      )
      print("   [USB] SendObjectInfo dataset length: \(dataset.count) bytes")
    }

    let sendObjectInfoCommand = PTPContainer(
      length: 20,
      type: PTPContainer.Kind.command.rawValue,
      code: PTPOp.sendObjectInfo.rawValue,
      txid: 0,
      params: [storageID, parent]
    )

    let infoOffset = BoxedOffset()
    let infoRes = try await link.executeStreamingCommand(
      sendObjectInfoCommand,
      dataPhaseLength: UInt64(dataset.count),
      dataInHandler: nil,
      dataOutHandler: { buf in
        let off = infoOffset.get()
        let remaining = dataset.count - off
        guard remaining > 0 else { return 0 }
        let toCopy = min(buf.count, remaining)
        dataset.copyBytes(to: buf, from: off..<off + toCopy)
        _ = infoOffset.getAndAdd(toCopy)
        return toCopy
      }
    )
    try infoRes.checkOK()

    // Extract new handle from response params[2] (storage, parent, handle)
    let newHandle: MTPObjectHandle
    if infoRes.params.count >= 3 {
      newHandle = infoRes.params[2]
    } else {
      newHandle = infoRes.params.last ?? 0
    }

    // PTP spec requires a zero-length SendObject after SendObjectInfo
    let sendObjectCommand = PTPContainer(
      length: 12,
      type: PTPContainer.Kind.command.rawValue,
      code: PTPOp.sendObject.rawValue,
      txid: 0,
      params: []
    )
    try await link.executeStreamingCommand(
      sendObjectCommand, dataPhaseLength: 0,
      dataInHandler: nil, dataOutHandler: { _ in 0 }
    )
    .checkOK()

    return newHandle
  }
}

// MARK: - Partial Read/Write

extension ProtoTransfer {

  /// GetPartialObject64 (0x95C4): 64-bit offset partial read.
  public static func readPartialObject64(
    handle: UInt32, offset: UInt64, maxBytes: UInt32,
    on link: MTPLink, dataHandler: @escaping MTPDataIn
  ) async throws {
    let offsetLo = UInt32(offset & 0xFFFFFFFF)
    let offsetHi = UInt32(offset >> 32)
    let command = PTPContainer(
      type: PTPContainer.Kind.command.rawValue,
      code: PTPOp.getPartialObject64.rawValue,
      txid: 0,
      params: [handle, offsetLo, offsetHi, maxBytes]
    )
    try await link.executeStreamingCommand(
      command, dataPhaseLength: nil,
      dataInHandler: dataHandler, dataOutHandler: nil
    )
    .checkOK()
  }

  /// GetPartialObject (0x101B): 32-bit offset partial read.
  public static func readPartialObject32(
    handle: UInt32, offset: UInt32, maxBytes: UInt32,
    on link: MTPLink, dataHandler: @escaping MTPDataIn
  ) async throws {
    let command = PTPContainer(
      type: PTPContainer.Kind.command.rawValue,
      code: PTPOp.getPartialObject.rawValue,
      txid: 0,
      params: [handle, offset, maxBytes]
    )
    try await link.executeStreamingCommand(
      command, dataPhaseLength: nil,
      dataInHandler: dataHandler, dataOutHandler: nil
    )
    .checkOK()
  }
}

extension PTPResponseResult {
  public func checkOK() throws {
    if isOK { return }
    switch code {
    case 0x2005:
      throw MTPError.notSupported("Operation not supported (\(PTPResponseCode.describe(code)))")
    case 0x2009:
      throw MTPError.objectNotFound
    case 0x200C:
      throw MTPError.storageFull
    case 0x200D:
      throw MTPError.objectWriteProtected
    case 0x200E:
      throw MTPError.readOnly
    case 0x200F:
      throw MTPError.permissionDenied
    case 0x2019:
      throw MTPError.busy
    default:
      throw MTPError.protocolError(code: code, message: PTPResponseCode.describe(code))
    }
  }
}

private extension UInt64 {
  func clampedToIntMax() -> UInt64 { Swift.min(self, UInt64(Int.max)) }
}
