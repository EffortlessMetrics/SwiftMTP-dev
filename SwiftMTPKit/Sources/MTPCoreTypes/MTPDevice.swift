// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation

// MARK: - MTPDevice Protocol

/// Protocol defining the interface for interacting with MTP devices.
///
/// This protocol provides the core functionality for browsing, reading from,
/// and writing to MTP-compliant devices such as smartphones, tablets, and cameras.
///
/// ## Example Usage
/// ```swift
/// // Get device information
/// let info = try await device.info
/// print("Connected to \(info.manufacturer) \(info.model)")
///
/// // List storage devices
/// let storages = try await device.storages()
/// for storage in storages {
///     print("Storage: \(storage.description)")
/// }
///
/// // Download a file
/// let progress = try await device.read(handle: fileHandle, range: nil, to: destinationURL)
/// print("Downloaded \(progress.completedUnitCount) bytes")
/// ```
public protocol MTPDevice: Sendable {
  /// Unique identifier for this device instance
  var id: MTPDeviceID { get }

  /// Device summary information
  var summary: MTPDeviceSummary { get }

  /// Detailed information about the device and its capabilities.
  ///
  /// This includes manufacturer, model, version, supported operations,
  /// and other device-specific information.
  var info: MTPDeviceInfo { get async throws }

  /// Get information about all storage devices on this MTP device.
  ///
  /// Most devices have a single storage (internal), but some devices
  /// like cameras may have multiple storages (internal + SD card).
  ///
  /// - Returns: Array of storage information structures
  func storages() async throws -> [MTPStorageInfo]

  /// Enumerate objects (files and folders) in a storage device.
  ///
  /// This method provides an asynchronous stream of object batches for
  /// efficient enumeration of large directories without loading everything
  /// into memory at once.
  ///
  /// - Parameters:
  ///   - parent: Parent directory handle, or `nil` for root directory
  ///   - storage: Storage device to enumerate
  /// - Returns: Async stream yielding batches of object information
  func list(parent: MTPObjectHandle?, in storage: MTPStorageID) -> AsyncThrowingStream<
    [MTPObjectInfo], Error
  >

  /// Get detailed information about a specific object.
  ///
  /// - Parameter handle: Handle of the object to query
  /// - Returns: Detailed object information
  func getInfo(handle: MTPObjectHandle) async throws -> MTPObjectInfo

  /// Read data from an object (download file).
  ///
  /// Supports resumable downloads when the device supports partial object operations.
  /// Progress is reported through the returned `Progress` object.
  ///
  /// - Parameters:
  ///   - handle: Handle of the object to read
  ///   - range: Byte range to read, or `nil` for entire file
  ///   - url: Local destination URL for the downloaded data
  /// - Returns: Progress object for monitoring transfer progress
  func read(handle: MTPObjectHandle, range: Range<UInt64>?, to url: URL) async throws -> Progress

  /// Write data to create a new object (upload file).
  ///
  /// - Parameters:
  ///   - parent: Parent directory handle, or `nil` for root
  ///   - name: Name for the new file
  ///   - size: Size of the data to be written
  ///   - url: Local source URL of the data to upload
  /// - Returns: Progress object for monitoring transfer progress
  func write(parent: MTPObjectHandle?, name: String, size: UInt64, from url: URL) async throws
    -> Progress

  /// Create a folder on the device.
  ///
  /// - Parameters:
  ///   - parent: Parent directory handle, or `nil` for root
  ///   - name: Name for the new folder
  ///   - storage: Target storage ID
  /// - Returns: Handle of the newly created folder
  func createFolder(parent: MTPObjectHandle?, name: String, storage: MTPStorageID) async throws
    -> MTPObjectHandle

  /// Delete an object from the device.
  ///
  /// - Parameters:
  ///   - handle: Handle of the object to delete
  ///   - recursive: If `true`, delete directories and their contents recursively
  func delete(_ handle: MTPObjectHandle, recursive: Bool) async throws

  /// Move an object to a new location on the device.
  ///
  /// - Parameters:
  ///   - handle: Handle of the object to move
  ///   - newParent: New parent directory handle, or `nil` for root
  func move(_ handle: MTPObjectHandle, to newParent: MTPObjectHandle?) async throws

  /// Ensure the device session is open, opening it if necessary.
  func openIfNeeded() async throws

  /// Stream of events from the device.
  ///
  /// Listen to this stream to be notified of changes to the device's
  /// content or state, such as files being added or removed.
  var events: AsyncStream<MTPEvent> { get }
}

// MARK: - Default Implementations

public extension MTPDevice {
  /// Default implementation returns an empty async stream
  var events: AsyncStream<MTPEvent> {
    AsyncStream { _ in }
  }
}
