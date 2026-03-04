// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import CLibusb
import OSLog
import SwiftMTPCore
import SwiftMTPObservability

private let log = MTPLog.transport

public struct LibUSBDiscovery {
  public struct USBDeviceIDs: Sendable {
    let vid: UInt16
    let pid: UInt16
    let bcdDevice: UInt16
    let ifaceClass: UInt8
    let ifaceSubclass: UInt8
    let ifaceProtocol: UInt8
    let bus: UInt8
    let address: UInt8
  }

  public static func enumerateMTPDevices() async throws -> [MTPDeviceSummary] {
    // Use a standalone libusb context to avoid initializing the shared
    // context (and its persistent event loop thread) during discovery.
    var ctx: OpaquePointer?
    guard libusb_init(&ctx) == 0, let ctx else { throw TransportError.io("libusb_init failed") }
    defer { libusb_exit(ctx) }

    var list: UnsafeMutablePointer<OpaquePointer?>?
    let cnt = libusb_get_device_list(ctx, &list)
    guard cnt >= 0 else { throw TransportError.io("libusb_get_device_list failed (rc=\(cnt))") }
    guard cnt > 0, let list else { return [] }
    defer { libusb_free_device_list(list, 1) }

    var summaries: [MTPDeviceSummary] = []
    for i in 0..<Int(cnt) {
      guard let dev = list[i] else { continue }
      var desc = libusb_device_descriptor()
      guard libusb_get_device_descriptor(dev, &desc) == 0 else { continue }

      var cfgPtr: UnsafeMutablePointer<libusb_config_descriptor>? = nil
      guard libusb_get_active_config_descriptor(dev, &cfgPtr) == 0, let cfg = cfgPtr else {
        continue
      }
      defer { libusb_free_config_descriptor(cfg) }

      var handle: OpaquePointer?
      if libusb_open(dev, &handle) != 0 { handle = nil }
      defer {
        if let h = handle { libusb_close(h) }
      }

      var isMTP = false
      for j in 0..<cfg.pointee.bNumInterfaces {
        let iface = cfg.pointee.interface[Int(j)]
        for a in 0..<iface.num_altsetting {
          let alt = iface.altsetting[Int(a)]
          let eps = findEndpoints(alt)
          let ifaceName = handle.map { getAsciiString($0, alt.iInterface) } ?? ""
          let heuristic = evaluateMTPInterfaceCandidate(
            interfaceClass: alt.bInterfaceClass,
            interfaceSubclass: alt.bInterfaceSubClass,
            interfaceProtocol: alt.bInterfaceProtocol,
            endpoints: eps,
            interfaceName: ifaceName
          )
          if heuristic.isCandidate {
            isMTP = true
            break
          }
        }
        if isMTP { break }
      }
      guard isMTP else { continue }

      let bus = libusb_get_bus_number(dev)
      let addr = libusb_get_device_address(dev)

      var manufacturer = "USB \(String(format: "%04x", desc.idVendor))"
      var model = "USB \(String(format: "%04x", desc.idProduct))"
      var serial: String? = nil

      if let h = handle {
        if desc.iManufacturer != 0 {
          var buf = [UInt8](repeating: 0, count: 128)
          let n = libusb_get_string_descriptor_ascii(h, desc.iManufacturer, &buf, Int32(buf.count))
          if n > 0 { manufacturer = String(decoding: buf.prefix(Int(n)), as: UTF8.self) }
        }
        if desc.iProduct != 0 {
          var buf = [UInt8](repeating: 0, count: 128)
          let n = libusb_get_string_descriptor_ascii(h, desc.iProduct, &buf, Int32(buf.count))
          if n > 0 { model = String(decoding: buf.prefix(Int(n)), as: UTF8.self) }
        }
        if desc.iSerialNumber != 0 {
          var buf = [UInt8](repeating: 0, count: 128)
          let n = libusb_get_string_descriptor_ascii(h, desc.iSerialNumber, &buf, Int32(buf.count))
          if n > 0 { serial = String(decoding: buf.prefix(Int(n)), as: UTF8.self) }
        }
      }

      summaries.append(
        MTPDeviceSummary(
          id: MTPDeviceID(
            raw: String(format: "%04x:%04x@%u:%u", desc.idVendor, desc.idProduct, bus, addr)),
          manufacturer: manufacturer,
          model: model,
          vendorID: desc.idVendor,
          productID: desc.idProduct,
          bus: bus,
          address: addr,
          usbSerial: serial
        ))
    }
    return summaries
  }
}

struct EPCandidates {
  var bulkIn: UInt8 = 0
  var bulkOut: UInt8 = 0
  var evtIn: UInt8 = 0
}
func findEndpoints(_ alt: libusb_interface_descriptor) -> EPCandidates {
  var eps = EPCandidates()
  for i in 0..<Int(alt.bNumEndpoints) {
    let ed = alt.endpoint[i]
    let addr = ed.bEndpointAddress, dirIn = (addr & 0x80) != 0, attr = ed.bmAttributes & 0x03
    if attr == 2 {
      if dirIn { eps.bulkIn = addr } else { eps.bulkOut = addr }
    } else if attr == 3, dirIn {
      eps.evtIn = addr
    }
  }
  return eps
}

func getAsciiString(_ handle: OpaquePointer, _ index: UInt8) -> String {
  if index == 0 { return "" }
  var buf = [UInt8](repeating: 0, count: 128)
  let n = libusb_get_string_descriptor_ascii(handle, index, &buf, Int32(buf.count))
  return n > 0 ? String(decoding: buf.prefix(Int(n)), as: UTF8.self) : ""
}

public actor LibUSBTransport: MTPTransport {
  private var activeLinks: [MTPUSBLink] = []

  public init() {}

  private static func isPixel7(vendorID: UInt16, productID: UInt16) -> Bool {
    vendorID == 0x18D1 && productID == 0x4EE1
  }

  private static func shouldSkipPixelClassResetControlTransfer(vendorID: UInt16, productID: UInt16)
    -> Bool
  {
    isPixel7(vendorID: vendorID, productID: productID)
      && ProcessInfo.processInfo.environment["SWIFTMTP_PIXEL_SKIP_CLASS_RESET"] == "1"
  }

  /// Pixel 7 is prone to disappearing from user-space after `libusb_reset_device`
  /// on macOS. Keep open-path recovery on non-reset rungs unless explicitly overridden.
  private static func shouldSkipUSBResetFallback(vendorID: UInt16, productID: UInt16) -> Bool {
    isPixel7(vendorID: vendorID, productID: productID)
      && ProcessInfo.processInfo.environment["SWIFTMTP_PIXEL_ALLOW_OPEN_RESET"] != "1"
  }

  private static func shouldAttemptNoResetReopenFallback(vendorID: UInt16, productID: UInt16)
    -> Bool
  {
    isPixel7(vendorID: vendorID, productID: productID)
      && ProcessInfo.processInfo.environment["SWIFTMTP_PIXEL_DISABLE_NO_RESET_REOPEN"] != "1"
  }

  private static func pixelNoResetReopenAttemptCount(vendorID: UInt16, productID: UInt16) -> Int {
    guard isPixel7(vendorID: vendorID, productID: productID) else { return 1 }
    if let raw = ProcessInfo.processInfo.environment["SWIFTMTP_PIXEL_NO_RESET_REOPEN_ATTEMPTS"],
      let parsed = Int(raw), parsed > 0
    {
      return min(parsed, 8)
    }
    return 4
  }

  private static func findDeviceByBusAndPort(
    ctx: OpaquePointer,
    bus: UInt8,
    portPath: [UInt8],
    portDepth: Int32
  ) -> OpaquePointer? {
    guard portDepth > 0 else { return nil }
    var list: UnsafeMutablePointer<OpaquePointer?>?
    let count = libusb_get_device_list(ctx, &list)
    guard count > 0, let list else { return nil }
    defer { libusb_free_device_list(list, 1) }

    for index in 0..<Int(count) {
      guard let device = list[index] else { continue }
      guard libusb_get_bus_number(device) == bus else { continue }
      var devicePortPath = [UInt8](repeating: 0, count: 7)
      let devicePortDepth = libusb_get_port_numbers(
        device, &devicePortPath, Int32(devicePortPath.count))
      if devicePortDepth == portDepth
        && devicePortPath[0..<Int(devicePortDepth)] == portPath[0..<Int(portDepth)]
      {
        libusb_ref_device(device)
        return device
      }
    }
    return nil
  }

  public func open(_ summary: MTPDeviceSummary, config: SwiftMTPConfig) async throws -> MTPLink {
    let debug = ProcessInfo.processInfo.environment["SWIFTMTP_DEBUG"] == "1"
    log.info(
      "Opening device: \(summary.manufacturer, privacy: .public) \(summary.model, privacy: .public) id=\(summary.id.raw, privacy: .public)"
    )
    let ctx = LibUSBContext.shared.ctx
    var devList: UnsafeMutablePointer<OpaquePointer?>?
    let cnt = libusb_get_device_list(ctx, &devList)
    guard cnt >= 0 else { throw TransportError.io("libusb_get_device_list failed (rc=\(cnt))") }
    guard cnt > 0, let devList else { throw TransportError.noDevice }
    var target: OpaquePointer?
    for i in 0..<Int(cnt) {
      let d = devList[i]!
      let bus = libusb_get_bus_number(d), addr = libusb_get_device_address(d)
      if summary.id.raw.hasSuffix(String(format: "@%u:%u", bus, addr)) {
        libusb_ref_device(d)
        target = d
        break
      }
    }
    libusb_free_device_list(devList, 1)
    guard var dev = target else { throw TransportError.noDevice }
    var h: OpaquePointer?
    guard libusb_open(dev, &h) == 0, var handle = h else {
      log.error(
        "libusb_open failed for device \(summary.id.raw, privacy: .public) — another process may hold an exclusive claim"
      )
      libusb_unref_device(dev)
      throw TransportError.accessDenied
    }

    // Get vendor/product IDs for device-specific handling
    var desc = libusb_device_descriptor()
    _ = libusb_get_device_descriptor(dev, &desc)
    let vendorID = desc.idVendor
    let productID = desc.idProduct

    // Determine if this is a vendor-specific MTP device (class 0xff)
    // Samsung, Xiaomi, and other Android devices often use vendor-specific interfaces
    var isVendorSpecificMTP = false

    // Rank MTP interface candidates from USB descriptors
    var candidates: [InterfaceCandidate]
    do {
      candidates = try rankMTPInterfaces(handle: handle, device: dev)
      // Check if any candidate is vendor-specific
      for candidate in candidates {
        if candidate.ifaceClass == 0xff {
          isVendorSpecificMTP = true
          break
        }
      }
    } catch {
      log.error(
        "Interface ranking failed for device \(summary.id.raw, privacy: .public): \(error.localizedDescription, privacy: .public)"
      )
      libusb_close(handle)
      libusb_unref_device(dev)
      throw error
    }
    guard !candidates.isEmpty else {
      log.warning(
        "No MTP interface found among USB descriptors for device \(summary.id.raw, privacy: .public). Ensure the device is set to File Transfer (MTP) mode."
      )
      libusb_close(handle)
      libusb_unref_device(dev)
      throw TransportError.io("no MTP interface found — set device to File Transfer (MTP) mode")
    }
    log.info(
      "Interface ranking complete: \(candidates.count) candidate(s) for VID=\(String(format: "%04x", vendorID), privacy: .public) PID=\(String(format: "%04x", productID), privacy: .public) vendorSpecific=\(isVendorSpecificMTP)"
    )

    let skipPixelResetByPolicy = Self.shouldSkipUSBResetFallback(
      vendorID: vendorID, productID: productID)

    // For vendor-specific devices (class 0xff), try USB reset before probing.
    // Pixel 7 is explicitly excluded by default to avoid re-enumeration collapse.
    // Samsung devices skip this entirely (skipPreClaimReset quirk) — the reset
    // eats into Samsung's ~3-second MTP session window.
    if isVendorSpecificMTP {
      if config.skipPreClaimReset {
        if debug {
          print(
            "   [Open] Skipping pre-claim reset (skipPreClaimReset quirk)"
          )
        }
      } else if skipPixelResetByPolicy {
        if debug {
          print(
            "   [Open] Vendor-specific MTP device is Pixel 7; skipping pre-claim reset (set SWIFTMTP_PIXEL_ALLOW_OPEN_RESET=1 to override)"
          )
        }
      } else {
        if debug {
          print(
            String(
              format:
                "   [Open] Vendor-specific MTP device (VID=0x%04X PID=0x%04X), attempting pre-claim reset",
              vendorID, productID))
        }
        // Attempt USB reset before claim - helps with stubborn non-Pixel devices.
        let resetRC = libusb_reset_device(handle)
        if debug {
          print(
            String(
              format: "   [Open] Pre-claim libusb_reset_device rc=%d", resetRC))
        }
      }
      // Brief pause after reset for device to stabilize.
      // 300ms: USB 2.0 spec allows 10ms, but Android devices with vendor-specific
      // MTP stacks need 100-250ms for firmware re-initialization. 300ms adds margin.
      if !skipPixelResetByPolicy && !config.skipPreClaimReset {
        usleep(300_000)
      }
    }

    // Pass 1: Normal probe (no USB reset).
    // claimCandidate uses set_configuration + set_alt_setting to reinitialize
    // endpoint pipes, which fixes stale pipe state on most devices.
    if debug { print("   [Open] Pass 1: probing \(candidates.count) candidate(s)") }

    // Use extended timeout for vendor-specific devices (class 0xff).
    // Vendor-specific MTP stacks (Samsung, Xiaomi, etc.) often initialize more
    // slowly because MTP runs atop a custom Android USB gadget driver rather than
    // the standard PTP/MTP class driver. Doubling the handshake timeout (minimum
    // 5000ms) accounts for the extra firmware initialization and USB mode switching.
    let effectiveTimeout =
      isVendorSpecificMTP ? max(config.handshakeTimeoutMs * 2, 5000) : config.handshakeTimeoutMs
    if isVendorSpecificMTP && debug {
      print(
        String(
          format: "   [Open] Using extended timeout %dms for vendor-specific device",
          effectiveTimeout))
    }

    var result = tryProbeAllCandidates(
      handle: handle, device: dev, candidates: candidates,
      handshakeTimeoutMs: effectiveTimeout, postClaimStabilizeMs: config.postClaimStabilizeMs,
      postProbeStabilizeMs: config.postProbeStabilizeMs, debug: debug,
      skipAltSetting: config.skipAltSetting
    )

    // Pass 1b (aggressive, no reset): force configuration + re-claim + alt=0 + clear_halt,
    // then rerun ladder once before escalating to reset/reopen.
    // Restrict this expensive rung to devices where it has shown value (Pixel/vendor-specific).
    // On Pixel 7, aggressive re-claim often degrades a good initial alt-setting
    // into persistent set_interface_alt_setting failures. Keep Pixel on pass-1
    // only unless reset fallback is explicitly allowed.
    let shouldRunAggressivePass =
      (isVendorSpecificMTP || vendorID == 0x18D1)
      && !Self.shouldSkipUSBResetFallback(vendorID: vendorID, productID: productID)
    if result.candidate == nil && shouldRunAggressivePass {
      if debug { print("   [Open] Pass 1 failed, attempting aggressive no-reset retry rung") }
      result = tryProbeAllCandidatesAggressive(
        handle: handle,
        device: dev,
        candidates: candidates,
        handshakeTimeoutMs: max(effectiveTimeout, config.handshakeTimeoutMs),
        postClaimStabilizeMs: max(config.postClaimStabilizeMs, 500),
        debug: debug,
        skipAltSetting: config.skipAltSetting
      )
    } else if result.candidate == nil && debug {
      print("   [Open] Pass 1 failed; skipping aggressive rung for this device family")
    }

    // Pass 1c (Pixel): if pass 1 fails, try close+reopen with no reset.
    // This refreshes host-side state without forcing device re-enumeration.
    if result.candidate == nil {
      let skipResetFallback = Self.shouldSkipUSBResetFallback(
        vendorID: vendorID, productID: productID)
      let tryNoResetReopen =
        skipResetFallback
        && Self.shouldAttemptNoResetReopenFallback(vendorID: vendorID, productID: productID)

      if tryNoResetReopen {
        let preBus = libusb_get_bus_number(dev)
        var portPath = [UInt8](repeating: 0, count: 7)
        let portDepth = libusb_get_port_numbers(dev, &portPath, Int32(portPath.count))
        var currentlyOpen = true
        let reopenAttempts = Self.pixelNoResetReopenAttemptCount(
          vendorID: vendorID, productID: productID)

        for reopenAttempt in 1...reopenAttempts {
          if debug {
            print(
              "   [Open] Pass 1 failed, attempting no-reset close+reopen fallback for Pixel 7 (\(reopenAttempt)/\(reopenAttempts))"
            )
          }

          if currentlyOpen {
            libusb_close(handle)
            libusb_unref_device(dev)
            currentlyOpen = false
          }

          let settleMs = UInt32(min(250 + (reopenAttempt - 1) * 250, 1500))
          usleep(settleMs * 1000)

          guard
            let reopenedDevice = Self.findDeviceByBusAndPort(
              ctx: ctx, bus: preBus, portPath: portPath, portDepth: portDepth)
          else {
            if debug {
              print(
                "   [Open] No-reset reopen attempt \(reopenAttempt) could not re-find device by bus/port"
              )
            }
            continue
          }
          dev = reopenedDevice

          var reopenedHandlePtr: OpaquePointer?
          guard libusb_open(dev, &reopenedHandlePtr) == 0, let reopenedHandle = reopenedHandlePtr
          else {
            if debug {
              print("   [Open] No-reset reopen attempt \(reopenAttempt) could not open device")
            }
            libusb_unref_device(dev)
            continue
          }
          handle = reopenedHandle
          currentlyOpen = true

          candidates = try rankMTPInterfaces(handle: handle, device: dev)
          if debug { print("   [Open] No-reset reopen got \(candidates.count) candidate(s)") }

          setConfigurationIfNeeded(handle: handle, device: dev, force: true, debug: debug)
          result = tryProbeAllCandidates(
            handle: handle, device: dev, candidates: candidates,
            handshakeTimeoutMs: effectiveTimeout,
            postClaimStabilizeMs: config.postClaimStabilizeMs,
            postProbeStabilizeMs: config.postProbeStabilizeMs, debug: debug,
            skipAltSetting: config.skipAltSetting
          )
          if result.candidate != nil { break }
        }

        if result.candidate == nil, !currentlyOpen {
          throw TransportError.noDevice
        }
      } else if skipResetFallback && debug {
        print("   [Open] Pass 1 failed; skipping no-reset reopen fallback for Pixel 7")
      }
    }

    // Pass 2 (fallback): if earlier passes fail, do USB reset + teardown + fresh reopen + re-probe.
    // This mirrors the libmtp-style recovery rung used by Pixel/OnePlus-class handshakes.
    if result.candidate == nil {
      let skipResetFallback = Self.shouldSkipUSBResetFallback(
        vendorID: vendorID, productID: productID)
      if skipResetFallback {
        if debug {
          print(
            "   [Open] Pass 1 failed; skipping USB reset fallback for Pixel 7 (set SWIFTMTP_PIXEL_ALLOW_OPEN_RESET=1 to override)"
          )
        }
      } else if debug {
        print("   [Open] Pass 1 failed, attempting USB reset fallback")
      }

      if !skipResetFallback {

        // Capture bus + port path before reset (address may change, bus+port won't)
        let preBus = libusb_get_bus_number(dev)
        var portPath = [UInt8](repeating: 0, count: 7)
        let portDepth = libusb_get_port_numbers(dev, &portPath, Int32(portPath.count))

        let resetRC = libusb_reset_device(handle)
        if debug { print("   [Open] libusb_reset_device rc=\(resetRC)") }

        let deviceReenumerated = (resetRC == Int32(LIBUSB_ERROR_NOT_FOUND.rawValue))

        if resetRC == 0 || deviceReenumerated {
          // Always teardown and reopen a fresh handle after reset.
          if debug {
            let kind = deviceReenumerated ? "re-enumerated" : "same address"
            print("   [Open] Reset succeeded (\(kind)); reopening fresh handle...")
          }
          libusb_close(handle)
          libusb_unref_device(dev)
          usleep(350_000)

          guard
            let nd = Self.findDeviceByBusAndPort(
              ctx: ctx, bus: preBus, portPath: portPath, portDepth: portDepth)
          else {
            if debug { print("   [Open] Could not re-find device after reset") }
            throw TransportError.noDevice
          }
          dev = nd

          var nh: OpaquePointer?
          guard libusb_open(dev, &nh) == 0, let newHandle = nh else {
            libusb_unref_device(dev)
            throw TransportError.accessDenied
          }
          handle = newHandle

          // Re-rank candidates with new handle.
          candidates = try rankMTPInterfaces(handle: handle, device: dev)
          if debug { print("   [Open] Reopened handle, \(candidates.count) candidate(s)") }

          // Poll GetDeviceStatus until MTP stack recovers (budget from stabilizeMs)
          let budget = max(config.stabilizeMs, 3000)
          let ifaceNum = candidates.first.map { UInt16($0.ifaceNumber) } ?? 0
          let ready = waitForMTPReady(handle: handle, iface: ifaceNum, budgetMs: budget)
          if debug { print("   [Open] waitForMTPReady → \(ready)") }

          // Re-set configuration to reinitialize pipes after reset
          setConfigurationIfNeeded(handle: handle, device: dev, force: true, debug: debug)

          result = tryProbeAllCandidates(
            handle: handle, device: dev, candidates: candidates,
            handshakeTimeoutMs: config.handshakeTimeoutMs,
            postClaimStabilizeMs: config.postClaimStabilizeMs,
            postProbeStabilizeMs: config.postProbeStabilizeMs,
            debug: debug,
            skipAltSetting: config.skipAltSetting
          )
        } else if debug {
          print("   [Open] USB reset failed (rc=\(resetRC)), skipping pass 2")
        }
      }
    }

    guard let sel = result.candidate else {
      libusb_close(handle)
      libusb_unref_device(dev)
      if result.probeStep == nil {
        if Self.isPixel7(vendorID: vendorID, productID: productID) {
          throw TransportError.io(
            "mtp interface claim failed across \(candidates.count) candidate(s). macOS reports IOService unavailable/exclusive claim (often Image Capture stack). Close competing USB apps and retry; running the CLI with elevated privileges may be required on this host."
          )
        }
        throw TransportError.io(
          "mtp interface claim failed across \(candidates.count) candidate(s). Close competing USB apps (Android File Transfer, adb, browsers) and retry."
        )
      }
      throw TransportError.io(
        "mtp handshake failed after interface claim: last probe step=\(result.probeStep ?? "none"). Device claimed but did not complete MTP command exchange; unlock/authorize the phone and replug."
      )
    }

    // PTP Device Reset (bRequest 0x66) to clear stale sessions from prior connections.
    // 5000ms timeout: PTP spec allows devices up to 5s to complete a class-specific reset.
    // Some Android devices (Samsung) take 2-3s; 5s covers the slowest observed responses.
    let skipClassReset = Self.shouldSkipPixelClassResetControlTransfer(
      vendorID: vendorID, productID: productID)
    let resetRC: Int32
    if skipClassReset {
      resetRC = 0
      if debug {
        print(
          "   [Open] Skipping PTP Device Reset (0x66) for Pixel 7 (SWIFTMTP_PIXEL_SKIP_CLASS_RESET=1)"
        )
      }
    } else {
      resetRC = libusb_control_transfer(
        handle, 0x21, 0x66, 0, UInt16(sel.ifaceNumber), nil, 0, 5000)
      if debug { print("   [Open] PTP Device Reset (0x66) rc=\(resetRC)") }
    }

    if resetRC < 0 {
      // Device doesn't support PTP Device Reset — send CloseSession (0x1003) via bulk
      // to clear any stale session from a previous unclean disconnect.
      // 2000ms write timeout: conservative upper bound for a 12-byte command container;
      // devices that don't recognize CloseSession will simply STALL, which we drain below.
      let closeCmd = makePTPCommand(opcode: 0x1003, txid: 0, params: [])
      var sent: Int32 = 0
      let writeRC = closeCmd.withUnsafeBytes { ptr -> Int32 in
        libusb_bulk_transfer(
          handle, sel.bulkOut,
          UnsafeMutablePointer(mutating: ptr.baseAddress!.assumingMemoryBound(to: UInt8.self)),
          Int32(closeCmd.count), &sent, 2000
        )
      }
      if debug { print("   [Open] CloseSession fallback write rc=\(writeRC)") }
      // Drain the response — 1000ms is enough for the short response container.
      var respBuf = [UInt8](repeating: 0, count: 512)
      var got: Int32 = 0
      _ = libusb_bulk_transfer(handle, sel.bulkIn, &respBuf, Int32(respBuf.count), &got, 1000)
      if debug { print("   [Open] CloseSession fallback read got=\(got)") }
    }

    try? await Task.sleep(nanoseconds: 200_000_000)

    // Drain stale data
    var drain = [UInt8](repeating: 0, count: 4096), got: Int32 = 0
    while libusb_bulk_transfer(handle, sel.bulkIn, &drain, Int32(drain.count), &got, 10) == 0
      && got > 0
    {}

    // Detect USB connection speed for adaptive chunk sizing
    let usbSpeedMBps: Int?
    let rawSpeed = libusb_get_device_speed(dev)
    switch rawSpeed {
    case 3:  // LIBUSB_SPEED_HIGH (USB 2.0 Hi-Speed) ≈ 40 MB/s practical
      usbSpeedMBps = 40
    case 4:  // LIBUSB_SPEED_SUPER (USB 3.0 SuperSpeed) ≈ 400 MB/s practical
      usbSpeedMBps = 400
    case 5:  // LIBUSB_SPEED_SUPER_PLUS (USB 3.1+) ≈ 1200 MB/s practical
      usbSpeedMBps = 1200
    default:
      usbSpeedMBps = nil
    }

    let descriptor = MTPLinkDescriptor(
      interfaceNumber: sel.ifaceNumber,
      interfaceClass: sel.ifaceClass,
      interfaceSubclass: sel.ifaceSubclass,
      interfaceProtocol: sel.ifaceProtocol,
      bulkInEndpoint: sel.bulkIn,
      bulkOutEndpoint: sel.bulkOut,
      interruptEndpoint: sel.eventIn != 0 ? sel.eventIn : nil,
      usbSpeedMBps: usbSpeedMBps
    )

    let link = MTPUSBLink(
      handle: handle, device: dev,
      iface: sel.ifaceNumber, epIn: sel.bulkIn, epOut: sel.bulkOut, epEvt: sel.eventIn,
      config: config, manufacturer: summary.manufacturer, model: summary.model,
      vendorID: vendorID, productID: productID,
      cachedDeviceInfoData: result.cachedDeviceInfo,
      linkDescriptor: descriptor
    )

    activeLinks.append(link)

    log.info(
      "Device opened successfully: \(summary.manufacturer, privacy: .public) \(summary.model, privacy: .public) iface=\(sel.ifaceNumber) bulkIn=\(String(format: "0x%02x", sel.bulkIn), privacy: .public) bulkOut=\(String(format: "0x%02x", sel.bulkOut), privacy: .public)"
    )

    return link
  }

  public func close() async throws {
    let links = activeLinks
    activeLinks.removeAll()

    for link in links {
      await link.close()
    }
  }
}

public final class MTPUSBLink: @unchecked Sendable, MTPLink {
  var h: OpaquePointer
  var dev: OpaquePointer
  let iface: UInt8
  let inEP: UInt8
  let outEP: UInt8
  let evtEP: UInt8
  private let ioQ = DispatchQueue(
    label: "com.effortlessmetrics.swiftmtp.usbio", qos: .userInitiated)
  // MTP 1.1 §9.3.1: 0 = no session open (pre-session commands use txid 0);
  // after OpenSession the counter starts at 1 and wraps from 0xFFFFFFFE → 1.
  var nextTx: UInt32 = 0
  let config: SwiftMTPConfig
  let manufacturer: String
  let model: String
  let vendorID: UInt16
  let productID: UInt16
  var didRunPixelPreOpenSessionPreflight = false
  var eventContinuation: AsyncStream<Data>.Continuation?
  var eventPumpTask: Task<Void, Never>?
  public let eventStream: AsyncStream<Data>
  /// Raw device-info bytes cached from the interface probe (avoids redundant GetDeviceInfo).
  let cachedDeviceInfoData: Data?
  /// USB interface/endpoint metadata from transport probing.
  public let linkDescriptor: MTPLinkDescriptor?

  static func shouldRecoverNoProgressTimeout(rc: Int32, sent: Int32) -> Bool {
    rc == Int32(LIBUSB_ERROR_TIMEOUT.rawValue) && sent == 0
  }

  init(
    handle: OpaquePointer, device: OpaquePointer, iface: UInt8, epIn: UInt8, epOut: UInt8,
    epEvt: UInt8, config: SwiftMTPConfig, manufacturer: String, model: String,
    vendorID: UInt16, productID: UInt16,
    cachedDeviceInfoData: Data? = nil, linkDescriptor: MTPLinkDescriptor? = nil
  ) {
    self.h = handle
    self.dev = device
    self.iface = iface
    self.inEP = epIn
    self.outEP = epOut
    self.evtEP = epEvt
    self.config = config
    self.manufacturer = manufacturer
    self.model = model
    self.vendorID = vendorID
    self.productID = productID
    self.cachedDeviceInfoData = cachedDeviceInfoData
    self.linkDescriptor = linkDescriptor
    var cont: AsyncStream<Data>.Continuation!
    self.eventStream = AsyncStream(Data.self, bufferingPolicy: .bufferingNewest(16)) { cont = $0 }
    self.eventContinuation = cont
  }

  public func close() async {
    log.info("Closing MTPUSBLink: \(self.manufacturer, privacy: .public) \(self.model, privacy: .public) iface=\(self.iface)")
    eventPumpTask?.cancel()
    eventContinuation?.finish()
    // noReleaseInterface: skip release if device locks up on release (SanDisk/Creative quirk)
    if !config.noReleaseInterface {
      let releaseRC = libusb_release_interface(h, Int32(iface))
      if releaseRC != 0 {
        log.warning("libusb_release_interface \(libusbErrorName(releaseRC), privacy: .public) (rc=\(releaseRC)) during close (non-fatal)")
      }
    }
    // forceResetOnClose: reset device before closing handle (AOSP/Sony quirk)
    if config.forceResetOnClose {
      let resetRC = libusb_reset_device(h)
      if resetRC != 0 && resetRC != Int32(LIBUSB_ERROR_NOT_FOUND.rawValue) {
        log.warning("forceResetOnClose: libusb_reset_device \(libusbErrorName(resetRC), privacy: .public) (rc=\(resetRC)) during close (non-fatal)")
      }
    }
    libusb_close(h)
    libusb_unref_device(dev)
    log.debug("MTPUSBLink closed (iface=\(self.iface))")
  }

  public func resetDevice() async throws {
    log.info(
      "Resetting USB device: \(self.manufacturer, privacy: .public) \(self.model, privacy: .public) VID=\(String(format: "%04x", self.vendorID), privacy: .public) PID=\(String(format: "%04x", self.productID), privacy: .public)"
    )
    let rc = libusb_reset_device(h)
    // NOT_FOUND means device re-enumerated (expected on some Android devices)
    if rc != 0 && rc != Int32(LIBUSB_ERROR_NOT_FOUND.rawValue) {
      log.error("libusb_reset_device failed: \(libusbErrorName(rc), privacy: .public) (rc=\(rc)) — device may need to be unplugged and reconnected")
      throw MTPError.transport(mapLibusb(rc))
    }
  }

  public func startEventPump() {
    guard evtEP != 0 else { return }
    guard eventPumpTask == nil else { return }
    let coalescer = MTPEventCoalescer()
    eventPumpTask = Task {
      while !Task.isCancelled {
        var buf = [UInt8](repeating: 0, count: 1024)
        guard let got = try? bulkReadOnce(evtEP, into: &buf, max: 1024, timeout: 1000), got > 0
        else { continue }
        let data = Data(buf[0..<got])
        if coalescer.shouldForward() {
          if let event = MTPEvent.fromRaw(data) {
            MTPLog.transport.debug("MTP event received: \(String(describing: event))")
          }
          eventContinuation?.yield(data)
        }
        // Brief pause to allow burst coalescing before the next read.
        try? await Task.sleep(nanoseconds: 10_000_000)
      }
    }
  }

  public func openUSBIfNeeded() async throws {}

  public func executeCommand(_ command: PTPContainer) async throws -> PTPResponseResult {
    try await executeStreamingCommand(
      command, dataPhaseLength: nil, dataInHandler: nil, dataOutHandler: nil)
  }

  public func executeStreamingCommand(
    _ command: PTPContainer, dataPhaseLength: UInt64? = nil, dataInHandler: MTPDataIn?,
    dataOutHandler: MTPDataOut?
  ) async throws -> PTPResponseResult {
    try await withCheckedThrowingContinuation { cont in
      ioQ.async {
        Task {
          do {
            cont.resume(
              returning: try await self.executeCommandAsync(
                command: command, dataPhaseLength: dataPhaseLength, dataInHandler: dataInHandler,
                dataOutHandler: dataOutHandler))
          } catch { cont.resume(throwing: error) }
        }
      }
    }
  }

}

final class SimpleCollector: @unchecked Sendable {
  var data = Data()
  private let lock = NSLock()
  func append(_ chunk: UnsafeRawBufferPointer) {
    lock.lock()
    defer { lock.unlock() }
    data.append(chunk)
  }
}
extension Data {
  mutating func append(_ buf: UnsafeRawBufferPointer) {
    guard buf.count > 0, let base = buf.baseAddress else { return }
    append(base.assumingMemoryBound(to: UInt8.self), count: buf.count)
  }
}
