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
        let ctx = LibUSBContext.shared.ctx
        var list: UnsafeMutablePointer<OpaquePointer?>?
        let cnt = libusb_get_device_list(ctx, &list)
        guard cnt > 0, let list else { throw TransportError.io("device list failed") }
        defer { libusb_free_device_list(list, 1) }

        var summaries: [MTPDeviceSummary] = []
        for i in 0..<Int(cnt) {
            guard let dev = list[i] else { continue }
            var desc = libusb_device_descriptor()
            guard libusb_get_device_descriptor(dev, &desc) == 0 else { continue }
            var cfgPtr: UnsafeMutablePointer<libusb_config_descriptor>? = nil
            guard libusb_get_active_config_descriptor(dev, &cfgPtr) == 0, let cfg = cfgPtr else { continue }
            defer { libusb_free_config_descriptor(cfg) }
            var isMTP = false
            for j in 0..<cfg.pointee.bNumInterfaces {
                let iface = cfg.pointee.interface[Int(j)]
                for a in 0..<iface.num_altsetting {
                    let alt = iface.altsetting[Int(a)]
                    if alt.bInterfaceClass == 0x06 { isMTP = true; break }
                }
                if isMTP { break }
            }
            if isMTP {
                let bus = libusb_get_bus_number(dev), addr = libusb_get_device_address(dev)
                summaries.append(MTPDeviceSummary(id: MTPDeviceID(raw: String(format:"%04x:%04x@%u:%u", desc.idVendor, desc.idProduct, bus, addr)), manufacturer: "USB \(String(format:"%04x", desc.idVendor))", model: "USB \(String(format:"%04x", desc.idProduct))", vendorID: desc.idVendor, productID: desc.idProduct, bus: bus, address: addr))
            }
        }
        return summaries
    }
}

private struct EPCandidates { var bulkIn: UInt8 = 0; var bulkOut: UInt8 = 0; var evtIn: UInt8 = 0 }
private func findEndpoints(_ alt: libusb_interface_descriptor) -> EPCandidates {
    var eps = EPCandidates()
    for i in 0..<Int(alt.bNumEndpoints) {
        let ed = alt.endpoint[i]
        let addr = ed.bEndpointAddress, dirIn = (addr & 0x80) != 0, attr = ed.bmAttributes & 0x03
        if attr == 2 { if dirIn { eps.bulkIn = addr } else { eps.bulkOut = addr } }
        else if attr == 3, dirIn { eps.evtIn = addr }
    }
    return eps
}

private func getAsciiString(_ handle: OpaquePointer, _ index: UInt8) -> String {
    if index == 0 { return "" }
    var buf = [UInt8](repeating: 0, count: 128)
    let n = libusb_get_string_descriptor_ascii(handle, index, &buf, Int32(buf.count))
    return n > 0 ? String(cString: &buf) : ""
}

private func claimMTPInterface(handle: OpaquePointer, device: OpaquePointer) throws -> (UInt8, UInt8, UInt8, UInt8, UInt8) {
    var cfgPtr: UnsafeMutablePointer<libusb_config_descriptor>?
    try check(libusb_get_active_config_descriptor(device, &cfgPtr))
    guard let cfg = cfgPtr?.pointee else { throw TransportError.io("no active config") }
    defer { libusb_free_config_descriptor(cfgPtr) }
    var best: (iface: UInt8, alt: UInt8, inEP: UInt8, outEP: UInt8, evt: UInt8, score: Int)? = nil
    for i in 0..<Int(cfg.bNumInterfaces) {
        let ifc = cfg.interface[i]
        for a in 0..<Int(ifc.num_altsetting) {
            let alt = ifc.altsetting[Int(a)], eps = findEndpoints(alt)
            if eps.bulkIn == 0 || eps.bulkOut == 0 { continue }
            var score = 0
            if alt.bInterfaceClass == 0x06 && alt.bInterfaceSubClass == 0x01 { score += 100 }
            let name = getAsciiString(handle, alt.iInterface).lowercased()
            if (alt.bInterfaceClass == 0xFF && alt.bInterfaceSubClass == 0x42) || name.contains("adb") { score -= 200 }
            if alt.bInterfaceClass == 0xFF && (name.contains("mtp") || name.contains("ptp")) { score += 60 }
            if eps.evtIn != 0 { score += 5 }
            if score > (best?.score ?? -1) { best = (UInt8(i), alt.bAlternateSetting, eps.bulkIn, eps.bulkOut, eps.evtIn, score) }
        }
    }
    guard let sel = best, sel.score >= 60 else { throw TransportError.io("no MTP interface") }
    
    // Detach kernel driver before claiming (if supported)
    _ = libusb_detach_kernel_driver(handle, Int32(sel.iface))
    
    try check(libusb_claim_interface(handle, Int32(sel.iface)))
    if sel.alt > 0 { try check(libusb_set_interface_alt_setting(handle, Int32(sel.iface), Int32(sel.alt))) }
    return (sel.iface, sel.alt, sel.inEP, sel.outEP, sel.evt)
}

public struct LibUSBTransport: MTPTransport {
  public init() {}
  public func open(_ summary: MTPDeviceSummary, config: SwiftMTPConfig) async throws -> MTPLink {
    let ctx = LibUSBContext.shared.ctx
    var list: UnsafeMutablePointer<OpaquePointer?>?
    let cnt = libusb_get_device_list(ctx, &list)
    guard cnt > 0, let list else { throw TransportError.io("device list failed") }
    var target: OpaquePointer?
    for i in 0..<Int(cnt) {
      let dev = list[i]!
      let bus = libusb_get_bus_number(dev), addr = libusb_get_device_address(dev)
      if summary.id.raw.hasSuffix(String(format:"@%u:%u", bus, addr)) { libusb_ref_device(dev); target = dev; break }
    }
    libusb_free_device_list(list, 1)
    guard let dev = target else { throw TransportError.noDevice }
    var h: OpaquePointer?
    guard libusb_open(dev, &h) == 0, let handle = h else { libusb_unref_device(dev); throw TransportError.accessDenied }
    
    if config.resetOnOpen {
        _ = libusb_reset_device(handle)
        try? await Task.sleep(nanoseconds: 500_000_000)
    }
    
    let (iface, _, epIn, epOut, epEvt) = try { do { return try claimMTPInterface(handle: handle, device: dev) } catch { libusb_close(handle); libusb_unref_device(dev); throw error } }()
    
    _ = libusb_clear_halt(handle, epIn); _ = libusb_clear_halt(handle, epOut)
    var drain = [UInt8](repeating: 0, count: 4096), got: Int32 = 0
    // Drain until empty with short timeout
    while libusb_bulk_transfer(handle, epIn, &drain, Int32(drain.count), &got, 10) == 0 && got > 0 {}
    
    return MTPUSBLink(handle: handle, device: dev, iface: iface, epIn: epIn, epOut: epOut, epEvt: epEvt, config: config, manufacturer: summary.manufacturer, model: summary.model)
  }
}

public final class MTPUSBLink: @unchecked Sendable, MTPLink {
  private let h: OpaquePointer, dev: OpaquePointer, iface: UInt8, inEP, outEP, evtEP: UInt8
  private let ioQ = DispatchQueue(label: "com.effortlessmetrics.swiftmtp.usbio", qos: .userInitiated)
  private var nextTx: UInt32 = 1
  private let config: SwiftMTPConfig, manufacturer: String, model: String
  private var eventContinuation: AsyncStream<Data>.Continuation?, eventPumpTask: Task<Void, Never>?

  init(handle: OpaquePointer, device: OpaquePointer, iface: UInt8, epIn: UInt8, epOut: UInt8, epEvt: UInt8, config: SwiftMTPConfig, manufacturer: String, model: String) {
    self.h = handle; self.dev = device; self.iface = iface; self.inEP = epIn; self.outEP = epOut; self.evtEP = epEvt; self.config = config; self.manufacturer = manufacturer; self.model = model
  }

  public func close() async { eventPumpTask?.cancel(); eventContinuation?.finish(); libusb_release_interface(h, Int32(iface)); libusb_close(h); libusb_unref_device(dev) }
  public func startEventPump() {
    guard evtEP != 0 else { return }
    let _ = AsyncStream<Data> { self.eventContinuation = $0 }
    eventPumpTask = Task {
      while !Task.isCancelled {
        var buf = [UInt8](repeating: 0, count: 1024)
        if let got = try? bulkReadOnce(evtEP, into: &buf, max: 1024, timeout: 1000), got > 0 { eventContinuation?.yield(Data(buf[0..<got])) }
      }
    }
  }

  public func openUSBIfNeeded() async throws {}
  public func openSession(id: UInt32) async throws { try await executeStreamingCommand(PTPContainer(type: 1, code: 0x1002, txid: 0, params: [id]), dataPhaseLength: nil, dataInHandler: nil, dataOutHandler: nil).checkOK() }
  public func closeSession() async throws { try await executeStreamingCommand(PTPContainer(type: 1, code: 0x1003, txid: 0, params: []), dataPhaseLength: nil, dataInHandler: nil, dataOutHandler: nil).checkOK() }

  public func getDeviceInfo() async throws -> MTPDeviceInfo {
    let collector = SimpleCollector()
    let res = try await executeStreamingCommand(PTPContainer(type: 1, code: 0x1001, txid: 0, params: []), dataPhaseLength: nil, dataInHandler: { collector.append($0); return $0.count }, dataOutHandler: nil)
    if res.isOK, let info = PTPDeviceInfo.parse(from: collector.data) {
        return MTPDeviceInfo(manufacturer: info.manufacturer, model: info.model, version: info.deviceVersion, serialNumber: info.serialNumber, operationsSupported: Set(info.operationsSupported), eventsSupported: Set(info.eventsSupported))
    }
    return MTPDeviceInfo(manufacturer: manufacturer, model: model, version: "1.0", serialNumber: "Unknown", operationsSupported: [], eventsSupported: [])
  }

  public func getStorageIDs() async throws -> [MTPStorageID] {
    let collector = SimpleCollector()
    let res = try await executeStreamingCommand(PTPContainer(type: 1, code: 0x1004, txid: 0, params: []), dataPhaseLength: nil, dataInHandler: { collector.append($0); return $0.count }, dataOutHandler: nil)
    if !res.isOK || collector.data.count < 4 { return [] }
    let count = collector.data.withUnsafeBytes { $0.load(as: UInt32.self).littleEndian }
    var ids = [MTPStorageID]()
    for i in 0..<Int(count) { ids.append(MTPStorageID(raw: collector.data.withUnsafeBytes { $0.load(fromByteOffset: 4+i*4, as: UInt32.self).littleEndian })) }
    return ids
  }

  public func getStorageInfo(id: MTPStorageID) async throws -> MTPStorageInfo {
    let collector = SimpleCollector()
    let res = try await executeStreamingCommand(PTPContainer(type: 1, code: 0x1005, txid: 0, params: [id.raw]), dataPhaseLength: nil, dataInHandler: { collector.append($0); return $0.count }, dataOutHandler: nil)
    try res.checkOK()
    var r = PTPReader(data: collector.data)
    _ = r.u16(); _ = r.u16(); let cap = r.u16(), max = r.u64(), free = r.u64(); _ = r.u32(); let desc = r.string() ?? ""
    return MTPStorageInfo(id: id, description: desc, capacityBytes: max ?? 0, freeBytes: free ?? 0, isReadOnly: cap == 0x0001)
  }

  public func getObjectHandles(storage: MTPStorageID, parent: MTPObjectHandle?) async throws -> [MTPObjectHandle] {
    let collector = SimpleCollector()
    let res = try await executeStreamingCommand(PTPContainer(type: 1, code: 0x1007, txid: 0, params: [storage.raw, 0, parent ?? 0x00000000]), dataPhaseLength: nil, dataInHandler: { collector.append($0); return $0.count }, dataOutHandler: nil)
    try res.checkOK()
    if collector.data.count < 4 { return [] }
    let count = collector.data.withUnsafeBytes { $0.load(as: UInt32.self).littleEndian }
    var handles = [MTPObjectHandle]()
    for i in 0..<Int(count) { handles.append(collector.data.withUnsafeBytes { $0.load(fromByteOffset: 4+i*4, as: UInt32.self).littleEndian }) }
    return handles
  }

  public func getObjectInfos(_ handles: [MTPObjectHandle]) async throws -> [MTPObjectInfo] {
    var out = [MTPObjectInfo]()
    for h in handles {
      let collector = SimpleCollector()
      let res = try await executeStreamingCommand(PTPContainer(type: 1, code: 0x1008, txid: 0, params: [h]), dataPhaseLength: nil, dataInHandler: { collector.append($0); return $0.count }, dataOutHandler: nil)
      if !res.isOK { continue }
      let responseData = collector.data
      var r = PTPReader(data: responseData)
      guard let sid = r.u32(), let fmt = r.u16() else { 
          continue 
      }
      _ = r.u16() // ProtectionStatus
      let size = r.u32()
      _ = r.u16() // ThumbFormat
      _ = r.u32() // ThumbCompressedSize
      _ = r.u32() // ThumbPixWidth
      _ = r.u32() // ThumbPixHeight
      _ = r.u32() // ImagePixWidth
      _ = r.u32() // ImagePixHeight
      _ = r.u32() // ImageBitDepth
      let par = r.u32()
      _ = r.u16() // AssociationType
      _ = r.u32() // AssociationDesc
      _ = r.u32() // SequenceNumber
      let name = r.string() ?? "Unknown"
      out.append(MTPObjectInfo(handle: h, storage: MTPStorageID(raw: sid), parent: par == 0 ? nil : par, name: name, sizeBytes: (size == nil || size == 0xFFFFFFFF) ? nil : UInt64(size!), modified: nil as Date?, formatCode: fmt, properties: [:]))
    }
    return out
  }

  public func getObjectInfos(storage: MTPStorageID, parent: MTPObjectHandle?, format: UInt16?) async throws -> [MTPObjectInfo] {
    let parentHandle = parent ?? 0x00000000, formatCode = format ?? 0x00000000
    
    func tryPropList(params: [UInt32]) async throws -> [MTPObjectInfo]? {
        let collector = SimpleCollector()
        let res = try await executeStreamingCommand(PTPContainer(type: 1, code: 0x9805, txid: 0, params: params), dataPhaseLength: nil, dataInHandler: { collector.append($0); return $0.count }, dataOutHandler: nil)
        if !res.isOK { return nil }
        guard let pl = PTPPropList.parse(from: collector.data) else { return nil }
        var grouped = [UInt32: [UInt16: PTPValue]]()
        for e in pl.entries { if grouped[e.handle] == nil { grouped[e.handle] = [:] }; if let v = e.value { grouped[e.handle]![e.propertyCode] = v } }
        return grouped.map { h, p in
            var name = "Unknown"; if case .string(let s) = p[0xDC07] { name = s }
            var size: UInt64? = nil; if let v = p[0xDC04] { if case .uint64(let u) = v { size = u } else if case .uint32(let u) = v { size = UInt64(u) } }
            var fmt: UInt16 = 0; if case .uint16(let u) = p[0xDC02] { fmt = u }
            var par: UInt32? = nil; if case .uint32(let u) = p[0xDC0B] { par = u }
            return MTPObjectInfo(handle: h, storage: storage, parent: par == 0 ? nil : par, name: name, sizeBytes: size, modified: nil, formatCode: fmt, properties: [:])
        }
    }

    if MTPFeatureFlags.shared.isEnabled(.propListFastPath) {
        if let res = try? await tryPropList(params: [parentHandle, 0xFFFFFFFF, UInt32(formatCode), storage.raw, 1]) { return res }
        if let res = try? await tryPropList(params: [parentHandle, 0x00000000, UInt32(formatCode)]) { return res }
    }

    let handles = try await getObjectHandles(storage: storage, parent: parent)
    return try await getObjectInfos(handles)
  }

  public func deleteObject(handle: MTPObjectHandle) async throws { try await executeStreamingCommand(PTPContainer(type: 1, code: 0x100B, txid: 0, params: [handle, 0]), dataPhaseLength: nil, dataInHandler: nil, dataOutHandler: nil).checkOK() }
  public func moveObject(handle: MTPObjectHandle, to storage: MTPStorageID, parent: MTPObjectHandle?) async throws { try await executeStreamingCommand(PTPContainer(type: 1, code: 0x100E, txid: 0, params: [handle, storage.raw, parent ?? 0xFFFFFFFF]), dataPhaseLength: nil, dataInHandler: nil, dataOutHandler: nil).checkOK() }

  public func executeCommand(_ command: PTPContainer) async throws -> PTPResponseResult { try await executeStreamingCommand(command, dataPhaseLength: nil, dataInHandler: nil, dataOutHandler: nil) }

  public func executeStreamingCommand(_ command: PTPContainer, dataPhaseLength: UInt64? = nil, dataInHandler: MTPDataIn?, dataOutHandler: MTPDataOut?) async throws -> PTPResponseResult {
    try await withCheckedThrowingContinuation { cont in
      ioQ.async { Task { do { cont.resume(returning: try await self.executeCommandAsync(command: command, dataPhaseLength: dataPhaseLength, dataInHandler: dataInHandler, dataOutHandler: dataOutHandler)) } catch { cont.resume(throwing: error) } } }
    }
  }

  private func executeCommandAsync(command: PTPContainer, dataPhaseLength: UInt64? = nil, dataInHandler: MTPDataIn?, dataOutHandler: MTPDataOut?) async throws -> PTPResponseResult {
    let signposter = MTPLog.Signpost.enumerateSignposter
    let state = signposter.beginInterval("executeCommand", id: signposter.makeSignpostID(), "\(String(format: "0x%04x", command.code))")
    defer { signposter.endInterval("executeCommand", state) }

    let txid = (command.code == 0x1002) ? 0 : { () -> UInt32 in let t = nextTx; nextTx = (nextTx == 0xFFFFFFFF) ? 1 : nextTx + 1; return t }()
    let debug = ProcessInfo.processInfo.environment["SWIFTMTP_DEBUG"] == "1"
    if debug { print(String(format: "   [USB] op=0x%04x tx=%u phase=COMMAND", command.code, txid)) }
    let cmdBytes = makePTPCommand(opcode: command.code, txid: txid, params: command.params)
    try cmdBytes.withUnsafeBytes { try bulkWriteAll(outEP, from: $0.baseAddress!, count: $0.count, timeout: UInt32(config.ioTimeoutMs)) }

    if let produce = dataOutHandler {
      if debug { print(String(format: "   [USB] op=0x%04x tx=%u phase=DATA-OUT", command.code, txid)) }
      let len = dataPhaseLength ?? 0
      let hdr = makePTPDataContainer(length: UInt32(PTPHeader.size + Int(min(len, UInt64(UInt32.max - 12)))), code: command.code, txid: txid)
      try hdr.withUnsafeBytes { try bulkWriteAll(outEP, from: $0.baseAddress!, count: $0.count, timeout: UInt32(config.ioTimeoutMs)) }
      var sent = 0, scratch = [UInt8](repeating: 0, count: 64*1024)
      while true {
        let wrote = scratch.withUnsafeMutableBytes { produce($0) }
        if wrote == 0 { break }
        let chunkState = MTPLog.Signpost.chunkSignposter.beginInterval("writeChunk", id: MTPLog.Signpost.chunkSignposter.makeSignpostID(), "\(wrote) bytes")
        try scratch.withUnsafeBytes { try bulkWriteAll(outEP, from: $0.baseAddress!, count: wrote, timeout: UInt32(config.ioTimeoutMs)) }
        MTPLog.Signpost.chunkSignposter.endInterval("writeChunk", chunkState)
        sent += wrote
      }
      if sent % 512 == 0 { var dummy: UInt8 = 0; _ = libusb_bulk_transfer(h, outEP, &dummy, 0, nil, 100) }
    }

    var firstChunk: Data? = nil
    if dataInHandler != nil {
      if debug { print(String(format: "   [USB] op=0x%04x tx=%u phase=DATA-IN", command.code, txid)) }
      var first = [UInt8](repeating: 0, count: 64*1024), got = 0, start = DispatchTime.now().uptimeNanoseconds
      let budget = UInt64(config.handshakeTimeoutMs) * 1_000_000
      while got == 0 {
        got = try bulkReadOnce(inEP, into: &first, max: first.count, timeout: 500)
        if got == 0 && DispatchTime.now().uptimeNanoseconds - start > budget { throw MTPError.timeout }
      }
      let hdr = first.withUnsafeBytes { PTPHeader.decode(from: $0.baseAddress!) }
      if hdr.type == 3 { firstChunk = Data(first[0..<got]) }
      else {
        let payload = Int(hdr.length) - PTPHeader.size, rem = got - PTPHeader.size
        if rem > 0 { _ = first.withUnsafeBytes { dataInHandler!(UnsafeRawBufferPointer(start: $0.baseAddress!.advanced(by: PTPHeader.size), count: rem)) } }
        var left = payload - max(0, rem)
        while left > 0 {
          var buf = [UInt8](repeating: 0, count: min(left, 1<<20))
          let chunkState = MTPLog.Signpost.chunkSignposter.beginInterval("readChunk", id: MTPLog.Signpost.chunkSignposter.makeSignpostID(), "\(buf.count) bytes")
          let g = try bulkReadOnce(inEP, into: &buf, max: buf.count, timeout: 1000)
          MTPLog.Signpost.chunkSignposter.endInterval("readChunk", chunkState)
          if g == 0 { throw MTPError.timeout }
          _ = buf.withUnsafeBytes { dataInHandler!($0) }; left -= g
        }
      }
    }

    if debug { print(String(format: "   [USB] op=0x%04x tx=%u phase=RESPONSE", command.code, txid)) }
    let rHdr: PTPHeader, initial: Data
    if let f = firstChunk { rHdr = f.withUnsafeBytes { PTPHeader.decode(from: $0.baseAddress!) }; initial = f.subdata(in: PTPHeader.size..<f.count) }
    else {
      var hBuf = [UInt8](repeating: 0, count: PTPHeader.size)
      try bulkReadExact(inEP, into: &hBuf, need: PTPHeader.size, timeout: UInt32(config.ioTimeoutMs))
      rHdr = hBuf.withUnsafeBytes { PTPHeader.decode(from: $0.baseAddress!) }; initial = Data()
    }
    var pCount = (Int(rHdr.length) - PTPHeader.size) / 4, params = [UInt32]()
    var pData = initial
    if pData.count < pCount * 4 {
      var extra = [UInt8](repeating: 0, count: pCount * 4 - pData.count)
      try bulkReadExact(inEP, into: &extra, need: extra.count, timeout: UInt32(config.ioTimeoutMs))
      pData.append(contentsOf: extra)
    }
    for i in 0..<pCount { params.append(pData.withUnsafeBytes { $0.load(fromByteOffset: i*4, as: UInt32.self).littleEndian }) }
    return PTPResponseResult(code: rHdr.code, txid: rHdr.txid, params: params)
  }

  @inline(__always) func bulkWriteAll(_ ep: UInt8, from ptr: UnsafeRawPointer, count: Int, timeout: UInt32) throws {
    var sent = 0
    while sent < count {
      var s: Int32 = 0
      let rc = libusb_bulk_transfer(h, ep, UnsafeMutablePointer<UInt8>(mutating: ptr.advanced(by: sent).assumingMemoryBound(to: UInt8.self)), Int32(count - sent), &s, timeout)
      if rc != 0 { throw MTPError.transport(mapLibusb(rc)) }; sent += Int(s)
    }
  }
  @inline(__always) func bulkReadOnce(_ ep: UInt8, into buf: UnsafeMutableRawPointer, max: Int, timeout: UInt32) throws -> Int {
    var g: Int32 = 0
    if max < 512 {
      var tmp = [UInt8](repeating: 0, count: 512)
      let rc = libusb_bulk_transfer(h, ep, &tmp, 512, &g, timeout)
      if rc == -7 { return 0 }; if rc != 0 && rc != -8 { throw MTPError.transport(mapLibusb(rc)) }
      let c = min(Int(g), max); if c > 0 { memcpy(buf, tmp, c) }; return c
    }
    let rc = libusb_bulk_transfer(h, ep, buf.assumingMemoryBound(to: UInt8.self), Int32(max), &g, timeout)
    if rc == -7 { return 0 }; if rc != 0 { throw MTPError.transport(mapLibusb(rc)) }
    return Int(g)
  }
  func bulkReadExact(_ ep: UInt8, into dst: UnsafeMutableRawPointer, need: Int, timeout: UInt32) throws {
    var got = 0
    while got < need {
      var tmp = [UInt8](repeating: 0, count: need - got)
      let g = try bulkReadOnce(ep, into: &tmp, max: tmp.count, timeout: timeout)
      if g == 0 { throw MTPError.timeout }; memcpy(dst.advanced(by: got), &tmp, g); got += g
    }
  }
}

extension PTPResponseResult { func checkOK() throws { if !isOK { throw MTPError.protocolError(code: code, message: nil) } } }
final class SimpleCollector: @unchecked Sendable {
    var data = Data(); private let lock = NSLock()
    func append(_ chunk: UnsafeRawBufferPointer) { lock.lock(); defer { lock.unlock() }; data.append(chunk) }
}
extension Data { mutating func append(_ buf: UnsafeRawBufferPointer) { append(buf.baseAddress!.assumingMemoryBound(to: UInt8.self), count: buf.count) } }