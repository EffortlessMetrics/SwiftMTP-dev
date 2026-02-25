// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import CLibusb

// Simple standalone MTP device probe using libusb directly
@main
struct SimpleProbe {
  static func main() async {
    print("🔌 Simple MTP Device Probe (Direct libusb)")
    print("Initializing libusb context...")

    // Initialize libusb
    var ctx: OpaquePointer?
    let rc = libusb_init(&ctx)
    if rc != 0 {
      print("❌ Failed to initialize libusb: \(rc)")
      return
    }
    defer { libusb_exit(ctx) }

    print("✅ libusb initialized successfully")

    // Get device list
    var list: UnsafeMutablePointer<OpaquePointer?>?
    let cnt = libusb_get_device_list(ctx, &list)
    if cnt < 0 {
      print("❌ Failed to get device list: \(cnt)")
      return
    }
    defer { libusb_free_device_list(list, 1) }

    print("📋 Found \(cnt) USB devices")

    // Scan for MTP devices
    var mtpDevices: [(bus: UInt8, addr: UInt8, vid: UInt16, pid: UInt16)] = []

    if let list = list {
      for i in 0..<Int(cnt) {
        if let dev = list[i] {
          var desc = libusb_device_descriptor()
          if libusb_get_device_descriptor(dev, &desc) == 0 {
            let bus = libusb_get_bus_number(dev)
            let addr = libusb_get_device_address(dev)

            // Check if this is a Xiaomi device (VID 0x2717) - could be MTP (0xff40) or PTP (0xff10)
            if desc.idVendor == 0x2717 && (desc.idProduct == 0xff40 || desc.idProduct == 0xff10) {
              print("🎯 Found Xiaomi Mi Note 2!")
              print("   Bus: \(bus), Address: \(addr)")
              print(
                "   VID:PID = \(String(format:"%04x", desc.idVendor)):\(String(format:"%04x", desc.idProduct))"
              )

              // Check for MTP/PTP interfaces
              var cfg: UnsafeMutablePointer<libusb_config_descriptor>?
              if libusb_get_active_config_descriptor(dev, &cfg) == 0, let cfg = cfg {
                defer { libusb_free_config_descriptor(cfg) }

                var hasMTP = false
                var hasPTP = false
                print("   Scanning \(cfg.pointee.bNumInterfaces) interfaces...")
                for i in 0..<cfg.pointee.bNumInterfaces {
                  let iface = cfg.pointee.interface[Int(i)]
                  for a in 0..<iface.num_altsetting {
                    let alt = iface.altsetting[Int(a)]
                    print(
                      "     Interface \(i), alt \(a): class=0x\(String(format:"%02x", alt.bInterfaceClass)), subclass=0x\(String(format:"%02x", alt.bInterfaceSubClass)), protocol=0x\(String(format:"%02x", alt.bInterfaceProtocol))"
                    )

                    // Show endpoint details
                    print("       Endpoints: \(alt.bNumEndpoints)")
                    for e in 0..<Int(alt.bNumEndpoints) {
                      let ep = alt.endpoint[e]
                      let addr = ep.bEndpointAddress
                      let dir = (addr & 0x80) != 0 ? "IN" : "OUT"
                      let typeRaw = ep.bmAttributes & 0x03
                      let type =
                        typeRaw == 1 ? "ISO" : typeRaw == 2 ? "BULK" : typeRaw == 3 ? "INT" : "CTRL"
                      print("         EP 0x\(String(format:"%02x", addr)): \(dir) \(type)")
                    }

                    if alt.bInterfaceClass == 0x06 {  // PTP/MTP
                      if alt.bInterfaceSubClass == 0x01 {
                        hasMTP = true
                        print("     ✅ Found MTP interface (class 0x06, subclass 0x01)!")
                      } else {
                        hasPTP = true
                        print("     ✅ Found PTP interface (class 0x06, subclass 0x00)!")
                      }
                      break
                    } else if alt.bInterfaceClass == 0xFF {  // Vendor-specific
                      print("     📋 Found vendor-specific interface (class 0xFF)")
                      // Check if it might be MTP/PTP in disguise
                      if alt.bInterfaceSubClass == 0x00 || alt.bInterfaceSubClass == 0x01 {
                        print("     🤔 Vendor interface might be MTP/PTP - check interface string")
                      }
                    }
                  }
                  if hasMTP || hasPTP { break }
                }

                if hasMTP {
                  print("✅ Xiaomi Mi Note 2 has MTP interface - device is ready!")
                  print("   You can now try: swift run swiftmtp probe")
                } else if hasPTP {
                  print("✅ Xiaomi Mi Note 2 has PTP interface - device is in PTP mode!")
                  print(
                    "   For MTP, try: unlock phone → Settings → Connected devices → USB → 'File Transfer'"
                  )
                  print("   Or use PTP-specific commands if available")
                } else {
                  print("⚠️  Xiaomi Mi Note 2 found but no MTP/PTP interface detected")
                  print("   Device may be in charging-only mode")
                  print(
                    "   Try: unlock phone → Settings → Connected devices → USB → 'File Transfer'")
                }
              } else {
                print("⚠️  Could not read device configuration")
              }

              mtpDevices.append((bus: bus, addr: addr, vid: desc.idVendor, pid: desc.idProduct))
            }
          }
        }
      }
    }

    if mtpDevices.isEmpty {
      print("❌ No Xiaomi Mi Note 2 (VID:PID 2717:ff40 or 2717:ff10) found")
      print("   Make sure the device is connected via USB")
      print("   Check: system_profiler SPUSBDataType | grep -A5 'Mi Note'")
      print("   Note: ff40 = MTP mode, ff10 = PTP mode")
    }

    print("\n🔍 Scan complete. Found \(mtpDevices.count) MTP-capable devices.")
  }
}
