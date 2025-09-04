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

                        // Check if this is the Xiaomi Mi Note 2 (VID:PID 0x2717:0xff40)
                        if desc.idVendor == 0x2717 && desc.idProduct == 0xff40 {
                            print("🎯 Found Xiaomi Mi Note 2!")
                            print("   Bus: \(bus), Address: \(addr)")
                            print("   VID:PID = \(String(format:"%04x", desc.idVendor)):\(String(format:"%04x", desc.idProduct))")

                            // Check for MTP interface
                            var cfg: UnsafeMutablePointer<libusb_config_descriptor>?
                            if libusb_get_active_config_descriptor(dev, &cfg) == 0, let cfg = cfg {
                                defer { libusb_free_config_descriptor(cfg) }

                                var hasMTP = false
                                print("   Scanning \(cfg.pointee.bNumInterfaces) interfaces...")
                                for i in 0..<cfg.pointee.bNumInterfaces {
                                    let iface = cfg.pointee.interface[Int(i)]
                                    for a in 0..<iface.num_altsetting {
                                        let alt = iface.altsetting[Int(a)]
                                        print("     Interface \(i), alt \(a): class=\(alt.bInterfaceClass), subclass=\(alt.bInterfaceSubClass)")
                                        if alt.bInterfaceClass == 0x06 { // PTP/MTP
                                            hasMTP = true
                                            print("     ✅ Found MTP interface (class 0x06)!")
                                            break
                                        }
                                    }
                                    if hasMTP { break }
                                }

                                if hasMTP {
                                    print("✅ Xiaomi Mi Note 2 has MTP interface - device is ready!")
                                    print("   You can now try: swift run swiftmtp probe")
                                } else {
                                    print("⚠️  Xiaomi Mi Note 2 found but no MTP interface detected")
                                    print("   Device may be in charging-only mode")
                                    print("   Try: unlock phone → Settings → Connected devices → USB → 'File Transfer'")
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
            print("❌ No Xiaomi Mi Note 2 (VID:PID 2717:ff40) found")
            print("   Make sure the device is connected via USB")
            print("   Check: system_profiler SPUSBDataType | grep -A5 'Mi Note'")
        }

        print("\n🔍 Scan complete. Found \(mtpDevices.count) MTP-capable devices.")
    }
}
