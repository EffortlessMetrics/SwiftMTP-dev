// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import MTPEndianCodec
import SwiftMTPCore

// MARK: - RecordedPacket

/// A single packet captured on the USB wire, used for deterministic replay in tests.
public struct RecordedPacket: Codable, Sendable {
  /// "in" = device → host (bulk-in); "out" = host → device (bulk-out).
  public let direction: String
  /// Raw MTP container bytes (12-byte header + payload).
  public let data: Data
  /// Approximate wall-clock timestamp in milliseconds (informational only).
  public let timestampMs: Double
  /// If non-nil, the link throws `TransportError.io` with this code instead of returning data.
  public let errorCode: Int?

  public init(direction: String, data: Data, timestampMs: Double, errorCode: Int? = nil) {
    self.direction = direction
    self.data = data
    self.timestampMs = timestampMs
    self.errorCode = errorCode
  }
}

// MARK: - RecordedMTPLink

/// An ``MTPLink`` that replays a pre-recorded sequence of ``RecordedPacket``s.
///
/// "in" packets are consumed as device responses; "out" packets are added to ``capturedWrites``.
/// This enables deterministic protocol regression testing without any real hardware.
///
/// ```swift
/// let packets = try JSONDecoder().decode([RecordedPacket].self, from: fixtureData)
/// let link = RecordedMTPLink(packets: packets)
/// let info = try await link.getDeviceInfo()
/// ```
public final class RecordedMTPLink: MTPLink, @unchecked Sendable {
  private let packets: [RecordedPacket]
  private var cursor: Int = 0
  private var _capturedWrites: [Data] = []
  private let lock = NSLock()

  /// Whether to throw when the replay queue is exhausted (default: false → returns empty data).
  public var exhaustedThrows: Bool = false

  public var cachedDeviceInfo: MTPDeviceInfo? { nil }

  public init(packets: [RecordedPacket]) {
    self.packets = packets
  }

  /// Bytes that were "written" to the device during replay (bulk-out packets).
  public var capturedWrites: [Data] {
    lock.withLock { _capturedWrites }
  }

  // MARK: - MTPLink Protocol

  public func openUSBIfNeeded() async throws {}

  public func openSession(id: UInt32) async throws {
    let response = try nextResponse()
    try checkResponseCode(response)
  }

  public func closeSession() async throws {
    let response = try nextResponse()
    try checkResponseCode(response)
  }

  public func close() async {}

  public func getDeviceInfo() async throws -> MTPDeviceInfo {
    let (dataPayload, responseCode) = try nextDataAndResponse()
    guard responseCode == 0x2001 else {
      throw MTPError.protocolError(code: responseCode, message: nil)
    }
    if let info = PTPDeviceInfo.parse(from: dataPayload) {
      return MTPDeviceInfo(
        manufacturer: info.manufacturer,
        model: info.model,
        version: info.deviceVersion,
        serialNumber: info.serialNumber,
        operationsSupported: Set(info.operationsSupported),
        eventsSupported: Set(info.eventsSupported)
      )
    }
    return MTPDeviceInfo(
      manufacturer: "Unknown", model: "Unknown", version: "0",
      serialNumber: nil, operationsSupported: [], eventsSupported: [])
  }

  public func getStorageIDs() async throws -> [MTPStorageID] {
    let (payload, responseCode) = try nextDataAndResponse()
    guard responseCode == 0x2001, payload.count >= 4 else { return [] }
    var dec = MTPDataDecoder(data: payload)
    guard let count = dec.readUInt32() else { return [] }
    return (0..<count).compactMap { _ in dec.readUInt32().map { MTPStorageID(raw: $0) } }
  }

  public func getStorageInfo(id: MTPStorageID) async throws -> MTPStorageInfo {
    let (_, responseCode) = try nextDataAndResponse()
    guard responseCode == 0x2001 else {
      throw MTPError.protocolError(code: responseCode, message: nil)
    }
    return MTPStorageInfo(
      id: id, description: "Recorded Storage",
      capacityBytes: 0, freeBytes: 0, isReadOnly: false)
  }

  public func getObjectHandles(storage: MTPStorageID, parent: MTPObjectHandle?) async throws
    -> [MTPObjectHandle]
  {
    let (payload, responseCode) = try nextDataAndResponse()
    guard responseCode == 0x2001, payload.count >= 4 else { return [] }
    var dec = MTPDataDecoder(data: payload)
    guard let count = dec.readUInt32() else { return [] }
    return (0..<count).compactMap { _ in dec.readUInt32().map { MTPObjectHandle($0) } }
  }

  public func getObjectInfos(_ handles: [MTPObjectHandle]) async throws -> [MTPObjectInfo] {
    throw MTPError.notSupported("RecordedMTPLink: getObjectInfos not supported in replay")
  }

  public func getObjectInfos(storage: MTPStorageID, parent: MTPObjectHandle?, format: UInt16?)
    async throws -> [MTPObjectInfo]
  {
    throw MTPError.notSupported("RecordedMTPLink: getObjectInfos not supported in replay")
  }

  public func resetDevice() async throws {
    throw MTPError.notSupported("RecordedMTPLink: resetDevice not supported in replay")
  }

  public func deleteObject(handle: MTPObjectHandle) async throws {
    throw MTPError.notSupported("RecordedMTPLink: deleteObject not supported in replay")
  }

  public func moveObject(handle: MTPObjectHandle, to storage: MTPStorageID, parent: MTPObjectHandle?)
    async throws
  {
    throw MTPError.notSupported("RecordedMTPLink: moveObject not supported in replay")
  }

  public func executeCommand(_ command: PTPContainer) async throws -> PTPResponseResult {
    let response = try nextResponse()
    let code = readLE16(from: response, at: 6) ?? 0x2001
    let txid = readLE32(from: response, at: 8) ?? command.txid
    return PTPResponseResult(code: code, txid: txid, params: [])
  }

  public func executeStreamingCommand(
    _ command: PTPContainer,
    dataPhaseLength: UInt64?,
    dataInHandler: MTPDataIn?,
    dataOutHandler: MTPDataOut?
  ) async throws -> PTPResponseResult {
    let (payload, responseCode) = try nextDataAndResponse()
    if let handler = dataInHandler, !payload.isEmpty {
      payload.withUnsafeBytes { _ = handler($0) }
    }
    return PTPResponseResult(code: responseCode, txid: command.txid, params: [])
  }

  // MARK: - Private helpers

  /// Advances the cursor past all "out" packets (capturing them) then returns the next "in" packet's raw bytes.
  private func nextResponse() throws -> Data {
    while true {
      let packet: RecordedPacket = try lock.withLock {
        if cursor >= packets.count {
          if exhaustedThrows {
            throw TransportError.io("RecordedMTPLink: replay queue exhausted")
          }
          return RecordedPacket(direction: "in", data: makeEmptyResponseOK(txid: 0), timestampMs: 0)
        }
        let p = packets[cursor]
        cursor += 1
        return p
      }
      if packet.direction == "out" {
        lock.withLock { _capturedWrites.append(packet.data) }
        continue
      }
      if let code = packet.errorCode {
        throw TransportError.io("Recorded error code: \(code)")
      }
      return packet.data
    }
  }

  /// Reads packets until a data "in" + response "in" pair is found.
  /// Returns (data phase payload bytes, response code).
  private func nextDataAndResponse() throws -> (Data, UInt16) {
    let first = try nextResponse()
    let firstType = readLE16(from: first, at: 4) ?? 0
    if firstType == 2 {
      // data container: payload is bytes after the 12-byte header
      let payload = first.count > 12 ? first.dropFirst(12) : Data()
      let responsePacket = try nextResponse()
      let code = readLE16(from: responsePacket, at: 6) ?? 0x2001
      return (Data(payload), code)
    } else {
      // no data phase; first packet is the response
      let code = readLE16(from: first, at: 6) ?? 0x2001
      return (Data(), code)
    }
  }

  private func checkResponseCode(_ data: Data) throws {
    let code = readLE16(from: data, at: 6) ?? 0x2001
    if code != 0x2001 {
      throw MTPError.protocolError(code: code, message: nil)
    }
  }

  private func makeEmptyResponseOK(txid: UInt32) -> Data {
    var d = Data(count: 12)
    d.withUnsafeMutableBytes { ptr in
      let p = ptr.baseAddress!
      var len: UInt32 = 12; memcpy(p, &len, 4)
      var t: UInt16 = 3; memcpy(p.advanced(by: 4), &t, 2)
      var c: UInt16 = 0x2001; memcpy(p.advanced(by: 6), &c, 2)
      var x: UInt32 = txid; memcpy(p.advanced(by: 8), &x, 4)
    }
    return d
  }

  private func readLE16(from data: Data, at offset: Int) -> UInt16? {
    guard offset + 1 < data.count else { return nil }
    return UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
  }

  private func readLE32(from data: Data, at offset: Int) -> UInt32? {
    guard offset + 3 < data.count else { return nil }
    return UInt32(data[offset])
      | (UInt32(data[offset + 1]) << 8)
      | (UInt32(data[offset + 2]) << 16)
      | (UInt32(data[offset + 3]) << 24)
  }
}
