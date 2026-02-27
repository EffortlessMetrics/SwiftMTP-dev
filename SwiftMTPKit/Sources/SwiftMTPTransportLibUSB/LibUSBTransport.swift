// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import CLibusb
import SwiftMTPCore
import SwiftMTPObservability

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
      libusb_close(handle)
      libusb_unref_device(dev)
      throw error
    }
    guard !candidates.isEmpty else {
      libusb_close(handle)
      libusb_unref_device(dev)
      throw TransportError.io("no MTP interface")
    }

    let skipPixelResetByPolicy = Self.shouldSkipUSBResetFallback(
      vendorID: vendorID, productID: productID)

    // For vendor-specific devices (class 0xff), try USB reset before probing.
    // Pixel 7 is explicitly excluded by default to avoid re-enumeration collapse.
    if isVendorSpecificMTP {
      if skipPixelResetByPolicy {
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
      if !skipPixelResetByPolicy {
        usleep(300_000)
      }
    }

    // Pass 1: Normal probe (no USB reset).
    // claimCandidate uses set_configuration + set_alt_setting to reinitialize
    // endpoint pipes, which fixes stale pipe state on most devices.
    if debug { print("   [Open] Pass 1: probing \(candidates.count) candidate(s)") }

    // Use extended timeout for vendor-specific devices (class 0xff)
    // Samsung, Xiaomi, and similar devices often respond more slowly
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
      postProbeStabilizeMs: config.postProbeStabilizeMs, debug: debug
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
        debug: debug
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
            postProbeStabilizeMs: config.postProbeStabilizeMs, debug: debug
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
            debug: debug
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

    // PTP Device Reset to clear stale sessions
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
      // Drain the response (don't care about result)
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
  private var h: OpaquePointer
  private var dev: OpaquePointer
  private let iface: UInt8
  private let inEP: UInt8
  private let outEP: UInt8
  private let evtEP: UInt8
  private let ioQ = DispatchQueue(
    label: "com.effortlessmetrics.swiftmtp.usbio", qos: .userInitiated)
  private var nextTx: UInt32 = 1
  private let config: SwiftMTPConfig
  private let manufacturer: String
  private let model: String
  private let vendorID: UInt16
  private let productID: UInt16
  private var didRunPixelPreOpenSessionPreflight = false
  private var eventContinuation: AsyncStream<Data>.Continuation?
  private var eventPumpTask: Task<Void, Never>?
  public let eventStream: AsyncStream<Data>
  /// Raw device-info bytes cached from the interface probe (avoids redundant GetDeviceInfo).
  private let cachedDeviceInfoData: Data?
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
    eventPumpTask?.cancel()
    eventContinuation?.finish()
    libusb_release_interface(h, Int32(iface))
    libusb_close(h)
    libusb_unref_device(dev)
  }

  public func resetDevice() async throws {
    let rc = libusb_reset_device(h)
    // NOT_FOUND means device re-enumerated (expected on some Android devices)
    if rc != 0 && rc != Int32(LIBUSB_ERROR_NOT_FOUND.rawValue) {
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

  private func recoverStall() {
    _ = libusb_clear_halt(h, outEP)
    _ = libusb_clear_halt(h, inEP)
    if evtEP != 0 { _ = libusb_clear_halt(h, evtEP) }
  }

  private var isPixel7PreflightTarget: Bool {
    vendorID == 0x18D1 && productID == 0x4EE1
  }

  private var skipPixelClassResetControlTransfer: Bool {
    isPixelClassNoProgressTarget
      && ProcessInfo.processInfo.environment["SWIFTMTP_PIXEL_SKIP_CLASS_RESET"] == "1"
  }

  private func runPixelPreOpenSessionPreflightIfNeeded() {
    guard isPixel7PreflightTarget, !didRunPixelPreOpenSessionPreflight else { return }
    didRunPixelPreOpenSessionPreflight = true

    let debug = ProcessInfo.processInfo.environment["SWIFTMTP_DEBUG"] == "1"
    setConfigurationIfNeeded(handle: h, device: dev, force: true, debug: debug)
    let setAltRC = libusb_set_interface_alt_setting(h, Int32(iface), 0)
    let clearOutRC = libusb_clear_halt(h, outEP)
    let clearInRC = libusb_clear_halt(h, inEP)
    let clearEventRC: Int32 =
      evtEP != 0 ? libusb_clear_halt(h, evtEP) : Int32(LIBUSB_SUCCESS.rawValue)
    let skipClassReset = skipPixelClassResetControlTransfer
    let classResetRC: Int32 =
      skipClassReset
      ? Int32(LIBUSB_SUCCESS.rawValue)
      : libusb_control_transfer(h, 0x21, 0x66, 0, UInt16(iface), nil, 0, 2000)
    usleep(200_000)

    if debug {
      print(
        String(
          format:
            "   [USB][Preflight][Pixel] setAlt0=%d clear(out=%d in=%d evt=%d) classReset=%d skipClassReset=%@ settleMs=200",
          setAltRC,
          clearOutRC,
          clearInRC,
          clearEventRC,
          classResetRC,
          skipClassReset ? "true" : "false"
        )
      )
    }
  }

  public func openSession(id: UInt32) async throws {
    runPixelPreOpenSessionPreflightIfNeeded()
    try await executeStreamingCommand(
      PTPContainer(type: 1, code: 0x1002, txid: 0, params: [id]), dataPhaseLength: nil,
      dataInHandler: nil, dataOutHandler: nil
    )
    .checkOK()
    nextTx = 1
  }
  public func closeSession() async throws {
    try await executeStreamingCommand(
      PTPContainer(type: 1, code: 0x1003, txid: 0, params: []), dataPhaseLength: nil,
      dataInHandler: nil, dataOutHandler: nil
    )
    .checkOK()
  }

  public func getDeviceInfo() async throws -> MTPDeviceInfo {
    // Use cached probe data if available (avoids redundant USB round-trip)
    if let cached = cachedDeviceInfoData, let info = PTPDeviceInfo.parse(from: cached) {
      return MTPDeviceInfo(
        manufacturer: info.manufacturer, model: info.model, version: info.deviceVersion,
        serialNumber: info.serialNumber, operationsSupported: Set(info.operationsSupported),
        eventsSupported: Set(info.eventsSupported))
    }
    let collector = SimpleCollector()
    let res = try await executeStreamingCommand(
      PTPContainer(type: 1, code: 0x1001, txid: 0, params: []), dataPhaseLength: nil,
      dataInHandler: {
        collector.append($0)
        return $0.count
      }, dataOutHandler: nil)
    if res.isOK, let info = PTPDeviceInfo.parse(from: collector.data) {
      return MTPDeviceInfo(
        manufacturer: info.manufacturer, model: info.model, version: info.deviceVersion,
        serialNumber: info.serialNumber, operationsSupported: Set(info.operationsSupported),
        eventsSupported: Set(info.eventsSupported))
    }
    return MTPDeviceInfo(
      manufacturer: manufacturer, model: model, version: "1.0", serialNumber: "Unknown",
      operationsSupported: [], eventsSupported: [])
  }

  public func getStorageIDs() async throws -> [MTPStorageID] {
    let collector = SimpleCollector()
    let res = try await executeStreamingCommand(
      PTPContainer(type: 1, code: 0x1004, txid: 0, params: []), dataPhaseLength: nil,
      dataInHandler: {
        collector.append($0)
        return $0.count
      }, dataOutHandler: nil)
    if !res.isOK || collector.data.count < 4 { return [] }
    var reader = PTPReader(data: collector.data)
    guard let count = reader.u32() else { return [] }
    let payloadCount = (collector.data.count - 4) / 4
    let total = min(Int(count), payloadCount)
    var ids = [MTPStorageID]()
    ids.reserveCapacity(total)
    for _ in 0..<total {
      guard let raw = reader.u32() else { break }
      ids.append(MTPStorageID(raw: raw))
    }
    return ids
  }

  public func getStorageInfo(id: MTPStorageID) async throws -> MTPStorageInfo {
    let collector = SimpleCollector()
    let res = try await executeStreamingCommand(
      PTPContainer(type: 1, code: 0x1005, txid: 0, params: [id.raw]), dataPhaseLength: nil,
      dataInHandler: {
        collector.append($0)
        return $0.count
      }, dataOutHandler: nil)
    try res.checkOK()
    var r = PTPReader(data: collector.data)
    _ = r.u16()
    _ = r.u16()
    let cap = r.u16(), max = r.u64(), free = r.u64()
    _ = r.u32()
    let desc = r.string() ?? ""
    return MTPStorageInfo(
      id: id, description: desc, capacityBytes: max ?? 0, freeBytes: free ?? 0,
      isReadOnly: cap == 0x0001)
  }

  public func getObjectHandles(storage: MTPStorageID, parent: MTPObjectHandle?) async throws
    -> [MTPObjectHandle]
  {
    let collector = SimpleCollector()
    let res = try await executeStreamingCommand(
      PTPContainer(type: 1, code: 0x1007, txid: 0, params: [storage.raw, 0, parent ?? 0x00000000]),
      dataPhaseLength: nil,
      dataInHandler: {
        collector.append($0)
        return $0.count
      }, dataOutHandler: nil)
    try res.checkOK()
    if collector.data.count < 4 { return [] }
    var reader = PTPReader(data: collector.data)
    guard let count = reader.u32() else { return [] }
    let payloadCount = (collector.data.count - 4) / 4
    let total = min(Int(count), payloadCount)
    var handles = [MTPObjectHandle]()
    handles.reserveCapacity(total)
    for _ in 0..<total {
      guard let raw = reader.u32() else { break }
      handles.append(raw)
    }
    return handles
  }

  public func getObjectInfos(_ handles: [MTPObjectHandle]) async throws -> [MTPObjectInfo] {
    var out = [MTPObjectInfo]()
    for h in handles {
      let collector = SimpleCollector()
      let res = try await executeStreamingCommand(
        PTPContainer(type: 1, code: 0x1008, txid: 0, params: [h]), dataPhaseLength: nil,
        dataInHandler: {
          collector.append($0)
          return $0.count
        }, dataOutHandler: nil)
      if !res.isOK { continue }
      let responseData = collector.data
      var r = PTPReader(data: responseData)
      guard let sid = r.u32(), let fmt = r.u16() else {
        continue
      }
      _ = r.u16()  // ProtectionStatus
      let size = r.u32()
      _ = r.u16()  // ThumbFormat
      _ = r.u32()  // ThumbCompressedSize
      _ = r.u32()  // ThumbPixWidth
      _ = r.u32()  // ThumbPixHeight
      _ = r.u32()  // ImagePixWidth
      _ = r.u32()  // ImagePixHeight
      _ = r.u32()  // ImageBitDepth
      let par = r.u32()
      _ = r.u16()  // AssociationType
      _ = r.u32()  // AssociationDesc
      _ = r.u32()  // SequenceNumber
      let name = r.string() ?? "Unknown"
      out.append(
        MTPObjectInfo(
          handle: h, storage: MTPStorageID(raw: sid), parent: par == 0 ? nil : par, name: name,
          sizeBytes: (size == nil || size == 0xFFFFFFFF) ? nil : UInt64(size!),
          modified: nil as Date?, formatCode: fmt, properties: [:]))
    }
    return out
  }

  public func getObjectInfos(storage: MTPStorageID, parent: MTPObjectHandle?, format: UInt16?)
    async throws -> [MTPObjectInfo]
  {
    let parentHandle = parent ?? 0x00000000, formatCode = format ?? 0x00000000

    func tryPropList(params: [UInt32]) async throws -> [MTPObjectInfo]? {
      let collector = SimpleCollector()
      let res = try await executeStreamingCommand(
        PTPContainer(type: 1, code: 0x9805, txid: 0, params: params), dataPhaseLength: nil,
        dataInHandler: {
          collector.append($0)
          return $0.count
        }, dataOutHandler: nil)
      if !res.isOK { return nil }
      guard let pl = PTPPropList.parse(from: collector.data) else { return nil }
      var grouped = [UInt32: [UInt16: PTPValue]]()
      for e in pl.entries {
        if grouped[e.handle] == nil { grouped[e.handle] = [:] }
        if let v = e.value { grouped[e.handle]![e.propertyCode] = v }
      }
      return grouped.map { h, p in
        var name = "Unknown"
        if case .string(let s) = p[0xDC07] { name = s }
        var size: UInt64? = nil
        if let v = p[0xDC04] {
          if case .uint64(let u) = v {
            size = u
          } else if case .uint32(let u) = v {
            size = UInt64(u)
          }
        }
        var fmt: UInt16 = 0
        if case .uint16(let u) = p[0xDC02] { fmt = u }
        var par: UInt32? = nil
        if case .uint32(let u) = p[0xDC0B] { par = u }
        return MTPObjectInfo(
          handle: h, storage: storage, parent: par == 0 ? nil : par, name: name, sizeBytes: size,
          modified: nil, formatCode: fmt, properties: [:])
      }
    }

    if MTPFeatureFlags.shared.isEnabled(.propListFastPath) {
      if let res = try? await tryPropList(params: [
        parentHandle, 0xFFFFFFFF, UInt32(formatCode), storage.raw, 1,
      ]) {
        return res
      }
      if let res = try? await tryPropList(params: [parentHandle, 0x00000000, UInt32(formatCode)]) {
        return res
      }
    }

    let handles = try await getObjectHandles(storage: storage, parent: parent)
    return try await getObjectInfos(handles)
  }

  public func deleteObject(handle: MTPObjectHandle) async throws {
    try await executeStreamingCommand(
      PTPContainer(type: 1, code: 0x100B, txid: 0, params: [handle, 0]), dataPhaseLength: nil,
      dataInHandler: nil, dataOutHandler: nil
    )
    .checkOK()
  }
  public func moveObject(
    handle: MTPObjectHandle, to storage: MTPStorageID, parent: MTPObjectHandle?
  ) async throws {
    try await executeStreamingCommand(
      PTPContainer(
        type: 1, code: 0x100E, txid: 0, params: [handle, storage.raw, parent ?? 0xFFFFFFFF]),
      dataPhaseLength: nil, dataInHandler: nil, dataOutHandler: nil
    )
    .checkOK()
  }

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

  private func executeCommandAsync(
    command: PTPContainer, dataPhaseLength: UInt64? = nil, dataInHandler: MTPDataIn?,
    dataOutHandler: MTPDataOut?
  ) async throws -> PTPResponseResult {
    let signposter = MTPLog.Signpost.enumerateSignposter
    let state = signposter.beginInterval(
      "executeCommand", id: signposter.makeSignpostID(), "\(String(format: "0x%04x", command.code))"
    )
    defer { signposter.endInterval("executeCommand", state) }

    let txid =
      (command.code == 0x1002)
      ? 0
      : { () -> UInt32 in
        let t = nextTx
        nextTx = (nextTx == 0xFFFFFFFF) ? 1 : nextTx + 1
        return t
      }()
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
      if sent % 512 == 0 {
        var dummy: UInt8 = 0
        _ = libusb_bulk_transfer(h, outEP, &dummy, 0, nil, 100)
      }
    }

    var firstChunk: Data? = nil
    if dataInHandler != nil {
      if debug {
        print(String(format: "   [USB] op=0x%04x tx=%u phase=DATA-IN", command.code, txid))
      }
      var first = [UInt8](repeating: 0, count: 64 * 1024), got = 0,
        start = DispatchTime.now().uptimeNanoseconds
      let budget = UInt64(config.handshakeTimeoutMs) * 1_000_000
      while got == 0 {
        got = try bulkReadOnce(inEP, into: &first, max: first.count, timeout: 500)
        if got == 0 && DispatchTime.now().uptimeNanoseconds - start > budget {
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
          let g = try bulkReadOnce(inEP, into: &buf, max: buf.count, timeout: 1000)
          MTPLog.Signpost.chunkSignposter.endInterval("readChunk", chunkState)
          if g == 0 { throw MTPError.timeout }
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

  private struct CommandWriteAttempt {
    let rc: Int32
    let sent: Int32
    let expected: Int32

    var succeeded: Bool { rc == 0 && sent == expected }
    var isNoProgressTimeout: Bool {
      MTPUSBLink.shouldRecoverNoProgressTimeout(rc: rc, sent: sent)
    }
  }

  private func attemptCommandWrite(_ bytes: [UInt8], timeout: UInt32) -> CommandWriteAttempt {
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

  private func throwCommandWriteFailure(_ attempt: CommandWriteAttempt, context: String) throws {
    if attempt.rc == 0, attempt.sent != attempt.expected {
      throw MTPError.transport(
        .io("\(context): short write sent=\(attempt.sent)/\(attempt.expected)"))
    }
    if attempt.isNoProgressTimeout {
      if isPixelClassNoProgressTarget {
        // Pixel 7 / macOS 26 specific: bulk OUT stalled with no bytes written.
        // Root cause: macOS does not expose MTP IOUSBInterface children for this device
        // when USB mode or developer options are not fully configured on the phone.
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
      throw MTPError.transport(
        .io("\(context): command-phase timeout with no progress (sent=0)"))
    }
    throw MTPError.transport(mapLibusb(attempt.rc))
  }

  private func writeCommandContainerWithRecovery(
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

  private var isPixelClassNoProgressTarget: Bool {
    vendorID == 0x18D1 && productID == 0x4EE1
  }

  private var allowPixelCommandResetRecovery: Bool {
    ProcessInfo.processInfo.environment["SWIFTMTP_PIXEL_ALLOW_COMMAND_RESET"] == "1"
  }

  private var shouldSkipPixelCommandResetRecovery: Bool {
    isPixelClassNoProgressTarget && !allowPixelCommandResetRecovery
  }

  private func shouldAttemptPixelResetReopenRecovery(after attempt: CommandWriteAttempt) -> Bool {
    isPixelClassNoProgressTarget && allowPixelCommandResetRecovery && attempt.isNoProgressTimeout
  }

  @discardableResult
  private func performCommandNoProgressLightRecovery(opcode: UInt16, txid: UInt32, debug: Bool)
    -> Bool
  {
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

  private func performCommandNoProgressHardRecovery(opcode: UInt16, txid: UInt32, debug: Bool)
    -> Bool
  {
    if shouldSkipPixelCommandResetRecovery {
      if debug {
        print(
          String(
            format:
              "   [USB][Recover][Hard] op=0x%04x tx=%u skipping reset rung for Pixel 7 (set SWIFTMTP_PIXEL_ALLOW_COMMAND_RESET=1 to override)",
            opcode, txid))
      }
      return false
    }

    let resetRC = libusb_reset_device(h)
    if resetRC != 0 {
      if debug {
        print(
          String(
            format:
              "   [USB][Recover][Hard] op=0x%04x tx=%u reset_device failed rc=%d",
            opcode, txid, resetRC))
      }
      return false
    }

    usleep(300_000)

    setConfigurationIfNeeded(handle: h, device: dev, force: true, debug: debug)
    let setAltRC = libusb_set_interface_alt_setting(h, Int32(iface), 0)
    let clearOutRC = libusb_clear_halt(h, outEP)
    let clearInRC = libusb_clear_halt(h, inEP)
    let clearEventRC: Int32 =
      evtEP != 0 ? libusb_clear_halt(h, evtEP) : Int32(LIBUSB_SUCCESS.rawValue)

    usleep(200_000)

    if debug {
      print(
        String(
          format:
            "   [USB][Recover][Hard] op=0x%04x tx=%u reset_device=0 setAlt0=%d clear(out=%d in=%d evt=%d)",
          opcode, txid, setAltRC, clearOutRC, clearInRC, clearEventRC))
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
              "   [USB][Recover][Reopen] op=0x%04x tx=%u skipping reset+reopen for Pixel 7 (set SWIFTMTP_PIXEL_ALLOW_COMMAND_RESET=1 to override)",
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
    let releaseRC = libusb_release_interface(oldHandle, Int32(iface))

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
    return reopenedHandle
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
        recoverStall()
        var r: Int32 = 0
        let rc2 = libusb_bulk_transfer(
          h, ep,
          UnsafeMutablePointer<UInt8>(
            mutating: ptr.advanced(by: sent).assumingMemoryBound(to: UInt8.self)),
          Int32(count - sent), &r, timeout)
        if rc2 != 0 { throw MTPError.transport(mapLibusb(rc2)) }
        sent += Int(r)
        continue
      }
      if rc != 0 { throw MTPError.transport(mapLibusb(rc)) }
      sent += Int(s)
    }
  }
  @inline(__always) func bulkReadOnce(
    _ ep: UInt8, into buf: UnsafeMutableRawPointer, max: Int, timeout: UInt32
  ) throws -> Int {
    var g: Int32 = 0
    if max < 512 {
      var tmp = [UInt8](repeating: 0, count: 512)
      let rc = libusb_bulk_transfer(h, ep, &tmp, 512, &g, timeout)
      if rc == -7 { return 0 }
      if rc == Int32(LIBUSB_ERROR_PIPE.rawValue) {
        recoverStall()
        var g2: Int32 = 0
        let rc2 = libusb_bulk_transfer(h, ep, &tmp, 512, &g2, timeout)
        if rc2 != 0 && rc2 != -8 { throw MTPError.transport(mapLibusb(rc2)) }
        let c = min(Int(g2), max)
        if c > 0 { memcpy(buf, tmp, c) }
        return c
      }
      if rc != 0 && rc != -8 { throw MTPError.transport(mapLibusb(rc)) }
      let c = min(Int(g), max)
      if c > 0 { memcpy(buf, tmp, c) }
      return c
    }
    let rc = libusb_bulk_transfer(
      h, ep, buf.assumingMemoryBound(to: UInt8.self), Int32(max), &g, timeout)
    if rc == -7 { return 0 }
    if rc == Int32(LIBUSB_ERROR_PIPE.rawValue) {
      recoverStall()
      var g2: Int32 = 0
      let rc2 = libusb_bulk_transfer(
        h, ep, buf.assumingMemoryBound(to: UInt8.self), Int32(max), &g2, timeout)
      if rc2 != 0 { throw MTPError.transport(mapLibusb(rc2)) }
      return Int(g2)
    }
    if rc != 0 { throw MTPError.transport(mapLibusb(rc)) }
    return Int(g)
  }
  func bulkReadExact(_ ep: UInt8, into dst: UnsafeMutableRawPointer, need: Int, timeout: UInt32)
    throws
  {
    var got = 0
    while got < need {
      var tmp = [UInt8](repeating: 0, count: need - got)
      let g = try bulkReadOnce(ep, into: &tmp, max: tmp.count, timeout: timeout)
      if g == 0 { throw MTPError.timeout }
      memcpy(dst.advanced(by: got), &tmp, g)
      got += g
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
