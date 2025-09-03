import Foundation
import CLibusb
import SwiftMTPCore
import SwiftMTPObservability

public struct LibUSBTransport: MTPTransport {
  public init() {}
  public func open(_ summary: MTPDeviceSummary) async throws -> MTPLink {
    // 1) Find device by bus/addr from summary.id (we encoded those earlier).
    guard let ctx = LibUSBContext.shared.contextPointer else { throw TransportError.io("no ctx") }
    var list: UnsafeMutablePointer<OpaquePointer?>?
    let cnt = libusb_get_device_list(ctx, &list)
    guard cnt > 0, let list else { throw TransportError.io("device list failed") }
    defer { libusb_free_device_list(list, 1) }

    var target: OpaquePointer?
    for i in 0..<Int(cnt) {
      let dev = list[i]!
      let bus = libusb_get_bus_number(dev)
      let addr = libusb_get_device_address(dev)
      if summary.id.raw.hasSuffix(String(format:"@%u:%u", bus, addr)) { target = dev; break }
    }
    guard let dev = target else { throw TransportError.noDevice }

    // 2) Open + claim interface with class 0x06; cache endpoints
    var handle: OpaquePointer?
    guard libusb_open(dev, &handle) == 0, let handle else { throw TransportError.accessDenied }

    var cfg: UnsafeMutablePointer<libusb_config_descriptor>? = nil
    guard libusb_get_active_config_descriptor(dev, &cfg) == 0, let cfg else {
      libusb_close(handle); throw TransportError.io("no config")
    }
    defer { libusb_free_config_descriptor(cfg) }

    var ifaceNum: UInt8 = 0
    var epIn: UInt8 = 0, epOut: UInt8 = 0, epEvt: UInt8 = 0
    outer: for i in 0..<cfg.pointee.bNumInterfaces {
      let iface = cfg.pointee.interface[Int(i)]
      for a in 0..<iface.num_altsetting {
        let alt = iface.altsetting[Int(a)]
        if alt.bInterfaceClass == 0x06 {
          ifaceNum = alt.bInterfaceNumber
          for e in 0..<alt.bNumEndpoints {
            let ep = alt.endpoint[Int(e)]
            let addr = ep.bEndpointAddress
            let transferType = ep.bmAttributes & UInt8(LIBUSB_TRANSFER_TYPE_MASK)
            if transferType == UInt8(LIBUSB_TRANSFER_TYPE_BULK.rawValue) {
              if (addr & 0x80) != 0 { epIn = addr } else { epOut = addr }
            } else if transferType == UInt8(LIBUSB_TRANSFER_TYPE_INTERRUPT.rawValue) {
              if (addr & 0x80) != 0 { epEvt = addr }
            }
          }
          break outer
        }
      }
    }
    guard epIn != 0 && epOut != 0 else { libusb_close(handle); throw TransportError.io("no bulk endpoints") }
    guard libusb_claim_interface(handle, Int32(ifaceNum)) == 0 else {
      libusb_close(handle); throw TransportError.busy
    }
    return MTPUSBLink(handle: handle, iface: ifaceNum, epIn: epIn, epOut: epOut, epEvt: epEvt)
  }
}

public final class MTPUSBLink: @unchecked Sendable, MTPLink {
  private let h: OpaquePointer
  private let iface: UInt8
  let inEP, outEP, evtEP: UInt8
  private let ioQ = DispatchQueue(label: "com.effortlessmetrics.swiftmtp.usbio", qos: .userInitiated)
  private var nextTx: UInt32 = 1

  init(handle: OpaquePointer, iface: UInt8, epIn: UInt8, epOut: UInt8, epEvt: UInt8) {
    self.h = handle; self.iface = iface; self.inEP = epIn; self.outEP = epOut; self.evtEP = epEvt
  }

  public func close() async {
    libusb_release_interface(h, Int32(iface))
    libusb_close(h)
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

    // 1) COMMAND container
    let cmdBytes = makePTPCommand(opcode: command.code, txid: txid, params: command.params)
    try cmdBytes.withUnsafeBytes { raw in
      try bulkWriteAll(outEP, from: raw.baseAddress!, count: raw.count, timeout: 5000)
    }

    // 2) Optional DATA OUT phase (host -> device)
    if let produce = dataOutHandler {
      var sent = 0
      var scratch = [UInt8](repeating: 0, count: min(1 << 20, 1024 * 1024)) // up to 1 MiB scratch
      while true {
        let wrote = scratch.withUnsafeMutableBytes { buf in
          produce(buf)
        }
        if wrote == 0 { break }
        try scratch.withUnsafeBytes { raw in
          try bulkWriteAll(outEP, from: raw.baseAddress!, count: wrote, timeout: 15000)
        }
        sent += wrote
      }
      if sent > 0 {
        // Send data container header
        let hdrBytes = makePTPDataContainer(length: UInt32(PTPHeader.size + sent), code: command.code, txid: txid)
        try hdrBytes.withUnsafeBytes { raw in
          try bulkWriteAll(outEP, from: raw.baseAddress!, count: raw.count, timeout: 5000)
        }
      }
    }

    // 3) Optional DATA IN phase (device -> host)
    var dataInCollector = DataCollector()
    var hasDataPhase = false
    var dataHeader: PTPHeader?

    if dataInHandler != nil {
      // First read: may contain header + some payload
      var first = [UInt8](repeating: 0, count: max(PTPHeader.size, 64 * 1024))
      let gotFirst = try bulkReadOnce(inEP, into: &first, max: first.count, timeout: 5000)
      if gotFirst >= PTPHeader.size {
        dataHeader = first.withUnsafeBytes { PTPHeader.decode(from: $0.baseAddress!) }
        if dataHeader?.type == PTPContainerType.data.rawValue {
          hasDataPhase = true
          let payloadLen = Int(dataHeader!.length) - PTPHeader.size
          let rem = gotFirst - PTPHeader.size
          if rem > 0 {
            first.withUnsafeBytes { raw in
              let chunk = UnsafeRawBufferPointer(start: raw.baseAddress!.advanced(by: PTPHeader.size), count: rem)
              _ = dataInHandler!(chunk)
            }
          }
          // Read the rest exactly
          var left = payloadLen - max(0, rem)
          while left > 0 {
            var buf = [UInt8](repeating: 0, count: min(left, 1 << 20))
            let got = try bulkReadOnce(inEP, into: &buf, max: buf.count, timeout: 15000)
            if got == 0 { continue }
            buf.withUnsafeBytes { raw in
              _ = dataInHandler!(UnsafeRawBufferPointer(start: raw.baseAddress!, count: got))
            }
            left -= got
          }
        }
      }
    }

    // 4) RESPONSE phase
    var respHdrBuf = [UInt8](repeating: 0, count: PTPHeader.size)
    try bulkReadExact(inEP, into: &respHdrBuf, need: PTPHeader.size, timeout: 5000)
    let rHdr = respHdrBuf.withUnsafeBytes { PTPHeader.decode(from: $0.baseAddress!) }
    guard rHdr.type == PTPContainerType.response.rawValue, rHdr.txid == txid else {
      throw MTPError.transport(.io("unexpected response container: type=\(rHdr.type) tx=\(rHdr.txid)"))
    }

    let respParamBytes = Int(rHdr.length) - PTPHeader.size
    var params: [UInt32] = []
    if respParamBytes > 0 {
      precondition(respParamBytes % 4 == 0, "response params not multiple of 4")
      var buf = [UInt8](repeating: 0, count: respParamBytes)
      try bulkReadExact(inEP, into: &buf, need: buf.count, timeout: 5000)
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
