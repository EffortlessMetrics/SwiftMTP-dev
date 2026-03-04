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

// MARK: - IOUSBHostDeviceLocator

/// Discovers MTP-capable USB devices using IOKit matching dictionaries.
///
/// Usage (future):
/// ```swift
/// let devices = try await IOUSBHostDeviceLocator.enumerateMTPDevices()
/// ```
///
/// - Note: This is architectural scaffolding only. All methods throw
///   `IOUSBHostTransportError.notImplemented`.
public enum IOUSBHostDeviceLocator {

  /// Scan the USB bus for MTP-capable devices and return summaries.
  ///
  /// Implementation plan:
  ///   1. Build IOServiceMatching("IOUSBHostDevice") dictionary
  ///   2. Iterate matching services via IOServiceGetMatchingServices
  ///   3. For each service, read idVendor / idProduct / bcdDevice
  ///   4. Open the device, inspect configuration descriptor for MTP interfaces
  ///      (class 6 / subclass 1 / protocol 1, or known VID:PID pairs)
  ///   5. Build MTPDeviceSummary for each candidate
  ///
  /// TODO: Implement IOUSBHost transport — full device enumeration
  public static func enumerateMTPDevices() async throws -> [MTPDeviceSummary] {
    throw IOUSBHostTransportError.notImplemented(
      "IOUSBHostDeviceLocator.enumerateMTPDevices: IOKit matching not yet implemented")
  }

  /// Start monitoring for USB device attach/detach events.
  ///
  /// Implementation plan:
  ///   1. Create IONotificationPort
  ///   2. Register for kIOFirstMatchNotification and kIOTerminatedNotification
  ///   3. Yield MTPDeviceEvent values on the returned AsyncStream
  ///
  /// TODO: Implement IOUSBHost transport — hotplug monitoring
  public static func deviceEvents() -> AsyncStream<MTPDeviceEvent> {
    // Return an empty stream until implemented.
    AsyncStream { $0.finish() }
  }
}

// MARK: - MTPDeviceEvent

/// Represents a USB device attach or detach event.
///
/// TODO: Implement IOUSBHost transport — expand with full device metadata
public enum MTPDeviceEvent: Sendable {
  /// An MTP-capable device was connected.
  case attached(MTPDeviceSummary)
  /// A previously-connected device was removed. The string is a device identifier.
  case detached(String)
}
