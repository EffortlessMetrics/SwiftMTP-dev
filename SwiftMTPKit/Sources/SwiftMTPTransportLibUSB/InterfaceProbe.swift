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

/// Claim a single interface candidate: detach kernel driver, claim, set alt.
func claimCandidate(handle: OpaquePointer, _ c: InterfaceCandidate) throws {
  let debug = ProcessInfo.processInfo.environment["SWIFTMTP_DEBUG"] == "1"

  if debug {
    let drvActive = libusb_kernel_driver_active(handle, Int32(c.ifaceNumber))
    // Pre-claim GetDeviceStatus to verify MTP service is alive
    var devStatusBuf = [UInt8](repeating: 0, count: 12)
    let devStatusRC = libusb_control_transfer(
      handle, 0xA1, 0x67, 0, UInt16(c.ifaceNumber), &devStatusBuf, UInt16(devStatusBuf.count), 2000
    )
    let statusCode: String
    if devStatusRC >= 4 {
      let code = UInt16(devStatusBuf[2]) | (UInt16(devStatusBuf[3]) << 8)
      statusCode = String(format: "0x%04x", code)
    } else {
      statusCode = "rc=\(devStatusRC)"
    }
    print(String(format: "   [Claim] iface=%d bulkIn=0x%02x bulkOut=0x%02x driver=%d devStatus=%@",
                 c.ifaceNumber, c.bulkIn, c.bulkOut, drvActive, statusCode as NSString))
  }

  // Use auto-detach rather than manual detach — uses different IOKit code path on macOS
  _ = libusb_set_auto_detach_kernel_driver(handle, 1)
  try check(libusb_claim_interface(handle, Int32(c.ifaceNumber)))
  if debug { print("   [Claim] claimed OK, waiting 500ms for pipe setup...") }
  usleep(500_000)
}

/// Release a previously claimed candidate.
func releaseCandidate(handle: OpaquePointer, _ c: InterfaceCandidate) {
  _ = libusb_release_interface(handle, Int32(c.ifaceNumber))
}

// MARK: - Probe

/// Send a sessionless GetDeviceInfo (0x1001) to validate the interface works.
/// Returns (success, cached raw device-info bytes).
func probeCandidate(handle: OpaquePointer, _ c: InterfaceCandidate, timeoutMs: UInt32 = 2000) -> (Bool, Data?) {
  let debug = ProcessInfo.processInfo.environment["SWIFTMTP_DEBUG"] == "1"

  _ = libusb_clear_halt(handle, c.bulkIn)
  _ = libusb_clear_halt(handle, c.bulkOut)

  if debug { print("   [Probe] sending GetDeviceInfo, timeoutMs=\(timeoutMs)") }

  // Build a raw GetDeviceInfo command (txid=0, no session required)
  let cmdBytes = makePTPCommand(opcode: 0x1001, txid: 0, params: [])

  // Send command
  var sent: Int32 = 0
  let writeRC = cmdBytes.withUnsafeBytes { ptr -> Int32 in
    libusb_bulk_transfer(
      handle, c.bulkOut,
      UnsafeMutablePointer(mutating: ptr.baseAddress!.assumingMemoryBound(to: UInt8.self)),
      Int32(cmdBytes.count), &sent, timeoutMs
    )
  }
  if debug { print("   [Probe] write rc=\(writeRC) sent=\(sent)/\(cmdBytes.count)") }
  guard writeRC == 0, sent == cmdBytes.count else { return (false, nil) }

  // Read response (data phase + response)
  var buf = [UInt8](repeating: 0, count: 64 * 1024)
  var got: Int32 = 0
  let readRC = libusb_bulk_transfer(handle, c.bulkIn, &buf, Int32(buf.count), &got, timeoutMs)
  if debug { print("   [Probe] read rc=\(readRC) got=\(got)") }
  guard readRC == 0, got >= PTPHeader.size else { return (false, nil) }

  let hdr = buf.withUnsafeBytes { PTPHeader.decode(from: $0.baseAddress!) }

  // Could be data phase (type=2) or response (type=3)
  if hdr.type == 2 {
    // This is the data container; extract payload
    let payloadStart = PTPHeader.size
    let payloadEnd = min(Int(got), Int(hdr.length))
    let deviceInfoData = Data(buf[payloadStart..<payloadEnd])

    // Drain the response container that follows
    var rBuf = [UInt8](repeating: 0, count: 512)
    var rGot: Int32 = 0
    _ = libusb_bulk_transfer(handle, c.bulkIn, &rBuf, Int32(rBuf.count), &rGot, timeoutMs)

    return (true, deviceInfoData)
  } else if hdr.type == 3 && hdr.code == 0x2001 {
    // Response OK but no data (unusual for GetDeviceInfo but valid)
    return (true, nil)
  }

  return (false, nil)
}
