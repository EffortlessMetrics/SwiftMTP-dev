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
  init(handle: OpaquePointer, iface: UInt8, epIn: UInt8, epOut: UInt8, epEvt: UInt8) {
    self.h = handle; self.iface = iface; self.inEP = epIn; self.outEP = epOut; self.evtEP = epEvt
  }
  public func close() async {
    libusb_release_interface(h, Int32(iface))
    libusb_close(h)
  }

  // Helper for a blocking bulk write/read (we'll wrap with continuations later)
  func bulkWrite(_ ep: UInt8, _ buf: UnsafePointer<UInt8>, _ len: Int, timeout: UInt32) throws -> Int {
    var transferred: Int32 = 0
    let rc = libusb_bulk_transfer(h, ep, UnsafeMutablePointer(mutating: buf), Int32(len), &transferred, timeout)
    if rc == Int32(LIBUSB_ERROR_TIMEOUT.rawValue) { throw TransportError.timeout }
    if rc != 0 { throw TransportError.io("bulk write rc=\(rc)") }
    return Int(transferred)
  }
  func bulkRead(_ ep: UInt8, _ buf: UnsafeMutablePointer<UInt8>, _ len: Int, timeout: UInt32) throws -> Int {
    var transferred: Int32 = 0
    let rc = libusb_bulk_transfer(h, ep, buf, Int32(len), &transferred, timeout)
    if rc == Int32(LIBUSB_ERROR_TIMEOUT.rawValue) { throw TransportError.timeout }
    if rc != 0 { throw TransportError.io("bulk read rc=\(rc)") }
    return Int(transferred)
  }

  // MTP command execution - placeholder for now
  public func executeCommand(_ command: PTPContainer) throws -> Data? {
    // TODO: Implement real MTP command execution via USB
    throw MTPError.notSupported("Real device command execution not yet implemented")
  }

  // Streaming command execution for file transfers
  public func executeStreamingCommand(
    _ command: PTPContainer,
    dataInHandler: ((UnsafeRawBufferPointer) -> Int)?,
    dataOutHandler: ((UnsafeMutableRawBufferPointer) -> Int)?
  ) async throws -> Data? {
    // TODO: Implement real MTP streaming command execution via USB
    // This would involve:
    // 1. Sending the command container
    // 2. Handling data-out phase with dataOutHandler
    // 3. Handling data-in phase with dataInHandler
    // 4. Reading response container
    throw MTPError.notSupported("Real device streaming command execution not yet implemented")
  }
}

// MTPTransport and MTPLink protocols are defined in SwiftMTPCore
