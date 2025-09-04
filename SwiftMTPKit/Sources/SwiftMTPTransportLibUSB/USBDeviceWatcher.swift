// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import CLibusb
import SwiftMTPCore
import SwiftMTPObservability

public enum USBDeviceWatcher {
    private final class Box {
        let onAttach: (MTPDeviceSummary) -> Void
        let onDetach: (MTPDeviceID) -> Void
        init(_ a: @escaping (MTPDeviceSummary)->Void, _ d: @escaping (MTPDeviceID)->Void) {
            onAttach=a
            onDetach=d
        }
    }

    // C callback trampoline
    private static let callback: libusb_hotplug_callback_fn? = { _, dev, event, userData in
        guard let dev = dev, let ud = userData else { return 0 }
        let box = Unmanaged<Box>.fromOpaque(ud).takeUnretainedValue()
        var desc = libusb_device_descriptor()
        guard libusb_get_device_descriptor(dev, &desc) == 0 else { return 0 }

        // Build a stable-ish ID: VID:PID:bus:addr (we'll switch to MTP DeviceInfo later)
        let id = MTPDeviceID(raw: String(format:"%04x:%04x@%u:%u",
                                         desc.idVendor, desc.idProduct,
                                         libusb_get_bus_number(dev), libusb_get_device_address(dev)))

        if event == LIBUSB_HOTPLUG_EVENT_DEVICE_ARRIVED {
            // Debug: Print device info
            MTPLog.transport.info("Device arrived: VID=\(String(format:"%04x", desc.idVendor)), PID=\(String(format:"%04x", desc.idProduct)), bus=\(libusb_get_bus_number(dev)), addr=\(libusb_get_device_address(dev))")

            // Filter for interface class 0x06 (MTP/PTP). Cheap check using config 0.
            var cfg: UnsafeMutablePointer<libusb_config_descriptor>? = nil
            if libusb_get_active_config_descriptor(dev, &cfg) == 0, let cfg {
                defer { libusb_free_config_descriptor(cfg) }
                var isMTP = false
                MTPLog.transport.info("Device has \(cfg.pointee.bNumInterfaces) interfaces")
                for i in 0..<cfg.pointee.bNumInterfaces {
                    let iface = cfg.pointee.interface[Int(i)]
                    for a in 0..<iface.num_altsetting {
                        let alt = iface.altsetting[Int(a)]
                        MTPLog.transport.info("Interface \(i), alt \(a): class=\(alt.bInterfaceClass), subclass=\(alt.bInterfaceSubClass), protocol=\(alt.bInterfaceProtocol)")
                        if alt.bInterfaceClass == 0x06 {
                            isMTP = true
                            break
                        }
                    }
                    if isMTP { break }
                }
                if !isMTP {
                    MTPLog.transport.info("Device is not MTP, skipping")
                    return 0
                }
            } else {
                MTPLog.transport.info("Could not get config descriptor")
                return 0
            }
            // Strings from USB descriptor are optional; use placeholders
            let summary = MTPDeviceSummary(id: id,
                                           manufacturer: "USB \(String(format:"%04x", desc.idVendor))",
                                           model: "USB \(String(format:"%04x", desc.idProduct))")
            box.onAttach(summary)
        } else if event == LIBUSB_HOTPLUG_EVENT_DEVICE_LEFT {
            MTPLog.transport.info("Device left: \(id.raw)")
            box.onDetach(id)
        }
        return 0
    }

    public static func start(onAttach: @escaping (MTPDeviceSummary)->Void,
                              onDetach: @escaping (MTPDeviceID)->Void) {
        _ = LibUSBContext.shared // ensure ctx + event loop
        guard let ctx = LibUSBContext.shared.contextPointer else { return }
        let flags: Int32 = Int32(LIBUSB_HOTPLUG_ENUMERATE.rawValue)
        var cb: Int32 = 0
        let box = Unmanaged.passRetained(Box(onAttach, onDetach)).toOpaque()
        let events: Int32 = Int32(LIBUSB_HOTPLUG_EVENT_DEVICE_ARRIVED.rawValue) | Int32(LIBUSB_HOTPLUG_EVENT_DEVICE_LEFT.rawValue)
        let rc = libusb_hotplug_register_callback(ctx,
                          events,
                          flags,
                          LIBUSB_HOTPLUG_MATCH_ANY, LIBUSB_HOTPLUG_MATCH_ANY, LIBUSB_HOTPLUG_MATCH_ANY,
                          callback, box, &cb)
        if rc != 0 {
            MTPLog.transport.error("hotplug register failed: \(rc)")
        } else {
            MTPLog.transport.info("Hotplug callback registered successfully")
        }
    }
}
