// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import CLibusb

struct USBDumper {
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
    var ctx: OpaquePointer?
    guard libusb_init(&ctx) == 0, let ctx else { print("libusb_init failed"); return }
    defer { libusb_exit(ctx) }

    var list: UnsafeMutablePointer<OpaquePointer?>?
    let cnt = libusb_get_device_list(ctx, &list)
    guard cnt > 0, let list else { print("no devices"); return }
    defer { libusb_free_device_list(list, 1) }

    for i in 0..<Int(cnt) {
      let dev = list[i]!
      var desc = libusb_device_descriptor()
      guard libusb_get_device_descriptor(dev, &desc) == 0 else { continue }
      let vid = String(format: "%04x", desc.idVendor)
      let pid = String(format: "%04x", desc.idProduct)

      print("Device \(vid):\(pid)")
      var handle: OpaquePointer?
      if libusb_open(dev, &handle) != 0 { print("  open: failed"); continue }
      defer { libusb_close(handle) }

      var cfgPtr: UnsafeMutablePointer<libusb_config_descriptor>?
      guard libusb_get_active_config_descriptor(dev, &cfgPtr) == 0, let cfg = cfgPtr?.pointee else {
        print("  no active config"); continue
      }
      defer { libusb_free_config_descriptor(cfgPtr) }

      for ifIndex in 0..<Int(cfg.bNumInterfaces) {
        let ifc = cfg.interface[ifIndex]
        for altIndex in 0..<Int(ifc.num_altsetting) {
          let alt = ifc.altsetting[altIndex]
          let cls = alt.bInterfaceClass, sub = alt.bInterfaceSubClass, pro = alt.bInterfaceProtocol
          var name = ""
          if alt.iInterface != 0 {
            var buf = [UInt8](repeating: 0, count: 128)
            if libusb_get_string_descriptor_ascii(handle, alt.iInterface, &buf, Int32(buf.count)) > 0 {
              // Find null terminator
              if let nullIndex = buf.firstIndex(of: 0) {
                name = String(decoding: buf[..<nullIndex], as: UTF8.self)
              }
            }
          }

          var bulkIn: UInt8 = 0, bulkOut: UInt8 = 0, evt: UInt8 = 0
          for e in 0..<Int(alt.bNumEndpoints) {
            let ed = alt.endpoint[e]
            let addr = ed.bEndpointAddress
            let dirIn = (addr & 0x80) != 0
            let attr = ed.bmAttributes & 0x03
            if attr == UInt8(LIBUSB_TRANSFER_TYPE_BULK.rawValue) {
              if dirIn { bulkIn = addr } else { bulkOut = addr }
            } else if attr == UInt8(LIBUSB_TRANSFER_TYPE_INTERRUPT.rawValue), dirIn {
              evt = addr
            }
          }

          print(String(format:
            "  iface=%d alt=%d class=0x%02x sub=0x%02x proto=0x%02x in=0x%02x out=0x%02x evt=0x%02x name=\"%@\"",
            ifIndex, alt.bAlternateSetting, cls, sub, pro, bulkIn, bulkOut, evt, name))
        }
      }
    }
  }
}
