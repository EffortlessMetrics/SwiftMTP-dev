#!/usr/bin/env swift
// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

// Simple USB probe script for SwiftMTP testing
// This script bypasses the complex dependencies and directly uses libusb

import Foundation

// Check if libusb is available
guard let libusb = dlopen("/opt/homebrew/lib/libusb-1.0.dylib", RTLD_LAZY) else {
    print("❌ libusb not found. Please install with: brew install libusb")
    exit(1)
}
defer { dlclose(libusb) }

// libusb function signatures
typealias libusb_init = @convention(c) (UnsafeMutablePointer<OpaquePointer?>) -> Int32
typealias libusb_exit = @convention(c) (OpaquePointer) -> ()
typealias libusb_get_device_list = @convention(c) (OpaquePointer, UnsafeMutablePointer<UnsafeMutablePointer<OpaquePointer?>?>) -> Int
typealias libusb_free_device_list = @convention(c) (UnsafeMutablePointer<OpaquePointer?>?, Int32) -> ()
typealias libusb_get_device_descriptor = @convention(c) (OpaquePointer, UnsafeMutablePointer<libusb_device_descriptor>) -> Int32
typealias libusb_open = @convention(c) (OpaquePointer, UnsafeMutablePointer<OpaquePointer?>) -> Int32
typealias libusb_close = @convention(c) (OpaquePointer) -> ()
typealias libusb_get_config_descriptor = @convention(c) (OpaquePointer, UInt8, UnsafeMutablePointer<UnsafeMutablePointer<libusb_config_descriptor>?>?) -> Int32
typealias libusb_free_config_descriptor = @convention(c) (UnsafeMutablePointer<libusb_config_descriptor>) -> ()
typealias libusb_get_string_descriptor_ascii = @convention(c) (OpaquePointer, UInt8, UnsafeMutablePointer<CChar>, Int32) -> Int32

// libusb structures (simplified)
struct libusb_device_descriptor {
    var bLength: UInt8 = 0
    var bDescriptorType: UInt8 = 0
    var bcdUSB: UInt16 = 0
    var bDeviceClass: UInt8 = 0
    var bDeviceSubClass: UInt8 = 0
    var bDeviceProtocol: UInt8 = 0
    var bMaxPacketSize0: UInt8 = 0
    var idVendor: UInt16 = 0
    var idProduct: UInt16 = 0
    var bcdDevice: UInt16 = 0
    var iManufacturer: UInt8 = 0
    var iProduct: UInt8 = 0
    var iSerialNumber: UInt8 = 0
    var bNumConfigurations: UInt8 = 0
}

struct libusb_config_descriptor {
    var bLength: UInt8 = 0
    var bDescriptorType: UInt8 = 0
    var wTotalLength: UInt16 = 0
    var bNumInterfaces: UInt8 = 0
    var bConfigurationValue: UInt8 = 0
    var iConfiguration: UInt8 = 0
    var bmAttributes: UInt8 = 0
    var bMaxPower: UInt8 = 0
    var `interface`: UnsafeMutablePointer<libusb_interface> = UnsafeMutablePointer(bitPattern: 0)!
    var extra: UnsafeMutablePointer<UInt8> = UnsafeMutablePointer(bitPattern: 0)!
    var extra_length: Int32 = 0
}

struct libusb_interface {
    var altsetting: UnsafeMutablePointer<libusb_interface_descriptor> = UnsafeMutablePointer(bitPattern: 0)!
    var num_altsetting: Int32 = 0
}

struct libusb_interface_descriptor {
    var bLength: UInt8 = 0
    var bDescriptorType: UInt8 = 0
    var bInterfaceNumber: UInt8 = 0
    var bAlternateSetting: UInt8 = 0
    var bNumEndpoints: UInt8 = 0
    var bInterfaceClass: UInt8 = 0
    var bInterfaceSubClass: UInt8 = 0
    var bInterfaceProtocol: UInt8 = 0
    var iInterface: UInt8 = 0
    var endpoint: UnsafeMutablePointer<libusb_endpoint_descriptor> = UnsafeMutablePointer(bitPattern: 0)!
    var extra: UnsafeMutablePointer<UInt8> = UnsafeMutablePointer(bitPattern: 0)!
    var extra_length: Int32 = 0
}

struct libusb_endpoint_descriptor {
    var bLength: UInt8 = 0
    var bDescriptorType: UInt8 = 0
    var bEndpointAddress: UInt8 = 0
    var bmAttributes: UInt8 = 0
    var wMaxPacketSize: UInt16 = 0
    var bInterval: UInt8 = 0
    var bRefresh: UInt8 = 0
    var bSynchAddress: UInt8 = 0
    var extra: UnsafeMutablePointer<UInt8> = UnsafeMutablePointer(bitPattern: 0)!
    var extra_length: Int32 = 0
}

// Get function pointers
guard let libusb_init_ptr = dlsym(libusb, "libusb_init"),
      let libusb_exit_ptr = dlsym(libusb, "libusb_exit"),
      let libusb_get_device_list_ptr = dlsym(libusb, "libusb_get_device_list"),
      let libusb_free_device_list_ptr = dlsym(libusb, "libusb_free_device_list"),
      let libusb_get_device_descriptor_ptr = dlsym(libusb, "libusb_get_device_descriptor"),
      let libusb_open_ptr = dlsym(libusb, "libusb_open"),
      let libusb_close_ptr = dlsym(libusb, "libusb_close"),
      let libusb_get_config_descriptor_ptr = dlsym(libusb, "libusb_get_config_descriptor"),
      let libusb_free_config_descriptor_ptr = dlsym(libusb, "libusb_free_config_descriptor"),
      let libusb_get_string_descriptor_ascii_ptr = dlsym(libusb, "libusb_get_string_descriptor_ascii") else {
    print("❌ Failed to load libusb functions")
    exit(1)
}

// Cast to function types
let libusb_init_fn = unsafeBitCast(libusb_init_ptr, to: libusb_init.self)
let libusb_exit_fn = unsafeBitCast(libusb_exit_ptr, to: libusb_exit.self)
let libusb_get_device_list_fn = unsafeBitCast(libusb_get_device_list_ptr, to: libusb_get_device_list.self)
let libusb_free_device_list_fn = unsafeBitCast(libusb_free_device_list_ptr, to: libusb_free_device_list.self)
let libusb_get_device_descriptor_fn = unsafeBitCast(libusb_get_device_descriptor_ptr, to: libusb_get_device_descriptor.self)
let libusb_open_fn = unsafeBitCast(libusb_open_ptr, to: libusb_open.self)
let libusb_close_fn = unsafeBitCast(libusb_close_ptr, to: libusb_close.self)
let libusb_get_config_descriptor_fn = unsafeBitCast(libusb_get_config_descriptor_ptr, to: libusb_get_config_descriptor.self)
let libusb_free_config_descriptor_fn = unsafeBitCast(libusb_free_config_descriptor_ptr, to: libusb_free_config_descriptor.self)
let libusb_get_string_descriptor_ascii_fn = unsafeBitCast(libusb_get_string_descriptor_ascii_ptr, to: libusb_get_string_descriptor_ascii.self)

// Initialize libusb
var context: OpaquePointer? = nil
if libusb_init_fn(&context) != 0 {
    print("❌ Failed to initialize libusb")
    exit(1)
}
defer { libusb_exit_fn(context!) }

// Get device list
var devices: UnsafeMutablePointer<OpaquePointer?>? = nil
let deviceCount = libusb_get_device_list_fn(context, &devices)
defer { libusb_free_device_list_fn(devices, 1) }

print("🔍 USB Device Probe")
print("Found \(deviceCount) devices")
print()

var mtpDevices: [(device: OpaquePointer, desc: libusb_device_descriptor)] = []

// Iterate through devices
for i in 0..<Int(deviceCount) {
    guard let device = devices?[i] else { continue }

    var desc = libusb_device_descriptor()
    if libusb_get_device_descriptor_fn(device, &desc) != 0 {
        print("❌ Failed to get device descriptor for device \(i)")
        continue
    }

    let vid = desc.idVendor
    let pid = desc.idProduct

    // Check if this looks like an MTP device (class 0x06 for PTP/MTP or vendor-specific)
    if desc.bDeviceClass == 0x06 || desc.bDeviceClass == 0xFF {
        mtpDevices.append((device, desc))
        print("🎯 Potential MTP Device \(mtpDevices.count - 1):")
        print("   VID:PID = \(String(format: "%04X:%04X", vid, pid))")
        print("   Device Class: 0x\(String(format: "%02X", desc.bDeviceClass))")
        print("   Device Subclass: 0x\(String(format: "%02X", desc.bDeviceSubClass))")
        print("   Protocol: 0x\(String(format: "%02X", desc.bDeviceProtocol))")
        print()
    }
}

// Detailed analysis of MTP devices
for (index, (device, desc)) in mtpDevices.enumerated() {
    print("📋 Detailed Analysis - Device \(index)")
    print("   VID:PID = \(String(format: "%04X:%04X", desc.idVendor, desc.idProduct))")

    // Try to get string descriptors
    var handle: OpaquePointer? = nil
    if libusb_open_fn(device, &handle) == 0 {
        defer { libusb_close_fn(handle!) }

        // Get manufacturer string
        var manufacturer = [CChar](repeating: 0, count: 256)
        if libusb_get_string_descriptor_ascii_fn(handle, desc.iManufacturer, &manufacturer, Int32(manufacturer.count)) > 0 {
            print("   Manufacturer: \(String(cString: manufacturer))")
        }

        // Get product string
        var product = [CChar](repeating: 0, count: 256)
        if libusb_get_string_descriptor_ascii_fn(handle, desc.iProduct, &product, Int32(product.count)) > 0 {
            print("   Product: \(String(cString: product))")
        }

        // Get configuration descriptor
        var config: UnsafeMutablePointer<libusb_config_descriptor>? = nil
        if libusb_get_config_descriptor_fn(device, 0, &config) == 0 {
            defer { libusb_free_config_descriptor_fn(config!) }

            print("   Configurations: \(desc.bNumConfigurations)")
            print("   Interfaces: \(config!.pointee.bNumInterfaces)")

            // Analyze interfaces
            let interfacePtr = config!.pointee.interface
            for ifaceIdx in 0..<Int(config!.pointee.bNumInterfaces) {
                let iface = interfacePtr[ifaceIdx]
                print("   Interface \(ifaceIdx):")

                for altIdx in 0..<Int(iface.num_altsetting) {
                    let alt = iface.altsetting[altIdx]
                    print("     Alt \(altIdx): class=0x\(String(format: "%02X", alt.bInterfaceClass)) sub=0x\(String(format: "%02X", alt.bInterfaceSubClass)) proto=0x\(String(format: "%02X", alt.bInterfaceProtocol))")

                    // Check for bulk endpoints (typical for MTP)
                    var bulkIn: UInt8? = nil
                    var bulkOut: UInt8? = nil
                    var interruptIn: UInt8? = nil

                    for epIdx in 0..<Int(alt.bNumEndpoints) {
                        let endpoint = alt.endpoint[epIdx]
                        let epAddr = endpoint.bEndpointAddress
                        let epType = endpoint.bmAttributes & 0x03

                        if epType == 2 { // Bulk endpoint
                            if (epAddr & 0x80) != 0 {
                                bulkIn = epAddr
                            } else {
                                bulkOut = epAddr
                            }
                        } else if epType == 3 { // Interrupt endpoint
                            if (epAddr & 0x80) != 0 {
                                interruptIn = epAddr
                            }
                        }
                    }

                    print("       Endpoints: \(alt.bNumEndpoints)")
                    if let bulkIn = bulkIn {
                        print("         Bulk IN: 0x\(String(format: "%02X", bulkIn))")
                    }
                    if let bulkOut = bulkOut {
                        print("         Bulk OUT: 0x\(String(format: "%02X", bulkOut))")
                    }
                    if let interruptIn = interruptIn {
                        print("         Interrupt IN: 0x\(String(format: "%02X", interruptIn))")
                    }

                    // Check if this looks like an MTP interface
                    let isMTP = (alt.bInterfaceClass == 0x06 && alt.bInterfaceSubClass == 0x01) || // PTP/MTP
                               (alt.bInterfaceClass == 0xFF) // Vendor specific (often MTP on older devices)

                    if isMTP && bulkIn != nil && bulkOut != nil {
                        print("       🎯 MTP CANDIDATE - Interface \(ifaceIdx) Alt \(altIdx)")
                        if let interruptIn = interruptIn {
                            print("         Has event endpoint (good for MTP)")
                        }
                    }
                }
            }
        } else {
            print("   ❌ Could not get configuration descriptor")
        }
    } else {
        print("   ❌ Could not open device (may require root/sudo)")
    }

    print()
}

if mtpDevices.isEmpty {
    print("❌ No MTP devices found")
    print("Make sure your device is:")
    print("  1. Connected via USB")
    print("  2. In 'File Transfer' or 'MTP' mode")
    print("  3. Unlocked (screen on)")
} else {
    print("✅ Found \(mtpDevices.count) potential MTP device(s)")
    print("Use the interface/alt numbers above to configure SwiftMTP")
}

print("\nProbe complete")
