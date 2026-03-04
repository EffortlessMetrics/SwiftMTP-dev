// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

// IOUSBHost native transport for App Store distribution.
// This module replaces LibUSBTransport with Apple's IOUSBHost framework,
// removing the libusb dependency for sandboxed / notarised builds.
//
// Requires macOS 15.0+ (IOUSBHost framework availability).

#if canImport(IOUSBHost)

import Foundation
import IOUSBHost
import SwiftMTPCore

/// Error thrown by unimplemented IOUSBHost transport stubs.
public enum IOUSBHostTransportError: Error, Sendable {
  case notImplemented(String)
}

// MARK: - IOUSBHostLink

/// MTPLink implementation backed by Apple's IOUSBHost framework.
///
/// Lifecycle:
///   1. `openUSBIfNeeded()` — claim the USB interface via IOUSBHostInterface
///   2. `openSession(id:)` — send MTP OpenSession command
///   3. Use device operations (getDeviceInfo, getStorageIDs, etc.)
///   4. `closeSession()` / `close()` — release USB resources
///
/// - Note: This is architectural scaffolding only. Every method currently
///   throws `IOUSBHostTransportError.notImplemented`.
public final class IOUSBHostLink: @unchecked Sendable, MTPLink {

  // TODO: Implement IOUSBHost transport — store IOUSBHostDevice reference
  // TODO: Implement IOUSBHost transport — store IOUSBHostInterface reference
  // TODO: Implement IOUSBHost transport — store IOUSBHostPipe references for bulk-in, bulk-out, interrupt-in

  public init() {}

  // MARK: - MTPLink Protocol

  public var cachedDeviceInfo: MTPDeviceInfo? { nil }
  public var linkDescriptor: MTPLinkDescriptor? { nil }

  /// Claim the USB interface and configure bulk/interrupt pipes.
  /// TODO: Implement IOUSBHost transport — use IOUSBHostDevice.configurationDescriptor
  /// to find the MTP interface, then IOUSBHostInterface to claim it and create pipes.
  public func openUSBIfNeeded() async throws {
    throw IOUSBHostTransportError.notImplemented("openUSBIfNeeded: claim IOUSBHostInterface")
  }

  /// Send MTP OpenSession (0x1002) to the device.
  /// TODO: Implement IOUSBHost transport — build PTP container, send via bulk-out pipe,
  /// read response from bulk-in pipe.
  public func openSession(id: UInt32) async throws {
    throw IOUSBHostTransportError.notImplemented("openSession")
  }

  /// Send MTP CloseSession (0x1003) to the device.
  /// TODO: Implement IOUSBHost transport
  public func closeSession() async throws {
    throw IOUSBHostTransportError.notImplemented("closeSession")
  }

  /// Release all USB resources (interface, pipes, device handle).
  /// TODO: Implement IOUSBHost transport — invalidate pipes, destroy IOUSBHostInterface
  public func close() async {
    // No-op stub — nothing to release yet.
  }

  /// Read MTP DeviceInfo (0x1001) from the device.
  /// TODO: Implement IOUSBHost transport — send GetDeviceInfo command, parse response data phase
  public func getDeviceInfo() async throws -> MTPDeviceInfo {
    throw IOUSBHostTransportError.notImplemented("getDeviceInfo")
  }

  /// Read storage IDs from the device (0x1004).
  /// TODO: Implement IOUSBHost transport
  public func getStorageIDs() async throws -> [MTPStorageID] {
    throw IOUSBHostTransportError.notImplemented("getStorageIDs")
  }

  /// Read storage info for a given storage ID (0x1005).
  /// TODO: Implement IOUSBHost transport
  public func getStorageInfo(id: MTPStorageID) async throws -> MTPStorageInfo {
    throw IOUSBHostTransportError.notImplemented("getStorageInfo")
  }

  /// Enumerate object handles in the given storage/parent (0x1007).
  /// TODO: Implement IOUSBHost transport
  public func getObjectHandles(storage: MTPStorageID, parent: MTPObjectHandle?) async throws
    -> [MTPObjectHandle]
  {
    throw IOUSBHostTransportError.notImplemented("getObjectHandles")
  }

  /// Batch-fetch object info for the given handles.
  /// TODO: Implement IOUSBHost transport — iterate handles, call GetObjectInfo (0x1008) each
  public func getObjectInfos(_ handles: [MTPObjectHandle]) async throws -> [MTPObjectInfo] {
    throw IOUSBHostTransportError.notImplemented("getObjectInfos(handles:)")
  }

  /// Fetch object infos filtered by storage/parent/format.
  /// TODO: Implement IOUSBHost transport
  public func getObjectInfos(storage: MTPStorageID, parent: MTPObjectHandle?, format: UInt16?)
    async throws -> [MTPObjectInfo]
  {
    throw IOUSBHostTransportError.notImplemented("getObjectInfos(storage:parent:format:)")
  }

  /// Send MTP ResetDevice (0x0010).
  /// TODO: Implement IOUSBHost transport
  public func resetDevice() async throws {
    throw IOUSBHostTransportError.notImplemented("resetDevice")
  }

  /// Delete an object on the device (0x100B).
  /// TODO: Implement IOUSBHost transport
  public func deleteObject(handle: MTPObjectHandle) async throws {
    throw IOUSBHostTransportError.notImplemented("deleteObject")
  }

  /// Move an object on the device (0x100D if supported).
  /// TODO: Implement IOUSBHost transport
  public func moveObject(handle: MTPObjectHandle, to storage: MTPStorageID, parent: MTPObjectHandle?)
    async throws
  {
    throw IOUSBHostTransportError.notImplemented("moveObject")
  }

  /// Copy an object on the device (0x100E if supported).
  /// TODO: Implement IOUSBHost transport
  public func copyObject(
    handle: MTPObjectHandle, toStorage storage: MTPStorageID, parent: MTPObjectHandle?
  ) async throws -> MTPObjectHandle {
    throw IOUSBHostTransportError.notImplemented("copyObject")
  }

  /// Execute a raw PTP/MTP command container.
  /// TODO: Implement IOUSBHost transport — send command via bulk-out, read response via bulk-in
  public func executeCommand(_ command: PTPContainer) async throws -> PTPResponseResult {
    throw IOUSBHostTransportError.notImplemented("executeCommand")
  }

  /// Execute a streaming command with data-in/data-out phases.
  /// TODO: Implement IOUSBHost transport — handle chunked bulk transfers via IOUSBHostPipe
  public func executeStreamingCommand(
    _ command: PTPContainer,
    dataPhaseLength: UInt64?,
    dataInHandler: MTPDataIn?,
    dataOutHandler: MTPDataOut?
  ) async throws -> PTPResponseResult {
    throw IOUSBHostTransportError.notImplemented("executeStreamingCommand")
  }
}

// MARK: - IOUSBHostTransport (MTPTransport)

/// MTPTransport factory that creates IOUSBHostLink instances.
///
/// TODO: Implement IOUSBHost transport — discover the target device using
/// IOUSBHostDeviceLocator, then hand it to IOUSBHostLink for session management.
public final class IOUSBHostTransport: @unchecked Sendable, MTPTransport {

  public init() {}

  /// Open a link to the specified MTP device via IOUSBHost.
  /// TODO: Implement IOUSBHost transport — match device by VID:PID, create IOUSBHostDevice,
  /// probe interfaces, return configured IOUSBHostLink.
  public func open(_ summary: MTPDeviceSummary, config: SwiftMTPConfig) async throws -> MTPLink {
    throw IOUSBHostTransportError.notImplemented("IOUSBHostTransport.open")
  }

  /// Close and release all transport resources.
  /// TODO: Implement IOUSBHost transport
  public func close() async throws {
    // No-op stub — nothing to release yet.
  }
}

// MARK: - IOUSBHostTransportFactory

/// TransportFactory for IOUSBHost-backed transport.
public struct IOUSBHostTransportFactory: TransportFactory {
  public static func createTransport() -> MTPTransport {
    IOUSBHostTransport()
  }
}

#else

// Fallback for platforms where IOUSBHost is unavailable (e.g. Linux, older macOS).
// Provides the same public types so downstream code can reference them without
// conditional compilation at every call site.

import Foundation
import SwiftMTPCore

public enum IOUSBHostTransportError: Error, Sendable {
  case notImplemented(String)
  case unavailable
}

public final class IOUSBHostLink: @unchecked Sendable, MTPLink {
  public init() {}
  public func openUSBIfNeeded() async throws {
    throw IOUSBHostTransportError.unavailable
  }
  public func openSession(id: UInt32) async throws {
    throw IOUSBHostTransportError.unavailable
  }
  public func closeSession() async throws {
    throw IOUSBHostTransportError.unavailable
  }
  public func close() async {}
  public func getDeviceInfo() async throws -> MTPDeviceInfo {
    throw IOUSBHostTransportError.unavailable
  }
  public func getStorageIDs() async throws -> [MTPStorageID] {
    throw IOUSBHostTransportError.unavailable
  }
  public func getStorageInfo(id: MTPStorageID) async throws -> MTPStorageInfo {
    throw IOUSBHostTransportError.unavailable
  }
  public func getObjectHandles(storage: MTPStorageID, parent: MTPObjectHandle?) async throws
    -> [MTPObjectHandle]
  {
    throw IOUSBHostTransportError.unavailable
  }
  public func getObjectInfos(_ handles: [MTPObjectHandle]) async throws -> [MTPObjectInfo] {
    throw IOUSBHostTransportError.unavailable
  }
  public func getObjectInfos(storage: MTPStorageID, parent: MTPObjectHandle?, format: UInt16?)
    async throws -> [MTPObjectInfo]
  {
    throw IOUSBHostTransportError.unavailable
  }
  public func resetDevice() async throws {
    throw IOUSBHostTransportError.unavailable
  }
  public func deleteObject(handle: MTPObjectHandle) async throws {
    throw IOUSBHostTransportError.unavailable
  }
  public func moveObject(handle: MTPObjectHandle, to storage: MTPStorageID, parent: MTPObjectHandle?)
    async throws
  {
    throw IOUSBHostTransportError.unavailable
  }
  public func copyObject(
    handle: MTPObjectHandle, toStorage storage: MTPStorageID, parent: MTPObjectHandle?
  ) async throws -> MTPObjectHandle {
    throw IOUSBHostTransportError.unavailable
  }
  public func executeCommand(_ command: PTPContainer) async throws -> PTPResponseResult {
    throw IOUSBHostTransportError.unavailable
  }
  public func executeStreamingCommand(
    _ command: PTPContainer,
    dataPhaseLength: UInt64?,
    dataInHandler: MTPDataIn?,
    dataOutHandler: MTPDataOut?
  ) async throws -> PTPResponseResult {
    throw IOUSBHostTransportError.unavailable
  }
}

public final class IOUSBHostTransport: @unchecked Sendable, MTPTransport {
  public init() {}
  public func open(_ summary: MTPDeviceSummary, config: SwiftMTPConfig) async throws -> MTPLink {
    throw IOUSBHostTransportError.unavailable
  }
  public func close() async throws {}
}

public struct IOUSBHostTransportFactory: TransportFactory {
  public static func createTransport() -> MTPTransport {
    IOUSBHostTransport()
  }
}

#endif
