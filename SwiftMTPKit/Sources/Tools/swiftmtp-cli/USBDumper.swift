// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import CLibusb

struct USBDumper {
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
            if libusb_get_string_descriptor_ascii(handle, alt.iInterface, &buf, UInt16(buf.count)) > 0 {
              name = String(cString: UnsafePointer<CChar>(OpaquePointer(&buf)))
            }
          }

          var bulkIn: UInt8 = 0, bulkOut: UInt8 = 0, evt: UInt8 = 0
          for e in 0..<Int(alt.bNumEndpoints) {
            let ed = alt.endpoint[e]
            let addr = ed.bEndpointAddress
            let dirIn = (addr & 0x80) != 0
            let attr = ed.bmAttributes & 0x03
            if attr == LIBUSB_TRANSFER_TYPE_BULK {
              if dirIn { bulkIn = addr } else { bulkOut = addr }
            } else if attr == LIBUSB_TRANSFER_TYPE_INTERRUPT, dirIn {
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
