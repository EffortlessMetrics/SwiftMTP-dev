// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation

/// Typed boolean/enum knobs replacing untyped `operations` maps.
/// Each flag controls a specific device behavior at a well-defined layer.
public struct QuirkFlags: Sendable, Codable, Equatable {

  // MARK: - Transport-level

  /// Issue `libusb_reset_device` after opening the handle.
  public var resetOnOpen: Bool = false

  /// Issue `libusb_reset_device` after closing the session.
  /// Required by Android (AOSP) and Sony NWZ Walkman devices to leave the
  /// device in a clean state. Maps to libmtp `DEVICE_FLAG_FORCE_RESET_ON_CLOSE`.
  public var forceResetOnClose: Bool = false

  /// Device does not send zero-length packets (ZLP) at USB transfer boundaries
  /// that are multiples of 64 bytes; instead it sends one extra byte.
  /// Without this workaround reads can hang waiting for a terminator that
  /// never arrives. Affects Samsung YP-series, iRiver, and many legacy players.
  /// Maps to libmtp `DEVICE_FLAG_NO_ZERO_READS`.
  public var noZeroReads: Bool = false

  /// Skip `libusb_release_interface` on close — device locks up if released.
  /// Affects SanDisk Sansa and some Creative devices.
  /// Maps to libmtp `DEVICE_FLAG_NO_RELEASE_INTERFACE`.
  public var noReleaseInterface: Bool = false

  /// Detach macOS kernel driver before claiming the interface.
  public var requiresKernelDetach: Bool = true

  /// Use longer handshake timeout for slow-to-respond devices.
  public var needsLongerOpenTimeout: Bool = false

  /// Use extended bulk transfer timeout (60s) for operational I/O.
  /// Matches libmtp's `DEVICE_FLAG_LONG_TIMEOUT` for devices that need
  /// extra time for large transfers or slow USB bus recovery.
  public var extendedBulkTimeout: Bool = false

  /// Skip `libusb_set_interface_alt_setting` after claim on macOS.
  /// Samsung devices reset their MTP state machine when this call is issued.
  /// libmtp guards this with `#ifndef __APPLE__`.
  public var skipAltSetting: Bool = false

  /// Skip the pre-claim `libusb_reset_device` + 300ms settle delay.
  /// Samsung devices have a ~3s session window; the reset eats into it.
  /// libmtp does not perform this reset.
  public var skipPreClaimReset: Bool = false

  // MARK: - Protocol-level

  /// Device requires an open session before GetDeviceInfo responds.
  public var requiresSessionBeforeDeviceInfo: Bool = false

  /// Device resets its transaction-ID counter when a new session opens.
  public var transactionIdResetsOnSession: Bool = false

  /// On first OpenSession timeout/I/O failure, perform a one-time
  /// reset+reopen recovery ladder before giving up.
  public var resetReopenOnOpenSessionIOError: Bool = false

  /// Tolerate broken PTP response headers where the code and transaction-ID
  /// fields contain junk bytes. Found in Creative ZEN and Aricent MTP stacks.
  /// Maps to libmtp `DEVICE_FLAG_IGNORE_HEADER_ERRORS`.
  public var ignoreHeaderErrors: Bool = false

  /// SendObjectPropList (0x9808) is broken — fall back to
  /// SendObjectInfo (0x100C) + SendObject (0x100D) for new objects.
  /// This is the #1 Android compatibility flag; affects all AOSP MTP devices.
  /// Maps to libmtp `DEVICE_FLAG_BROKEN_SEND_OBJECT_PROPLIST`.
  public var brokenSendObjectPropList: Bool = false

  /// SetObjectPropList (0x9806) is broken for metadata updates.
  /// Fall back to individual SetObjectPropValue (0x9804) calls.
  /// Affects Motorola RAZR2 and Android devices.
  /// Maps to libmtp `DEVICE_FLAG_BROKEN_SET_OBJECT_PROPLIST`.
  public var brokenSetObjectPropList: Bool = false

  /// Skip CloseSession on disconnect — 2016+ Canon EOS cameras enter an
  /// error state after CloseSession and refuse further PTP commands.
  /// Maps to libmtp `DEVICE_FLAG_DONT_CLOSE_SESSION`.
  public var skipCloseSession: Bool = false

  // MARK: - Transfer-level

  /// Device supports GetPartialObject64 (0x95C1).
  public var supportsPartialRead64: Bool = true

  /// Device supports GetPartialObject (0x101B).
  public var supportsPartialRead32: Bool = true

  /// Device supports SendPartialObject (0x95C2).
  public var supportsPartialWrite: Bool = true

  /// Prefer GetObjectPropList (batch) over GetObjectInfo (per-handle).
  public var prefersPropListEnumeration: Bool = true

  /// Prefer MTP property list data over GetObjectInfo results.
  /// Samsung Galaxy devices return malformed ObjectInfo with 64-bit fields
  /// packed into 32-bit slots. When set, always use property list values.
  /// Maps to libmtp `DEVICE_FLAG_PROPLIST_OVERRIDES_OI`.
  public var propListOverridesObjectInfo: Bool = false

  /// Samsung GetPartialObject hangs when the last USB packet in the response
  /// exactly matches 512-byte USB 2.0 packet size. Workaround: adjust
  /// read offset or size to avoid the boundary.
  /// Maps to libmtp `DEVICE_FLAG_SAMSUNG_OFFSET_BUG`.
  public var samsungPartialObjectBoundaryBug: Bool = false

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

  /// Always probe the USB OS Descriptor for proper MTP operation.
  /// Required by SanDisk Sansa v2 chipset (AMS AD3525) which needs the
  /// extra descriptor probe to initialize its MTP stack correctly.
  /// Maps to libmtp `DEVICE_FLAG_ALWAYS_PROBE_DESCRIPTOR`.
  public var alwaysProbeDescriptor: Bool = false

  /// Device sends ObjectDeleted (0x4003) events after delete operations.
  /// When set, the event pump expects and processes these events for cache
  /// invalidation. When false, caches are invalidated eagerly on delete.
  /// Maps to libmtp `DEVICE_FLAG_DELETE_SENDS_EVENT`.
  public var deleteSendsEvent: Bool = false

  // MARK: - Write-level

  /// Device supports Android edit extensions (BeginEditObject/EndEditObject/TruncateObject).
  /// When true, in-place file editing is possible without full re-upload.
  public var supportsAndroidEditExtensions: Bool = false

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

  /// Force format code 0x3000 (Undefined Object) as the primary format in SendObjectInfo.
  /// libmtp always uses Undefined format for generic files on Android. Eliminates the
  /// retry round-trip for devices that reject specific format codes (e.g., OnePlus 3T).
  /// Maps to libmtp behavior under `DEVICE_FLAG_BROKEN_SEND_OBJECT_PROPLIST`.
  public var forceUndefinedFormatOnWrite: Bool = false

  /// Force ObjectCompressedSize to 0xFFFFFFFF in SendObjectInfo.
  /// Disabled by default; some devices reject unknown-size semantics.
  public var unknownSizeInSendObjectInfo: Bool = false

  // MARK: - Filename-level

  /// Device only accepts 7-bit ASCII filenames (characters ≤ 0x7F).
  /// Violates PTP spec which mandates Unicode. Found on Philips Shoqbox and
  /// some legacy media players. When set, filenames are sanitized to ASCII
  /// before SendObjectInfo. Maps to libmtp `DEVICE_FLAG_ONLY_7BIT_FILENAMES`.
  public var only7BitFilenames: Bool = false

  /// Device requires globally unique filenames — no two files on the device
  /// may share the same name, even across different folders. When set, the
  /// write path appends a short hash suffix when a name collision is detected.
  /// Affects Sony NWZ Walkman and some Samsung YP-series players.
  /// Maps to libmtp `DEVICE_FLAG_UNIQUE_FILENAMES`.
  public var requireUniqueFilenames: Bool = false

  // MARK: - Property-level

  /// Device claims DateModified is read/write but silently fails to update it.
  /// The date can only be set correctly on the first SendObjectInfo; subsequent
  /// SetObjectPropValue calls for DateModified are ignored. When set, metadata
  /// update paths skip DateModified writes to avoid silent failures.
  /// Affects SanDisk Sansa E250 and similar firmware. Maps to libmtp
  /// `DEVICE_FLAG_CANNOT_HANDLE_DATEMODIFIED`.
  public var cannotHandleDateModified: Bool = false

  /// GetDevicePropValue for battery level (0x5001) is broken and returns
  /// errors or hangs. When set, battery level queries are skipped.
  /// Maps to libmtp `DEVICE_FLAG_BROKEN_BATTERY_LEVEL`.
  public var brokenBatteryLevel: Bool = false

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

  // MARK: - Device-class hints

  /// Device is a PTP camera (Still-Image-Capture class).
  /// Used to select camera-specific defaults and UI presentation.
  public var cameraClass: Bool = false

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
    case forceResetOnClose
    case noZeroReads
    case noReleaseInterface
    case requiresKernelDetach
    case needsLongerOpenTimeout
    case extendedBulkTimeout
    case skipAltSetting
    case skipPreClaimReset
    case requiresSessionBeforeDeviceInfo
    case transactionIdResetsOnSession
    case resetReopenOnOpenSessionIOError
    case ignoreHeaderErrors
    case brokenSendObjectPropList
    case brokenSetObjectPropList
    case skipCloseSession
    case supportsPartialRead64
    case supportsPartialRead32
    case supportsPartialWrite
    case prefersPropListEnumeration
    case propListOverridesObjectInfo
    case samsungPartialObjectBoundaryBug
    case needsShortReads
    case stallOnLargeReads
    case disableEventPump
    case requireStabilization
    case skipPTPReset
    case alwaysProbeDescriptor
    case deleteSendsEvent
    case supportsAndroidEditExtensions
    case writeToSubfolderOnly
    case preferredWriteFolder
    case forceFFFFFFFForSendObject
    case emptyDatesInSendObject
    case forceUndefinedFormatOnWrite
    case unknownSizeInSendObjectInfo
    case skipGetObjectPropValue
    case only7BitFilenames
    case requireUniqueFilenames
    case cannotHandleDateModified
    case brokenBatteryLevel
    case supportsGetObjectPropList
    case supportsGetPartialObject
    case cameraClass
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.resetOnOpen = try container.decodeIfPresent(Bool.self, forKey: .resetOnOpen) ?? false
    self.forceResetOnClose =
      try container.decodeIfPresent(Bool.self, forKey: .forceResetOnClose) ?? false
    self.noZeroReads =
      try container.decodeIfPresent(Bool.self, forKey: .noZeroReads) ?? false
    self.noReleaseInterface =
      try container.decodeIfPresent(Bool.self, forKey: .noReleaseInterface) ?? false
    self.requiresKernelDetach =
      try container.decodeIfPresent(Bool.self, forKey: .requiresKernelDetach) ?? true
    self.needsLongerOpenTimeout =
      try container.decodeIfPresent(Bool.self, forKey: .needsLongerOpenTimeout) ?? false
    self.extendedBulkTimeout =
      try container.decodeIfPresent(Bool.self, forKey: .extendedBulkTimeout) ?? false
    self.skipAltSetting =
      try container.decodeIfPresent(Bool.self, forKey: .skipAltSetting) ?? false
    self.skipPreClaimReset =
      try container.decodeIfPresent(Bool.self, forKey: .skipPreClaimReset) ?? false
    self.requiresSessionBeforeDeviceInfo =
      try container.decodeIfPresent(Bool.self, forKey: .requiresSessionBeforeDeviceInfo) ?? false
    self.transactionIdResetsOnSession =
      try container.decodeIfPresent(Bool.self, forKey: .transactionIdResetsOnSession) ?? false
    self.resetReopenOnOpenSessionIOError =
      try container.decodeIfPresent(Bool.self, forKey: .resetReopenOnOpenSessionIOError) ?? false
    self.ignoreHeaderErrors =
      try container.decodeIfPresent(Bool.self, forKey: .ignoreHeaderErrors) ?? false
    self.brokenSendObjectPropList =
      try container.decodeIfPresent(Bool.self, forKey: .brokenSendObjectPropList) ?? false
    self.brokenSetObjectPropList =
      try container.decodeIfPresent(Bool.self, forKey: .brokenSetObjectPropList) ?? false
    self.skipCloseSession =
      try container.decodeIfPresent(Bool.self, forKey: .skipCloseSession) ?? false
    self.supportsPartialRead64 =
      try container.decodeIfPresent(Bool.self, forKey: .supportsPartialRead64) ?? true
    self.supportsPartialRead32 =
      try container.decodeIfPresent(Bool.self, forKey: .supportsPartialRead32) ?? true
    self.supportsPartialWrite =
      try container.decodeIfPresent(Bool.self, forKey: .supportsPartialWrite) ?? true
    self.prefersPropListEnumeration =
      try container.decodeIfPresent(Bool.self, forKey: .prefersPropListEnumeration) ?? true
    self.propListOverridesObjectInfo =
      try container.decodeIfPresent(Bool.self, forKey: .propListOverridesObjectInfo) ?? false
    self.samsungPartialObjectBoundaryBug =
      try container.decodeIfPresent(Bool.self, forKey: .samsungPartialObjectBoundaryBug) ?? false
    self.needsShortReads =
      try container.decodeIfPresent(Bool.self, forKey: .needsShortReads) ?? false
    self.stallOnLargeReads =
      try container.decodeIfPresent(Bool.self, forKey: .stallOnLargeReads) ?? false
    self.disableEventPump =
      try container.decodeIfPresent(Bool.self, forKey: .disableEventPump) ?? false
    self.requireStabilization =
      try container.decodeIfPresent(Bool.self, forKey: .requireStabilization) ?? false
    self.skipPTPReset = try container.decodeIfPresent(Bool.self, forKey: .skipPTPReset) ?? false
    self.alwaysProbeDescriptor =
      try container.decodeIfPresent(Bool.self, forKey: .alwaysProbeDescriptor) ?? false
    self.deleteSendsEvent =
      try container.decodeIfPresent(Bool.self, forKey: .deleteSendsEvent) ?? false
    self.supportsAndroidEditExtensions =
      try container.decodeIfPresent(Bool.self, forKey: .supportsAndroidEditExtensions) ?? false
    self.writeToSubfolderOnly =
      try container.decodeIfPresent(Bool.self, forKey: .writeToSubfolderOnly) ?? false
    self.preferredWriteFolder = try container.decodeIfPresent(
      String.self, forKey: .preferredWriteFolder)
    self.forceFFFFFFFForSendObject =
      try container.decodeIfPresent(Bool.self, forKey: .forceFFFFFFFForSendObject) ?? false
    self.emptyDatesInSendObject =
      try container.decodeIfPresent(Bool.self, forKey: .emptyDatesInSendObject) ?? false
    self.forceUndefinedFormatOnWrite =
      try container.decodeIfPresent(Bool.self, forKey: .forceUndefinedFormatOnWrite) ?? false
    self.unknownSizeInSendObjectInfo =
      try container.decodeIfPresent(Bool.self, forKey: .unknownSizeInSendObjectInfo) ?? false
    self.skipGetObjectPropValue =
      try container.decodeIfPresent(Bool.self, forKey: .skipGetObjectPropValue) ?? false
    self.only7BitFilenames =
      try container.decodeIfPresent(Bool.self, forKey: .only7BitFilenames) ?? false
    self.requireUniqueFilenames =
      try container.decodeIfPresent(Bool.self, forKey: .requireUniqueFilenames) ?? false
    self.cannotHandleDateModified =
      try container.decodeIfPresent(Bool.self, forKey: .cannotHandleDateModified) ?? false
    self.brokenBatteryLevel =
      try container.decodeIfPresent(Bool.self, forKey: .brokenBatteryLevel) ?? false
    self.supportsGetObjectPropList =
      try container.decodeIfPresent(Bool.self, forKey: .supportsGetObjectPropList) ?? false
    self.supportsGetPartialObject =
      try container.decodeIfPresent(Bool.self, forKey: .supportsGetPartialObject) ?? false
    self.cameraClass =
      try container.decodeIfPresent(Bool.self, forKey: .cameraClass) ?? false
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encodeIfPresent(resetOnOpen, forKey: .resetOnOpen)
    try container.encodeIfPresent(forceResetOnClose, forKey: .forceResetOnClose)
    try container.encodeIfPresent(noZeroReads, forKey: .noZeroReads)
    try container.encodeIfPresent(noReleaseInterface, forKey: .noReleaseInterface)
    try container.encodeIfPresent(requiresKernelDetach, forKey: .requiresKernelDetach)
    try container.encodeIfPresent(needsLongerOpenTimeout, forKey: .needsLongerOpenTimeout)
    try container.encodeIfPresent(extendedBulkTimeout, forKey: .extendedBulkTimeout)
    try container.encodeIfPresent(skipAltSetting, forKey: .skipAltSetting)
    try container.encodeIfPresent(skipPreClaimReset, forKey: .skipPreClaimReset)
    try container.encodeIfPresent(
      requiresSessionBeforeDeviceInfo, forKey: .requiresSessionBeforeDeviceInfo)
    try container.encodeIfPresent(
      transactionIdResetsOnSession, forKey: .transactionIdResetsOnSession)
    try container.encodeIfPresent(
      resetReopenOnOpenSessionIOError, forKey: .resetReopenOnOpenSessionIOError)
    try container.encodeIfPresent(ignoreHeaderErrors, forKey: .ignoreHeaderErrors)
    try container.encodeIfPresent(brokenSendObjectPropList, forKey: .brokenSendObjectPropList)
    try container.encodeIfPresent(brokenSetObjectPropList, forKey: .brokenSetObjectPropList)
    try container.encodeIfPresent(skipCloseSession, forKey: .skipCloseSession)
    try container.encodeIfPresent(supportsPartialRead64, forKey: .supportsPartialRead64)
    try container.encodeIfPresent(supportsPartialRead32, forKey: .supportsPartialRead32)
    try container.encodeIfPresent(supportsPartialWrite, forKey: .supportsPartialWrite)
    try container.encodeIfPresent(prefersPropListEnumeration, forKey: .prefersPropListEnumeration)
    try container.encodeIfPresent(propListOverridesObjectInfo, forKey: .propListOverridesObjectInfo)
    try container.encodeIfPresent(
      samsungPartialObjectBoundaryBug, forKey: .samsungPartialObjectBoundaryBug)
    try container.encodeIfPresent(needsShortReads, forKey: .needsShortReads)
    try container.encodeIfPresent(stallOnLargeReads, forKey: .stallOnLargeReads)
    try container.encodeIfPresent(disableEventPump, forKey: .disableEventPump)
    try container.encodeIfPresent(requireStabilization, forKey: .requireStabilization)
    try container.encodeIfPresent(skipPTPReset, forKey: .skipPTPReset)
    try container.encodeIfPresent(alwaysProbeDescriptor, forKey: .alwaysProbeDescriptor)
    try container.encodeIfPresent(deleteSendsEvent, forKey: .deleteSendsEvent)
    try container.encodeIfPresent(
      supportsAndroidEditExtensions, forKey: .supportsAndroidEditExtensions)
    try container.encodeIfPresent(writeToSubfolderOnly, forKey: .writeToSubfolderOnly)
    try container.encodeIfPresent(preferredWriteFolder, forKey: .preferredWriteFolder)
    try container.encodeIfPresent(forceFFFFFFFForSendObject, forKey: .forceFFFFFFFForSendObject)
    try container.encodeIfPresent(emptyDatesInSendObject, forKey: .emptyDatesInSendObject)
    try container.encodeIfPresent(
      forceUndefinedFormatOnWrite, forKey: .forceUndefinedFormatOnWrite)
    try container.encodeIfPresent(unknownSizeInSendObjectInfo, forKey: .unknownSizeInSendObjectInfo)
    try container.encodeIfPresent(skipGetObjectPropValue, forKey: .skipGetObjectPropValue)
    try container.encodeIfPresent(only7BitFilenames, forKey: .only7BitFilenames)
    try container.encodeIfPresent(requireUniqueFilenames, forKey: .requireUniqueFilenames)
    try container.encodeIfPresent(cannotHandleDateModified, forKey: .cannotHandleDateModified)
    try container.encodeIfPresent(brokenBatteryLevel, forKey: .brokenBatteryLevel)
    try container.encodeIfPresent(supportsGetObjectPropList, forKey: .supportsGetObjectPropList)
    try container.encodeIfPresent(supportsGetPartialObject, forKey: .supportsGetPartialObject)
    try container.encodeIfPresent(cameraClass, forKey: .cameraClass)
  }
}
