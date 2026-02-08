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

  // Hard exclude ADB interfaces (class 0xff with subclass 0x42 or name contains ADB)
  if (interfaceClass == 0xFF && interfaceSubclass == 0x42) || nameLooksLikeADB(interfaceName) {
    return MTPInterfaceHeuristic(isCandidate: false, score: Int.min)
  }

  var score = 0
  let name = interfaceName.lowercased()

  // Canonical MTP/PTP interface (class 0x06).
  // Score hierarchy:
  // - 0x06/0x01/* = canonical MTP/PTP (highest priority)
  // - 0x06/*/* = other Still Image or vendor subclasses
  // - 0xFF/*/* = vendor-specific (lower than canonical)
  // - 0x08/*/* = mass storage (deprioritized when MTP exists)
  if interfaceClass == 0x06 && interfaceSubclass == 0x01 {
    score += 100
  } else if interfaceClass == 0x06 {
    score += 65
  }

  // Vendor-specific Android stacks often expose MTP on class 0xFF.
  // These are acceptable but scored lower than canonical MTP.
  if interfaceClass == 0xFF {
    if nameLooksLikeMTP(name) {
      score += 80
    } else if endpoints.evtIn != 0 {
      // Event endpoint + bulk pair is a strong MTP signal.
      score += 62
    }
  }

  // Deprioritize mass storage interfaces (class 0x08) when MTP exists.
  // Mass storage is valid for USB storage devices but not for MTP file transfer.
  if interfaceClass == 0x08 {
    // Only include as candidate if no better MTP interface is likely available
    // Mass storage gets a very low score to ensure MTP interfaces win
    score -= 50
  }

  // Bonus for MTP/PTP in interface name
  if name.contains("ptp") || name.contains("mtp") { score += 15 }
  if interfaceProtocol == 0x01 { score += 5 }
  if endpoints.evtIn != 0 { score += 5 }

  let isCandidate = score >= 60
  return MTPInterfaceHeuristic(isCandidate: isCandidate, score: score)
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
      let name = getAsciiString(handle, alt.iInterface).lowercased()
      let heuristic = evaluateMTPInterfaceCandidate(
        interfaceClass: alt.bInterfaceClass,
        interfaceSubclass: alt.bInterfaceSubClass,
        interfaceProtocol: alt.bInterfaceProtocol,
        endpoints: eps,
        interfaceName: name
      )
      guard heuristic.isCandidate else { continue }

      candidates.append(InterfaceCandidate(
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
    return 1 // Safe default
  }
  let value = Int32(cfg.pointee.bConfigurationValue)
  libusb_free_config_descriptor(cfgPtr)
  return value
}

/// Set USB configuration only if needed (current != target), or if `force` is true.
func setConfigurationIfNeeded(handle: OpaquePointer, device: OpaquePointer, force: Bool = false, debug: Bool) {
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

/// Probe ladder: try sessionless GetDeviceInfo, then OpenSession+GetDeviceInfo, then GetStorageIDs.
/// Returns (success, cached raw device-info bytes) and which step succeeded.
func probeCandidateWithLadder(handle: OpaquePointer, _ c: InterfaceCandidate, timeoutMs: UInt32 = 2000, debug: Bool = false) -> ProbeLadderResult {
  // Step 1: Sessionless GetDeviceInfo (original behavior)
  if debug { print("   [ProbeLadder] Step 1: sessionless GetDeviceInfo") }
  let (step1OK, infoData) = probeCandidate(handle: handle, c, timeoutMs: timeoutMs)
  if step1OK {
    return ProbeLadderResult(succeeded: true, cachedDeviceInfoData: infoData, stepAttempted: "sessionlessGetDeviceInfo")
  }

  // Step 2: OpenSession then GetDeviceInfo
  if debug { print("   [ProbeLadder] Step 2: OpenSession + GetDeviceInfo") }
  if probeOpenSession(handle: handle, c, timeoutMs: timeoutMs, debug: debug) {
    let (step2OK, infoData2) = probeCandidate(handle: handle, c, timeoutMs: timeoutMs)
    if step2OK {
      return ProbeLadderResult(succeeded: true, cachedDeviceInfoData: infoData2, stepAttempted: "openSessionThenGetDeviceInfo")
    }
  }

  // Step 3: GetStorageIDs (some devices respond to this even if DeviceInfo fails)
  if debug { print("   [ProbeLadder] Step 3: GetStorageIDs") }
  if probeGetStorageIDs(handle: handle, c, timeoutMs: timeoutMs, debug: debug) {
    // Even without device info, consider this a successful probe for vendor-specific stacks
    return ProbeLadderResult(succeeded: true, cachedDeviceInfoData: nil, stepAttempted: "getStorageIDs")
  }

  return ProbeLadderResult(succeeded: false, cachedDeviceInfoData: nil, stepAttempted: "none")
}

/// Send OpenSession (0x1002) to establish an MTP session.
func probeOpenSession(handle: OpaquePointer, _ c: InterfaceCandidate, timeoutMs: UInt32, debug: Bool) -> Bool {
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

  // Read response
  var readBuf = [UInt8](repeating: 0, count: 64)
  var got: Int32 = 0
  let readRC = libusb_bulk_transfer(handle, c.bulkIn, &readBuf, Int32(readBuf.count), &got, timeoutMs)
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
func probeGetStorageIDs(handle: OpaquePointer, _ c: InterfaceCandidate, timeoutMs: UInt32, debug: Bool) -> Bool {
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
    let readRC = libusb_bulk_transfer(handle, c.bulkIn, &readBuf, Int32(readBuf.count), &got, UInt32(min(remaining, UInt64(timeoutMs))))

    if readRC == 0 && got > 0 {
      accumulator.append(contentsOf: readBuf[0..<Int(got)])

      // Check for Response container
      if accumulator.count >= PTPHeader.size {
        let hdr = accumulator.withUnsafeBytes { PTPHeader.decode(from: $0.baseAddress!) }
        if hdr.type == 3 {
          // Response received - check if successful (0x2001) or at least we got a response
          if debug { print("   [ProbeLadder] GetStorageIDs response code=0x\(String(format: "%04x", hdr.code))") }
          // Consider it a success if we got any response (some devices return different codes)
          return hdr.code == 0x2001 || (hdr.code & 0x2000) == 0x2000
        }
      }
    } else {
      break
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
    let readRC = libusb_bulk_transfer(handle, c.bulkIn, &readBuf, Int32(readBuf.count), &got, readTimeout)

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
        print(String(format: "   [Probe] container type=%d code=0x%04x txid=%u len=%u",
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
  let selectionReason: String?
  let skippedAlternatives: [SkippedInterface]
}

/// Try to claim and probe each candidate in order. Returns the first that succeeds.
/// Uses probe ladder for vendor-specific interfaces (class 0xff like Samsung).
/// Records skipped alternatives and selection reason for diagnostics.
func tryProbeAllCandidates(
  handle: OpaquePointer,
  device: OpaquePointer,
  candidates: [InterfaceCandidate],
  handshakeTimeoutMs: Int,
  postClaimStabilizeMs: Int,
  debug: Bool
) -> ProbeAllResult {
  var skippedAlternatives: [SkippedInterface] = []
  
  for candidate in candidates {
    let start = DispatchTime.now()
    let isVendorSpecific = candidate.ifaceClass == 0xff
    let isMassStorage = candidate.ifaceClass == 0x08
    
    if debug {
      print(String(format: "   [Probe] Trying interface %d (score=%d, class=0x%02x) %@",
                   candidate.ifaceNumber, candidate.score, candidate.ifaceClass,
                   isVendorSpecific ? "(vendor-specific, using ladder)" : ""))
    }

    do {
      try claimCandidate(handle: handle, device: device, candidate, postClaimStabilizeMs: postClaimStabilizeMs)
    } catch {
      if debug { print("   [Probe] Claim failed: \(error)") }
      // Record as skipped due to claim failure
      skippedAlternatives.append(SkippedInterface(
        interfaceNumber: Int(candidate.ifaceNumber),
        interfaceClass: candidate.ifaceClass,
        interfaceSubclass: candidate.ifaceSubclass,
        interfaceProtocol: candidate.ifaceProtocol,
        score: candidate.score,
        reason: "claim failed: \(error)"
      ))
      continue
    }

    let probeResult: ProbeLadderResult
    if isVendorSpecific {
      // Use probe ladder for vendor-specific interfaces (Samsung, etc.)
      probeResult = probeCandidateWithLadder(
        handle: handle, candidate,
        timeoutMs: UInt32(handshakeTimeoutMs),
        debug: debug
      )
    } else {
      // Use standard probe for canonical MTP interfaces
      let (ok, info) = probeCandidate(
        handle: handle, candidate, timeoutMs: UInt32(handshakeTimeoutMs)
      )
      probeResult = ProbeLadderResult(
        succeeded: ok,
        cachedDeviceInfoData: info,
        stepAttempted: ok ? "sessionlessGetDeviceInfo" : "none"
      )
    }

    let elapsed = Int((DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000)

    if probeResult.succeeded {
      if debug {
        print(String(format: "   [Probe] Interface %d OK (%@) in %dms",
                     candidate.ifaceNumber, probeResult.stepAttempted, elapsed))
      }
      
      // Generate selection reason
      let selectionReason: String
      if isVendorSpecific {
        selectionReason = "vendor-specific (class=0xFF) accepted via probe ladder"
      } else if candidate.ifaceClass == 0x06 && candidate.ifaceSubclass == 0x01 {
        selectionReason = "canonical MTP/PTP (class=0x06, subclass=0x01)"
      } else if candidate.ifaceClass == 0x06 {
        selectionReason = "MTP-like (class=0x06, subclass=0x\(String(format: "%02x", candidate.ifaceSubclass)))"
      } else {
        selectionReason = "selected by score (score=\(candidate.score))"
      }
      
      return ProbeAllResult(
        candidate: candidate,
        cachedDeviceInfo: probeResult.cachedDeviceInfoData,
        probeStep: probeResult.stepAttempted,
        selectionReason: selectionReason,
        skippedAlternatives: skippedAlternatives
      )
    } else {
      if debug {
        print(String(format: "   [Probe] Interface %d failed (%@) in %dms, trying next...",
                     candidate.ifaceNumber, probeResult.stepAttempted, elapsed))
      }
      // Record as skipped due to probe failure
      skippedAlternatives.append(SkippedInterface(
        interfaceNumber: Int(candidate.ifaceNumber),
        interfaceClass: candidate.ifaceClass,
        interfaceSubclass: candidate.ifaceSubclass,
        interfaceProtocol: candidate.ifaceProtocol,
        score: candidate.score,
        reason: "probe \(probeResult.stepAttempted ?? "unknown") failed"
      ))
      releaseCandidate(handle: handle, candidate)
    }
  }
  
  // Generate reason for why no candidate succeeded
  let failureReason: String
  if candidates.isEmpty {
    failureReason = "no MTP-capable interfaces found"
  } else if skippedAlternatives.isEmpty {
    failureReason = "all candidates failed"
  } else {
    let vendorSkipped = skippedAlternatives.filter { $0.interfaceClass == 0xff }.count
    let massSkipped = skippedAlternatives.filter { $0.interfaceClass == 0x08 }.count
    failureReason = "\(skippedAlternatives.count) candidate(s) failed (\(vendorSkipped) vendor-specific, \(massSkipped) mass storage)"
  }
  
  return ProbeAllResult(
    candidate: nil,
    cachedDeviceInfo: nil,
    probeStep: nil,
    selectionReason: "failed: \(failureReason)",
    skippedAlternatives: skippedAlternatives
  )
}
