// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation

/// Errors that can occur during MTP protocol operations.
///
/// These errors cover device-level issues (disconnection, permissions),
/// protocol-level failures (invalid parameters, unsupported operations),
/// and storage constraints (full, read-only).
public enum MTPError: Error, Sendable, Equatable {
  case deviceDisconnected, permissionDenied
  case notSupported(String)
  case transport(TransportError)
  case protocolError(code: UInt16, message: String?)
  case objectNotFound, objectWriteProtected, storageFull, readOnly, timeout, busy
  /// A protocol transaction is already in progress on this device.
  case sessionBusy
  case preconditionFailed(String)
  /// The remote object size after a write does not match the expected size.
  case verificationFailed(expected: UInt64, actual: UInt64)
  /// The remote file changed since the partial download began (size or modification time differs).
  case etagMismatch
}

public extension MTPError {
  /// Back-compat factory used by CLI/tools. Maps to an existing error case.
  static func internalError(_ message: String) -> MTPError {
    return .notSupported(message)
  }

  /// True when the device reports SessionAlreadyOpen (0x201E).
  var isSessionAlreadyOpen: Bool {
    if case .protocolError(let code, _) = self, code == 0x201E { return true }
    return false
  }
}

extension MTPError: LocalizedError {
  public var errorDescription: String? {
    switch self {
    case .deviceDisconnected:
      return "The device disconnected during the operation."
    case .permissionDenied:
      return "Access to the USB device was denied."
    case .notSupported(let message):
      return "Not supported: \(message)"
    case .transport(let transportError):
      return transportError.errorDescription
    case .protocolError(let code, let message):
      return protocolMessage(for: code, message: message)
    case .objectNotFound:
      return "The requested object was not found."
    case .objectWriteProtected:
      return "The target object is write-protected."
    case .storageFull:
      return "The destination storage is full."
    case .readOnly:
      return "The storage is read-only."
    case .timeout:
      return "The operation timed out while waiting for the device."
    case .busy:
      return "The device is busy. Retry shortly."
    case .sessionBusy:
      return "A protocol transaction is already in progress on this device."
    case .preconditionFailed(let reason):
      return "Precondition failed: \(reason)"
    case .verificationFailed(let expected, let actual):
      return
        "Write verification failed: remote size \(actual) does not match expected \(expected)."
    case .etagMismatch:
      return "The remote file changed since the partial download began."
    }
  }

  public var failureReason: String? {
    switch self {
    case .deviceDisconnected:
      return "The USB cable may have been unplugged or the device powered off mid-transfer."
    case .permissionDenied:
      return "macOS requires explicit permission for USB device access."
    case .notSupported:
      return "The device or firmware does not support the requested MTP operation."
    case .objectNotFound:
      return "The object handle may have been invalidated by a device-side change."
    case .objectWriteProtected:
      return "The file or folder is marked as write-protected on the device."
    case .storageFull:
      return "The device storage has no remaining free space for this transfer."
    case .readOnly:
      return "The storage volume is mounted as read-only by the device."
    case .timeout:
      return "The device did not respond within the configured timeout window."
    case .busy:
      return "The device is processing another request or is in a locked state."
    case .sessionBusy:
      return "Only one MTP transaction can be in-flight per session at a time."
    case .preconditionFailed:
      return "A required precondition was not met before the operation could proceed."
    case .verificationFailed:
      return "The file may have been truncated or corrupted during transfer."
    case .etagMismatch:
      return "The object size or modification time changed on the device since the partial was saved."
    case .protocolError(let code, _):
      return protocolFailureReason(for: code)
    case .transport(let transportError):
      return transportError.failureReason
    }
  }

  public var recoverySuggestion: String? {
    switch self {
    case .deviceDisconnected:
      return "Reconnect the cable, unlock the device, and retry the operation."
    case .permissionDenied:
      return
        "Open System Settings > Privacy & Security and grant USB access. You may also need to re-approve the device trust prompt."
    case .notSupported:
      return "Check that the device firmware is up to date, or try a different operation."
    case .objectNotFound:
      return "Refresh the object listing and verify the file still exists on the device."
    case .objectWriteProtected:
      return "Remove write-protection on the device, or choose a different target file."
    case .storageFull:
      return "Free space on the device by deleting unneeded files, then re-attempt the transfer."
    case .readOnly:
      return
        "Check whether the storage is locked (e.g. SD card write-protect switch) and remount as writable."
    case .timeout:
      return
        "Ensure the device is unlocked and the screen is on, then retry. For large files, increase `SWIFTMTP_IO_TIMEOUT_MS`."
    case .busy:
      return
        "Unlock the device screen and dismiss any prompts, then wait a moment and retry."
    case .sessionBusy:
      return "Wait for the current operation to complete, then retry."
    case .preconditionFailed:
      return "Verify that the device session is open and storage IDs are valid."
    case .verificationFailed:
      return "Re-send the file and verify the transfer completes without interruption."
    case .etagMismatch:
      return "Discard the partial download and restart the transfer from the beginning."
    case .protocolError(let code, _):
      return protocolRecoverySuggestion(for: code)
    case .transport(let transportError):
      return transportError.recoverySuggestion
    }
  }

  private func protocolMessage(for code: UInt16, message: String?) -> String {
    let codeHex = String(format: "0x%04X", code)
    let codeName = message ?? Self.protocolCodeName(for: code)
    // Use the centralized user message for all known codes.
    let userMsg = PTPResponseCode.userMessage(for: code)
    return "\(codeName) (\(codeHex)): \(userMsg)"
  }

  private static func protocolCodeName(for code: UInt16) -> String {
    PTPResponseCode.name(for: code) ?? "UnknownResponse"
  }

  private func protocolFailureReason(for code: UInt16) -> String {
    switch code {
    case 0x2002:
      return "The device encountered an internal error it could not classify."
    case 0x2003:
      return "The MTP session was closed or never opened."
    case 0x2004:
      return "The transaction ID is out of sequence or does not match the device expectation."
    case 0x2005:
      return "The device firmware does not implement this MTP operation."
    case 0x2006:
      return "One or more command parameters are not recognized by the device."
    case 0x2007:
      return "The data phase was interrupted before all bytes were transferred."
    case 0x2008:
      return "The storage ID sent to the device does not match any available storage."
    case 0x2009:
      return "The object handle was deleted or invalidated on the device."
    case 0x200A:
      return "The device does not recognize or support the requested device property."
    case 0x200B:
      return "The object format code does not match any format the device accepts."
    case 0x200C:
      return "The device storage has no remaining space for this transfer."
    case 0x200D:
      return "The object is marked write-protected by the device firmware."
    case 0x200E:
      return "The storage volume is mounted read-only (e.g. SD card write-protect switch)."
    case 0x200F:
      return "The device denied access, possibly due to DRM or permission restrictions."
    case 0x2010:
      return "The object does not have an embedded thumbnail."
    case 0x2011:
      return "The device hardware self-test reported a failure."
    case 0x2012:
      return "Some objects could not be deleted; a subset was removed."
    case 0x2013:
      return "The storage may have been ejected, unmounted, or is otherwise unavailable."
    case 0x2014:
      return "The device does not support filtering objects by format code."
    case 0x2015:
      return "SendObjectInfo must be called before SendObject to describe the file."
    case 0x2016:
      return "The code format value is not recognized by the device."
    case 0x2017:
      return "The vendor extension code is not recognized by the device."
    case 0x2018:
      return "The capture was already stopped before the termination request."
    case 0x2019:
      return "The device is processing a prior request and cannot accept a new one."
    case 0x201A:
      return "The parent object handle does not refer to a valid folder."
    case 0x201B:
      return "The format of the device property value does not match the expected type."
    case 0x201C:
      return "The device property value is outside the allowed range."
    case 0x201D:
      return "This device rejected invalid write parameters."
    case 0x201E:
      return "A session is already open; MTP allows only one session per connection."
    case 0x201F:
      return "The initiator or responder cancelled the in-progress transaction."
    case 0x2020:
      return "The device does not support the specified copy/move destination."
    case 0xA801:
      return "The object property code is not recognized by the device."
    case 0xA802:
      return "The object property format does not match the expected type."
    case 0xA803:
      return "The object property value is outside the allowed range."
    case 0xA804:
      return "The referenced object does not exist or the reference is broken."
    case 0xA805:
      return "The device does not support group-based operations."
    case 0xA806:
      return "The property dataset sent to the device is malformed or incomplete."
    case 0xA807:
      return "The device does not support filtering by object property group."
    case 0xA808:
      return "The device does not support filtering by hierarchy depth."
    case 0xA809:
      return "The file exceeds the maximum object size the device can store."
    case 0xA80A:
      return "The specified object property is not implemented by the device."
    default:
      return "The device response indicates a protocol error."
    }
  }

  private func protocolRecoverySuggestion(for code: UInt16) -> String {
    switch code {
    case 0x2002:
      return "Retry the operation. If it persists, reconnect the device."
    case 0x2003:
      return "Re-open the MTP session (disconnect and reconnect if needed), then retry."
    case 0x2004:
      return "Reconnect the device to reset the transaction counter."
    case 0x2005:
      return "This operation is not supported by the device firmware. Try an alternative approach."
    case 0x2006:
      return "Check that all parameters are valid for this device and firmware version."
    case 0x2007:
      return "Retry the transfer. If it fails repeatedly, try a smaller file or check the cable."
    case 0x2008:
      return "Refresh the storage list and retry with a valid storage ID."
    case 0x2009:
      return "Refresh the object listing and retry with a valid object handle."
    case 0x200A:
      return "Use a different device property, or check the device's supported properties list."
    case 0x200B:
      return "Verify the file format is supported by the device."
    case 0x200C:
      return "Free space on the device, then retry."
    case 0x200D:
      return "Remove write-protection on the device, or choose a different target file."
    case 0x200E:
      return "Check the device for a read-only lock (e.g. SD card switch) and remount as writable."
    case 0x200F:
      return "Check device permissions and DRM restrictions."
    case 0x2010:
      return "Thumbnails are not available for all objects. Skip thumbnail requests for this object."
    case 0x2011:
      return "The device may need servicing. Check the device manufacturer's support resources."
    case 0x2012:
      return "Retry deleting the remaining objects individually."
    case 0x2013:
      return "Check that the storage media is inserted and the device is unlocked, then retry."
    case 0x2014, 0xA807, 0xA808:
      return "Remove the unsupported filter and retry the operation."
    case 0x2015:
      return "Send ObjectInfo (SendObjectInfo) before attempting to send the object data."
    case 0x2016:
      return "Verify the code format matches the MTP specification."
    case 0x2017:
      return "Use only standard MTP codes unless the device's vendor extension is confirmed."
    case 0x2018:
      return "The capture is already stopped. No further action is needed."
    case 0x2019:
      return "Wait a moment for the device to finish its current task, then retry."
    case 0x201A:
      return "Verify the parent folder exists and use a valid parent object handle."
    case 0x201B, 0xA802:
      return "Check the property type and send the value in the correct format."
    case 0x201C, 0xA803:
      return "Check the allowed range for this property and send a valid value."
    case 0x201D:
      return
        "Write to a writable folder (for example Download, DCIM, or a nested folder) instead of root."
    case 0x201E:
      return "Close the existing session first, or disconnect and reconnect the device."
    case 0x201F:
      return "Retry the operation if the cancellation was unintentional."
    case 0x2020:
      return "Choose a different destination that the device supports."
    case 0xA801, 0xA80A:
      return "Use only object property codes supported by the device."
    case 0xA804:
      return "Refresh the object listing and use a valid object reference."
    case 0xA805:
      return "Perform operations on individual objects instead of groups."
    case 0xA806:
      return "Verify the property dataset structure matches the MTP specification."
    case 0xA809:
      return "Reduce the file size or split the file into smaller parts."
    default:
      return "Retry the operation. If the error persists, reconnect the device."
    }
  }
}

/// Phase of a USB bulk transfer where a timeout or error occurred.
public enum TransportPhase: Sendable, Equatable {
  case bulkOut, bulkIn, responseWait

  public var description: String {
    switch self {
    case .bulkOut: return "bulk-out"
    case .bulkIn: return "bulk-in"
    case .responseWait: return "response-wait"
    }
  }
}

/// Low-level USB transport errors that occur during device communication.
public enum TransportError: Error, Sendable, Equatable {
  case noDevice, timeout, busy, accessDenied, stall
  case io(String)
  case timeoutInPhase(TransportPhase)
}

extension TransportError: LocalizedError {
  public var errorDescription: String? {
    switch self {
    case .noDevice:
      return
        "No MTP-capable USB device found. Ensure the phone is in File Transfer (MTP) mode and still connected."
    case .timeout:
      return "The USB transfer timed out."
    case .busy:
      return "USB access is temporarily busy."
    case .accessDenied:
      return "The USB device is currently unavailable due to access/claim restrictions."
    case .stall:
      return "A USB endpoint stalled; the transfer was aborted."
    case .timeoutInPhase(let phase):
      return "The USB transfer timed out during the \(phase.description) phase."
    case .io(let message):
      return message
    }
  }

  public var failureReason: String? {
    switch self {
    case .noDevice:
      return "No matching USB interface was claimed for MTP operations."
    case .accessDenied:
      return "Another process may own the interface (Android File Transfer, adb, browsers)."
    case .timeout:
      return "The device did not complete the USB request on time."
    case .busy:
      return "The USB bus or host controller is contended by another transfer or process."
    case .stall:
      return
        "The device endpoint halted, typically due to an unsupported command or protocol mismatch."
    case .timeoutInPhase(let phase):
      return "The device stopped responding during the \(phase.description) phase of the transfer."
    case .io(let message):
      return "A low-level USB I/O error occurred: \(message)"
    }
  }

  public var recoverySuggestion: String? {
    switch self {
    case .noDevice:
      return "Unplug and replug the device, confirm screen unlocked and trust prompt accepted."
    case .accessDenied:
      return
        "Close competing USB tools (Android File Transfer, adb, Samsung Smart Switch), then retry."
    case .timeout:
      return
        "Retry after increasing timeout values (`SWIFTMTP_IO_TIMEOUT_MS`). Ensure the device screen is on."
    case .busy:
      return
        "Wait a moment for the bus to become available, then retry. Close other USB-intensive applications."
    case .stall:
      return
        "Disconnect and reconnect the device. If the issue persists, try a different USB port or cable."
    case .timeoutInPhase:
      return
        "Check the cable connection and ensure the device is unlocked. Retry with `SWIFTMTP_IO_TIMEOUT_MS` increased."
    case .io:
      return
        "Try a different USB port or cable. If the error persists, reconnect the device and retry."
    }
  }
}
