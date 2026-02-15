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

    // For vendor-specific devices (class 0xff), try USB reset before probing
    // This helps with Samsung, Xiaomi, and similar devices that have interface claiming issues
    if isVendorSpecificMTP {
      if debug {
        print(
          String(
            format:
              "   [Open] Vendor-specific MTP device (VID=0x%04X PID=0x%04X), attempting pre-claim reset",
            vendorID, productID))
      }
      // Attempt USB reset before claim - helps with stubborn devices
      let resetRC = libusb_reset_device(handle)
      if debug {
        print(String(format: "   [Open] Pre-claim libusb_reset_device rc=%d", resetRC))
      }
      // Brief pause after reset for device to stabilize
      usleep(300_000)
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

    // Pass 2 (fallback): If pass 1 failed entirely and resetOnOpen is enabled,
    // do USB reset + MTP readiness poll + re-probe.
    // Also try Pass 2 for vendor-specific devices even without resetOnOpen
    if result.candidate == nil && (config.resetOnOpen || isVendorSpecificMTP) {
      if debug { print("   [Open] Pass 1 failed, attempting USB reset fallback") }

      // Capture bus + port path before reset (address may change, bus+port won't)
      let preBus = libusb_get_bus_number(dev)
      var portPath = [UInt8](repeating: 0, count: 7)
      let portDepth = libusb_get_port_numbers(dev, &portPath, Int32(portPath.count))

      let resetRC = libusb_reset_device(handle)
      if debug { print("   [Open] libusb_reset_device rc=\(resetRC)") }

      let deviceReenumerated = (resetRC == Int32(LIBUSB_ERROR_NOT_FOUND.rawValue))

      if resetRC == 0 || deviceReenumerated {
        if deviceReenumerated {
          // Device re-enumerated after reset — close old handle, find new device
          if debug { print("   [Open] Device re-enumerated after reset, reopening handle...") }
          libusb_close(handle)
          libusb_unref_device(dev)

          // Brief pause for USB enumeration
          usleep(500_000)

          // Re-enumerate and match by bus + port path
          var newList: UnsafeMutablePointer<OpaquePointer?>?
          let newCnt = libusb_get_device_list(ctx, &newList)
          var newTarget: OpaquePointer?
          if newCnt > 0, let newList {
            for i in 0..<Int(newCnt) {
              guard let d = newList[i] else { continue }
              let dBus = libusb_get_bus_number(d)
              guard dBus == preBus else { continue }
              var dPort = [UInt8](repeating: 0, count: 7)
              let dDepth = libusb_get_port_numbers(d, &dPort, Int32(dPort.count))
              if dDepth == portDepth && dPort[0..<Int(dDepth)] == portPath[0..<Int(portDepth)] {
                libusb_ref_device(d)
                newTarget = d
                break
              }
            }
            libusb_free_device_list(newList, 1)
          }

          guard let nd = newTarget else {
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

          // Re-rank candidates with new handle
          candidates = try rankMTPInterfaces(handle: handle, device: dev)
          if debug { print("   [Open] Reopened handle, \(candidates.count) candidate(s)") }
        }

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

    guard let sel = result.candidate else {
      libusb_close(handle)
      libusb_unref_device(dev)
      // Determine if this is a claim failure vs probe failure
      var failureGuidance = ""
      if result.probeStep == nil {
        // Claim succeeded but no probe response - device not responding to MTP commands
        // This is a TIMEOUT situation: device is claimed but not responding
        failureGuidance = """

          The USB interface was claimed successfully, but the device did not respond to MTP commands.
          This typically indicates:
          - Device is in PTP mode instead of MTP mode (check phone USB settings)
          - USB cable is charge-only (no data lines)
          - Device screen is locked or in sleep mode
          - USB hub or port issue

          Try:
          1. On the device, verify "File Transfer (MTP)" mode is selected in USB preferences
          2. Unlock the device screen
          3. Try a different USB cable (must support data, not just charging)
          4. Try a different USB port (directly on Mac, not through hub)
          5. Check if ioreg shows the device with idProduct=0x4EE1 (MTP mode)
          """
      } else {
        // Some probe steps worked but final candidate selection failed
        failureGuidance = """

          The probe ladder completed some steps but failed to establish a working session.
          This may indicate a device-specific quirk or timing issue.
          """
      }
      throw TransportError.io(
        "no suitable MTP interface found: last probe step=\(result.probeStep ?? "none")\(failureGuidance)"
      )
    }

    // PTP Device Reset to clear stale sessions
    let resetRC = libusb_control_transfer(
      handle, 0x21, 0x66, 0, UInt16(sel.ifaceNumber), nil, 0, 5000)
    if debug { print("   [Open] PTP Device Reset (0x66) rc=\(resetRC)") }

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

    let descriptor = MTPLinkDescriptor(
      interfaceNumber: sel.ifaceNumber,
      interfaceClass: sel.ifaceClass,
      interfaceSubclass: sel.ifaceSubclass,
      interfaceProtocol: sel.ifaceProtocol,
      bulkInEndpoint: sel.bulkIn,
      bulkOutEndpoint: sel.bulkOut,
      interruptEndpoint: sel.eventIn != 0 ? sel.eventIn : nil
    )

    let link = MTPUSBLink(
      handle: handle, device: dev,
      iface: sel.ifaceNumber, epIn: sel.bulkIn, epOut: sel.bulkOut, epEvt: sel.eventIn,
      config: config, manufacturer: summary.manufacturer, model: summary.model,
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
  private let h: OpaquePointer, dev: OpaquePointer, iface: UInt8, inEP, outEP, evtEP: UInt8
  private let ioQ = DispatchQueue(
    label: "com.effortlessmetrics.swiftmtp.usbio", qos: .userInitiated)
  private var nextTx: UInt32 = 1
  private let config: SwiftMTPConfig, manufacturer: String, model: String
  private var eventContinuation: AsyncStream<Data>.Continuation?, eventPumpTask: Task<Void, Never>?
  /// Raw device-info bytes cached from the interface probe (avoids redundant GetDeviceInfo).
  private let cachedDeviceInfoData: Data?
  /// USB interface/endpoint metadata from transport probing.
  public let linkDescriptor: MTPLinkDescriptor?

  init(
    handle: OpaquePointer, device: OpaquePointer, iface: UInt8, epIn: UInt8, epOut: UInt8,
    epEvt: UInt8, config: SwiftMTPConfig, manufacturer: String, model: String,
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
    self.cachedDeviceInfoData = cachedDeviceInfoData
    self.linkDescriptor = linkDescriptor
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
    let _ = AsyncStream<Data> { self.eventContinuation = $0 }
    eventPumpTask = Task {
      while !Task.isCancelled {
        var buf = [UInt8](repeating: 0, count: 1024)
        if let got = try? bulkReadOnce(evtEP, into: &buf, max: 1024, timeout: 1000), got > 0 {
          eventContinuation?.yield(Data(buf[0..<got]))
        }
      }
    }
  }

  public func openUSBIfNeeded() async throws {}
  public func openSession(id: UInt32) async throws {
    try await executeStreamingCommand(
      PTPContainer(type: 1, code: 0x1002, txid: 0, params: [id]), dataPhaseLength: nil,
      dataInHandler: nil, dataOutHandler: nil
    )
    .checkOK()
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
    try cmdBytes.withUnsafeBytes {
      try bulkWriteAll(
        outEP, from: $0.baseAddress!, count: $0.count, timeout: UInt32(config.ioTimeoutMs))
    }

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
    return PTPResponseResult(code: rHdr.code, txid: rHdr.txid, params: params)
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
      if rc != 0 && rc != -8 { throw MTPError.transport(mapLibusb(rc)) }
      let c = min(Int(g), max)
      if c > 0 { memcpy(buf, tmp, c) }
      return c
    }
    let rc = libusb_bulk_transfer(
      h, ep, buf.assumingMemoryBound(to: UInt8.self), Int32(max), &g, timeout)
    if rc == -7 { return 0 }
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
