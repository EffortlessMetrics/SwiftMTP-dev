// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import CLibusb
import SwiftMTPCore

// MARK: - InterfaceCandidate

/// A ranked MTP interface candidate extracted from the USB config descriptor.
struct InterfaceCandidate: Sendable {
  let ifaceNumber: UInt8
  let altSetting: UInt8
  let bulkIn: UInt8
  let bulkOut: UInt8
  let eventIn: UInt8
  let score: Int

  /// Interface class/subclass/protocol triple.
  let ifaceClass: UInt8
  let ifaceSubclass: UInt8
  let ifaceProtocol: UInt8
}

/// Result of probing a single interface candidate.
struct InterfaceProbeAttempt: Sendable {
  let candidate: InterfaceCandidate
  let succeeded: Bool
  let cachedDeviceInfoData: Data?
  let durationMs: Int
  let error: String?
}

// MARK: - Ranking

/// Rank all MTP-capable interfaces on a device, sorted by score descending.
func rankMTPInterfaces(handle: OpaquePointer, device: OpaquePointer) throws -> [InterfaceCandidate] {
  var cfgPtr: UnsafeMutablePointer<libusb_config_descriptor>?
  try check(libusb_get_active_config_descriptor(device, &cfgPtr))
  guard let cfg = cfgPtr?.pointee else { throw TransportError.io("no active config") }
  defer { libusb_free_config_descriptor(cfgPtr) }

  var candidates: [InterfaceCandidate] = []
  for i in 0..<Int(cfg.bNumInterfaces) {
    let ifc = cfg.interface[i]
    for a in 0..<Int(ifc.num_altsetting) {
      let alt = ifc.altsetting[Int(a)]
      let eps = findEndpoints(alt)
      guard eps.bulkIn != 0, eps.bulkOut != 0 else { continue }

      var score = 0
      if alt.bInterfaceClass == 0x06 && alt.bInterfaceSubClass == 0x01 { score += 100 }
      let name = getAsciiString(handle, alt.iInterface).lowercased()
      if (alt.bInterfaceClass == 0xFF && alt.bInterfaceSubClass == 0x42) || name.contains("adb") { score -= 200 }
      if alt.bInterfaceClass == 0xFF && (name.contains("mtp") || name.contains("ptp")) { score += 60 }
      if eps.evtIn != 0 { score += 5 }

      guard score >= 60 else { continue }

      candidates.append(InterfaceCandidate(
        ifaceNumber: UInt8(i),
        altSetting: alt.bAlternateSetting,
        bulkIn: eps.bulkIn,
        bulkOut: eps.bulkOut,
        eventIn: eps.evtIn,
        score: score,
        ifaceClass: alt.bInterfaceClass,
        ifaceSubclass: alt.bInterfaceSubClass,
        ifaceProtocol: alt.bInterfaceProtocol
      ))
    }
  }
  return candidates.sorted { $0.score > $1.score }
}

// MARK: - Claim / Release

/// Claim a single interface candidate using the libmtp-aligned sequence:
/// detach kernel driver → set_configuration → claim → set_interface_alt_setting.
///
/// `set_configuration` before claim forces macOS host controller to reinitialize
/// endpoint pipes, clearing stale state from any prior accessor.
/// `set_interface_alt_setting` after claim activates MTP endpoints at the host
/// controller level.
func claimCandidate(handle: OpaquePointer, _ c: InterfaceCandidate) throws {
  let debug = ProcessInfo.processInfo.environment["SWIFTMTP_DEBUG"] == "1"
  let iface = Int32(c.ifaceNumber)

  if debug {
    print(String(format: "   [Claim] iface=%d bulkIn=0x%02x bulkOut=0x%02x",
                 c.ifaceNumber, c.bulkIn, c.bulkOut))
  }

  // Explicitly detach kernel driver (different IOKit code path from auto-detach on macOS)
  let detachRC = libusb_detach_kernel_driver(handle, iface)
  if debug && detachRC != 0 && detachRC != Int32(LIBUSB_ERROR_NOT_FOUND.rawValue) {
    print("   [Claim] detach_kernel_driver rc=\(detachRC) (non-fatal)")
  }

  // Set configuration before claim — reinitializes endpoint pipes at host controller level
  let setConfigRC = libusb_set_configuration(handle, 1)
  if debug { print("   [Claim] set_configuration(1) rc=\(setConfigRC)") }

  try check(libusb_claim_interface(handle, iface))

  // Set alt setting after claim — activates MTP endpoints
  let setAltRC = libusb_set_interface_alt_setting(handle, iface, Int32(c.altSetting))
  if debug { print("   [Claim] set_interface_alt_setting(\(c.altSetting)) rc=\(setAltRC)") }

  // Brief pause for pipe setup (alt-setting does the real work, so 100ms suffices)
  if debug { print("   [Claim] claimed OK, waiting 100ms for pipe activation") }
  usleep(100_000)
}

/// Release a previously claimed candidate.
func releaseCandidate(handle: OpaquePointer, _ c: InterfaceCandidate) {
  _ = libusb_release_interface(handle, Int32(c.ifaceNumber))
}

// MARK: - Probe

/// Send a sessionless GetDeviceInfo (0x1001) to validate the interface works.
///
/// Uses a non-zero txid and reads until the matching Response container is seen,
/// ensuring the PTP transaction is fully completed. This prevents leaving the
/// device mid-transaction, which would wedge subsequent bulk transfers.
///
/// Returns (success, cached raw device-info bytes).
func probeCandidate(handle: OpaquePointer, _ c: InterfaceCandidate, timeoutMs: UInt32 = 2000) -> (Bool, Data?) {
  let debug = ProcessInfo.processInfo.environment["SWIFTMTP_DEBUG"] == "1"

  _ = libusb_clear_halt(handle, c.bulkIn)
  _ = libusb_clear_halt(handle, c.bulkOut)

  // Use txid=1 so we can match the Response container and complete the transaction
  let probeTxid: UInt32 = 1
  if debug { print("   [Probe] sending GetDeviceInfo txid=\(probeTxid), timeoutMs=\(timeoutMs)") }

  let cmdBytes = makePTPCommand(opcode: 0x1001, txid: probeTxid, params: [])

  // Send command container
  var sent: Int32 = 0
  let writeRC = cmdBytes.withUnsafeBytes { ptr -> Int32 in
    libusb_bulk_transfer(
      handle, c.bulkOut,
      UnsafeMutablePointer(mutating: ptr.baseAddress!.assumingMemoryBound(to: UInt8.self)),
      Int32(cmdBytes.count), &sent, timeoutMs
    )
  }
  if debug { print("   [Probe] write rc=\(writeRC) sent=\(sent)/\(cmdBytes.count)") }
  guard writeRC == 0, sent == cmdBytes.count else {
    drainBulkIn(handle: handle, ep: c.bulkIn)
    return (false, nil)
  }

  // Read until we see a Response container (type=3) for our txid.
  // We may get: Data container (type=2) then Response, or just Response.
  var deviceInfoData: Data? = nil
  var sawResponse = false
  var responseOK = false
  let deadline = DispatchTime.now().uptimeNanoseconds + UInt64(timeoutMs) * 1_000_000
  var buf = [UInt8](repeating: 0, count: 64 * 1024)

  while !sawResponse && DispatchTime.now().uptimeNanoseconds < deadline {
    var got: Int32 = 0
    let remaining = (deadline - DispatchTime.now().uptimeNanoseconds) / 1_000_000
    let readTimeout = UInt32(min(remaining, UInt64(timeoutMs)))
    let readRC = libusb_bulk_transfer(handle, c.bulkIn, &buf, Int32(buf.count), &got, readTimeout)

    if debug {
      if got >= PTPHeader.size {
        let hdr = buf.withUnsafeBytes { PTPHeader.decode(from: $0.baseAddress!) }
        print(String(format: "   [Probe] read rc=%d got=%d (type=%d code=0x%04x txid=%u len=%u)",
                     readRC, got, hdr.type, hdr.code, hdr.txid, hdr.length))
      } else {
        print("   [Probe] read rc=\(readRC) got=\(got)")
      }
    }

    guard readRC == 0, got >= PTPHeader.size else {
      // Timeout or error — drain and bail
      drainBulkIn(handle: handle, ep: c.bulkIn)
      return (false, nil)
    }

    // Parse container(s) from this transfer. A single bulk read can contain
    // one or (rarely) multiple containers back-to-back.
    var offset = 0
    while offset + PTPHeader.size <= Int(got) {
      let hdr = buf.withUnsafeBytes {
        PTPHeader.decode(from: $0.baseAddress!.advanced(by: offset))
      }

      if hdr.type == 2 {
        // Data container — extract device info payload
        let payloadStart = offset + PTPHeader.size
        let payloadEnd = min(offset + Int(hdr.length), Int(got))
        if payloadEnd > payloadStart {
          deviceInfoData = Data(buf[payloadStart..<payloadEnd])
        }
      } else if hdr.type == 3 {
        // Response container — transaction is complete
        sawResponse = true
        responseOK = (hdr.code == 0x2001)
        break
      }

      // Advance past this container
      let containerLen = max(Int(hdr.length), PTPHeader.size)
      offset += containerLen
    }
  }

  if !sawResponse {
    if debug { print("   [Probe] never saw Response container, draining") }
    drainBulkIn(handle: handle, ep: c.bulkIn)
    return (false, nil)
  }

  return (responseOK, responseOK ? deviceInfoData : nil)
}

/// Best-effort drain of stale data from bulk IN endpoint after a failed probe.
/// Prevents poisoning subsequent probe attempts.
private func drainBulkIn(handle: OpaquePointer, ep: UInt8, maxAttempts: Int = 5) {
  var drain = [UInt8](repeating: 0, count: 4096)
  var got: Int32 = 0
  for _ in 0..<maxAttempts {
    let rc = libusb_bulk_transfer(handle, ep, &drain, Int32(drain.count), &got, 50)
    if rc != 0 || got == 0 { break }
  }
  _ = libusb_clear_halt(handle, ep)
}

// MARK: - MTP Readiness Polling

/// Poll GetDeviceStatus (0x67) until the device reports OK (0x2001) or timeout.
///
/// Replaces fixed sleep after USB reset with adaptive detection — fast for
/// quick-recovering devices, patient for slow ones.
func waitForMTPReady(handle: OpaquePointer, iface: UInt16, budgetMs: Int) -> Bool {
  let debug = ProcessInfo.processInfo.environment["SWIFTMTP_DEBUG"] == "1"
  let deadline = DispatchTime.now().uptimeNanoseconds + UInt64(budgetMs) * 1_000_000
  let pollIntervalUs: useconds_t = 200_000  // 200ms

  while DispatchTime.now().uptimeNanoseconds < deadline {
    var statusBuf = [UInt8](repeating: 0, count: 12)
    let rc = libusb_control_transfer(
      handle, 0xA1, 0x67, 0, iface, &statusBuf, UInt16(statusBuf.count), 500
    )
    if rc >= 4 {
      let code = UInt16(statusBuf[0]) | (UInt16(statusBuf[1]) << 8)
      if debug { print(String(format: "   [Ready] GetDeviceStatus → 0x%04x", code)) }
      if code == 0x2001 { return true }
    } else if debug {
      print("   [Ready] GetDeviceStatus rc=\(rc)")
    }
    usleep(pollIntervalUs)
  }
  if debug { print("   [Ready] timed out after \(budgetMs)ms") }
  return false
}

// MARK: - Probe All Candidates

/// Result of attempting to probe all candidates on a device.
struct ProbeAllResult {
  let candidate: InterfaceCandidate?
  let cachedDeviceInfo: Data?
}

/// Try to claim and probe each candidate in order. Returns the first that succeeds.
func tryProbeAllCandidates(
  handle: OpaquePointer,
  candidates: [InterfaceCandidate],
  handshakeTimeoutMs: Int,
  debug: Bool
) -> ProbeAllResult {
  for candidate in candidates {
    let start = DispatchTime.now()
    if debug {
      print(String(format: "   [Probe] Trying interface %d (score=%d, class=0x%02x)",
                   candidate.ifaceNumber, candidate.score, candidate.ifaceClass))
    }

    do {
      try claimCandidate(handle: handle, candidate)
    } catch {
      if debug { print("   [Probe] Claim failed: \(error)") }
      continue
    }

    let (probeOK, infoData) = probeCandidate(
      handle: handle, candidate, timeoutMs: UInt32(handshakeTimeoutMs)
    )
    let elapsed = Int((DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000)

    if probeOK {
      if debug { print("   [Probe] Interface \(candidate.ifaceNumber) OK (\(elapsed)ms)") }
      return ProbeAllResult(candidate: candidate, cachedDeviceInfo: infoData)
    } else {
      if debug { print("   [Probe] Interface \(candidate.ifaceNumber) failed (\(elapsed)ms), trying next...") }
      releaseCandidate(handle: handle, candidate)
    }
  }
  return ProbeAllResult(candidate: nil, cachedDeviceInfo: nil)
}
