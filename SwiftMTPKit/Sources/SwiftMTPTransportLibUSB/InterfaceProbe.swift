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

struct MTPInterfaceHeuristic: Sendable {
  let isCandidate: Bool
  let score: Int
}

@inline(__always)
private func nameLooksLikeMTP(_ interfaceName: String) -> Bool {
  let lower = interfaceName.lowercased()
  return lower.contains("mtp") || lower.contains("ptp")
}

@inline(__always)
private func nameLooksLikeADB(_ interfaceName: String) -> Bool {
  let lower = interfaceName.lowercased()
  return lower.contains("adb") || lower.contains("android debug")
}

/// Shared heuristic used for discovery, hotplug, and interface ranking.
func evaluateMTPInterfaceCandidate(
  interfaceClass: UInt8,
  interfaceSubclass: UInt8,
  interfaceProtocol: UInt8,
  endpoints: EPCandidates,
  interfaceName: String
) -> MTPInterfaceHeuristic {
  // Must have a bulk IN/OUT pair for command/data traffic.
  guard endpoints.bulkIn != 0, endpoints.bulkOut != 0 else {
    return MTPInterfaceHeuristic(isCandidate: false, score: Int.min)
  }

  if (interfaceClass == 0xFF && interfaceSubclass == 0x42) || nameLooksLikeADB(interfaceName) {
    return MTPInterfaceHeuristic(isCandidate: false, score: Int.min)
  }

  var score = 0
  let name = interfaceName.lowercased()

  // Canonical MTP/PTP interface.
  if interfaceClass == 0x06 && interfaceSubclass == 0x01 {
    score += 100
  } else if interfaceClass == 0x06 {
    score += 65
  }

  // Vendor-specific Android stacks often expose MTP on class 0xFF.
  if interfaceClass == 0xFF {
    if nameLooksLikeMTP(name) {
      score += 80
    } else if endpoints.evtIn != 0 {
      // Event endpoint + bulk pair is a strong MTP signal.
      score += 62
    }
  }

  if name.contains("ptp") || name.contains("mtp") { score += 15 }
  if interfaceProtocol == 0x01 { score += 5 }
  if endpoints.evtIn != 0 { score += 5 }

  let isCandidate = score >= 60
  return MTPInterfaceHeuristic(isCandidate: isCandidate, score: score)
}

// MARK: - Ranking

/// Rank all MTP-capable interfaces on a device, sorted by score descending.
func rankMTPInterfaces(handle: OpaquePointer, device: OpaquePointer) throws -> [InterfaceCandidate]
{
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
      let name = getAsciiString(handle, alt.iInterface).lowercased()
      let heuristic = evaluateMTPInterfaceCandidate(
        interfaceClass: alt.bInterfaceClass,
        interfaceSubclass: alt.bInterfaceSubClass,
        interfaceProtocol: alt.bInterfaceProtocol,
        endpoints: eps,
        interfaceName: name
      )
      guard heuristic.isCandidate else { continue }

      candidates.append(
        InterfaceCandidate(
          ifaceNumber: UInt8(i),
          altSetting: alt.bAlternateSetting,
          bulkIn: eps.bulkIn,
          bulkOut: eps.bulkOut,
          eventIn: eps.evtIn,
          score: heuristic.score,
          ifaceClass: alt.bInterfaceClass,
          ifaceSubclass: alt.bInterfaceSubClass,
          ifaceProtocol: alt.bInterfaceProtocol
        ))
    }
  }
  return candidates.sorted { $0.score > $1.score }
}

// MARK: - Configuration Helper

/// Derive the target configuration value from the device's first config descriptor.
/// Returns the bConfigurationValue, or 1 as a safe fallback.
func configurationValue(for device: OpaquePointer) -> Int32 {
  var cfgPtr: UnsafeMutablePointer<libusb_config_descriptor>?
  guard libusb_get_config_descriptor(device, 0, &cfgPtr) == 0, let cfg = cfgPtr else {
    return 1  // Safe default
  }
  let value = Int32(cfg.pointee.bConfigurationValue)
  libusb_free_config_descriptor(cfgPtr)
  return value
}

/// Set USB configuration only if needed (current != target), or if `force` is true.
func setConfigurationIfNeeded(
  handle: OpaquePointer, device: OpaquePointer, force: Bool = false, debug: Bool
) {
  let target = configurationValue(for: device)
  var current: Int32 = 0
  let getRC = libusb_get_configuration(handle, &current)
  if debug {
    print(String(format: "   [Config] current=%d target=%d (getRC=%d)", current, target, getRC))
  }
  if !force && getRC == 0 && current == target {
    if debug { print("   [Config] already at target config, skipping set_configuration") }
    return
  }
  let setRC = libusb_set_configuration(handle, target)
  if debug { print("   [Config] set_configuration(\(target)) rc=\(setRC)") }
}

// MARK: - Claim / Release

// libusb error code constants (raw values from libusb.h)
private let LIBUSB_SUCCESS = Int32(0)
private let LIBUSB_ERROR_ACCESS_DENIED = Int32(-3)
private let LIBUSB_ERROR_NO_DEVICE = Int32(-4)
private let LIBUSB_ERROR_NOT_FOUND = Int32(-5)
private let LIBUSB_ERROR_BUSY = Int32(-6)
private let LIBUSB_ERROR_TIMEOUT = Int32(-7)
private let LIBUSB_ERROR_NOT_SUPPORTED = Int32(-12)

/// Claim a single interface candidate using the libmtp-aligned sequence:
/// detach kernel driver → set_configuration → claim → set_interface_alt_setting.
///
/// `set_configuration` before claim forces macOS host controller to reinitialize
/// endpoint pipes, clearing stale state from any prior accessor.
/// `set_interface_alt_setting` after claim activates MTP endpoints at the host
/// controller level.
///
/// Enhanced with retry logic for vendor-specific devices (Samsung, Xiaomi, etc.)
func claimCandidate(
  handle: OpaquePointer, device: OpaquePointer, _ c: InterfaceCandidate, retryCount: Int = 2,
  postClaimStabilizeMs: Int = 250
) throws {
  let debug = ProcessInfo.processInfo.environment["SWIFTMTP_DEBUG"] == "1"
  let iface = Int32(c.ifaceNumber)

  if debug {
    print(
      String(
        format: "   [Claim] iface=%d bulkIn=0x%02x bulkOut=0x%02x class=0x%02x",
        c.ifaceNumber, c.bulkIn, c.bulkOut, c.ifaceClass))
  }

  // Always attempt auto-detach before claim on first contact.
  // Some devices need this even before we can "learn" a profile.
  let autoDetachRC = libusb_set_auto_detach_kernel_driver(handle, 1)
  if debug {
    if autoDetachRC == LIBUSB_SUCCESS {
      print("   [Claim] set_auto_detach_kernel_driver: enabled")
    } else {
      print("   [Claim] set_auto_detach_kernel_driver rc=\(autoDetachRC) (continuing anyway)")
    }
  }

  // Try claim with optional retry for vendor-specific devices
  for attempt in 0...retryCount {
    if attempt > 0 {
      if debug { print("   [Claim] Retrying claim (attempt \(attempt + 1)/\(retryCount + 1))") }
      // Brief delay before retry
      usleep(100_000)
    }

    // Explicitly detach kernel driver (different IOKit code path from auto-detach on macOS)
    let detachRC = libusb_detach_kernel_driver(handle, iface)
    if debug {
      if detachRC == LIBUSB_SUCCESS {
        print("   [Claim] detach_kernel_driver: succeeded")
      } else if detachRC == LIBUSB_ERROR_NOT_FOUND {
        print("   [Claim] detach_kernel_driver: no kernel driver to detach")
      } else {
        print("   [Claim] detach_kernel_driver rc=\(detachRC) (continuing anyway)")
      }
    }

    // Smart configuration: only set if needed or during recovery
    setConfigurationIfNeeded(handle: handle, device: device, debug: debug)

    // Attempt to claim the interface
    let claimRC = libusb_claim_interface(handle, iface)
    if debug {
      print(String(format: "   [Claim] libusb_claim_interface rc=%d", claimRC))
    }

    if claimRC == LIBUSB_SUCCESS {
      // Successfully claimed - proceed with alt setting
      let setAltRC = libusb_set_interface_alt_setting(handle, iface, Int32(c.altSetting))
      if debug {
        print(
          String(format: "   [Claim] set_interface_alt_setting(%d) rc=%d", c.altSetting, setAltRC))
      }

      // Brief pause for pipe setup (alt-setting does the real work, but some devices need more time)
      // Samsung and similar vendor-specific MTP stacks benefit from 250-500ms stabilization
      if debug {
        print("   [Claim] claimed OK, waiting \(postClaimStabilizeMs)ms for pipe activation")
      }
      usleep(UInt32(postClaimStabilizeMs) * 1000)

      // CRITICAL: Clear HALT state on both bulk endpoints before first command.
      // This fixes "sent=0/12" timeouts on devices like Pixel 7 where endpoints may be
      // left in halted state from Chrome/WebUSB interference or previous failed attempts.
      // libusb_clear_halt is safe to call even if endpoint is not halted (returns success).
      let clearInRC = libusb_clear_halt(handle, c.bulkIn)
      let clearOutRC = libusb_clear_halt(handle, c.bulkOut)
      if debug {
        print(
          String(
            format: "   [Claim] clear_halt: bulkIn=0x%02x rc=%d, bulkOut=0x%02x rc=%d",
            c.bulkIn, clearInRC, c.bulkOut, clearOutRC))

        // Additional endpoint diagnostics (debug only, non-fatal)
        let inMax = libusb_get_max_packet_size(libusb_get_device(handle), c.bulkIn)
        let outMax = libusb_get_max_packet_size(libusb_get_device(handle), c.bulkOut)
        print(String(format: "   [Claim] maxPacketSize: bulkIn=%d bulkOut=%d", inMax, outMax))
        if inMax < 0 { print("   [Claim] WARNING: bulkIn max_packet_size negative (bad pipe)") }
        if outMax < 0 { print("   [Claim] WARNING: bulkOut max_packet_size negative (bad pipe)") }
      }

      return  // Success - exit the retry loop
    }

    // Claim failed - log the error and retry if we have attempts left
    if debug {
      let errorName: String
      switch claimRC {
      case LIBUSB_ERROR_ACCESS_DENIED:
        errorName = "ACCESS_DENIED"
      case LIBUSB_ERROR_NO_DEVICE:
        errorName = "NO_DEVICE"
      case LIBUSB_ERROR_BUSY:
        errorName = "BUSY"
      case LIBUSB_ERROR_NOT_FOUND:
        errorName = "NOT_FOUND"
      case LIBUSB_ERROR_TIMEOUT:
        errorName = "TIMEOUT"
      case LIBUSB_ERROR_NOT_SUPPORTED:
        errorName = "NOT_SUPPORTED"
      default:
        errorName = "UNKNOWN (\(claimRC))"
      }
      print("   [Claim] FAILED: \(errorName), attempt \(attempt + 1)/\(retryCount + 1)")
    }

    // If this was the last attempt, throw the error
    if attempt == retryCount {
      throw TransportError.io("libusb_claim_interface failed: rc=\(claimRC)")
    }

    // Brief delay before retry to allow device to settle
    usleep(200_000)
  }
}

/// Release a previously claimed candidate.
func releaseCandidate(handle: OpaquePointer, _ c: InterfaceCandidate) {
  _ = libusb_release_interface(handle, Int32(c.ifaceNumber))
}

// MARK: - Probe

/// Result of probing a single interface candidate with ladder support.
struct ProbeLadderResult: Sendable {
  let succeeded: Bool
  let cachedDeviceInfoData: Data?
  let stepAttempted: String
}

/// Probe ladder: try OpenSession first (like libmtp), then sessionless GetDeviceInfo, then GetStorageIDs.
/// Returns (success, cached raw device-info bytes) and which step succeeded.
func probeCandidateWithLadder(
  handle: OpaquePointer,
  _ c: InterfaceCandidate,
  timeoutMs: UInt32 = 2000,
  debug: Bool = false,
  includeStorageProbe: Bool = true
) -> ProbeLadderResult {
  var lastAttemptedStep = "openSessionThenGetDeviceInfo"

  // Step 1: OpenSession FIRST - this is what libmtp does and it handles Pixel 7 better
  // Some devices need a session before they respond to other commands
  if debug { print("   [ProbeLadder] Step 1: OpenSession first (like libmtp)") }
  if probeOpenSession(handle: handle, c, timeoutMs: timeoutMs, debug: debug) {
    let (step1OK, infoData) = probeCandidate(handle: handle, c, timeoutMs: timeoutMs)
    if step1OK {
      return ProbeLadderResult(
        succeeded: true, cachedDeviceInfoData: infoData,
        stepAttempted: "openSessionThenGetDeviceInfo")
    }
  }

  // Step 2: Fallback to sessionless GetDeviceInfo
  lastAttemptedStep = "sessionlessGetDeviceInfo"
  if debug { print("   [ProbeLadder] Step 2: sessionless GetDeviceInfo fallback") }
  let (step2OK, infoData2) = probeCandidate(handle: handle, c, timeoutMs: timeoutMs)
  if step2OK {
    return ProbeLadderResult(
      succeeded: true, cachedDeviceInfoData: infoData2, stepAttempted: "sessionlessGetDeviceInfo")
  }

  if includeStorageProbe {
    // Step 3: GetStorageIDs (some vendor-specific devices respond to this even if DeviceInfo fails)
    lastAttemptedStep = "getStorageIDs"
    if debug { print("   [ProbeLadder] Step 3: GetStorageIDs") }
    if probeGetStorageIDs(handle: handle, c, timeoutMs: timeoutMs, debug: debug) {
      // Even without device info, consider this a successful probe for vendor-specific stacks
      return ProbeLadderResult(
        succeeded: true, cachedDeviceInfoData: nil, stepAttempted: "getStorageIDs")
    }
  }

  return ProbeLadderResult(
    succeeded: false,
    cachedDeviceInfoData: nil,
    stepAttempted: lastAttemptedStep
  )
}

/// Send OpenSession (0x1002) to establish an MTP session.
func probeOpenSession(
  handle: OpaquePointer, _ c: InterfaceCandidate, timeoutMs: UInt32, debug: Bool
) -> Bool {
  let txid: UInt32 = 1
  // OpenSession params: transaction ID (32-bit)
  let cmdBytes = makePTPCommand(opcode: 0x1002, txid: txid, params: [txid])

  var sent: Int32 = 0
  let writeRC = cmdBytes.withUnsafeBytes { ptr -> Int32 in
    libusb_bulk_transfer(
      handle, c.bulkOut,
      UnsafeMutablePointer(mutating: ptr.baseAddress!.assumingMemoryBound(to: UInt8.self)),
      Int32(cmdBytes.count), &sent, timeoutMs
    )
  }
  if writeRC != 0 || sent != cmdBytes.count {
    if debug { print("   [ProbeLadder] OpenSession write failed: rc=\(writeRC) sent=\(sent)") }
    drainBulkIn(handle: handle, ep: c.bulkIn)
    return false
  }

  // Read response
  var readBuf = [UInt8](repeating: 0, count: 64)
  var got: Int32 = 0
  let readRC = libusb_bulk_transfer(
    handle, c.bulkIn, &readBuf, Int32(readBuf.count), &got, timeoutMs)
  if debug { print("   [ProbeLadder] OpenSession read rc=\(readRC) got=\(got)") }

  if readRC == 0 && got >= PTPHeader.size {
    let hdr = readBuf.withUnsafeBytes { PTPHeader.decode(from: $0.baseAddress!) }
    // Response code 0x2001 = OK
    if hdr.type == 3 && hdr.code == 0x2001 {
      if debug { print("   [ProbeLadder] OpenSession succeeded") }
      return true
    }
  }

  drainBulkIn(handle: handle, ep: c.bulkIn)
  return false
}

/// Send GetStorageIDs (0x1005) to validate the device speaks MTP.
func probeGetStorageIDs(
  handle: OpaquePointer, _ c: InterfaceCandidate, timeoutMs: UInt32, debug: Bool
) -> Bool {
  let txid: UInt32 = 1
  let cmdBytes = makePTPCommand(opcode: 0x1005, txid: txid, params: [])

  var sent: Int32 = 0
  let writeRC = cmdBytes.withUnsafeBytes { ptr -> Int32 in
    libusb_bulk_transfer(
      handle, c.bulkOut,
      UnsafeMutablePointer(mutating: ptr.baseAddress!.assumingMemoryBound(to: UInt8.self)),
      Int32(cmdBytes.count), &sent, timeoutMs
    )
  }
  if writeRC != 0 || sent != cmdBytes.count {
    if debug { print("   [ProbeLadder] GetStorageIDs write failed: rc=\(writeRC) sent=\(sent)") }
    drainBulkIn(handle: handle, ep: c.bulkIn)
    return false
  }

  // Read response (we expect Data container with storage IDs, then Response)
  var readBuf = [UInt8](repeating: 0, count: 1024)
  var got: Int32 = 0
  let deadline = DispatchTime.now().uptimeNanoseconds + UInt64(timeoutMs) * 1_000_000
  var accumulator = Data()

  while DispatchTime.now().uptimeNanoseconds < deadline {
    let remaining = (deadline - DispatchTime.now().uptimeNanoseconds) / 1_000_000
    let readRC = libusb_bulk_transfer(
      handle, c.bulkIn, &readBuf, Int32(readBuf.count), &got,
      UInt32(min(remaining, UInt64(timeoutMs))))

    guard readRC == 0 && got > 0 else {
      break
    }
    accumulator.append(contentsOf: readBuf[0..<Int(got)])

    // Check for Response container
    if accumulator.count >= PTPHeader.size {
      let hdr = accumulator.withUnsafeBytes { PTPHeader.decode(from: $0.baseAddress!) }
      if hdr.type == 3 {
        // Response received - check if successful (0x2001) or at least we got a response
        if debug {
          print(
            "   [ProbeLadder] GetStorageIDs response code=0x\(String(format: "%04x", hdr.code))")
        }
        // Consider it a success if we got any response (some devices return different codes)
        return hdr.code == 0x2001 || (hdr.code & 0x2000) == 0x2000
      }
    }
  }

  drainBulkIn(handle: handle, ep: c.bulkIn)
  return false
}

/// Send a sessionless GetDeviceInfo (0x1001) to validate the interface works.
///
/// Uses a non-zero txid and reads until the matching Response container is seen,
/// ensuring the PTP transaction is fully completed. This prevents leaving the
/// device mid-transaction, which would wedge subsequent bulk transfers.
///
/// Returns (success, cached raw device-info bytes).
func probeCandidate(handle: OpaquePointer, _ c: InterfaceCandidate, timeoutMs: UInt32 = 2000) -> (
  Bool, Data?
) {
  let debug = ProcessInfo.processInfo.environment["SWIFTMTP_DEBUG"] == "1"

  _ = libusb_clear_halt(handle, c.bulkIn)
  _ = libusb_clear_halt(handle, c.bulkOut)

  // CRITICAL: Add delay after clear_halt before first bulk write.
  // Some devices (especially Pixel) need time for the endpoint to become writable after reset.
  // This is distinct from postClaimStabilizeMs which happens during claim.
  // Try 2000ms for Pixel 7 - devices with "UI says File transfer, USB stack still waking up"
  let preFirstCommandDelayMs = 2000  // 2000ms - adjust per-device if needed
  if debug {
    print("   [Probe] waiting \(preFirstCommandDelayMs)ms after clear_halt before first command")
  }
  usleep(UInt32(preFirstCommandDelayMs) * 1000)

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

  // Special handling for sent=0 timeouts - this indicates the endpoint is not accepting writes
  // This is a distinct failure mode from partial writes (sent > 0 but < expected)
  // LIBUSB_ERROR_TIMEOUT = -7
  if sent == 0 && writeRC == -7 {
    if debug {
      print("   [Probe] WARNING: sent=0 timeout - endpoint not accepting writes!")
      print(
        "   [Probe] This may indicate: wrong alt setting, device not ready, or host interference")
    }
    // Drain any pending data and try to recover
    drainBulkIn(handle: handle, ep: c.bulkIn)
    return (false, nil)
  }

  guard writeRC == 0, sent == cmdBytes.count else {
    drainBulkIn(handle: handle, ep: c.bulkIn)
    return (false, nil)
  }

  // Read until we see a Response container (type=3) for our txid.
  // We may get: Data container (type=2) then Response, or just Response.
  // Use a Data accumulator to handle partial containers across bulk reads.
  var deviceInfoData: Data? = nil
  var sawResponse = false
  var responseOK = false
  let deadline = DispatchTime.now().uptimeNanoseconds + UInt64(timeoutMs) * 1_000_000
  var readBuf = [UInt8](repeating: 0, count: 64 * 1024)
  var accumulator = Data()

  while !sawResponse && DispatchTime.now().uptimeNanoseconds < deadline {
    var got: Int32 = 0
    let remaining = (deadline - DispatchTime.now().uptimeNanoseconds) / 1_000_000
    let readTimeout = UInt32(min(remaining, UInt64(timeoutMs)))
    let readRC = libusb_bulk_transfer(
      handle, c.bulkIn, &readBuf, Int32(readBuf.count), &got, readTimeout)

    if debug {
      print("   [Probe] read rc=\(readRC) got=\(got) accum=\(accumulator.count)")
    }

    guard readRC == 0, got > 0 else {
      // Timeout or error — drain and bail
      drainBulkIn(handle: handle, ep: c.bulkIn)
      return (false, nil)
    }

    accumulator.append(contentsOf: readBuf[0..<Int(got)])

    // Parse complete container(s) from the accumulator.
    while accumulator.count >= PTPHeader.size {
      let hdr: PTPHeader = accumulator.withUnsafeBytes { PTPHeader.decode(from: $0.baseAddress!) }
      let containerLen = max(Int(hdr.length), PTPHeader.size)

      // Wait for more data if the container isn't fully received yet
      guard accumulator.count >= containerLen else { break }

      if debug {
        print(
          String(
            format: "   [Probe] container type=%d code=0x%04x txid=%u len=%u",
            hdr.type, hdr.code, hdr.txid, hdr.length))
      }

      if hdr.type == 2 && hdr.txid == probeTxid {
        // Data container — extract device info payload
        let payloadStart = PTPHeader.size
        let payloadEnd = Int(hdr.length)
        if payloadEnd > payloadStart {
          deviceInfoData = accumulator.subdata(in: payloadStart..<payloadEnd)
        }
      } else if hdr.type == 3 && hdr.txid == probeTxid {
        // Response container — transaction is complete
        sawResponse = true
        responseOK = (hdr.code == 0x2001)
        accumulator.removeFirst(containerLen)
        break
      } else if hdr.type == 2 || hdr.type == 3 {
        if debug { print("   [Probe] skipping stale container type=\(hdr.type) txid=\(hdr.txid)") }
      }

      accumulator.removeFirst(containerLen)
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
      let length = UInt16(statusBuf[0]) | (UInt16(statusBuf[1]) << 8)
      let code = UInt16(statusBuf[2]) | (UInt16(statusBuf[3]) << 8)
      if debug { print(String(format: "   [Ready] GetDeviceStatus len=%u → 0x%04x", length, code)) }
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
  let probeStep: String?
}

/// Try to claim and probe each candidate in order. Returns the first that succeeds.
/// Uses probe ladder for vendor-specific interfaces (class 0xff like Samsung).
func tryProbeAllCandidates(
  handle: OpaquePointer,
  device: OpaquePointer,
  candidates: [InterfaceCandidate],
  handshakeTimeoutMs: Int,
  postClaimStabilizeMs: Int,
  postProbeStabilizeMs: Int,
  debug: Bool
) -> ProbeAllResult {
  var lastProbeStep: String?

  for candidate in candidates {
    let start = DispatchTime.now()
    let isVendorSpecific = candidate.ifaceClass == 0xff

    if debug {
      print(
        String(
          format: "   [Probe] Trying interface %d (score=%d, class=0x%02x) %@",
          candidate.ifaceNumber, candidate.score, candidate.ifaceClass,
          isVendorSpecific ? "(vendor-specific, using ladder)" : ""))
    }

    do {
      try claimCandidate(
        handle: handle, device: device, candidate, postClaimStabilizeMs: postClaimStabilizeMs)
    } catch {
      if debug { print("   [Probe] Claim failed: \(error)") }
      continue
    }

    // Use the same ladder for canonical and vendor-specific interfaces.
    // Pixel-class devices can require OpenSession-first probing.
    let probeResult = probeCandidateWithLadder(
      handle: handle, candidate,
      timeoutMs: UInt32(handshakeTimeoutMs),
      debug: debug,
      includeStorageProbe: isVendorSpecific
    )
    lastProbeStep = probeResult.stepAttempted

    let elapsed = Int((DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000)

    if probeResult.succeeded {
      if debug {
        print(
          String(
            format: "   [Probe] Interface %d OK (%@) in %dms",
            candidate.ifaceNumber, probeResult.stepAttempted, elapsed))
      }
      return ProbeAllResult(
        candidate: candidate,
        cachedDeviceInfo: probeResult.cachedDeviceInfoData,
        probeStep: probeResult.stepAttempted
      )
    } else {
      if debug {
        print(
          String(
            format: "   [Probe] Interface %d failed (%@) in %dms, trying next...",
            candidate.ifaceNumber, probeResult.stepAttempted, elapsed))
      }
      releaseCandidate(handle: handle, candidate)
    }
  }
  return ProbeAllResult(candidate: nil, cachedDeviceInfo: nil, probeStep: lastProbeStep)
}
