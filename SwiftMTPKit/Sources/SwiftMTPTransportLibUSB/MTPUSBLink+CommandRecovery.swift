// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import CLibusb
import Foundation
import OSLog
import SwiftMTPCore
import SwiftMTPObservability

private let log = MTPLog.transport

// MARK: - Command Write Recovery

extension MTPUSBLink {

  struct CommandWriteAttempt {
    let rc: Int32
    let sent: Int32
    let expected: Int32

    var succeeded: Bool { rc == 0 && sent == expected }
    var isNoProgressTimeout: Bool {
      MTPUSBLink.shouldRecoverNoProgressTimeout(rc: rc, sent: sent)
    }
  }

  func attemptCommandWrite(_ bytes: [UInt8], timeout: UInt32) -> CommandWriteAttempt {
    var sent: Int32 = 0
    let rc = bytes.withUnsafeBytes { ptr -> Int32 in
      libusb_bulk_transfer(
        h, outEP,
        UnsafeMutablePointer(
          mutating: ptr.baseAddress!.assumingMemoryBound(to: UInt8.self)),
        Int32(bytes.count), &sent, timeout)
    }
    return CommandWriteAttempt(rc: rc, sent: sent, expected: Int32(bytes.count))
  }

  func throwCommandWriteFailure(_ attempt: CommandWriteAttempt, context: String) throws {
    if attempt.rc == 0, attempt.sent != attempt.expected {
      log.error(
        "Short write: sent=\(attempt.sent)/\(attempt.expected) — \(context, privacy: .public)"
      )
      throw MTPError.transport(
        .io("\(context): short write sent=\(attempt.sent)/\(attempt.expected)"))
    }
    if attempt.isNoProgressTimeout {
      if isPixelClassNoProgressTarget {
        // Pixel 7 / macOS 26 specific: bulk OUT stalled with no bytes written.
        // Root cause: macOS does not expose MTP IOUSBInterface children for this device
        // when USB mode or developer options are not fully configured on the phone.
        log.error("Pixel 7 no-progress timeout: bulk OUT stalled (rc=\(attempt.rc))")
        throw MTPError.transport(
          .io(
            "\(context): Google Pixel 7 — bulk OUT timeout, no bytes sent (rc=\(attempt.rc)). "
              + "Action: on the phone, enable Developer Options → USB Debugging, "
              + "set USB Preferences to 'File Transfer' (not 'Charging only'), "
              + "and tap 'Allow' on the 'Trust this computer?' prompt. "
              + "Then unplug and replug the cable. "
              + "If the problem persists, verify ioreg shows IOUSBInterface children for VID 18D1:4EE1."
          ))
      }
      log.error("No-progress timeout: sent=0 rc=\(attempt.rc) — \(context, privacy: .public)")
      throw MTPError.transport(
        .io("\(context): command-phase timeout with no progress (sent=0)"))
    }
    log.error("Bulk write failed: rc=\(attempt.rc) — \(context, privacy: .public)")
    throw MTPError.transport(mapLibusb(attempt.rc))
  }

  var isPixelClassNoProgressTarget: Bool {
    vendorID == 0x18D1 && productID == 0x4EE1
  }

  var skipPixelClassResetControlTransfer: Bool {
    isPixelClassNoProgressTarget
      && ProcessInfo.processInfo.environment["SWIFTMTP_PIXEL_SKIP_CLASS_RESET"] == "1"
  }

  private var allowPixelCommandResetRecovery: Bool {
    ProcessInfo.processInfo.environment["SWIFTMTP_PIXEL_DISABLE_COMMAND_RESET"] != "1"
  }

  private var shouldSkipPixelCommandResetRecovery: Bool {
    isPixelClassNoProgressTarget
      && ProcessInfo.processInfo.environment["SWIFTMTP_PIXEL_DISABLE_COMMAND_RESET"] == "1"
  }

  private func shouldAttemptPixelResetReopenRecovery(after attempt: CommandWriteAttempt) -> Bool {
    isPixelClassNoProgressTarget && allowPixelCommandResetRecovery && attempt.isNoProgressTimeout
  }

  /// Three-rung escalating recovery for command-phase write failures.
  ///
  /// When a bulk OUT transfer times out with zero bytes sent (no-progress), the
  /// endpoint is likely in a HALT or wedged state. This method attempts recovery
  /// through progressively more disruptive actions:
  ///
  /// **Rung 1 – Light recovery**: Clear HALT on all endpoints, re-assert alt-setting,
  /// send PTP class reset. Fixes most transient stalls from prior session cleanup.
  ///
  /// **Rung 2 – Reset+reopen** (Pixel 7 only, opt-in): Full `libusb_reset_device`,
  /// close the old handle, re-enumerate the device on the same bus/port, and re-claim.
  /// Needed when macOS host controller loses track of endpoint state.
  ///
  /// **Rung 3 – Hard recovery**: `libusb_reset_device` in-place without re-enumeration,
  /// then re-assert configuration and clear endpoints. Last resort before failing.
  func writeCommandContainerWithRecovery(
    _ bytes: [UInt8], opcode: UInt16, txid: UInt32, timeout: UInt32, debug: Bool
  ) throws {
    let initialAttempt = attemptCommandWrite(bytes, timeout: timeout)
    if initialAttempt.succeeded { return }
    guard initialAttempt.isNoProgressTimeout else {
      try throwCommandWriteFailure(initialAttempt, context: "command write failed")
      return
    }

    if debug {
      print(
        String(
          format:
            "   [USB][Recover] op=0x%04x tx=%u no-progress timeout detected (rc=%d sent=%d), running light rung",
          opcode, txid, initialAttempt.rc, initialAttempt.sent))
    }
    _ = performCommandNoProgressLightRecovery(opcode: opcode, txid: txid, debug: debug)
    let lightRetry = attemptCommandWrite(bytes, timeout: timeout)
    if lightRetry.succeeded {
      if debug {
        print(
          String(
            format:
              "   [USB][Recover] op=0x%04x tx=%u recovered after light rung",
            opcode, txid))
      }
      return
    }

    if shouldAttemptPixelResetReopenRecovery(after: lightRetry) {
      if debug {
        print(
          String(
            format:
              "   [USB][Recover] op=0x%04x tx=%u light rung still no-progress (rc=%d sent=%d), running reset+reopen rung",
            opcode, txid, lightRetry.rc, lightRetry.sent))
      }
      if performCommandNoProgressResetReopenRecovery(opcode: opcode, txid: txid, debug: debug) {
        _ = performCommandNoProgressLightRecovery(opcode: opcode, txid: txid, debug: debug)
        let reopenRetry = attemptCommandWrite(bytes, timeout: timeout)
        if reopenRetry.succeeded {
          if debug {
            print(
              String(
                format:
                  "   [USB][Recover] op=0x%04x tx=%u recovered after reset+reopen rung",
                opcode, txid))
          }
          return
        }
        try throwCommandWriteFailure(
          reopenRetry, context: "command write failed after reset+reopen recovery")
        return
      }
      try throwCommandWriteFailure(
        lightRetry, context: "command write failed after reset+reopen recovery")
      return
    }

    if debug {
      print(
        String(
          format:
            "   [USB][Recover] op=0x%04x tx=%u light rung did not recover (rc=%d sent=%d), running hard rung",
          opcode, txid, lightRetry.rc, lightRetry.sent))
    }
    guard performCommandNoProgressHardRecovery(opcode: opcode, txid: txid, debug: debug) else {
      try throwCommandWriteFailure(lightRetry, context: "command write failed after light recovery")
      return
    }
    let hardRetry = attemptCommandWrite(bytes, timeout: timeout)
    if hardRetry.succeeded {
      if debug {
        print(
          String(
            format:
              "   [USB][Recover] op=0x%04x tx=%u recovered after hard rung",
            opcode, txid))
      }
      return
    }

    try throwCommandWriteFailure(
      hardRetry, context: "command write failed after recovery rungs")
  }

  /// Light recovery rung: clear endpoint HALT, re-assert alt-setting, PTP class reset.
  ///
  /// Sequence rationale:
  /// 1. `clear_halt` on all endpoints — reset data toggles per USB 2.0 §9.4.5
  /// 2. PTP class reset (0x66) — tells the device to abandon any in-progress transaction
  /// 3. `set_configuration` + `set_interface_alt_setting(0)` — forces macOS to
  ///    tear down and rebuild endpoint pipes at the host controller level
  /// 4. Post-clear on endpoints — ensures pipes are clean after alt-setting change
  /// 5. 200ms settle — allows host controller DMA ring buffer reconfiguration
  @discardableResult
  func performCommandNoProgressLightRecovery(opcode: UInt16, txid: UInt32, debug: Bool)
    -> Bool
  {
    log.debug(
      "Light recovery: clearing endpoints and re-asserting alt-setting (op=\(String(format: "0x%04x", opcode)))"
    )
    // Diagnostic: log endpoint status before clearing (Fix 6 from analysis)
    logEndpointStatus(context: "pre-recovery", debug: debug)
    let clearOutRC = libusb_clear_halt(h, outEP)
    let clearInRC = libusb_clear_halt(h, inEP)
    let clearEventRC: Int32 =
      evtEP != 0 ? libusb_clear_halt(h, evtEP) : Int32(LIBUSB_SUCCESS.rawValue)
    let skipClassReset = skipPixelClassResetControlTransfer
    let classResetRC: Int32 =
      skipClassReset
      ? Int32(LIBUSB_SUCCESS.rawValue)
      : libusb_control_transfer(h, 0x21, 0x66, 0, UInt16(iface), nil, 0, 2000)

    setConfigurationIfNeeded(handle: h, device: dev, force: true, debug: debug)
    let setAltRC = libusb_set_interface_alt_setting(h, Int32(iface), 0)

    let clearOutPostRC = libusb_clear_halt(h, outEP)
    let clearInPostRC = libusb_clear_halt(h, inEP)
    let clearEventPostRC: Int32 =
      evtEP != 0 ? libusb_clear_halt(h, evtEP) : Int32(LIBUSB_SUCCESS.rawValue)

    usleep(200_000)

    if debug {
      print(
        String(
          format:
            "   [USB][Recover][Light] op=0x%04x tx=%u clear(out=%d in=%d evt=%d) classReset=%d skipClassReset=%@ setAlt0=%d postClear(out=%d in=%d evt=%d)",
          opcode, txid, clearOutRC, clearInRC, clearEventRC, classResetRC,
          skipClassReset ? "true" : "false", setAltRC,
          clearOutPostRC, clearInPostRC, clearEventPostRC))
    }
    return true
  }

  /// Hard recovery rung: full USB device reset followed by handle close/re-open.
  ///
  /// `libusb_reset_device` causes the host to issue a USB bus reset signal, which
  /// forces the device firmware to re-initialize its USB stack. After reset, the old
  /// handle is stale on macOS/Darwin — libmtp always does a full close → re-open
  /// cycle to obtain a fresh handle with valid IOKit resources.
  ///
  /// 350ms post-reset delay: USB 2.0 spec requires devices to be ready within 10ms
  /// of reset completion, but Android MTP implementations (Samsung, Xiaomi, Pixel)
  /// take 100-250ms to re-initialize their MTP responder. 350ms provides margin.
  /// 200ms post-claim delay: allows host controller pipe setup after re-claim.
  private func performCommandNoProgressHardRecovery(opcode: UInt16, txid: UInt32, debug: Bool)
    -> Bool
  {
    if shouldSkipPixelCommandResetRecovery {
      if debug {
        print(
          String(
            format:
              "   [USB][Recover][Hard] op=0x%04x tx=%u skipping reset rung (set SWIFTMTP_PIXEL_DISABLE_COMMAND_RESET=0 or unset to re-enable)",
            opcode, txid))
      }
      return false
    }

    // Cancel event pump to avoid reads on stale handle during close/reopen.
    eventPumpTask?.cancel()
    eventPumpTask = nil

    let oldHandle = h
    let oldDevice = dev

    let oldBus = libusb_get_bus_number(oldDevice)
    var oldPortPath = [UInt8](repeating: 0, count: 7)
    let oldPortDepth = libusb_get_port_numbers(oldDevice, &oldPortPath, Int32(oldPortPath.count))

    let resetRC = libusb_reset_device(oldHandle)
    if resetRC != 0 && resetRC != Int32(LIBUSB_ERROR_NOT_FOUND.rawValue) {
      log.error(
        "Hard recovery: libusb_reset_device failed \(libusbErrorName(resetRC), privacy: .public) (rc=\(resetRC)) for op=\(String(format: "0x%04x", opcode), privacy: .public)"
      )
      if debug {
        print(
          String(
            format:
              "   [USB][Recover][Hard] op=0x%04x tx=%u reset_device failed rc=%d",
            opcode, txid, resetRC))
      }
      return false
    }

    // libmtp compat: clear_stall before release (check+clear endpoints)
    recoverStall()

    // Full close/re-open per libmtp recovery sequence (Difference 1 fix).
    // Release interface first, then attempt to find + open + claim a new handle.
    // Keep old handle open until new one is ready for safe fallback.
    let releaseRC = libusb_release_interface(oldHandle, Int32(iface))

    // forceDoubleReset: second libusb_reset_device after release, matching
    // libmtp's FORCE_RESET_ON_CLOSE. Triggers a second USBDeviceReEnumerate
    // on Darwin to fully flush IOKit pipe state for FunctionFS devices.
    var resetRC2: Int32 = 0
    if config.forceDoubleReset {
      resetRC2 = libusb_reset_device(oldHandle)
      if debug {
        print(
          String(
            format:
              "   [USB][Recover][Hard] op=0x%04x tx=%u forceDoubleReset: 2nd reset rc=%d",
            opcode, txid, resetRC2))
      }
    }

    usleep(350_000)

    guard
      let reopenedDevice = findRecoveryDevice(
        bus: oldBus,
        address: libusb_get_device_address(oldDevice),
        portPath: oldPortPath,
        portDepth: oldPortDepth
      ),
      let reopenedHandle = openAndClaimRecoveryHandle(device: reopenedDevice, debug: debug)
    else {
      // Reopen failed — try to reclaim on old handle as fallback.
      let reclaimRC = libusb_claim_interface(oldHandle, Int32(iface))
      if reclaimRC == 0 {
        _ = libusb_set_interface_alt_setting(oldHandle, Int32(iface), 0)
      }
      if debug {
        print(
          String(
            format:
              "   [USB][Recover][Hard] op=0x%04x tx=%u close/reopen failed (reset=%d release=%d reclaim=%d)",
            opcode, txid, resetRC, releaseRC, reclaimRC))
      }
      return false
    }

    h = reopenedHandle
    dev = reopenedDevice

    libusb_close(oldHandle)
    libusb_unref_device(oldDevice)
    usleep(200_000)

    if debug {
      print(
        String(
          format:
            "   [USB][Recover][Hard] op=0x%04x tx=%u reset=%d release=%d reopened iface=%d",
          opcode, txid, resetRC, releaseRC, iface))
    }
    return true
  }

  private func performCommandNoProgressResetReopenRecovery(
    opcode: UInt16,
    txid: UInt32,
    debug: Bool
  ) -> Bool {
    if shouldSkipPixelCommandResetRecovery {
      if debug {
        print(
          String(
            format:
              "   [USB][Recover][Reopen] op=0x%04x tx=%u skipping reset+reopen (set SWIFTMTP_PIXEL_DISABLE_COMMAND_RESET=0 or unset to re-enable)",
            opcode, txid))
      }
      return false
    }

    // Ensure no concurrent event reads are still using the old handle.
    eventPumpTask?.cancel()
    eventPumpTask = nil

    let oldHandle = h
    let oldDevice = dev

    let oldBus = libusb_get_bus_number(oldDevice)
    let oldAddress = libusb_get_device_address(oldDevice)
    var oldPortPath = [UInt8](repeating: 0, count: 7)
    let oldPortDepth = libusb_get_port_numbers(oldDevice, &oldPortPath, Int32(oldPortPath.count))

    let resetRC = libusb_reset_device(oldHandle)
    recoverStall()  // libmtp compat: clear_stall before release
    let releaseRC = libusb_release_interface(oldHandle, Int32(iface))

    // forceDoubleReset: second reset after release (libmtp FORCE_RESET_ON_CLOSE)
    var resetRC2: Int32 = 0
    if config.forceDoubleReset {
      resetRC2 = libusb_reset_device(oldHandle)
      if debug {
        print(
          String(
            format:
              "   [USB][Recover][Reopen] op=0x%04x tx=%u forceDoubleReset: 2nd reset rc=%d",
            opcode, txid, resetRC2))
      }
    }

    guard
      let reopenedDevice = findRecoveryDevice(
        bus: oldBus,
        address: oldAddress,
        portPath: oldPortPath,
        portDepth: oldPortDepth
      ),
      let reopenedHandle = openAndClaimRecoveryHandle(device: reopenedDevice, debug: debug)
    else {
      let reclaimRC = libusb_claim_interface(oldHandle, Int32(iface))
      if reclaimRC == 0 {
        _ = libusb_set_interface_alt_setting(oldHandle, Int32(iface), 0)
      }
      if debug {
        print(
          String(
            format:
              "   [USB][Recover][Reopen] op=0x%04x tx=%u failed to reopen (reset=%d release=%d reclaim=%d)",
            opcode, txid, resetRC, releaseRC, reclaimRC))
      }
      return false
    }

    h = reopenedHandle
    dev = reopenedDevice

    libusb_close(oldHandle)
    libusb_unref_device(oldDevice)
    usleep(200_000)

    if debug {
      print(
        String(
          format:
            "   [USB][Recover][Reopen] op=0x%04x tx=%u reset=%d release=%d reopened iface=%d",
          opcode, txid, resetRC, releaseRC, iface))
    }
    return true
  }

  private func findRecoveryDevice(
    bus: UInt8,
    address: UInt8,
    portPath: [UInt8],
    portDepth: Int32
  ) -> OpaquePointer? {
    let ctx = LibUSBContext.shared.ctx
    var list: UnsafeMutablePointer<OpaquePointer?>?
    let count = libusb_get_device_list(ctx, &list)
    guard count > 0, let list else { return nil }
    defer { libusb_free_device_list(list, 1) }

    for index in 0..<Int(count) {
      guard let device = list[index] else { continue }
      guard libusb_get_bus_number(device) == bus else { continue }

      if portDepth > 0 {
        var candidatePortPath = [UInt8](repeating: 0, count: 7)
        let candidateDepth = libusb_get_port_numbers(
          device,
          &candidatePortPath,
          Int32(candidatePortPath.count)
        )
        if candidateDepth == portDepth
          && candidatePortPath[0..<Int(candidateDepth)] == portPath[0..<Int(portDepth)]
        {
          libusb_ref_device(device)
          return device
        }
        continue
      }

      if libusb_get_device_address(device) == address {
        libusb_ref_device(device)
        return device
      }
    }
    return nil
  }

  private func openAndClaimRecoveryHandle(device: OpaquePointer, debug: Bool) -> OpaquePointer? {
    var reopenedHandle: OpaquePointer?
    guard libusb_open(device, &reopenedHandle) == 0, let reopenedHandle else {
      libusb_unref_device(device)
      return nil
    }

    _ = libusb_set_auto_detach_kernel_driver(reopenedHandle, 1)
    _ = libusb_detach_kernel_driver(reopenedHandle, Int32(iface))
    setConfigurationIfNeeded(handle: reopenedHandle, device: device, force: true, debug: debug)

    let claimRC = libusb_claim_interface(reopenedHandle, Int32(iface))
    if claimRC != 0 {
      libusb_close(reopenedHandle)
      libusb_unref_device(device)
      return nil
    }

    _ = libusb_set_interface_alt_setting(reopenedHandle, Int32(iface), 0)
    _ = libusb_clear_halt(reopenedHandle, outEP)
    _ = libusb_clear_halt(reopenedHandle, inEP)
    if evtEP != 0 {
      _ = libusb_clear_halt(reopenedHandle, evtEP)
    }

    // Drain stale data from IN endpoint after re-claim to prevent residual
    // bytes from a previous interrupted transaction from corrupting the next
    // command/response cycle.
    let savedHandle = h
    h = reopenedHandle
    drainEndpoint(inEP, debug: debug)
    h = savedHandle

    return reopenedHandle
  }
}
