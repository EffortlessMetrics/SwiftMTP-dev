// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import CLibusb
import Foundation
import OSLog
import SwiftMTPCore
import SwiftMTPObservability

private let log = MTPLog.transport

// MARK: - Bulk Transfer Helpers

extension MTPUSBLink {

  /// Clears HALT/STALL condition on all bulk endpoints (and interrupt if present).
  ///
  /// USB STALL is a protocol-level error response where an endpoint indicates it
  /// cannot process a request. This commonly occurs when:
  /// - A previous transfer was interrupted mid-stream (e.g. cable glitch)
  /// - The device rejected a malformed or unexpected PTP container
  /// - Another process (Chrome/WebUSB, Android File Transfer) left endpoints in a
  ///   dirty state after releasing the interface
  ///
  /// Per USB 2.0 spec §9.4.5, `CLEAR_FEATURE(ENDPOINT_HALT)` resets the endpoint's
  /// data toggle and allows the next transfer to proceed. We clear all three
  /// endpoints (bulk OUT, bulk IN, interrupt IN) because a stall on one endpoint
  /// can leave the others in an ambiguous state — the MTP transaction model requires
  /// all endpoints to be synchronized for command/data/response phases.
  ///
  /// Safe to call even if no endpoint is actually halted (returns success).
  func recoverStall() {
    log.debug(
      "Recovering stall: clearing HALT on all endpoints (out=\(String(format: "0x%02x", self.outEP), privacy: .public) in=\(String(format: "0x%02x", self.inEP), privacy: .public) evt=\(String(format: "0x%02x", self.evtEP), privacy: .public))"
    )
    _ = libusb_clear_halt(h, outEP)
    _ = libusb_clear_halt(h, inEP)
    if evtEP != 0 { _ = libusb_clear_halt(h, evtEP) }
  }

  @inline(__always) func bulkWriteAll(
    _ ep: UInt8, from ptr: UnsafeRawPointer, count: Int, timeout: UInt32
  ) throws {
    var sent = 0
    while sent < count {
      var s: Int32 = 0
      let rc = libusb_bulk_transfer(
        h, ep,
        UnsafeMutablePointer<UInt8>(
          mutating: ptr.advanced(by: sent).assumingMemoryBound(to: UInt8.self)),
        Int32(count - sent), &s, timeout)
      if rc == Int32(LIBUSB_ERROR_PIPE.rawValue) {
        // PIPE error = endpoint STALL. Attempt stall recovery (clear HALT on all
        // endpoints) then retry once. If the retry also fails, propagate the error.
        log.warning(
          "Bulk write PIPE/STALL on ep=\(String(format: "0x%02x", ep), privacy: .public), attempting stall recovery"
        )
        recoverStall()
        var r: Int32 = 0
        let rc2 = libusb_bulk_transfer(
          h, ep,
          UnsafeMutablePointer<UInt8>(
            mutating: ptr.advanced(by: sent).assumingMemoryBound(to: UInt8.self)),
          Int32(count - sent), &r, timeout)
        if rc2 != 0 {
          log.error("Bulk write retry after stall recovery failed: \(libusbErrorName(rc2), privacy: .public) (rc=\(rc2)) ep=\(String(format: "0x%02x", ep), privacy: .public) sent=\(sent)/\(count)")
          throw MTPError.transport(mapLibusb(rc2))
        }
        sent += Int(r)
        continue
      }
      if rc != 0 {
        log.error(
          "Bulk write failed: \(libusbErrorName(rc), privacy: .public) (rc=\(rc)) ep=\(String(format: "0x%02x", ep), privacy: .public) sent=\(sent)/\(count) timeout=\(timeout)ms"
        )
        throw MTPError.transport(mapLibusb(rc))
      }
      sent += Int(s)
    }
  }

  @inline(__always) func bulkReadOnce(
    _ ep: UInt8, into buf: UnsafeMutableRawPointer, max: Int, timeout: UInt32
  ) throws -> Int {
    var g: Int32 = 0
    if max < 512 {
      // USB bulk transfers require buffers aligned to max packet size (512 bytes
      // for Hi-Speed). Use a temporary buffer to avoid short-packet issues on
      // host controllers that enforce alignment.
      var tmp = [UInt8](repeating: 0, count: 512)
      let rc = libusb_bulk_transfer(h, ep, &tmp, 512, &g, timeout)
      if rc == -7 { return 0 }  // LIBUSB_ERROR_TIMEOUT — no data yet
      if rc == Int32(LIBUSB_ERROR_PIPE.rawValue) {
        log.warning(
          "Bulk read PIPE/STALL on ep=\(String(format: "0x%02x", ep), privacy: .public), attempting stall recovery"
        )
        recoverStall()
        var g2: Int32 = 0
        let rc2 = libusb_bulk_transfer(h, ep, &tmp, 512, &g2, timeout)
        if rc2 != 0 && rc2 != -8 {
          log.error("Bulk read retry after stall recovery failed: \(libusbErrorName(rc2), privacy: .public) (rc=\(rc2)) ep=\(String(format: "0x%02x", ep), privacy: .public)")
          throw MTPError.transport(mapLibusb(rc2))
        }
        let c = min(Int(g2), max)
        if c > 0 { memcpy(buf, tmp, c) }
        return c
      }
      if rc != 0 && rc != -8 {
        log.error("Bulk read failed: \(libusbErrorName(rc), privacy: .public) (rc=\(rc)) ep=\(String(format: "0x%02x", ep), privacy: .public) requested=\(max) timeout=\(timeout)ms")
        throw MTPError.transport(mapLibusb(rc))
      }
      let c = min(Int(g), max)
      if c > 0 { memcpy(buf, tmp, c) }
      return c
    }
    let rc = libusb_bulk_transfer(
      h, ep, buf.assumingMemoryBound(to: UInt8.self), Int32(max), &g, timeout)
    if rc == -7 { return 0 }  // LIBUSB_ERROR_TIMEOUT — no data yet
    if rc == Int32(LIBUSB_ERROR_PIPE.rawValue) {
      log.warning(
        "Bulk read PIPE/STALL on ep=\(String(format: "0x%02x", ep), privacy: .public), attempting stall recovery"
      )
      recoverStall()
      var g2: Int32 = 0
      let rc2 = libusb_bulk_transfer(
        h, ep, buf.assumingMemoryBound(to: UInt8.self), Int32(max), &g2, timeout)
      if rc2 != 0 {
        log.error("Bulk read retry after stall recovery failed: \(libusbErrorName(rc2), privacy: .public) (rc=\(rc2)) ep=\(String(format: "0x%02x", ep), privacy: .public)")
        throw MTPError.transport(mapLibusb(rc2))
      }
      return Int(g2)
    }
    if rc != 0 {
      log.error("Bulk read failed: \(libusbErrorName(rc), privacy: .public) (rc=\(rc)) ep=\(String(format: "0x%02x", ep), privacy: .public) requested=\(max) timeout=\(timeout)ms")
      throw MTPError.transport(mapLibusb(rc))
    }
    return Int(g)
  }

  /// Reads exactly `need` bytes from the bulk IN endpoint, retrying until complete.
  /// Throws `MTPError.timeout` if any individual read returns 0 bytes.
  func bulkReadExact(_ ep: UInt8, into dst: UnsafeMutableRawPointer, need: Int, timeout: UInt32)
    throws
  {
    var got = 0
    while got < need {
      var tmp = [UInt8](repeating: 0, count: need - got)
      let g = try bulkReadOnce(ep, into: &tmp, max: tmp.count, timeout: timeout)
      if g == 0 {
        log.error("bulkReadExact timeout: got=\(got)/\(need) bytes on ep=\(String(format: "0x%02x", ep), privacy: .public) timeout=\(timeout)ms — device may have stopped responding")
        throw MTPError.timeout
      }
      memcpy(dst.advanced(by: got), &tmp, g)
      got += g
    }
  }

  /// Drain stale data from the bulk IN endpoint before starting a new transfer.
  ///
  /// Some devices (notably Pixel 7 with FunctionFS) may leave residual data in
  /// the IN endpoint from a previous interrupted transaction. Reading with a short
  /// timeout (50ms) discards any buffered bytes so the next command/response cycle
  /// starts cleanly.
  func drainEndpoint(_ ep: UInt8, debug: Bool = false) {
    var drained = 0
    var buf = [UInt8](repeating: 0, count: 512)
    for _ in 0..<8 {
      var got: Int32 = 0
      let rc = libusb_bulk_transfer(h, ep, &buf, Int32(buf.count), &got, 50)
      if got > 0 {
        drained += Int(got)
        continue
      }
      // Timeout or error means no more stale data
      if rc == Int32(LIBUSB_ERROR_TIMEOUT.rawValue) || rc != 0 { break }
      break
    }
    if drained > 0 {
      log.info("Drained \(drained) stale bytes from ep=\(String(format: "0x%02x", ep), privacy: .public)")
      if debug {
        print(
          String(format: "   [USB][Drain] drained %d stale bytes from ep=0x%02x", drained, ep))
      }
    }
  }

  /// Query USB endpoint status via GET_STATUS control transfer.
  ///
  /// Returns the 2-byte endpoint status word (bit 0 = halted) or nil on error.
  /// Provides diagnostic information without changing device state.
  func getEndpointStatus(_ ep: UInt8) -> UInt16? {
    var status: UInt16 = 0
    let rc = withUnsafeMutableBytes(of: &status) { ptr -> Int32 in
      libusb_control_transfer(
        h,
        UInt8(LIBUSB_ENDPOINT_IN.rawValue) | UInt8(LIBUSB_RECIPIENT_ENDPOINT.rawValue),
        0x00,  // GET_STATUS
        0,     // USB_FEATURE_HALT
        UInt16(ep),
        ptr.baseAddress!.assumingMemoryBound(to: UInt8.self),
        2,
        1000)
    }
    return rc == 2 ? status : nil
  }

  /// Log diagnostic endpoint status for all bulk endpoints.
  func logEndpointStatus(context: String, debug: Bool) {
    guard debug else { return }
    let outStatus = getEndpointStatus(outEP)
    let inStatus = getEndpointStatus(inEP)
    let outHalted = outStatus.map { $0 & 1 != 0 } ?? false
    let inHalted = inStatus.map { $0 & 1 != 0 } ?? false
    print(
      String(
        format: "   [USB][Status] %@ out=0x%02x(%@) in=0x%02x(%@)",
        context, outEP, outHalted ? "HALTED" : "ok",
        inEP, inHalted ? "HALTED" : "ok"))
  }
}
