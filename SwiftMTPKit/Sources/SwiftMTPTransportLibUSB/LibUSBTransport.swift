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

    public static func enumerateMTPDevices() async throws -> [MTPDeviceSummary] {
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

            var cfg: UnsafeMutablePointer<libusb_config_descriptor>? = nil
            guard libusb_get_active_config_descriptor(dev, &cfg) == 0, let cfg else { continue }
            defer { libusb_free_config_descriptor(cfg) }

            var isMTP = false
            for j in 0..<cfg.pointee.bNumInterfaces {
                let iface = cfg.pointee.interface[Int(j)]
                for a in 0..<iface.num_altsetting {
                    let alt = iface.altsetting[Int(a)]
                    if alt.bInterfaceClass == 0x06 { 
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
        } else if attr == 3, dirIn { // LIBUSB_TRANSFER_TYPE_INTERRUPT
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
            let eps = endpoints(alt)
            if eps.bulkIn == 0 || eps.bulkOut == 0 { continue }

            var score = 0
            if cls == 0x06 && sub == 0x01 { score += 100 }
            let name = asciiString(handle, alt.iInterface).lowercased()
            if (cls == 0xFF && sub == 0x42) || name.contains("adb") { score -= 200 }
            if cls == 0xFF && (name.contains("mtp") || name.contains("ptp")) { score += 60 }
            if eps.evtIn != 0 { score += 5 }

            if score > (best?.score ?? -1) {
                best = (UInt8(i), alt.bAlternateSetting, eps.bulkIn, eps.bulkOut, eps.evtIn, score)
            }
        }
    }

    guard let sel = best, sel.score >= 60 else {
        throw TransportError.io("no MTP-like interface (scan failed)")
    }

    try check(libusb_claim_interface(handle, Int32(sel.iface)))
    if sel.alt > 0 {
        try check(libusb_set_interface_alt_setting(handle, Int32(sel.iface), Int32(sel.alt)))
    }
    return (sel.iface, sel.alt, sel.inEP, sel.outEP, sel.evt)
}

public struct LibUSBTransport: MTPTransport {
  public init() {}

  public func open(_ summary: MTPDeviceSummary, config: SwiftMTPConfig = .init()) async throws -> MTPLink {
    let ctx = LibUSBContext.shared.ctx
    var list: UnsafeMutablePointer<OpaquePointer?>?
    let cnt = libusb_get_device_list(ctx, &list)
    guard cnt > 0, let list else { throw TransportError.io("device list failed") }

    var target: OpaquePointer?
    for i in 0..<Int(cnt) {
      let dev = list[i]!
      let bus = libusb_get_bus_number(dev)
      let addr = libusb_get_device_address(dev)
      if summary.id.raw.hasSuffix(String(format:"@%u:%u", bus, addr)) {
        libusb_ref_device(dev)
        target = dev
        break
      }
    }
    libusb_free_device_list(list, 1)

    guard let dev = target else { throw TransportError.noDevice }

    var handle: OpaquePointer?
    guard libusb_open(dev, &handle) == 0, let handle else {
      libusb_unref_device(dev)
      throw TransportError.accessDenied
    }

    _ = libusb_reset_device(handle)
    try? await Task.sleep(nanoseconds: 500_000_000)

    var cfg: UnsafeMutablePointer<libusb_config_descriptor>? = nil
    guard libusb_get_active_config_descriptor(dev, &cfg) == 0, let cfg else {
      libusb_close(handle)
      libusb_unref_device(dev)
      throw TransportError.io("no config")
    }
    defer { libusb_free_config_descriptor(cfg) }

    let (ifaceNum, altSetting, epIn, epOut, epEvt) = try {
      do { return try findMTPInterface(handle: handle, device: dev) }
      catch { libusb_close(handle); libusb_unref_device(dev); throw error }
    }()

    if ProcessInfo.processInfo.environment["SWIFTMTP_DEBUG"] == "1" {
      let evtStr = epEvt != 0 ? String(format: "0x%02x", epEvt) : "none"
      print("MTP iface=\(ifaceNum) alt=\(altSetting) epIn=0x\(String(format: "%02x", epIn)) epOut=0x\(String(format: "%02x", epOut)) evt=\(evtStr)")
    }

    _ = libusb_clear_halt(handle, epIn)
    _ = libusb_clear_halt(handle, epOut)
    var drainBuf = [UInt8](repeating: 0, count: 512)
    var got: Int32 = 0
    while libusb_bulk_transfer(handle, epIn, &drainBuf, 512, &got, 50) == 0 && got > 0 {}

    return MTPUSBLink(handle: handle, device: dev, iface: ifaceNum, epIn: epIn, epOut: epOut, epEvt: epEvt, config: config, manufacturer: summary.manufacturer, model: summary.model)
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
  private let manufacturer: String
  private let model: String

  private var eventContinuation: AsyncStream<Data>.Continuation?
  private var eventPumpTask: Task<Void, Never>?

  init(handle: OpaquePointer, device: OpaquePointer, iface: UInt8, epIn: UInt8, epOut: UInt8, epEvt: UInt8, config: SwiftMTPConfig, manufacturer: String, model: String) {
    self.h = handle; self.device = device; self.iface = iface; self.inEP = epIn; self.outEP = epOut; self.evtEP = epEvt; self.config = config
    self.manufacturer = manufacturer; self.model = model
  }

  public func close() async {
    eventPumpTask?.cancel()
    eventPumpTask = nil
    eventContinuation?.finish()
    eventContinuation = nil
    libusb_release_interface(h, Int32(iface))
    libusb_close(h)
    libusb_unref_device(device)
  }

  public func startEventPump() {
    guard evtEP != 0 else { return }
    let _ = AsyncStream<Data> { continuation in
      self.eventContinuation = continuation
    }
    eventPumpTask = Task {
      while !Task.isCancelled {
        do {
          var buf = [UInt8](repeating: 0, count: 64 * 1024)
          let got = try bulkReadOnce(evtEP, into: &buf, max: buf.count, timeout: 1000)
          if got > 0 { eventContinuation?.yield(Data(bytes: &buf, count: got)) }
        } catch {
          try? await Task.sleep(nanoseconds: 100_000_000)
        }
      }
    }
  }

  public func openUSBIfNeeded() async throws {}

  public func openSession(id: UInt32) async throws {
    let command = PTPContainer(length: 16, type: PTPContainer.Kind.command.rawValue, code: PTPOp.openSession.rawValue, txid: nextTx, params: [id])
    _ = try await executeStreamingCommand(command, dataPhaseLength: nil, dataInHandler: nil, dataOutHandler: nil)
  }

  public func closeSession() async throws {
    let command = PTPContainer(length: 12, type: PTPContainer.Kind.command.rawValue, code: PTPOp.closeSession.rawValue, txid: nextTx, params: [])
    _ = try await executeStreamingCommand(command, dataPhaseLength: nil, dataInHandler: nil, dataOutHandler: nil)
  }

  public func getDeviceInfo() async throws -> MTPDeviceInfo {
    let command = PTPContainer(length: 12, type: PTPContainer.Kind.command.rawValue, code: PTPOp.getDeviceInfo.rawValue, txid: 0, params: [])
    let collector = SimpleCollector()
    _ = try await executeStreamingCommand(command, dataPhaseLength: nil, dataInHandler: { chunk in
        collector.append(chunk)
        return chunk.count
    }, dataOutHandler: nil)

    if let ptpInfo = PTPDeviceInfo.parse(from: collector.data) {
        return MTPDeviceInfo(manufacturer: ptpInfo.manufacturer, model: ptpInfo.model, version: ptpInfo.deviceVersion, serialNumber: ptpInfo.serialNumber, operationsSupported: Set(ptpInfo.operationsSupported), eventsSupported: Set(ptpInfo.eventsSupported))
    }
    return MTPDeviceInfo(manufacturer: manufacturer, model: model, version: "1.0", serialNumber: "Unknown", operationsSupported: Set(), eventsSupported: Set())
  }

  public func getStorageIDs() async throws -> [MTPStorageID] {
    let command = PTPContainer(length: 12, type: PTPContainer.Kind.command.rawValue, code: PTPOp.getStorageIDs.rawValue, txid: 0, params: [])
    let collector = SimpleCollector()
    _ = try await executeStreamingCommand(command, dataPhaseLength: nil, dataInHandler: { chunk in
        collector.append(chunk)
        return chunk.count
    }, dataOutHandler: nil)

    let collectedData = collector.data
    guard collectedData.count >= 4 else { return [] }
    let count = collectedData.withUnsafeBytes { $0.load(fromByteOffset: 0, as: UInt32.self).littleEndian }
    guard collectedData.count >= 4 + Int(count) * 4 else { return [] }
    var storageIDs = [MTPStorageID]()
    for i in 0..<Int(count) {
      let storageIDRaw = collectedData.withUnsafeBytes { $0.load(fromByteOffset: 4 + i * 4, as: UInt32.self).littleEndian }
      storageIDs.append(MTPStorageID(raw: storageIDRaw))
    }
    return storageIDs
  }

  public func getStorageInfo(id: MTPStorageID) async throws -> MTPStorageInfo {
    let command = PTPContainer(length: 16, type: PTPContainer.Kind.command.rawValue, code: PTPOp.getStorageInfo.rawValue, txid: 0, params: [id.raw])
    let collector = SimpleCollector()
    _ = try await executeStreamingCommand(command, dataPhaseLength: nil, dataInHandler: { chunk in
        collector.append(chunk)
        return chunk.count
    }, dataOutHandler: nil)

    let responseData = collector.data
    var offset = 0
    func read16() -> UInt16 { var v: UInt16 = 0; _ = withUnsafeMutableBytes(of: &v) { responseData.copyBytes(to: $0, from: offset..<offset+2) }; offset += 2; return v.littleEndian }
    func read32() -> UInt32 { var v: UInt32 = 0; _ = withUnsafeMutableBytes(of: &v) { responseData.copyBytes(to: $0, from: offset..<offset+4) }; offset += 4; return v.littleEndian }
    func read64() -> UInt64 { var v: UInt64 = 0; _ = withUnsafeMutableBytes(of: &v) { responseData.copyBytes(to: $0, from: offset..<offset+8) }; offset += 8; return v.littleEndian }
    func readString() -> String { guard let s = PTPString.parse(from: responseData, at: &offset) else { return "Unknown" }; return s }

    guard responseData.count >= 22 else { throw MTPError.protocolError(code: 0, message: "Storage info response too short") }
    _ = read16(); _ = read16()
    let accessCapability = read16()
    let maxCapacity = read64()
    let freeSpace = read64()
    _ = read32()
    let description = readString()
    return MTPStorageInfo(id: id, description: description, capacityBytes: maxCapacity, freeBytes: freeSpace, isReadOnly: accessCapability == 0x0001)
  }

  public func getObjectHandles(storage: MTPStorageID, parent: MTPObjectHandle?) async throws -> [MTPObjectHandle] {
    let parentHandle = parent ?? 0x00000000
    let command = PTPContainer(length: 24, type: PTPContainer.Kind.command.rawValue, code: PTPOp.getObjectHandles.rawValue, txid: 0, params: [storage.raw, 0, parentHandle])
    let collector = SimpleCollector()
    _ = try await executeStreamingCommand(command, dataPhaseLength: nil, dataInHandler: { chunk in
        collector.append(chunk)
        return chunk.count
    }, dataOutHandler: nil)

    let collectedData = collector.data
    guard collectedData.count >= 4 else { return [] }
    let count = collectedData.withUnsafeBytes { $0.load(fromByteOffset: 0, as: UInt32.self).littleEndian }
    guard collectedData.count >= 4 + Int(count) * 4 else { return [] }
    var objectHandles = [MTPObjectHandle]()
    for i in 0..<Int(count) {
      let handle = collectedData.withUnsafeBytes { $0.load(fromByteOffset: 4 + i * 4, as: UInt32.self).littleEndian }
      objectHandles.append(handle)
    }
    return objectHandles
  }

  public func getObjectInfos(_ handles: [MTPObjectHandle]) async throws -> [MTPObjectInfo] {
    var objectInfos = [MTPObjectInfo]()
    for handle in handles {
      let command = PTPContainer(length: 16, type: PTPContainer.Kind.command.rawValue, code: PTPOp.getObjectInfo.rawValue, txid: 0, params: [handle])
      let collector = SimpleCollector()
      _ = try await executeStreamingCommand(command, dataPhaseLength: nil, dataInHandler: { chunk in
          collector.append(chunk)
          return chunk.count
      }, dataOutHandler: nil)

      let responseData = collector.data
      var offset = 0
      func read16() -> UInt16 { var v: UInt16 = 0; _ = withUnsafeMutableBytes(of: &v) { responseData.copyBytes(to: $0, from: offset..<offset+2) }; offset += 2; return v.littleEndian }
      func read32() -> UInt32 { var v: UInt32 = 0; _ = withUnsafeMutableBytes(of: &v) { responseData.copyBytes(to: $0, from: offset..<offset+4) }; offset += 4; return v.littleEndian }
      func readString() -> String { guard let s = PTPString.parse(from: responseData, at: &offset) else { return "Unknown" }; return s }

      if responseData.count < 52 { continue }
      let storageIDRaw = read32()
      let formatCode = read16()
      _ = read16()
      let compressedSize = read32()
      _ = read16(); _ = read32(); _ = read32(); _ = read32(); _ = read32(); _ = read32(); _ = read32()
      let parentObject = read32()
      _ = read16(); _ = read32(); _ = read32()
      let filename = readString()
      objectInfos.append(MTPObjectInfo(handle: handle, storage: MTPStorageID(raw: storageIDRaw), parent: parentObject == 0 ? nil : parentObject, name: filename, sizeBytes: compressedSize == 0xFFFFFFFF ? nil : UInt64(compressedSize), modified: nil, formatCode: formatCode, properties: [:]))
    }
    return objectInfos
  }

  public func getObjectInfos(storage: MTPStorageID, parent: MTPObjectHandle?, format: UInt16?) async throws -> [MTPObjectInfo] {
    let parentHandle = parent ?? 0x00000000
    let formatCode = format ?? 0x00000000
    let command = PTPContainer(length: 32, type: PTPContainer.Kind.command.rawValue, code: 0x9805, txid: 0, params: [parentHandle, 0xFFFFFFFF, UInt32(formatCode), storage.raw, 1])
    let collector = SimpleCollector()
    let debugEnabled = ProcessInfo.processInfo.environment["SWIFTMTP_DEBUG"] == "1"
    do {
        _ = try await executeStreamingCommand(command, dataPhaseLength: nil, dataInHandler: { chunk in
            collector.append(chunk)
            return chunk.count
        }, dataOutHandler: nil)
    } catch {
        if debugEnabled { print("   [USB] GetObjectPropList failed: \(error), falling back to slow path") }
        let handles = try await getObjectHandles(storage: storage, parent: parent)
        return try await getObjectInfos(handles)
    }

    guard let propList = PTPPropList.parse(from: collector.data) else {
        if debugEnabled { print("   [USB] PTPPropList.parse failed (data size: \(collector.data.count)), falling back to slow path") }
        let handles = try await getObjectHandles(storage: storage, parent: parent)
        return try await getObjectInfos(handles)
    }

    if debugEnabled { print("   [USB] GetObjectPropList returned \(propList.entries.count) property entries") }
    var grouped = [UInt32: [UInt16: Any]]()
    for entry in propList.entries {
        if grouped[entry.handle] == nil { grouped[entry.handle] = [:] }
        if let val = entry.value { grouped[entry.handle]![entry.propertyCode] = val }
    }

    return grouped.map { handle, props in
        let storageID = (props[0xDC01] as? UInt32).map { MTPStorageID(raw: $0) } ?? storage
        let parentID = props[0xDC0B] as? UInt32
        let name = (props[0xDC07] as? String) ?? "Unknown"
        let size = (props[0xDC04] as? UInt64)
        let format = (props[0xDC02] as? UInt16) ?? 0
        return MTPObjectInfo(handle: handle, storage: storageID, parent: parentID == 0 ? nil : parentID, name: name, sizeBytes: size, modified: nil, formatCode: format, properties: [:])
    }
  }

  public func deleteObject(handle: MTPObjectHandle) async throws {
    let command = PTPContainer(length: 16, type: PTPContainer.Kind.command.rawValue, code: PTPOp.deleteObject.rawValue, txid: 0, params: [handle, 0])
    _ = try await executeStreamingCommand(command, dataPhaseLength: nil, dataInHandler: nil, dataOutHandler: nil)
  }

  public func moveObject(handle: MTPObjectHandle, to storage: MTPStorageID, parent: MTPObjectHandle?) async throws {
    let command = PTPContainer(length: 20, type: PTPContainer.Kind.command.rawValue, code: PTPOp.moveObject.rawValue, txid: 0, params: [handle, storage.raw, parent ?? 0xFFFFFFFF])
    _ = try await executeStreamingCommand(command, dataPhaseLength: nil, dataInHandler: nil, dataOutHandler: nil)
  }

  @inline(__always)
  func bulkWriteAll(_ ep: UInt8, from ptr: UnsafeRawPointer, count: Int, timeout: UInt32) throws {
    var sentTotal = 0
    while sentTotal < count {
      var sent: Int32 = 0
      let rc = libusb_bulk_transfer(h, ep, UnsafeMutablePointer<UInt8>(mutating: ptr.advanced(by: sentTotal).assumingMemoryBound(to: UInt8.self)), Int32(count - sentTotal), &sent, timeout)
      if rc != 0 { throw MTPError.transport(mapLibusb(rc)) }
      sentTotal += Int(sent)
    }
  }

  @inline(__always)
  func bulkReadOnce(_ ep: UInt8, into buf: UnsafeMutableRawPointer, max: Int, timeout: UInt32) throws -> Int {
    var got: Int32 = 0
    if max < 512 {
        var tmp = [UInt8](repeating: 0, count: 512)
        let rc = libusb_bulk_transfer(h, ep, &tmp, 512, &got, timeout)
        if rc == Int32(LIBUSB_ERROR_TIMEOUT.rawValue) { return 0 }
        if rc != 0 && rc != Int32(LIBUSB_ERROR_OVERFLOW.rawValue) { throw MTPError.transport(mapLibusb(rc)) }
        let actualToCopy = min(Int(got), max)
        if actualToCopy > 0 { memcpy(buf, tmp, actualToCopy) }
        return actualToCopy
    }
    let rc = libusb_bulk_transfer(h, ep, buf.assumingMemoryBound(to: UInt8.self), Int32(max), &got, timeout)
    if rc == Int32(LIBUSB_ERROR_TIMEOUT.rawValue) { return 0 }
    if rc != 0 { throw MTPError.transport(mapLibusb(rc)) }
    return Int(got)
  }

  func bulkReadExact(_ ep: UInt8, into dst: UnsafeMutableRawPointer, need: Int, timeout: UInt32, firstChunk: UnsafeRawBufferPointer? = nil) throws {
    var copied = 0
    if let first = firstChunk, first.count > 0 {
      let toCopy = min(first.count, need); memcpy(dst, first.baseAddress!, toCopy); copied += toCopy
    }
    let startNs = DispatchTime.now().uptimeNanoseconds
    let budgetNs = UInt64(timeout) * 1_000_000
    while copied < need {
      var tmp = [UInt8](repeating: 0, count: min(64 * 1024, need - copied))
      let got = try bulkReadOnce(ep, into: &tmp, max: tmp.count, timeout: 1000)
      if got > 0 { memcpy(dst.advanced(by: copied), &tmp, got); copied += got }
      else if DispatchTime.now().uptimeNanoseconds - startNs > budgetNs { throw MTPError.timeout }
    }
  }

  public func executeCommand(_ command: PTPContainer) throws -> Data? {
    // This synchronous method is deprecated in favor of executeStreamingCommand
    // For now, it fails if called from outside our internal async context
    fatalError("executeCommand sync called directly")
  }

  public func executeStreamingCommand(_ command: PTPContainer, dataPhaseLength: UInt64? = nil, dataInHandler: MTPDataIn?, dataOutHandler: MTPDataOut?) async throws -> Data? {
    return try await withCheckedThrowingContinuation { cont in
      ioQ.async {
        Task {
            do {
                let res = try await self.executeCommandAsync(command: command, dataPhaseLength: dataPhaseLength, dataInHandler: dataInHandler, dataOutHandler: dataOutHandler)
                cont.resume(returning: res)
            } catch {
                cont.resume(throwing: error)
            }
        }
      }
    }
  }

  private func executeCommandAsync(command: PTPContainer, dataPhaseLength: UInt64? = nil, dataInHandler: MTPDataIn?, dataOutHandler: MTPDataOut?) async throws -> Data? {
    let txid: UInt32 = (command.code == 0x1002) ? 0 : { let t = nextTx; nextTx = (nextTx == 0xFFFFFFFF) ? 1 : nextTx + 1; return t }()
    let opStartNs = DispatchTime.now().uptimeNanoseconds
    let opBudgetNs = UInt64(config.overallDeadlineMs) * 1_000_000
    @inline(__always) func checkDeadline() throws { if DispatchTime.now().uptimeNanoseconds - opStartNs > opBudgetNs { throw MTPError.timeout } }
    let debugEnabled = ProcessInfo.processInfo.environment["SWIFTMTP_DEBUG"] == "1"
    if debugEnabled { print(String(format: "   [USB] op=0x%04x tx=%u phase=COMMAND", command.code, txid)) }

    let cmdBytes = makePTPCommand(opcode: command.code, txid: txid, params: command.params)
    try cmdBytes.withUnsafeBytes { try bulkWriteAll(outEP, from: $0.baseAddress!, count: $0.count, timeout: UInt32(config.ioTimeoutMs)) }
    try checkDeadline()

    if let produce = dataOutHandler {
      if debugEnabled { print(String(format: "   [USB] op=0x%04x tx=%u phase=DATA-OUT", command.code, txid)) }
      if let length = dataPhaseLength {
        let hdrBytes = makePTPDataContainer(length: UInt32(PTPHeader.size + Int(min(length, UInt64(UInt32.max - 12)))), code: command.code, txid: txid)
        try hdrBytes.withUnsafeBytes { try bulkWriteAll(outEP, from: $0.baseAddress!, count: $0.count, timeout: UInt32(config.ioTimeoutMs)) }
        var sent = 0; var scratch = [UInt8](repeating: 0, count: 64 * 1024)
        while true {
          let wrote = scratch.withUnsafeMutableBytes { produce($0) }
          if wrote == 0 { break }
          try scratch.withUnsafeBytes { try bulkWriteAll(outEP, from: $0.baseAddress!, count: wrote, timeout: UInt32(config.ioTimeoutMs)) }
          sent += wrote
        }
        if sent % 512 == 0 { var dummy: UInt8 = 0; _ = libusb_bulk_transfer(h, outEP, &dummy, 0, nil, 100) }
      } else {
        var collected = Data(); var scratch = [UInt8](repeating: 0, count: 64 * 1024)
        while true { let wrote = scratch.withUnsafeMutableBytes { produce($0) }; if wrote == 0 { break }; collected.append(contentsOf: scratch[0..<wrote]) }
        let hdrBytes = makePTPDataContainer(length: UInt32(PTPHeader.size + collected.count), code: command.code, txid: txid)
        try hdrBytes.withUnsafeBytes { try bulkWriteAll(outEP, from: $0.baseAddress!, count: $0.count, timeout: UInt32(config.ioTimeoutMs)) }
        
        if !collected.isEmpty {
            try? await Task.sleep(nanoseconds: 10_000_000)
            try collected.withUnsafeBytes { try bulkWriteAll(outEP, from: $0.baseAddress!, count: $0.count, timeout: UInt32(config.ioTimeoutMs)) }
        }
        if collected.count % 512 == 0 { var dummy: UInt8 = 0; _ = libusb_bulk_transfer(h, outEP, &dummy, 0, nil, 100) }
      }
      try checkDeadline()
    }

    var hasDataPhase = false; let collector = SimpleCollector(); var firstChunkForResponse: Data? = nil
    if dataInHandler != nil {
      if debugEnabled { print(String(format: "   [USB] op=0x%04x tx=%u phase=DATA-IN", command.code, txid)) }
      let startNs = DispatchTime.now().uptimeNanoseconds; let handshakeBudgetNs = UInt64(max(config.handshakeTimeoutMs, 3000)) * 1_000_000
      var gotFirst = 0; var first = [UInt8](repeating: 0, count: max(PTPHeader.size, 64 * 1024))
      while gotFirst == 0 {
        gotFirst = try bulkReadOnce(inEP, into: &first, max: first.count, timeout: 500)
        if gotFirst == 0 {
          if DispatchTime.now().uptimeNanoseconds - startNs > handshakeBudgetNs { throw MTPError.timeout }
          try checkDeadline(); continue
        }
      }
      let dataHeader = first.withUnsafeBytes { PTPHeader.decode(from: $0.baseAddress!) }
      if dataHeader.type == PTPContainer.Kind.response.rawValue { 
          if debugEnabled { print(String(format: "   [USB] op=0x%04x tx=%u skipped data phase, got response 0x%04x", command.code, txid, dataHeader.code)) }
          firstChunkForResponse = Data(first[0..<gotFirst]) 
      }
      else {
        guard dataHeader.type == PTPContainer.Kind.data.rawValue, dataHeader.code == command.code, dataHeader.txid == txid else { throw MTPError.transport(.io("unexpected data header type=\(dataHeader.type) code=0x\(String(format: "%04x", dataHeader.code)) tx=\(dataHeader.txid)")) }
        hasDataPhase = true; let payloadLen = Int(dataHeader.length) - PTPHeader.size; let rem = gotFirst - PTPHeader.size
        if rem > 0 { first.withUnsafeBytes { _ = dataInHandler!(UnsafeRawBufferPointer(start: $0.baseAddress!.advanced(by: PTPHeader.size), count: rem)) } }
        var left = payloadLen - max(0, rem); var lastProgressNs = DispatchTime.now().uptimeNanoseconds; let stallNs = UInt64(config.inactivityTimeoutMs) * 1_000_000
        while left > 0 {
          var buf = [UInt8](repeating: 0, count: min(left, 1 << 20))
          let got = try bulkReadOnce(inEP, into: &buf, max: buf.count, timeout: 1000)
          if got == 0 { if DispatchTime.now().uptimeNanoseconds - lastProgressNs > stallNs { throw MTPError.timeout }; try checkDeadline(); continue }
          lastProgressNs = DispatchTime.now().uptimeNanoseconds; buf.withUnsafeBytes { _ = dataInHandler!($0) }; left -= got
        }
      }
      try checkDeadline()
    }

    if debugEnabled { print(String(format: "   [USB] op=0x%04x tx=%u phase=RESPONSE", command.code, txid)) }
    let rHdr: PTPHeader; var respParamBytes = 0; var params: [UInt32] = []
    if let first = firstChunkForResponse {
        rHdr = first.withUnsafeBytes { PTPHeader.decode(from: $0.baseAddress!) }
        respParamBytes = Int(rHdr.length) - PTPHeader.size
        if respParamBytes > 0 {
            let available = first.count - PTPHeader.size; let toProcess = min(available, respParamBytes)
            params = first.withUnsafeBytes { raw in var p = [UInt32](); var off = PTPHeader.size; while off < PTPHeader.size + toProcess { p.append(raw.load(fromByteOffset: off, as: UInt32.self).littleEndian); off += 4 }; return p }
            respParamBytes -= toProcess
        }
    } else {
        var respHdrBuf = [UInt8](repeating: 0, count: PTPHeader.size)
        try bulkReadExact(inEP, into: &respHdrBuf, need: PTPHeader.size, timeout: UInt32(config.ioTimeoutMs))
        rHdr = respHdrBuf.withUnsafeBytes { PTPHeader.decode(from: $0.baseAddress!) }
        respParamBytes = Int(rHdr.length) - PTPHeader.size
    }
    guard rHdr.type == PTPContainer.Kind.response.rawValue, rHdr.txid == txid else { throw MTPError.transport(.io("unexpected response container: type=\(rHdr.type) tx=\(rHdr.txid)")) }
    if respParamBytes > 0 {
      var buf = [UInt8](repeating: 0, count: respParamBytes)
      try bulkReadExact(inEP, into: &buf, need: buf.count, timeout: UInt32(config.ioTimeoutMs))
      buf.withUnsafeBytes { raw in var off = 0; while off < respParamBytes { params.append(raw.load(fromByteOffset: off, as: UInt32.self).littleEndian); off += 4 } }
    }
    try mapResponse(PTPResponse(code: rHdr.code, txid: rHdr.txid, params: params))
    if command.code == 0x100C && !params.isEmpty { var handleData = Data(); withUnsafeBytes(of: params[0].littleEndian) { handleData.append(contentsOf: $0) }; return handleData }
    return hasDataPhase ? collector.data : nil
  }
}

final class SimpleCollector: @unchecked Sendable {
    var data = Data()
    private let lock = NSLock()
    func append(_ chunk: UnsafeRawBufferPointer) {
        lock.lock(); defer { lock.unlock() }; data.append(Data(bytes: chunk.baseAddress!, count: chunk.count))
    }
}
