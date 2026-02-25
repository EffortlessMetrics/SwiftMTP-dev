// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import CLibusb
import SwiftMTPCore

// MARK: - PTP Container Type Enum (using canonical types from SwiftMTPCore)

import SwiftMTPCore  // Ensure we have access to canonical PTPContainer.Kind

@inline(__always)
func readUnalignedLittleEndian<T: FixedWidthInteger>(
  from ptr: UnsafeRawPointer, offset: Int = 0, as: T.Type = T.self
) -> T {
  var value: T = 0
  memcpy(&value, ptr.advanced(by: offset), MemoryLayout<T>.size)
  return T(littleEndian: value)
}

// MARK: - PTP Header Structure

struct PTPHeader {
  static let size = 12  // 4 + 2 + 2 + 4
  var length: UInt32
  var type: UInt16
  var code: UInt16
  var txid: UInt32

  @inline(__always)
  func encode(into out: UnsafeMutableRawPointer) {
    var L = length.littleEndian
    var T = type.littleEndian
    var C = code.littleEndian
    var X = txid.littleEndian
    memcpy(out.advanced(by: 0), &L, 4)
    memcpy(out.advanced(by: 4), &T, 2)
    memcpy(out.advanced(by: 6), &C, 2)
    memcpy(out.advanced(by: 8), &X, 4)
  }

  @inline(__always)
  static func decode(from ptr: UnsafeRawPointer) -> PTPHeader {
    let L: UInt32 = readUnalignedLittleEndian(from: ptr, offset: 0)
    let T: UInt16 = readUnalignedLittleEndian(from: ptr, offset: 4)
    let C: UInt16 = readUnalignedLittleEndian(from: ptr, offset: 6)
    let X: UInt32 = readUnalignedLittleEndian(from: ptr, offset: 8)
    return PTPHeader(length: L, type: T, code: C, txid: X)
  }
}

// MARK: - PTP Response Structure

struct PTPResponse {
  let code: UInt16
  let txid: UInt32
  let params: [UInt32]
}

// MARK: - Container Encoding Functions

@inline(__always)
func makePTPCommand(opcode: UInt16, txid: UInt32, params: [UInt32]) -> [UInt8] {
  precondition(params.count <= 5, "PTP allows up to 5 params")
  let total = PTPHeader.size + params.count * 4
  var out = [UInt8](repeating: 0, count: total)
  let hdr = PTPHeader(
    length: UInt32(total), type: PTPContainer.Kind.command.rawValue,
    code: opcode, txid: txid)
  out.withUnsafeMutableBytes { hdr.encode(into: $0.baseAddress!) }
  var off = PTPHeader.size
  for p in params {
    var v = p.littleEndian
    _ = withUnsafeBytes(of: &v) { src in
      out.withUnsafeMutableBytes { dst in
        memcpy(dst.baseAddress!.advanced(by: off), src.baseAddress!, 4)
      }
    }
    off += 4
  }
  return out
}

@inline(__always)
func makePTPDataContainer(length: UInt32, code: UInt16, txid: UInt32) -> [UInt8] {
  var out = [UInt8](repeating: 0, count: PTPHeader.size)
  let hdr = PTPHeader(
    length: length, type: PTPContainer.Kind.data.rawValue,
    code: code, txid: txid)
  out.withUnsafeMutableBytes { hdr.encode(into: $0.baseAddress!) }
  return out
}

// MARK: - Error Mapping

@inline(__always)
func mapLibusb(_ rc: Int32) -> TransportError {
  switch rc {
  case Int32(LIBUSB_ERROR_TIMEOUT.rawValue): return .timeout
  case Int32(LIBUSB_ERROR_BUSY.rawValue): return .busy
  case Int32(LIBUSB_ERROR_ACCESS.rawValue): return .accessDenied
  case Int32(LIBUSB_ERROR_NO_DEVICE.rawValue): return .noDevice
  default: return .io("libusb rc=\(rc)")
  }
}

@inline(__always)
func check(_ rc: Int32) throws {
  if rc != 0 { throw MTPError.transport(mapLibusb(rc)) }
}
