// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import CLibusb
import SwiftMTPCore

/// Discovery utilities for LibUSB MTP devices
public struct USBIDs: Sendable {
  public let vendorID: UInt16
  public let productID: UInt16
  public let bcdDevice: UInt16
  public let ifaceClass: UInt8
  public let ifaceSubclass: UInt8
  public let ifaceProtocol: UInt8
}

extension LibUSBDiscovery {
  static func readIDs(device: OpaquePointer, iface: libusb_interface_descriptor) throws -> USBIDs {
    var desc = libusb_device_descriptor()
    guard libusb_get_device_descriptor(device, &desc) == 0 else {
      throw NSError(domain: "LibUSB", code: -1, userInfo: [NSLocalizedDescriptionKey: "get_device_descriptor failed"])
    }
    return USBIDs(
      vendorID: desc.idVendor,
      productID: desc.idProduct,
      bcdDevice: desc.bcdDevice,
      ifaceClass: iface.bInterfaceClass,
      ifaceSubclass: iface.bInterfaceSubClass,
      ifaceProtocol: iface.bInterfaceProtocol
    )
  }
}

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

    public static func readIDs(_ dev: OpaquePointer, ifaceIndex: UInt8) throws -> USBDeviceIDs {
      var desc = libusb_device_descriptor()
      guard libusb_get_device_descriptor(dev, &desc) == 0 else {
        throw NSError(domain: "LibUSB", code: 2, userInfo: [NSLocalizedDescriptionKey: "get_device_descriptor failed"])
      }

      var configDescPtr: UnsafeMutablePointer<libusb_config_descriptor>?
      guard libusb_get_active_config_descriptor(dev, &configDescPtr) == 0, let cfg = configDescPtr?.pointee else {
        throw NSError(domain: "LibUSB", code: 3, userInfo: [NSLocalizedDescriptionKey: "get_active_config_descriptor failed"])
      }
      defer { libusb_free_config_descriptor(configDescPtr) }

      let iface = cfg.interface.advanced(by: Int(ifaceIndex)).pointee
      let alt = iface.altsetting.pointee
      let bus = libusb_get_bus_number(dev)
      let addr = libusb_get_device_address(dev)

      return USBDeviceIDs(
        vid: desc.idVendor, pid: desc.idProduct, bcdDevice: desc.bcdDevice,
        ifaceClass: alt.bInterfaceClass, ifaceSubclass: alt.bInterfaceSubClass, ifaceProtocol: alt.bInterfaceProtocol,
        bus: bus, address: addr
      )
    }

    /// Enumerate all currently connected MTP devices
    public static func enumerateMTPDevices() async throws -> [MTPDeviceSummary] {
        // Use the shared context for consistency
        let ctx = LibUSBContext.shared.ctx

        var list: UnsafeMutablePointer<OpaquePointer?>?
        let cnt = libusb_get_device_list(ctx, &list)
        guard cnt > 0, let list else {
            throw TransportError.io("device list failed")
        }
        defer { libusb_free_device_list(list, 1) }

        var summaries: [MTPDeviceSummary] = []

        for i in 0..<Int(cnt) {
            guard let dev = list[i] else { continue }

            var desc = libusb_device_descriptor()
            guard libusb_get_device_descriptor(dev, &desc) == 0 else { continue }

            // Check if this is an MTP device (interface class 0x06)
            var cfg: UnsafeMutablePointer<libusb_config_descriptor>? = nil
            guard libusb_get_active_config_descriptor(dev, &cfg) == 0, let cfg else { continue }
            defer { libusb_free_config_descriptor(cfg) }

            var isMTP = false
            for i in 0..<cfg.pointee.bNumInterfaces {
                let iface = cfg.pointee.interface[Int(i)]
                for a in 0..<iface.num_altsetting {
                    let alt = iface.altsetting[Int(a)]
                    if alt.bInterfaceClass == 0x06 { // PTP/MTP
                        isMTP = true
                        break
                    }
                }
                if isMTP { break }
            }

            if isMTP {
                let bus = libusb_get_bus_number(dev)
                let addr = libusb_get_device_address(dev)
                let id = MTPDeviceID(raw: String(format:"%04x:%04x@%u:%u",
                                                 desc.idVendor, desc.idProduct, bus, addr))

                let summary = MTPDeviceSummary(
                    id: id,
                    manufacturer: "USB \(String(format:"%04x", desc.idVendor))",
                    model: "USB \(String(format:"%04x", desc.idProduct))",
                    vendorID: desc.idVendor,
                    productID: desc.idProduct,
                    bus: bus,
                    address: addr
                )
                summaries.append(summary)
            }
        }

        return summaries
    }
}

// MARK: - MTP Interface Discovery Helpers

private struct EPCandidates {
    var bulkIn: UInt8 = 0
    var bulkOut: UInt8 = 0
    var evtIn: UInt8 = 0
}

private func endpoints(_ alt: libusb_interface_descriptor) -> EPCandidates {
    var eps = EPCandidates()
    for i in 0..<Int(alt.bNumEndpoints) {
        let ed = alt.endpoint[i]
        let addr = ed.bEndpointAddress
        let dirIn = (addr & 0x80) != 0
        let attr = ed.bmAttributes & 0x03
        if attr == 2 { // LIBUSB_TRANSFER_TYPE_BULK
            if dirIn { eps.bulkIn = addr } else { eps.bulkOut = addr }
        } else if attr == 3 /* LIBUSB_TRANSFER_TYPE_INTERRUPT */, dirIn {
            eps.evtIn = addr
        }
    }
    return eps
}

private func asciiString(_ handle: OpaquePointer, _ index: UInt8) -> String {
    guard index != 0 else { return "" }
    var buf = [UInt8](repeating: 0, count: 128)
    let n = libusb_get_string_descriptor_ascii(handle, index, &buf, Int32(buf.count))
    if n > 0 { return String(cString: &buf) }
    return ""
}

/// Returns (ifaceIndex, altSetting, inEP, outEP, evtEP)
private func findMTPInterface(handle: OpaquePointer, device: OpaquePointer) throws -> (UInt8, UInt8, UInt8, UInt8, UInt8) {
    var cfgPtr: UnsafeMutablePointer<libusb_config_descriptor>?
    try check(libusb_get_active_config_descriptor(device, &cfgPtr))
    guard let cfg = cfgPtr?.pointee else { throw TransportError.io("no active config") }
    defer { libusb_free_config_descriptor(cfgPtr) }

    var best: (iface: UInt8, alt: UInt8, inEP: UInt8, outEP: UInt8, evt: UInt8, score: Int)? = nil

    for i in 0..<Int(cfg.bNumInterfaces) {
        let ifc = cfg.interface[i]
        for a in 0..<Int(ifc.num_altsetting) {
            let alt = ifc.altsetting[Int(a)]
            let cls = alt.bInterfaceClass
            let sub = alt.bInterfaceSubClass
            let pro = alt.bInterfaceProtocol
            let eps = endpoints(alt)
            if eps.bulkIn == 0 || eps.bulkOut == 0 { continue }

            // Score the candidate
            var score = 0
            // Primary path: PTP/MTP class (proto sometimes 0x00, 0x01, or vendor)
            if cls == 0x06 && sub == 0x01 { score += 100 }
            // Avoid ADB: vendor class with 0x42/0x01 or name containing "adb"
            let name = asciiString(handle, alt.iInterface).lowercased()
            let isADB = (cls == 0xFF && sub == 0x42 && pro == 0x01) || name.contains("adb")
            if isADB { score -= 200 }
            // Vendor-specific but labelled MTP/PTP in the string? accept cautiously
            if cls == 0xFF && (name.contains("mtp") || name.contains("ptp")) { score += 60 }
            // Bonus: has interrupt IN (event endpoint)
            if eps.evtIn != 0 { score += 5 }

            if score > (best?.score ?? -1) {
                best = (UInt8(i), alt.bAlternateSetting, eps.bulkIn, eps.bulkOut, eps.evtIn, score)
            }
        }
    }

    guard let sel = best, sel.score >= 60 else {
        throw TransportError.io("no MTP-like interface (scan failed)")
    }

    // Claim interface and set the selected alt
    try check(libusb_claim_interface(handle, Int32(sel.iface)))
    try check(libusb_set_interface_alt_setting(handle, Int32(sel.iface), Int32(sel.alt)))
    return (sel.iface, sel.alt, sel.inEP, sel.outEP, sel.evt)
}

public struct LibUSBTransport: MTPTransport {
  public init() {}

  public func open(_ summary: MTPDeviceSummary, config: SwiftMTPConfig = .init()) async throws -> MTPLink {
    // Use the shared context for consistency
    let ctx = LibUSBContext.shared.ctx

    // 1) Find device by bus/addr from summary.id
    var list: UnsafeMutablePointer<OpaquePointer?>?
    let cnt = libusb_get_device_list(ctx, &list)
    guard cnt > 0, let list else { throw TransportError.io("device list failed") }

    var target: OpaquePointer?
    for i in 0..<Int(cnt) {
      let dev = list[i]!
      let bus = libusb_get_bus_number(dev)
      let addr = libusb_get_device_address(dev)
      if summary.id.raw.hasSuffix(String(format:"@%u:%u", bus, addr)) {
        // Ref the device before we free the list
        libusb_ref_device(dev)
        target = dev
        break
      }
    }

    // Free the device list now that we've ref'd our target device
    libusb_free_device_list(list, 1)

    guard let dev = target else { throw TransportError.noDevice }

    // 2) Open + claim interface with class 0x06; cache endpoints
    var handle: OpaquePointer?
    guard libusb_open(dev, &handle) == 0, let handle else {
      libusb_unref_device(dev)
      throw TransportError.accessDenied
    }

    var cfg: UnsafeMutablePointer<libusb_config_descriptor>? = nil
    guard libusb_get_active_config_descriptor(dev, &cfg) == 0, let cfg else {
      libusb_close(handle)
      libusb_unref_device(dev)
      throw TransportError.io("no config")
    }
    defer { libusb_free_config_descriptor(cfg) }

    // Find the best MTP interface using robust alt-setting selection
    let (ifaceNum, altSetting, epIn, epOut, epEvt) = try {
      do {
        return try findMTPInterface(handle: handle, device: dev)
      } catch {
        libusb_close(handle)
        libusb_unref_device(dev)
        throw error
      }
    }()
    guard epIn != 0 && epOut != 0 else {
      libusb_close(handle)
      libusb_unref_device(dev)
      throw TransportError.io("no bulk endpoints")
    }

    // Debug logging for interface selection
    if ProcessInfo.processInfo.environment["SWIFTMTP_DEBUG"] == "1" {
      let evtStr = epEvt != 0 ? String(format: "0x%02x", epEvt) : "none"
      print("MTP iface=\(ifaceNum) alt=\(altSetting) epIn=0x\(String(format: "%02x", epIn)) epOut=0x\(String(format: "%02x", epOut)) evt=\(evtStr)")
    }

    return MTPUSBLink(handle: handle, device: dev, iface: ifaceNum, epIn: epIn, epOut: epOut, epEvt: epEvt, config: config)
  }
}

public final class MTPUSBLink: @unchecked Sendable, MTPLink {
  private let h: OpaquePointer
  private let device: OpaquePointer
  private let iface: UInt8
  let inEP, outEP, evtEP: UInt8
  private let ioQ = DispatchQueue(label: "com.effortlessmetrics.swiftmtp.usbio", qos: .userInitiated)
  private var nextTx: UInt32 = 1
  private let config: SwiftMTPConfig

  // Event streaming
  private var eventContinuation: AsyncStream<Data>.Continuation?
  private var eventPumpTask: Task<Void, Never>?

  /// Get USB device IDs for fingerprinting
  public func getUSBIDs(ifaceIndex: UInt8 = 0) throws -> LibUSBDiscovery.USBDeviceIDs {
    return try LibUSBDiscovery.readIDs(device, ifaceIndex: ifaceIndex)
  }

  init(handle: OpaquePointer, device: OpaquePointer, iface: UInt8, epIn: UInt8, epOut: UInt8, epEvt: UInt8, config: SwiftMTPConfig) {
    self.h = handle; self.device = device; self.iface = iface; self.inEP = epIn; self.outEP = epOut; self.evtEP = epEvt; self.config = config
  }

  public func close() async {
    // Stop event pump
    eventPumpTask?.cancel()
    eventPumpTask = nil
    eventContinuation?.finish()
    eventContinuation = nil

    libusb_release_interface(h, Int32(iface))
    libusb_close(h)
    libusb_unref_device(device)
  }

  /// Start event pump for interrupt IN endpoint
  public func startEventPump() {
    guard evtEP != 0 else { return } // No event endpoint available

    let stream = AsyncStream<Data> { continuation in
      self.eventContinuation = continuation
    }

    eventPumpTask = Task {
      await withTaskCancellationHandler {
        // Event pump loop
        while !Task.isCancelled {
          do {
            var buf = [UInt8](repeating: 0, count: 64 * 1024) // Large enough for event data
            let got = try bulkReadOnce(evtEP, into: &buf, max: buf.count, timeout: 1000) // 1s timeout for events
            if got > 0 {
              let data = Data(bytes: &buf, count: got)
              eventContinuation?.yield(data)
            }
          } catch {
            // Event read failed, but don't crash - just continue
            try? await Task.sleep(nanoseconds: 100_000_000) // 100ms backoff
          }
        }
      } onCancel: {
        eventContinuation?.finish()
      }
    }
  }

  // MARK: - Protocol Implementation

  public func openUSBIfNeeded() async throws {
    // Interface is already claimed during initialization
    // This method exists for protocol compliance but USB opening is handled in init
  }

  public func openSession(id: UInt32) async throws {
    let command = PTPContainer(
      length: 16,
      type: PTPContainer.Kind.command.rawValue,
      code: PTPOp.openSession.rawValue,
      txid: nextTx,
      params: [id]
    )
    nextTx &+= 1

    guard let response = try executeCommand(command) else {
      throw MTPError.protocolError(code: 0, message: "OpenSession command failed")
    }

    guard response.count >= 12 else {
      throw MTPError.protocolError(code: 0, message: "OpenSession response too short")
    }

    let responseCode = response.withUnsafeBytes {
      $0.load(fromByteOffset: 6, as: UInt16.self).littleEndian
    }

    guard responseCode == 0x2001 else {
      throw MTPError.protocolError(code: responseCode, message: "OpenSession failed")
    }
  }

  public func closeSession() async throws {
    let command = PTPContainer(
      length: 12,
      type: PTPContainer.Kind.command.rawValue,
      code: PTPOp.closeSession.rawValue,
      txid: nextTx,
      params: []
    )
    nextTx &+= 1

    _ = try executeCommand(command)
  }

  public func getDeviceInfo() async throws -> MTPDeviceInfo {
    let command = PTPContainer(
      length: 12,
      type: PTPContainer.Kind.command.rawValue,
      code: PTPOp.getDeviceInfo.rawValue,
      txid: nextTx,
      params: []
    )
    nextTx &+= 1

    guard try executeCommand(command) != nil else {
      throw MTPError.protocolError(code: 0, message: "No device info response")
    }

    // Parse DeviceInfo dataset - simplified implementation
    return MTPDeviceInfo(
      manufacturer: "Unknown",
      model: "Unknown",
      version: "1.0",
      serialNumber: "Unknown",
      operationsSupported: Set(),
      eventsSupported: Set()
    )
  }

  public func getStorageIDs() async throws -> [MTPStorageID] {
    let command = PTPContainer(
      length: 12,
      type: PTPContainer.Kind.command.rawValue,
      code: PTPOp.getStorageIDs.rawValue,
      txid: nextTx,
      params: []
    )
    nextTx &+= 1

    guard let responseData = try executeCommand(command) else {
      return []
    }

    guard responseData.count >= 4 else { return [] }

    let count = responseData.withUnsafeBytes { ptr in
      ptr.load(fromByteOffset: 0, as: UInt32.self).littleEndian
    }

    guard responseData.count >= 4 + Int(count) * 4 else { return [] }

    var storageIDs = [MTPStorageID]()
    for i in 0..<Int(count) {
      let offset = 4 + i * 4
      let storageIDRaw = responseData.withUnsafeBytes { ptr in
        ptr.load(fromByteOffset: offset, as: UInt32.self).littleEndian
      }
      storageIDs.append(MTPStorageID(raw: storageIDRaw))
    }

    return storageIDs
  }

  public func getStorageInfo(id: MTPStorageID) async throws -> MTPStorageInfo {
    let command = PTPContainer(
      length: 16,
      type: PTPContainer.Kind.command.rawValue,
      code: PTPOp.getStorageInfo.rawValue,
      txid: nextTx,
      params: [id.raw]
    )
    nextTx &+= 1

    guard let responseData = try executeCommand(command) else {
      throw MTPError.protocolError(code: 0, message: "No storage info response")
    }

    // Simplified parsing - full implementation would parse the complete StorageInfo dataset
    var offset = 0

    func read16() -> UInt16 {
      let value = responseData.withUnsafeBytes { ptr in
        let b0 = UInt16(ptr[offset])
        let b1 = UInt16(ptr[offset + 1]) << 8
        return b0 | b1
      }
      offset += 2
      return value
    }

    func read32() -> UInt32 {
      let value = responseData.withUnsafeBytes { ptr in
        let b0 = UInt32(ptr[offset])
        let b1 = UInt32(ptr[offset + 1]) << 8
        let b2 = UInt32(ptr[offset + 2]) << 16
        let b3 = UInt32(ptr[offset + 3]) << 24
        return b0 | b1 | b2 | b3
      }
      offset += 4
      return value
    }

    func read64() -> UInt64 {
      let value = responseData.withUnsafeBytes { ptr in
        let b0 = UInt64(ptr[offset])
        let b1 = UInt64(ptr[offset + 1]) << 8
        let b2 = UInt64(ptr[offset + 2]) << 16
        let b3 = UInt64(ptr[offset + 3]) << 24
        let b4 = UInt64(ptr[offset + 4]) << 32
        let b5 = UInt64(ptr[offset + 5]) << 40
        let b6 = UInt64(ptr[offset + 6]) << 48
        let b7 = UInt64(ptr[offset + 7]) << 56
        return b0 | b1 | b2 | b3 | b4 | b5 | b6 | b7
      }
      offset += 8
      return value
    }

    func readString() -> String {
      guard let string = PTPString.parse(from: responseData, at: &offset) else {
        return "Unknown"
      }
      return string
    }

    guard responseData.count >= 22 else {
      throw MTPError.protocolError(code: 0, message: "Storage info response too short")
    }

    let _ = read16() // StorageType
    let _ = read16() // FilesystemType
    let accessCapability = read16()
    let maxCapacity = read64()
    let freeSpace = read64()
    let _ = read32() // FreeSpaceInObjects
    let description = readString()
    let _ = readString() // VolumeLabel

    let isReadOnly = accessCapability == 0x0001

    return MTPStorageInfo(
      id: id,
      description: description,
      capacityBytes: maxCapacity,
      freeBytes: freeSpace,
      isReadOnly: isReadOnly
    )
  }

  public func getObjectHandles(storage: MTPStorageID, parent: MTPObjectHandle?) async throws -> [MTPObjectHandle] {
    let parentHandle = parent ?? 0xFFFFFFFF // 0xFFFFFFFF means root level

    let command = PTPContainer(
      length: 20,
      type: PTPContainer.Kind.command.rawValue,
      code: PTPOp.getObjectHandles.rawValue,
      txid: nextTx,
      params: [storage.raw, parentHandle]
    )
    nextTx &+= 1

    guard let responseData = try executeCommand(command) else {
      return []
    }

    guard responseData.count >= 4 else { return [] }

    let count = responseData.withUnsafeBytes { ptr in
      ptr.load(fromByteOffset: 0, as: UInt32.self).littleEndian
    }

    guard responseData.count >= 4 + Int(count) * 4 else { return [] }

    var objectHandles = [MTPObjectHandle]()
    for i in 0..<Int(count) {
      let offset = 4 + i * 4
      let handle = responseData.withUnsafeBytes { ptr in
        ptr.load(fromByteOffset: offset, as: UInt32.self).littleEndian
      }
      objectHandles.append(handle)
    }

    return objectHandles
  }

  public func getObjectInfos(_ handles: [MTPObjectHandle]) async throws -> [MTPObjectInfo] {
    var objectInfos = [MTPObjectInfo]()

    for handle in handles {
      let command = PTPContainer(
        length: 16,
        type: PTPContainer.Kind.command.rawValue,
        code: PTPOp.getObjectInfo.rawValue,
        txid: nextTx,
        params: [handle]
      )
      nextTx &+= 1

      guard let responseData = try executeCommand(command) else {
        continue
      }

      // Simplified parsing - full implementation would parse complete ObjectInfo dataset
      var offset = 0

      func read16() -> UInt16 {
        let value = responseData.withUnsafeBytes { ptr in
          let b0 = UInt16(ptr[offset])
          let b1 = UInt16(ptr[offset + 1]) << 8
          return b0 | b1
        }
        offset += 2
        return value
      }

      func read32() -> UInt32 {
        let value = responseData.withUnsafeBytes { ptr in
          let b0 = UInt32(ptr[offset])
          let b1 = UInt32(ptr[offset + 1]) << 8
          let b2 = UInt32(ptr[offset + 2]) << 16
          let b3 = UInt32(ptr[offset + 3]) << 24
          return b0 | b1 | b2 | b3
        }
        offset += 4
        return value
      }

      func readString() -> String {
        guard let string = PTPString.parse(from: responseData, at: &offset) else {
          return "Unknown"
        }
        return string
      }

      guard responseData.count >= 52 else {
        continue
      }

      let storageIDRaw = read32()
      let formatCode = read16()
      let _ = read16() // ProtectionStatus
      let compressedSize = read32()
      let _ = read16() // ThumbFormat
      let _ = read32() // ThumbCompressedSize
      let _ = read32() // ThumbWidth
      let _ = read32() // ThumbHeight
      let _ = read32() // ImageWidth
      let _ = read32() // ImageHeight
      let _ = read32() // ImageBitDepth
      let parentObject = read32()
      let _ = read16() // AssociationType
      let _ = read32() // AssociationDesc
      let _ = read32() // SequenceNumber
      let filename = readString()
      let _ = readString() // CaptureDate
      let _ = readString() // ModificationDate
      let _ = readString() // Keywords

      let storage = MTPStorageID(raw: storageIDRaw)
      let parent = parentObject == 0 ? nil : parentObject
      let size = compressedSize == 0xFFFFFFFF ? nil : UInt64(compressedSize)

      let objectInfo = MTPObjectInfo(
        handle: handle,
        storage: storage,
        parent: parent,
        name: filename,
        sizeBytes: size,
        modified: nil, // TODO: Parse modification date
        formatCode: formatCode,
        properties: [:] // TODO: Parse additional properties
      )
      objectInfos.append(objectInfo)
    }

    return objectInfos
  }

  // MARK: - Bulk I/O helpers

  @inline(__always)
  func bulkWriteAll(_ ep: UInt8, from ptr: UnsafeRawPointer, count: Int, timeout: UInt32) throws {
    var sentTotal = 0
    while sentTotal < count {
      var sent: Int32 = 0
      let rc = libusb_bulk_transfer(h, ep, UnsafeMutablePointer<UInt8>(mutating: ptr.advanced(by: sentTotal).assumingMemoryBound(to: UInt8.self)),
                                    Int32(count - sentTotal), &sent, timeout)
      if rc != 0 { throw MTPError.transport(mapLibusb(rc)) }
      sentTotal += Int(sent)
    }
  }

  /// Reads up to `max` bytes into `buf`. Returns bytes read (0 on timeout if device sent nothing).
  @inline(__always)
  func bulkReadOnce(_ ep: UInt8, into buf: UnsafeMutableRawPointer, max: Int, timeout: UInt32) throws -> Int {
    var got: Int32 = 0
    let rc = libusb_bulk_transfer(h, ep, buf.assumingMemoryBound(to: UInt8.self), Int32(max), &got, timeout)
    if rc == Int32(LIBUSB_ERROR_TIMEOUT.rawValue) { return 0 } // non-fatal; caller loop decides
    if rc != 0 { throw MTPError.transport(mapLibusb(rc)) }
    return Int(got)
  }

  /// Read exactly `need` bytes. Allows `firstChunk` pre-read (e.g., header+payload from same transfer).
  func bulkReadExact(_ ep: UInt8, into dst: UnsafeMutableRawPointer, need: Int, timeout: UInt32, firstChunk: UnsafeRawBufferPointer? = nil) throws {
    var copied = 0
    if let first = firstChunk, first.count > 0 {
      memcpy(dst, first.baseAddress!, first.count)
      copied += first.count
    }
    while copied < need {
      var tmp = [UInt8](repeating: 0, count: min(64 * 1024, need - copied))
      let got = try bulkReadOnce(ep, into: &tmp, max: tmp.count, timeout: timeout)
      if got == 0 { continue }
      memcpy(dst.advanced(by: copied), &tmp, got)
      copied += got
    }
  }

  // MARK: - MTP Command Execution

  public func executeCommand(_ command: PTPContainer) throws -> Data? {
    return try executeCommandSync(command: command, dataInHandler: nil, dataOutHandler: nil)
  }

  public func executeStreamingCommand(
    _ command: PTPContainer,
    dataInHandler: MTPDataIn?,
    dataOutHandler: MTPDataOut?
  ) async throws -> Data? {
    return try await withCheckedThrowingContinuation { cont in
      ioQ.async {
        do {
          let result = try self.executeCommandSync(command: command,
                                                   dataInHandler: dataInHandler,
                                                   dataOutHandler: dataOutHandler)
          cont.resume(returning: result)
        } catch {
          cont.resume(throwing: error)
        }
      }
    }
  }

  private func executeCommandSync(
    command: PTPContainer,
    dataInHandler: MTPDataIn?,
    dataOutHandler: MTPDataOut?
  ) throws -> Data? {
    let txid = nextTx &- 0 == 0 ? 1 : nextTx
    nextTx &+= 1

    // Overall operation deadline
    let opStartNs = DispatchTime.now().uptimeNanoseconds
    let opBudgetNs = UInt64(config.overallDeadlineMs) * 1_000_000
    @inline(__always) func checkDeadline() throws {
      if DispatchTime.now().uptimeNanoseconds - opStartNs > opBudgetNs {
        throw MTPError.timeout
      }
    }

    // Debug logging
    let debugEnabled = ProcessInfo.processInfo.environment["SWIFTMTP_DEBUG"] == "1"
    if debugEnabled {
      print(String(format: "MTP op=0x%04x tx=%u phase=command", command.code, txid))
    }

    // 1) COMMAND container
    let cmdBytes = makePTPCommand(opcode: command.code, txid: txid, params: command.params)
    try cmdBytes.withUnsafeBytes { raw in
      try bulkWriteAll(outEP, from: raw.baseAddress!, count: raw.count, timeout: UInt32(config.ioTimeoutMs))
    }
    try checkDeadline()

    // 2) Optional DATA OUT phase (host -> device)
    if let produce = dataOutHandler {
      if debugEnabled {
        print(String(format: "MTP op=0x%04x tx=%u phase=data-out", command.code, txid))
      }

      var sent = 0
      var scratch = [UInt8](repeating: 0, count: min(1 << 20, 1024 * 1024)) // up to 1 MiB scratch
      var lastProgressNs = DispatchTime.now().uptimeNanoseconds
      let stallNs = UInt64(config.inactivityTimeoutMs) * 1_000_000

      while true {
        let wrote = scratch.withUnsafeMutableBytes { buf in
          produce(buf)
        }
        if wrote == 0 { break }
        if DispatchTime.now().uptimeNanoseconds - lastProgressNs > stallNs {
          throw MTPError.timeout
        }
        try scratch.withUnsafeBytes { raw in
          try bulkWriteAll(outEP, from: raw.baseAddress!, count: wrote, timeout: UInt32(config.ioTimeoutMs))
        }
        lastProgressNs = DispatchTime.now().uptimeNanoseconds
        sent += wrote
      }

      if sent > 0 {
        // Send data container header
        let hdrBytes = makePTPDataContainer(length: UInt32(PTPHeader.size + sent), code: command.code, txid: txid)
        try hdrBytes.withUnsafeBytes { raw in
          try bulkWriteAll(outEP, from: raw.baseAddress!, count: raw.count, timeout: UInt32(config.ioTimeoutMs))
        }
      }
      try checkDeadline()
    }

    // 3) Optional DATA IN phase (device -> host)
    var dataInCollector = DataCollector()
    var hasDataPhase = false
    var dataHeader: PTPHeader?

    if dataInHandler != nil {
      if debugEnabled {
        print(String(format: "MTP op=0x%04x tx=%u phase=data-in", command.code, txid))
      }

      // Handshake timeout for first DATA-IN packet
      let startNs = DispatchTime.now().uptimeNanoseconds
      let handshakeBudgetNs = UInt64(max(config.handshakeTimeoutMs, 3000)) * 1_000_000 // at least 3s
      var gotFirst = 0
      var first = [UInt8](repeating: 0, count: max(PTPHeader.size, 64 * 1024))

      while gotFirst == 0 {
        gotFirst = try bulkReadOnce(inEP, into: &first, max: first.count, timeout: UInt32(config.ioTimeoutMs))
        if gotFirst == 0 {
          let elapsed = DispatchTime.now().uptimeNanoseconds - startNs
          if elapsed > handshakeBudgetNs {
            if debugEnabled {
              print(String(format: "MTP op=0x%04x tx=%u phase=handshake-in timeout after %d ms",
                          command.code, txid, Int(elapsed / 1_000_000)))
            }
            throw MTPError.timeout
          }
          continue
        }
      }

      guard gotFirst >= PTPHeader.size else {
        throw MTPError.transport(.io("short data header"))
      }

      dataHeader = first.withUnsafeBytes { PTPHeader.decode(from: $0.baseAddress!) }
      guard dataHeader?.type == PTPContainer.Kind.data.rawValue,
            dataHeader?.code == command.code,
            dataHeader?.txid == txid else {
        throw MTPError.transport(.io("unexpected data header type/code/tx"))
      }

      if dataHeader?.type == PTPContainer.Kind.data.rawValue {
        hasDataPhase = true
        let payloadLen = Int(dataHeader!.length) - PTPHeader.size
        let rem = gotFirst - PTPHeader.size
        if rem > 0 {
          first.withUnsafeBytes { raw in
            let chunk = UnsafeRawBufferPointer(start: raw.baseAddress!.advanced(by: PTPHeader.size), count: rem)
            _ = dataInHandler!(chunk)
          }
        }

        // Read the rest with inactivity timeout protection
        var left = payloadLen - max(0, rem)
        var lastProgressNs = DispatchTime.now().uptimeNanoseconds
        let stallNs = UInt64(config.inactivityTimeoutMs) * 1_000_000

        while left > 0 {
          var buf = [UInt8](repeating: 0, count: min(left, 1 << 20))
          let got = try bulkReadOnce(inEP, into: &buf, max: buf.count, timeout: UInt32(config.ioTimeoutMs))
          if got == 0 {
            if DispatchTime.now().uptimeNanoseconds - lastProgressNs > stallNs {
              if debugEnabled {
                print(String(format: "MTP op=0x%04x tx=%u phase=data-in timeout after %lld bytes",
                            command.code, txid, Int64(payloadLen - left)))
              }
              throw MTPError.timeout
            }
            continue
          }
          lastProgressNs = DispatchTime.now().uptimeNanoseconds
          buf.withUnsafeBytes { raw in
            _ = dataInHandler!(UnsafeRawBufferPointer(start: raw.baseAddress!, count: got))
          }
          left -= got
        }
      }
      try checkDeadline()
    }

    // 4) RESPONSE phase
    if debugEnabled {
      print(String(format: "MTP op=0x%04x tx=%u phase=response", command.code, txid))
    }

    var respHdrBuf = [UInt8](repeating: 0, count: PTPHeader.size)
    try bulkReadExact(inEP, into: &respHdrBuf, need: PTPHeader.size, timeout: UInt32(config.ioTimeoutMs))
    let rHdr = respHdrBuf.withUnsafeBytes { PTPHeader.decode(from: $0.baseAddress!) }
    guard rHdr.type == PTPContainer.Kind.response.rawValue, rHdr.txid == txid else {
      throw MTPError.transport(.io("unexpected response container: type=\(rHdr.type) tx=\(rHdr.txid)"))
    }

    let respParamBytes = Int(rHdr.length) - PTPHeader.size
    var params: [UInt32] = []
    if respParamBytes > 0 {
      precondition(respParamBytes % 4 == 0, "response params not multiple of 4")
      var buf = [UInt8](repeating: 0, count: respParamBytes)
      try bulkReadExact(inEP, into: &buf, need: buf.count, timeout: UInt32(config.ioTimeoutMs))
      params.reserveCapacity(respParamBytes / 4)
      buf.withUnsafeBytes { raw in
        var off = 0
        while off < respParamBytes {
          let v = raw.baseAddress!.advanced(by: off).load(as: UInt32.self).littleEndian
          params.append(v)
          off += 4
        }
      }
    }

    let response = PTPResponse(code: rHdr.code, txid: rHdr.txid, params: params)
    try mapResponse(response)

    // Return data if we collected any
    return hasDataPhase ? dataInCollector.finish() : nil
  }

  public func deleteObject(handle: MTPObjectHandle) async throws {
    let command = PTPContainer(
      length: 16,
      type: PTPContainer.Kind.command.rawValue,
      code: PTPOp.deleteObject.rawValue,
      txid: nextTx,
      params: [handle, 0]  // handle, format code (0 = delete object regardless of format)
    )
    nextTx &+= 1

    _ = try executeCommand(command)
  }

  public func moveObject(handle: MTPObjectHandle, to storage: MTPStorageID, parent: MTPObjectHandle?) async throws {
    let command = PTPContainer(
      length: 20,
      type: PTPContainer.Kind.command.rawValue,
      code: PTPOp.moveObject.rawValue,
      txid: nextTx,
      params: [handle, storage.raw, parent ?? 0xFFFFFFFF]
    )
    nextTx &+= 1

    _ = try executeCommand(command)
  }
}

// MARK: - Simple Data collector
private struct DataCollector {
  private var chunks: [Data] = []
  private var total = 0
  mutating func append(_ chunk: UnsafeRawBufferPointer) {
    chunks.append(Data(bytes: chunk.baseAddress!, count: chunk.count))
    total += chunk.count
  }
  mutating func finish() -> Data {
    var out = Data()
    out.reserveCapacity(total)
    for c in chunks { out.append(c) }
    chunks.removeAll(keepingCapacity: false)
    total = 0
    return out
  }
}

// MTPTransport and MTPLink protocols are defined in SwiftMTPCore
