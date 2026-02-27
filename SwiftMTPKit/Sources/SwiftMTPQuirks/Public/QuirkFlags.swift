// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation

/// Typed boolean/enum knobs replacing untyped `operations` maps.
/// Each flag controls a specific device behavior at a well-defined layer.
public struct QuirkFlags: Sendable, Codable, Equatable {

  // MARK: - Transport-level

  /// Issue `libusb_reset_device` after opening the handle.
  public var resetOnOpen: Bool = false

  /// Detach macOS kernel driver before claiming the interface.
  public var requiresKernelDetach: Bool = true

  /// Use longer handshake timeout for slow-to-respond devices.
  public var needsLongerOpenTimeout: Bool = false

  // MARK: - Protocol-level

  /// Device requires an open session before GetDeviceInfo responds.
  public var requiresSessionBeforeDeviceInfo: Bool = false

  /// Device resets its transaction-ID counter when a new session opens.
  public var transactionIdResetsOnSession: Bool = false

  /// On first OpenSession timeout/I/O failure, perform a one-time
  /// reset+reopen recovery ladder before giving up.
  public var resetReopenOnOpenSessionIOError: Bool = false

  // MARK: - Transfer-level

  /// Device supports GetPartialObject64 (0x95C4).
  public var supportsPartialRead64: Bool = true

  /// Device supports GetPartialObject (0x101B).
  public var supportsPartialRead32: Bool = true

  /// Device supports SendPartialObject (0x95C1).
  public var supportsPartialWrite: Bool = true

  /// Prefer GetObjectPropList (batch) over GetObjectInfo (per-handle).
  public var prefersPropListEnumeration: Bool = true

  /// Device stalls on reads larger than its internal buffer.
  public var needsShortReads: Bool = false

  /// Device stalls on large bulk reads (limit chunk size).
  public var stallOnLargeReads: Bool = false

  // MARK: - Session-level

  /// Suppress the interrupt-endpoint event pump.
  public var disableEventPump: Bool = false

  /// Insert a post-open stabilization delay.
  public var requireStabilization: Bool = false

  /// Skip PTP Device Reset (0x66) control transfer on open.
  public var skipPTPReset: Bool = false

  // MARK: - Write-level

  /// Device requires writes to a subfolder (not storage root).
  /// Some Xiaomi/OnePlus devices return InvalidParameter (0x201D) when writing to root.
  public var writeToSubfolderOnly: Bool = false

  /// Preferred folder name for writes when writeToSubfolderOnly is true.
  /// Example: "Download", "DCIM", "Pictures"
  public var preferredWriteFolder: String?

  /// Force 0xFFFFFFFF for storage ID in SendObjectInfo command.
  /// Some devices reject the real storage ID and require the wildcard.
  public var forceFFFFFFFForSendObject: Bool = false

  /// Use empty strings for dates (CaptureDate, ModificationDate) in SendObjectInfo.
  /// Some devices reject date strings with InvalidParameter.
  public var emptyDatesInSendObject: Bool = false

  /// Force ObjectCompressedSize to 0xFFFFFFFF in SendObjectInfo.
  /// Disabled by default; some devices reject unknown-size semantics.
  public var unknownSizeInSendObjectInfo: Bool = false

  // MARK: - Property-level

  /// Skip GetObjectPropValue / SetObjectPropValue calls for all objects.
  /// Some devices hang or return error codes on these operations.
  /// Disabling prop-value calls degrades metadata accuracy (e.g., dates, sizes > 4 GB).
  public var skipGetObjectPropValue: Bool = false

  /// Device supports GetObjectPropList (0x9805) for batch directory enumeration.
  /// When true, a single round-trip fetches all properties for all children of a parent.
  public var supportsGetObjectPropList: Bool = false

  /// Device supports GetPartialObject (0x101B) for partial/resumable reads.
  /// When true, interrupted downloads can resume from a byte offset instead of restarting.
  public var supportsGetPartialObject: Bool = false

  public init() {}

  /// Reasonable defaults for an unrecognized PTP/Still-Image-Capture class device
  /// (USB interface class 0x06, subclass 0x01, protocol 0x01).
  /// Used when a device connects with no matching quirk entry.
  public static func ptpCameraDefaults() -> QuirkFlags {
    var f = QuirkFlags()
    f.requiresKernelDetach = false
    f.supportsGetObjectPropList = true
    f.prefersPropListEnumeration = true
    f.supportsPartialRead32 = true
    return f
  }

  // MARK: - Custom Codable for backward compatibility

  private enum CodingKeys: String, CodingKey {
    case resetOnOpen
    case requiresKernelDetach
    case needsLongerOpenTimeout
    case requiresSessionBeforeDeviceInfo
    case transactionIdResetsOnSession
    case resetReopenOnOpenSessionIOError
    case supportsPartialRead64
    case supportsPartialRead32
    case supportsPartialWrite
    case prefersPropListEnumeration
    case needsShortReads
    case stallOnLargeReads
    case disableEventPump
    case requireStabilization
    case skipPTPReset
    case writeToSubfolderOnly
    case preferredWriteFolder
    case forceFFFFFFFForSendObject
    case emptyDatesInSendObject
    case unknownSizeInSendObjectInfo
    case skipGetObjectPropValue
    case supportsGetObjectPropList
    case supportsGetPartialObject
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.resetOnOpen = try container.decodeIfPresent(Bool.self, forKey: .resetOnOpen) ?? false
    self.requiresKernelDetach =
      try container.decodeIfPresent(Bool.self, forKey: .requiresKernelDetach) ?? true
    self.needsLongerOpenTimeout =
      try container.decodeIfPresent(Bool.self, forKey: .needsLongerOpenTimeout) ?? false
    self.requiresSessionBeforeDeviceInfo =
      try container.decodeIfPresent(Bool.self, forKey: .requiresSessionBeforeDeviceInfo) ?? false
    self.transactionIdResetsOnSession =
      try container.decodeIfPresent(Bool.self, forKey: .transactionIdResetsOnSession) ?? false
    self.resetReopenOnOpenSessionIOError =
      try container.decodeIfPresent(Bool.self, forKey: .resetReopenOnOpenSessionIOError) ?? false
    self.supportsPartialRead64 =
      try container.decodeIfPresent(Bool.self, forKey: .supportsPartialRead64) ?? true
    self.supportsPartialRead32 =
      try container.decodeIfPresent(Bool.self, forKey: .supportsPartialRead32) ?? true
    self.supportsPartialWrite =
      try container.decodeIfPresent(Bool.self, forKey: .supportsPartialWrite) ?? true
    self.prefersPropListEnumeration =
      try container.decodeIfPresent(Bool.self, forKey: .prefersPropListEnumeration) ?? true
    self.needsShortReads =
      try container.decodeIfPresent(Bool.self, forKey: .needsShortReads) ?? false
    self.stallOnLargeReads =
      try container.decodeIfPresent(Bool.self, forKey: .stallOnLargeReads) ?? false
    self.disableEventPump =
      try container.decodeIfPresent(Bool.self, forKey: .disableEventPump) ?? false
    self.requireStabilization =
      try container.decodeIfPresent(Bool.self, forKey: .requireStabilization) ?? false
    self.skipPTPReset = try container.decodeIfPresent(Bool.self, forKey: .skipPTPReset) ?? false
    self.writeToSubfolderOnly =
      try container.decodeIfPresent(Bool.self, forKey: .writeToSubfolderOnly) ?? false
    self.preferredWriteFolder = try container.decodeIfPresent(
      String.self, forKey: .preferredWriteFolder)
    self.forceFFFFFFFForSendObject =
      try container.decodeIfPresent(Bool.self, forKey: .forceFFFFFFFForSendObject) ?? false
    self.emptyDatesInSendObject =
      try container.decodeIfPresent(Bool.self, forKey: .emptyDatesInSendObject) ?? false
    self.unknownSizeInSendObjectInfo =
      try container.decodeIfPresent(Bool.self, forKey: .unknownSizeInSendObjectInfo) ?? false
    self.skipGetObjectPropValue =
      try container.decodeIfPresent(Bool.self, forKey: .skipGetObjectPropValue) ?? false
    self.supportsGetObjectPropList =
      try container.decodeIfPresent(Bool.self, forKey: .supportsGetObjectPropList) ?? false
    self.supportsGetPartialObject =
      try container.decodeIfPresent(Bool.self, forKey: .supportsGetPartialObject) ?? false
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encodeIfPresent(resetOnOpen, forKey: .resetOnOpen)
    try container.encodeIfPresent(requiresKernelDetach, forKey: .requiresKernelDetach)
    try container.encodeIfPresent(needsLongerOpenTimeout, forKey: .needsLongerOpenTimeout)
    try container.encodeIfPresent(
      requiresSessionBeforeDeviceInfo, forKey: .requiresSessionBeforeDeviceInfo)
    try container.encodeIfPresent(
      transactionIdResetsOnSession, forKey: .transactionIdResetsOnSession)
    try container.encodeIfPresent(
      resetReopenOnOpenSessionIOError, forKey: .resetReopenOnOpenSessionIOError)
    try container.encodeIfPresent(supportsPartialRead64, forKey: .supportsPartialRead64)
    try container.encodeIfPresent(supportsPartialRead32, forKey: .supportsPartialRead32)
    try container.encodeIfPresent(supportsPartialWrite, forKey: .supportsPartialWrite)
    try container.encodeIfPresent(prefersPropListEnumeration, forKey: .prefersPropListEnumeration)
    try container.encodeIfPresent(needsShortReads, forKey: .needsShortReads)
    try container.encodeIfPresent(stallOnLargeReads, forKey: .stallOnLargeReads)
    try container.encodeIfPresent(disableEventPump, forKey: .disableEventPump)
    try container.encodeIfPresent(requireStabilization, forKey: .requireStabilization)
    try container.encodeIfPresent(skipPTPReset, forKey: .skipPTPReset)
    try container.encodeIfPresent(writeToSubfolderOnly, forKey: .writeToSubfolderOnly)
    try container.encodeIfPresent(preferredWriteFolder, forKey: .preferredWriteFolder)
    try container.encodeIfPresent(forceFFFFFFFForSendObject, forKey: .forceFFFFFFFForSendObject)
    try container.encodeIfPresent(emptyDatesInSendObject, forKey: .emptyDatesInSendObject)
    try container.encodeIfPresent(unknownSizeInSendObjectInfo, forKey: .unknownSizeInSendObjectInfo)
    try container.encodeIfPresent(skipGetObjectPropValue, forKey: .skipGetObjectPropValue)
    try container.encodeIfPresent(supportsGetObjectPropList, forKey: .supportsGetObjectPropList)
    try container.encodeIfPresent(supportsGetPartialObject, forKey: .supportsGetPartialObject)
  }
}
