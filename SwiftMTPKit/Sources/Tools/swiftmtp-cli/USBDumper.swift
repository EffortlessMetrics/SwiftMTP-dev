// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import CLibusb

struct USBDumper {
  struct DumpEndpoint: Codable, Sendable {
    let address: String
    let direction: String
    let transferType: String
  }

  struct DumpInterface: Codable, Sendable {
    let number: Int
    let altSetting: Int
    let interfaceClass: String
    let interfaceSubclass: String
    let interfaceProtocol: String
    let name: String
    let endpoints: [DumpEndpoint]
  }

  struct DumpDevice: Codable, Sendable {
    let id: String
    let vendorID: String
    let productID: String
    let bus: Int
    let address: Int
    let manufacturer: String?
    let product: String?
    let serial: String?
    let interfaces: [DumpInterface]
  }

  struct DumpReport: Codable, Sendable {
    let schemaVersion: String
    let generatedAt: Date
    let devices: [DumpDevice]
  }

  @inline(__always)
  private static func transferTypeLabel(_ endpoint: libusb_endpoint_descriptor) -> String {
    let attr = endpoint.bmAttributes & 0x03
    switch attr {
    case UInt8(LIBUSB_TRANSFER_TYPE_CONTROL.rawValue): return "control"
    case UInt8(LIBUSB_TRANSFER_TYPE_ISOCHRONOUS.rawValue): return "isochronous"
    case UInt8(LIBUSB_TRANSFER_TYPE_BULK.rawValue): return "bulk"
    case UInt8(LIBUSB_TRANSFER_TYPE_INTERRUPT.rawValue): return "interrupt"
    default: return "unknown"
    }
  }

  @inline(__always)
  private static func directionLabel(_ address: UInt8) -> String {
    (address & 0x80) != 0 ? "in" : "out"
  }

  private static func readStringDescriptor(_ handle: OpaquePointer, _ index: UInt8) -> String? {
    guard index != 0 else { return nil }
    var buf = [UInt8](repeating: 0, count: 128)
    let n = libusb_get_string_descriptor_ascii(handle, index, &buf, Int32(buf.count))
    guard n > 0 else { return nil }
    return String(decoding: buf.prefix(Int(n)), as: UTF8.self)
  }

  func collect() throws -> DumpReport {
    var ctx: OpaquePointer?
    guard libusb_init(&ctx) == 0, let ctx else { throw NSError(domain: "USBDumper", code: 1, userInfo: [NSLocalizedDescriptionKey: "libusb_init failed"]) }
    defer { libusb_exit(ctx) }

    var list: UnsafeMutablePointer<OpaquePointer?>?
    let cnt = libusb_get_device_list(ctx, &list)
    guard cnt >= 0 else { throw NSError(domain: "USBDumper", code: 2, userInfo: [NSLocalizedDescriptionKey: "libusb_get_device_list failed"]) }
    guard cnt > 0, let list else {
      return DumpReport(schemaVersion: "1.0.0", generatedAt: Date(), devices: [])
    }
    defer { libusb_free_device_list(list, 1) }

    var devices: [DumpDevice] = []
    devices.reserveCapacity(Int(cnt))

    for i in 0..<Int(cnt) {
      guard let dev = list[i] else { continue }
      var desc = libusb_device_descriptor()
      guard libusb_get_device_descriptor(dev, &desc) == 0 else { continue }
      let vid = String(format: "%04x", desc.idVendor)
      let pid = String(format: "%04x", desc.idProduct)
      let bus = Int(libusb_get_bus_number(dev))
      let address = Int(libusb_get_device_address(dev))

      var handle: OpaquePointer?
      if libusb_open(dev, &handle) != 0 { handle = nil }
      defer {
        if let h = handle { libusb_close(h) }
      }

      var cfgPtr: UnsafeMutablePointer<libusb_config_descriptor>?
      guard libusb_get_active_config_descriptor(dev, &cfgPtr) == 0, let cfg = cfgPtr?.pointee else {
        continue
      }
      defer { libusb_free_config_descriptor(cfgPtr) }

      var interfaces: [DumpInterface] = []
      for ifIndex in 0..<Int(cfg.bNumInterfaces) {
        let ifc = cfg.interface[ifIndex]
        for altIndex in 0..<Int(ifc.num_altsetting) {
          let alt = ifc.altsetting[altIndex]
          let name = handle.flatMap { Self.readStringDescriptor($0, alt.iInterface) } ?? ""
          var endpoints: [DumpEndpoint] = []
          for e in 0..<Int(alt.bNumEndpoints) {
            let endpoint = alt.endpoint[e]
            let epAddress = String(format: "0x%02x", endpoint.bEndpointAddress)
            endpoints.append(
              DumpEndpoint(
                address: epAddress,
                direction: Self.directionLabel(endpoint.bEndpointAddress),
                transferType: Self.transferTypeLabel(endpoint)
              )
            )
          }
          interfaces.append(
            DumpInterface(
              number: ifIndex,
              altSetting: Int(alt.bAlternateSetting),
              interfaceClass: String(format: "0x%02x", alt.bInterfaceClass),
              interfaceSubclass: String(format: "0x%02x", alt.bInterfaceSubClass),
              interfaceProtocol: String(format: "0x%02x", alt.bInterfaceProtocol),
              name: name,
              endpoints: endpoints
            )
          )
        }
      }

      let manufacturer = handle.flatMap { Self.readStringDescriptor($0, desc.iManufacturer) }
      let product = handle.flatMap { Self.readStringDescriptor($0, desc.iProduct) }
      let serial = handle.flatMap { Self.readStringDescriptor($0, desc.iSerialNumber) }

      devices.append(
        DumpDevice(
          id: "\(vid):\(pid)@\(bus):\(address)",
          vendorID: vid,
          productID: pid,
          bus: bus,
          address: address,
          manufacturer: manufacturer,
          product: product,
          serial: serial,
          interfaces: interfaces
        )
      )
    }

    return DumpReport(schemaVersion: "1.0.0", generatedAt: Date(), devices: devices)
  }

  /// Sanitize text output to remove privacy-sensitive information
  static func sanitizeTextFile(_ url: URL) throws {
      var text = String(decoding: try Data(contentsOf: url), as: UTF8.self)

      // Define comprehensive patterns to redact for privacy protection
      let patterns: [(String, String)] = [
          // Serial numbers in various formats
          (#"(?im)^(\s*Serial Number:\s*)(\S+)$"#, "$1<redacted>"),
          (#"(?im)^(\s*iSerial\s+)(\S+)$"#, "$1<redacted>"),
          (#"(?im)^(\s*Serial:\s*)(\S+)$"#, "$1<redacted>"),

          // Device-friendly names that may contain personal info
          (#"(?im)^(\s*(Product|Manufacturer|Device Name|Model|Friendly Name):\s+)(.+)$"#, "$1<redacted>"),

          // Absolute user paths - comprehensive coverage
          (#"/Users/[^/\s]+"#, "/Users/<redacted>"),
          (#"(?i)C:\\Users\\[^\\[:space:]]+"#, "C:\\Users\\<redacted>"),
          (#"(?i)/home/[^/[:space:]]+"#, "/home/<redacted>"),

          // Additional privacy-sensitive patterns
          (#"(?i)\b(Hostname|Computer Name|Machine Name):\s+(.+)$"#, "$1: <redacted>"),
          (#"(?i)\b(User Name|Owner|Author):\s+(.+)$"#, "$1: <redacted>"),

          // Network-related identifiers that might leak personal info
          (#"(?i)\b(MAC Address|Ethernet ID|WiFi Address):\s+([0-9A-Fa-f:-]+)"#, "$1: <redacted>"),

          // UUIDs that might be device-specific
          (#"(?i)\b(UUID|GUID):\s+([0-9A-Fa-f-]+)"#, "$1: <redacted>")
      ]

      // Apply all patterns
      for (pattern, replacement) in patterns {
          text = text.replacingOccurrences(
              of: pattern,
              with: replacement,
              options: .regularExpression
          )
      }

      try text.data(using: .utf8)!.write(to: url)
  }

  func run() async throws {
    let report = try collect()
    if report.devices.isEmpty {
      print("no devices")
      return
    }

    for device in report.devices {
      print("Device \(device.vendorID):\(device.productID)")
      for iface in device.interfaces {
        var bulkIn = "0x00"
        var bulkOut = "0x00"
        var evtIn = "0x00"
        for endpoint in iface.endpoints {
          if endpoint.transferType == "bulk" {
            if endpoint.direction == "in" { bulkIn = endpoint.address } else { bulkOut = endpoint.address }
          } else if endpoint.transferType == "interrupt", endpoint.direction == "in" {
            evtIn = endpoint.address
          }
        }

        print(
          "  iface=\(iface.number) alt=\(iface.altSetting) class=\(iface.interfaceClass) " +
          "sub=\(iface.interfaceSubclass) proto=\(iface.interfaceProtocol) " +
          "in=\(bulkIn) out=\(bulkOut) evt=\(evtIn) name=\"\(iface.name)\""
        )
      }
    }
  }
}
