import Foundation
import SwiftMTPCore

extension MTPUSBLink {
  public func openSession(sessionID: UInt32, timeoutMs: Int = 10_000) throws {
    let cmd = PTPContainer(length: 16, type: PTPContainer.Kind.command.rawValue,
                           code: PTPOp.openSession.rawValue, txid: 1, params: [sessionID])
    var out = [UInt8](repeating: 0, count: 16)
    _ = out.withUnsafeMutableBufferPointer { buf in cmd.encode(into: buf.baseAddress!) }
    try out.withUnsafeBytes { raw in
      try bulkWriteAll(outEP, from: raw.baseAddress!, count: raw.count, timeout: UInt32(timeoutMs))
    }

    // Read response header (12 bytes) - no data phase for OpenSession
    var resp = [UInt8](repeating: 0, count: 12)
    try bulkReadExact(inEP, into: &resp, need: resp.count, timeout: UInt32(timeoutMs))

    // Check response code (should be 0x2001 for OK)
    let responseCode = resp.withUnsafeBytes {
        $0.load(fromByteOffset: 6, as: UInt16.self).littleEndian
    }
    guard responseCode == 0x2001 else {
        throw MTPError.protocolError(code: responseCode, message: "OpenSession failed")
    }
  }

  public func getDeviceInfo(timeoutMs: Int = 10_000) throws -> Data {
    let cmd = PTPContainer(length: 12, type: PTPContainer.Kind.command.rawValue,
                           code: PTPOp.getDeviceInfo.rawValue, txid: 1, params: [])
    var out = [UInt8](repeating: 0, count: 12)
    _ = out.withUnsafeMutableBufferPointer { buf in cmd.encode(into: buf.baseAddress!) }
    try out.withUnsafeBytes { raw in
      try bulkWriteAll(outEP, from: raw.baseAddress!, count: raw.count, timeout: UInt32(timeoutMs))
    }

    // Expect a DATA container back, then a RESPONSE
    var hdr = [UInt8](repeating: 0, count: 12)
    try bulkReadExact(inEP, into: &hdr, need: hdr.count, timeout: UInt32(timeoutMs))
    // Parse length for data payload
    let totalLen = hdr.withUnsafeBytes { $0.load(as: UInt32.self).littleEndian }
    let dataLen = Int(totalLen) - 12
    var payload = [UInt8](repeating: 0, count: max(0, dataLen))
    if dataLen > 0 {
      try bulkReadExact(inEP, into: &payload, need: dataLen, timeout: UInt32(timeoutMs))
    }

    // Read response header (12 bytes)
    var resp = [UInt8](repeating: 0, count: 12)
    try bulkReadExact(inEP, into: &resp, need: resp.count, timeout: UInt32(timeoutMs))
    return Data(payload)
  }
}
