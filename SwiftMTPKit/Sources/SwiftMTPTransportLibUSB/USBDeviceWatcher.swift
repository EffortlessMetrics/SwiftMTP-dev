// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import CLibusb
import SwiftMTPCore
import OSLog

public enum USBDeviceWatcher {
  private final class Box {
    let onAttach: (MTPDeviceSummary) -> Void
    let onDetach: (MTPDeviceID) -> Void
    init(_ a: @escaping (MTPDeviceSummary) -> Void, _ d: @escaping (MTPDeviceID) -> Void) {
      onAttach = a
      onDetach = d
    }
  }

  // C callback trampoline
  private static let callback: libusb_hotplug_callback_fn? = { _, dev, event, userData in
    guard let dev = dev, let ud = userData else { return 0 }
    let box = Unmanaged<Box>.fromOpaque(ud).takeUnretainedValue()
    var desc = libusb_device_descriptor()
    guard libusb_get_device_descriptor(dev, &desc) == 0 else { return 0 }

    // Build a stable-ish ID: VID:PID:bus:addr (we'll switch to MTP DeviceInfo later)
    let id = MTPDeviceID(
      raw: String(
        format: "%04x:%04x@%u:%u",
        desc.idVendor, desc.idProduct,
        libusb_get_bus_number(dev), libusb_get_device_address(dev)))

    if event == LIBUSB_HOTPLUG_EVENT_DEVICE_ARRIVED {
      // Debug: Print device info
      Logger(subsystem: "SwiftMTP", category: "transport")
        .info(
          "Device arrived: VID=\(String(format:"%04x", desc.idVendor)), PID=\(String(format:"%04x", desc.idProduct)), bus=\(libusb_get_bus_number(dev)), addr=\(libusb_get_device_address(dev))"
        )

      var usbHandle: OpaquePointer?
      if libusb_open(dev, &usbHandle) != 0 { usbHandle = nil }
      defer {
        if let h = usbHandle { libusb_close(h) }
      }

      // Shared MTP heuristic: canonical class and vendor-specific candidates.
      var cfg: UnsafeMutablePointer<libusb_config_descriptor>? = nil
      guard libusb_get_active_config_descriptor(dev, &cfg) == 0, let cfg else {
        Logger(subsystem: "SwiftMTP", category: "transport").info("Could not get config descriptor")
        return 0
      }
      defer { libusb_free_config_descriptor(cfg) }
      var isMTP = false
      Logger(subsystem: "SwiftMTP", category: "transport")
        .info("Device has \(cfg.pointee.bNumInterfaces) interfaces")
      for i in 0..<cfg.pointee.bNumInterfaces {
        let iface = cfg.pointee.interface[Int(i)]
        for a in 0..<iface.num_altsetting {
          let alt = iface.altsetting[Int(a)]
          let endpoints = findEndpoints(alt)
          let interfaceName = usbHandle.map { getAsciiString($0, alt.iInterface) } ?? ""
          let heuristic = evaluateMTPInterfaceCandidate(
            interfaceClass: alt.bInterfaceClass,
            interfaceSubclass: alt.bInterfaceSubClass,
            interfaceProtocol: alt.bInterfaceProtocol,
            endpoints: endpoints,
            interfaceName: interfaceName
          )
          Logger(subsystem: "SwiftMTP", category: "transport")
            .info(
              "Interface \(i), alt \(a): class=\(alt.bInterfaceClass), subclass=\(alt.bInterfaceSubClass), protocol=\(alt.bInterfaceProtocol)"
            )
          if heuristic.isCandidate {
            isMTP = true
            break
          }
        }
        if isMTP { break }
      }
      if !isMTP {
        Logger(subsystem: "SwiftMTP", category: "transport").info("Device is not MTP, skipping")
        return 0
      }
      // Read USB string descriptors if possible
      var manufacturer = "USB \(String(format:"%04x", desc.idVendor))"
      var model = "USB \(String(format:"%04x", desc.idProduct))"
      var serial: String? = nil
      if let h = usbHandle {
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
      let summary = MTPDeviceSummary(
        id: id,
        manufacturer: manufacturer,
        model: model,
        vendorID: desc.idVendor,
        productID: desc.idProduct,
        bus: libusb_get_bus_number(dev),
        address: libusb_get_device_address(dev),
        usbSerial: serial)
      box.onAttach(summary)
    } else if event == LIBUSB_HOTPLUG_EVENT_DEVICE_LEFT {
      Logger(subsystem: "SwiftMTP", category: "transport").info("Device left: \(id.raw)")
      box.onDetach(id)
    }
    return 0
  }

  public static func start(
    onAttach: @escaping (MTPDeviceSummary) -> Void,
    onDetach: @escaping (MTPDeviceID) -> Void
  ) {
    _ = LibUSBContext.shared  // ensure ctx + event loop
    let ctx = LibUSBContext.shared.contextPointer
    let flags: Int32 = Int32(LIBUSB_HOTPLUG_ENUMERATE.rawValue)
    var cb: Int32 = 0
    let box = Unmanaged.passRetained(Box(onAttach, onDetach)).toOpaque()
    let events: Int32 =
      Int32(LIBUSB_HOTPLUG_EVENT_DEVICE_ARRIVED.rawValue)
      | Int32(LIBUSB_HOTPLUG_EVENT_DEVICE_LEFT.rawValue)
    let rc = libusb_hotplug_register_callback(
      ctx,
      events,
      flags,
      LIBUSB_HOTPLUG_MATCH_ANY, LIBUSB_HOTPLUG_MATCH_ANY, LIBUSB_HOTPLUG_MATCH_ANY,
      callback, box, &cb)
    if rc != 0 {
      Logger(subsystem: "SwiftMTP", category: "transport").error("hotplug register failed: \(rc)")
    } else {
      Logger(subsystem: "SwiftMTP", category: "transport")
        .info("Hotplug callback registered successfully")
    }
  }
}
