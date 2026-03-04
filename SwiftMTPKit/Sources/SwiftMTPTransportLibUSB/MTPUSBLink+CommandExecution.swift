// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import CLibusb
import Foundation
import OSLog
import SwiftMTPCore
import SwiftMTPObservability

private let log = MTPLog.transport

// MARK: - MTP Command Execution

extension MTPUSBLink {

  func executeCommandAsync(
    command: PTPContainer, dataPhaseLength: UInt64? = nil, dataInHandler: MTPDataIn?,
    dataOutHandler: MTPDataOut?
  ) async throws -> PTPResponseResult {
    let signposter = MTPLog.Signpost.enumerateSignposter
    let state = signposter.beginInterval(
      "executeCommand", id: signposter.makeSignpostID(), "\(String(format: "0x%04x", command.code))"
    )
    defer { signposter.endInterval("executeCommand", state) }

    // MTP 1.1 §9.3.1: OpenSession and pre-session commands use txid 0.
    // Valid transaction IDs are 1…0xFFFFFFFE; 0xFFFFFFFF is reserved.
    let txid: UInt32
    if command.code == 0x1002 || nextTx == 0 {
      txid = 0
    } else {
      txid = nextTx
      nextTx = (nextTx >= 0xFFFFFFFE) ? 1 : nextTx + 1
    }
    let debug = ProcessInfo.processInfo.environment["SWIFTMTP_DEBUG"] == "1"
    if debug { print(String(format: "   [USB] op=0x%04x tx=%u phase=COMMAND", command.code, txid)) }
    let cmdBytes = makePTPCommand(opcode: command.code, txid: txid, params: command.params)
    try writeCommandContainerWithRecovery(
      cmdBytes, opcode: command.code, txid: txid, timeout: UInt32(config.ioTimeoutMs), debug: debug)

    if let produce = dataOutHandler {
      if debug {
        print(String(format: "   [USB] op=0x%04x tx=%u phase=DATA-OUT", command.code, txid))
      }
      let len = dataPhaseLength ?? 0
      let hdr = makePTPDataContainer(
        length: UInt32(PTPHeader.size + Int(min(len, UInt64(UInt32.max - 12)))), code: command.code,
        txid: txid)
      try hdr.withUnsafeBytes {
        try bulkWriteAll(
          outEP, from: $0.baseAddress!, count: $0.count, timeout: UInt32(config.ioTimeoutMs))
      }
      var sent = 0, scratch = [UInt8](repeating: 0, count: 64 * 1024)
      while true {
        let wrote = scratch.withUnsafeMutableBytes { produce($0) }
        if wrote == 0 { break }
        let chunkState = MTPLog.Signpost.chunkSignposter.beginInterval(
          "writeChunk", id: MTPLog.Signpost.chunkSignposter.makeSignpostID(), "\(wrote) bytes")
        try scratch.withUnsafeBytes {
          try bulkWriteAll(
            outEP, from: $0.baseAddress!, count: wrote, timeout: UInt32(config.ioTimeoutMs))
        }
        MTPLog.Signpost.chunkSignposter.endInterval("writeChunk", chunkState)
        sent += wrote
      }
      if sent % 512 == 0 && !config.noZeroReads {
        // USB bulk transfers require a zero-length packet (ZLP) to signal end of
        // transfer when the payload is an exact multiple of the max packet size (512
        // bytes for Hi-Speed). Without this, the device may wait indefinitely for
        // more data. 100ms timeout is ample for a zero-byte transfer.
        // noZeroReads: some devices (Samsung YP, iRiver) choke on ZLP.
        var dummy: UInt8 = 0
        _ = libusb_bulk_transfer(h, outEP, &dummy, 0, nil, 100)
      }
    }

    var firstChunk: Data? = nil
    if dataInHandler != nil {
      if debug {
        print(String(format: "   [USB] op=0x%04x tx=%u phase=DATA-IN", command.code, txid))
      }
      // First read uses a short 500ms timeout: the device should begin responding
      // quickly after receiving the command. We poll in a loop up to the full
      // handshake budget so transient delays don't cause false timeouts.
      var first = [UInt8](repeating: 0, count: 64 * 1024), got = 0,
        start = DispatchTime.now().uptimeNanoseconds
      let budget = UInt64(config.handshakeTimeoutMs) * 1_000_000
      while got == 0 {
        got = try bulkReadOnce(inEP, into: &first, max: first.count, timeout: 500)
        if got == 0 && DispatchTime.now().uptimeNanoseconds - start > budget {
          log.error(
            "Data-IN phase timeout: no response within \(self.config.handshakeTimeoutMs)ms budget for op=\(String(format: "0x%04x", command.code), privacy: .public). Ensure device screen is on and unlocked."
          )
          throw MTPError.timeout
        }
      }
      let hdr = first.withUnsafeBytes { PTPHeader.decode(from: $0.baseAddress!) }
      if hdr.type == 3 {
        firstChunk = Data(first[0..<got])
      } else {
        let payload = Int(hdr.length) - PTPHeader.size, rem = got - PTPHeader.size
        if rem > 0 {
          _ = first.withUnsafeBytes {
            dataInHandler!(
              UnsafeRawBufferPointer(
                start: $0.baseAddress!.advanced(by: PTPHeader.size), count: rem))
          }
        }
        var left = payload - max(0, rem)
        while left > 0 {
          var buf = [UInt8](repeating: 0, count: min(left, 1 << 20))
          let chunkState = MTPLog.Signpost.chunkSignposter.beginInterval(
            "readChunk", id: MTPLog.Signpost.chunkSignposter.makeSignpostID(), "\(buf.count) bytes")
          // 1000ms per-chunk timeout: longer than the 500ms initial read because
          // mid-transfer chunks may be delayed by device-side file I/O or flash
          // write latency, especially on large file reads from SD cards.
          let g = try bulkReadOnce(inEP, into: &buf, max: buf.count, timeout: 1000)
          MTPLog.Signpost.chunkSignposter.endInterval("readChunk", chunkState)
          if g == 0 {
            log.error("Data-IN chunk read timeout: 0 bytes after 1000ms (remaining=\(left) bytes) for op=\(String(format: "0x%04x", command.code), privacy: .public). Device may have stalled mid-transfer.")
            throw MTPError.timeout
          }
          _ = buf.withUnsafeBytes { dataInHandler!($0) }
          left -= g
        }
      }
    }

    if debug {
      print(String(format: "   [USB] op=0x%04x tx=%u phase=RESPONSE", command.code, txid))
    }
    let rHdr: PTPHeader, initial: Data
    if let f = firstChunk {
      rHdr = f.withUnsafeBytes { PTPHeader.decode(from: $0.baseAddress!) }
      initial = f.subdata(in: PTPHeader.size..<f.count)
    } else {
      var hBuf = [UInt8](repeating: 0, count: PTPHeader.size)
      try bulkReadExact(
        inEP, into: &hBuf, need: PTPHeader.size, timeout: UInt32(config.ioTimeoutMs))
      rHdr = hBuf.withUnsafeBytes { PTPHeader.decode(from: $0.baseAddress!) }
      initial = Data()
    }
    let paramBytes = max(0, Int(rHdr.length) - PTPHeader.size)
    // ignoreHeaderErrors: validate response header type, but tolerate junk when flag is set
    let expectedResponseType: UInt16 = PTPContainer.Kind.response.rawValue
    if rHdr.type != expectedResponseType && rHdr.type != PTPContainer.Kind.data.rawValue {
      if config.ignoreHeaderErrors {
        log.warning(
          "Ignoring malformed response header: type=\(rHdr.type) code=\(String(format: "0x%04x", rHdr.code)) (expected type=\(expectedResponseType)) for op=\(String(format: "0x%04x", command.code), privacy: .public)"
        )
      } else {
        log.error(
          "Unexpected response header type=\(rHdr.type) (expected \(expectedResponseType)) for op=\(String(format: "0x%04x", command.code), privacy: .public)"
        )
      }
    }
    let pCount = paramBytes / 4
    var params = [UInt32]()
    params.reserveCapacity(pCount)
    var pData = initial
    if pData.count < pCount * 4 {
      var extra = [UInt8](repeating: 0, count: pCount * 4 - pData.count)
      try bulkReadExact(inEP, into: &extra, need: extra.count, timeout: UInt32(config.ioTimeoutMs))
      pData.append(contentsOf: extra)
    }
    var paramReader = PTPReader(data: pData)
    for _ in 0..<pCount {
      guard let param = paramReader.u32() else { break }
      params.append(param)
    }
    if debug {
      let paramsText =
        params.isEmpty
        ? "[]" : "[" + params.map { String(format: "0x%08x", $0) }.joined(separator: ",") + "]"
      print(
        String(
          format: "   [USB] op=0x%04x tx=%u response=0x%04x params=%@",
          command.code, txid, rHdr.code, paramsText
        ))
    }

    return PTPResponseResult(code: rHdr.code, txid: rHdr.txid, params: params)
  }
}
