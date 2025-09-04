// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import CLibusb
import SwiftMTPCore

// MARK: - PTP Container Type Enum (using canonical types from SwiftMTPCore)

import SwiftMTPCore  // Ensure we have access to canonical PTPContainer.Kind

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
        memcpy(out.advanced(by: 0),  &L, 4)
        memcpy(out.advanced(by: 4),  &T, 2)
        memcpy(out.advanced(by: 6),  &C, 2)
        memcpy(out.advanced(by: 8),  &X, 4)
    }

    @inline(__always)
    static func decode(from ptr: UnsafeRawPointer) -> PTPHeader {
        let L = ptr.load(as: UInt32.self).littleEndian
        let T = ptr.advanced(by: 4).load(as: UInt16.self).littleEndian
        let C = ptr.advanced(by: 6).load(as: UInt16.self).littleEndian
        let X = ptr.advanced(by: 8).load(as: UInt32.self).littleEndian
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
    let hdr = PTPHeader(length: UInt32(total), type: PTPContainer.Kind.command.rawValue,
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
    let hdr = PTPHeader(length: length, type: PTPContainer.Kind.data.rawValue,
                        code: code, txid: txid)
    out.withUnsafeMutableBytes { hdr.encode(into: $0.baseAddress!) }
    return out
}

// MARK: - Error Mapping

@inline(__always)
func mapLibusb(_ rc: Int32) -> TransportError {
    switch rc {
    case Int32(LIBUSB_ERROR_TIMEOUT.rawValue):      return .timeout
    case Int32(LIBUSB_ERROR_BUSY.rawValue):         return .busy
    case Int32(LIBUSB_ERROR_ACCESS.rawValue):       return .accessDenied
    case Int32(LIBUSB_ERROR_NO_DEVICE.rawValue):    return .noDevice
    default:                        return .io("libusb rc=\(rc)")
    }
}

@inline(__always)
func check(_ rc: Int32) throws {
    if rc != 0 { throw MTPError.transport(mapLibusb(rc)) }
}

// MARK: - Response Mapping

@inline(__always)
func mapResponse(_ r: PTPResponse) throws {
    guard r.code == 0x2001 /* OK */ else {
        switch r.code {
        case 0x2019: throw MTPError.busy
        case 0x2005: throw MTPError.notSupported("Operation not supported (0x2005)")
        case 0x2009: throw MTPError.objectNotFound
        case 0x200D: throw MTPError.storageFull
        case 0x200E: throw MTPError.readOnly
        case 0x2012: throw MTPError.timeout
        default:     throw MTPError.protocolError(code: r.code, message: "")
        }
    }
}
