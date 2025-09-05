// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation

// Sendable closure type aliases for MTP data transfer
public typealias MTPDataIn = @Sendable (UnsafeRawBufferPointer) -> Int
public typealias MTPDataOut = @Sendable (UnsafeMutableRawBufferPointer) -> Int

public struct PTPContainer: Sendable {
  public enum Kind: UInt16, Sendable { case command = 1, data = 2, response = 3, event = 4 }
  public var length: UInt32 = 12
  public var type: UInt16
  public var code: UInt16
  public var txid: UInt32
  public var params: [UInt32] = []

  public init(length: UInt32 = 12, type: UInt16, code: UInt16, txid: UInt32, params: [UInt32] = []) {
    self.length = length
    self.type = type
    self.code = code
    self.txid = txid
    self.params = params
  }

  public func encode(into buf: UnsafeMutablePointer<UInt8>) -> Int {
    var off = 0
    func put32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { m in m.copyBytes(to: UnsafeMutableRawBufferPointer(start: buf+off, count: 4)); off += 4 } }
    func put16(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { m in m.copyBytes(to: UnsafeMutableRawBufferPointer(start: buf+off, count: 2)); off += 2 } }
    put32(length); put16(type); put16(code); put32(txid)
    for p in params { put32(p) }
    return off
  }
}

public enum PTPOp: UInt16 {
    case getDeviceInfo = 0x1001
    case openSession = 0x1002
    case closeSession = 0x1003
    case getStorageIDs = 0x1004
    case getStorageInfo = 0x1005
    case getNumObjects = 0x1006
    case getObjectHandles = 0x1007
    case getObjectInfo = 0x1008
    case getObject = 0x1009
    case getThumb = 0x100A
    case deleteObject = 0x100B
    case sendObjectInfo = 0x100C
    case sendObject = 0x100D
    case moveObject = 0x100E  // MoveObject operation
    case getDevicePropDesc = 0x1014
    case getDevicePropValue = 0x1015
    case setDevicePropValue = 0x1016
    case resetDevicePropValue = 0x1017
    case getPartialObject = 0x101B
    // Optional (resume on capable devices):
    case getPartialObject64 = 0x95C4  // common Android vendor opcode
    case sendPartialObject = 0x95C1  // ditto
}
