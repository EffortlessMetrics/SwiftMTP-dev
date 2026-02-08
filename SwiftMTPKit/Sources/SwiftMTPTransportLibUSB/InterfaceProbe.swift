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
  let detachRC = libusb_detach_kernel_driver(handle, Int32(c.ifaceNumber))
  if debug {
    print(String(format: "   [Claim] iface=%d alt=%d bulkIn=0x%02x bulkOut=0x%02x evtIn=0x%02x detachKernel=%d",
                 c.ifaceNumber, c.altSetting, c.bulkIn, c.bulkOut, c.eventIn, detachRC))
  }
  try check(libusb_claim_interface(handle, Int32(c.ifaceNumber)))
  if debug { print("   [Claim] claim_interface OK") }
  if c.altSetting > 0 {
    try check(libusb_set_interface_alt_setting(handle, Int32(c.ifaceNumber), Int32(c.altSetting)))
  }
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

  // Send PTP Device Reset (class request 0x66) to clear any stale session
  // held by the macOS IOKit PTP driver. This is a USB control transfer that
  // works even when bulk endpoints are blocked by a stale session.
  let resetRC = libusb_control_transfer(
    handle,
    0x21,                        // bmRequestType: host-to-device, class, interface
    0x66,                        // bRequest: PTP Device Reset
    0,                           // wValue
    UInt16(c.ifaceNumber),       // wIndex: interface number
    nil,                         // no data
    0,                           // wLength
    5000                         // 5s timeout
  )
  if debug { print("   [Probe] PTP Device Reset (0x66) rc=\(resetRC)") }

  let haltIn = libusb_clear_halt(handle, c.bulkIn)
  let haltOut = libusb_clear_halt(handle, c.bulkOut)
  if debug { print("   [Probe] clear_halt in=\(haltIn) out=\(haltOut), timeoutMs=\(timeoutMs)") }

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
