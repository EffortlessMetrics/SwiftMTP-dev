// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

// Device enumeration and hotplug monitoring using IOKit / IOUSBHost.
//
// This locator mirrors the role of LibUSBDiscovery (in SwiftMTPTransportLibUSB)
// but uses Apple-native APIs:
//   - IOServiceMatching / IOServiceGetMatchingServices for enumeration
//   - IOUSBHostDevice for device access (macOS 15+)
//   - IOServiceAddMatchingNotification for hotplug events
//
// For the MTP interface heuristic (class 6 / subclass 1 / protocol 1, or
// vendor-specific with known VID:PID), see InterfaceProbe.swift in the
// LibUSB transport for the canonical scoring logic.

import Foundation
import SwiftMTPCore

#if canImport(IOUSBHost)
import IOKit
import IOKit.usb
import IOUSBHost
import OSLog

private let log = Logger(subsystem: "com.swiftmtp.transport.iousbhost", category: "Locator")
#endif

// MARK: - IOUSBHostDeviceLocator

/// Discovers MTP-capable USB devices using IOKit matching dictionaries.
///
/// Usage:
/// ```swift
/// let devices = try await IOUSBHostDeviceLocator.enumerateMTPDevices()
/// ```
public enum IOUSBHostDeviceLocator {

  /// Scan the USB bus for MTP-capable devices and return summaries.
  ///
  /// Implementation:
  ///   1. Build IOServiceMatching("IOUSBHostDevice") dictionary
  ///   2. Iterate matching services via IOServiceGetMatchingServices
  ///   3. For each service, read idVendor / idProduct
  ///   4. Inspect child interfaces for MTP class (6/1/1) or known VID:PID pairs
  ///   5. Build MTPDeviceSummary for each candidate
  public static func enumerateMTPDevices() async throws -> [MTPDeviceSummary] {
    #if canImport(IOUSBHost)
    return enumerateViaIOKit()
    #else
    throw IOUSBHostTransportError.unavailable
    #endif
  }

  /// Start monitoring for USB device attach/detach events.
  ///
  /// TODO: Implement IOUSBHost transport — hotplug monitoring via IONotificationPort.
  /// Current implementation returns an empty stream.
  public static func deviceEvents() -> AsyncStream<MTPDeviceEvent> {
    AsyncStream { $0.finish() }
  }

  #if canImport(IOUSBHost)
  /// Enumerate USB devices via IOKit matching, filtering for MTP candidates.
  private static func enumerateViaIOKit() -> [MTPDeviceSummary] {
    guard let matchDict = IOServiceMatching("IOUSBHostDevice") else { return [] }

    var iterator: io_iterator_t = 0
    let kr = IOServiceGetMatchingServices(kIOMainPortDefault, matchDict, &iterator)
    guard kr == KERN_SUCCESS else {
      log.warning("IOServiceGetMatchingServices failed: \(kr)")
      return []
    }
    defer { IOObjectRelease(iterator) }

    var devices: [MTPDeviceSummary] = []
    var service = IOIteratorNext(iterator)
    while service != IO_OBJECT_NULL {
      defer {
        IOObjectRelease(service)
        service = IOIteratorNext(iterator)
      }

      guard let props = readProperties(service) else { continue }
      guard let vid = props["idVendor"] as? Int,
        let pid = props["idProduct"] as? Int
      else { continue }

      // Check if any child interface matches MTP class (6/1/1)
      let hasMTPInterface = checkForMTPInterface(device: service)
      // Also accept known MTP VID:PID ranges (Android: 0xff10-0xff60 on Xiaomi, etc.)
      let isKnownMTPDevice = isKnownMTPVendor(vid: UInt16(vid), pid: UInt16(pid))

      if hasMTPInterface || isKnownMTPDevice {
        let manufacturer = props["USB Vendor Name"] as? String ?? "Unknown"
        let model = props["USB Product Name"] as? String ?? "Unknown"
        let serial = props["USB Serial Number"] as? String
        let bus = props["locationID"] as? Int
        let busNum = bus.map { UInt8(($0 >> 24) & 0xFF) }

        let summary = MTPDeviceSummary(
          id: MTPDeviceID(raw: String(format: "%04x:%04x", vid, pid)),
          manufacturer: manufacturer,
          model: model,
          vendorID: UInt16(vid),
          productID: UInt16(pid),
          bus: busNum,
          address: nil,
          usbSerial: serial
        )
        devices.append(summary)
        log.info(
          "Found MTP candidate: \(manufacturer, privacy: .public) \(model, privacy: .public) [\(String(format: "%04x:%04x", vid, pid), privacy: .public)]"
        )
      }
    }
    return devices
  }

  /// Check if a USB device has a child interface matching MTP class 6/1/1.
  private static func checkForMTPInterface(device: io_service_t) -> Bool {
    var childIterator: io_iterator_t = 0
    let kr = IORegistryEntryGetChildIterator(device, kIOServicePlane, &childIterator)
    guard kr == KERN_SUCCESS else { return false }
    defer { IOObjectRelease(childIterator) }

    var child = IOIteratorNext(childIterator)
    while child != IO_OBJECT_NULL {
      defer {
        IOObjectRelease(child)
        child = IOIteratorNext(childIterator)
      }
      guard let props = readProperties(child) else { continue }
      let ifClass = props["bInterfaceClass"] as? Int ?? 0
      let ifSubclass = props["bInterfaceSubClass"] as? Int ?? 0
      let ifProtocol = props["bInterfaceProtocol"] as? Int ?? 0
      if ifClass == Int(MTPInterfaceMatch.interfaceClass)
        && ifSubclass == Int(MTPInterfaceMatch.interfaceSubclass)
        && ifProtocol == Int(MTPInterfaceMatch.interfaceProtocol)
      {
        return true
      }
    }
    return false
  }

  /// Known MTP device vendors that use vendor-specific class instead of 6/1/1.
  private static func isKnownMTPVendor(vid: UInt16, pid: UInt16) -> Bool {
    switch vid {
    case 0x2717: return true  // Xiaomi
    case 0x18D1: return true  // Google
    case 0x04E8: return true  // Samsung
    case 0x2A70: return true  // OnePlus
    case 0x22D9: return true  // OPPO
    case 0x2341: return true  // Realme
    default: return false
    }
  }

  /// Read all registry properties of an IOService.
  private static func readProperties(_ service: io_service_t) -> [String: Any]? {
    var propsRef: Unmanaged<CFMutableDictionary>?
    let kr = IORegistryEntryCreateCFProperties(service, &propsRef, kCFAllocatorDefault, 0)
    guard kr == KERN_SUCCESS, let props = propsRef?.takeRetainedValue() as? [String: Any] else {
      return nil
    }
    return props
  }

  /// MTP interface class constants (duplicated here to avoid cross-file dependency).
  private enum MTPInterfaceMatch {
    static let interfaceClass: UInt8 = 6
    static let interfaceSubclass: UInt8 = 1
    static let interfaceProtocol: UInt8 = 1
  }
  #endif
}

// MARK: - MTPDeviceEvent

/// Represents a USB device attach or detach event.
public enum MTPDeviceEvent: Sendable {
  /// An MTP-capable device was connected.
  case attached(MTPDeviceSummary)
  /// A previously-connected device was removed. The string is a device identifier.
  case detached(String)
}
