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
    case .protocolError(let code, _):
      return protocolRecoverySuggestion(for: code)
    case .transport(let transportError):
      return transportError.recoverySuggestion
    }
  }

  private func protocolMessage(for code: UInt16, message: String?) -> String {
    let codeHex = String(format: "0x%04X", code)
    let codeName = message ?? Self.protocolCodeName(for: code)
    switch code {
    case 0x201D:
      return "Protocol error \(codeName) (\(codeHex)): write request rejected by device."
    case 0x2002:
      return "\(codeName) (\(codeHex)): the device reported an unspecified failure."
    case 0x2003:
      return "\(codeName) (\(codeHex)): no MTP session is currently open."
    case 0x2005:
      return "\(codeName) (\(codeHex)): the device does not support this operation."
    case 0x2007:
      return "\(codeName) (\(codeHex)): the transfer did not complete."
    case 0x2008:
      return "\(codeName) (\(codeHex)): the storage ID is not recognized by the device."
    case 0x2009:
      return "\(codeName) (\(codeHex)): the object handle does not refer to a valid object."
    case 0x200C:
      return "\(codeName) (\(codeHex)): the device storage is full."
    case 0x200D:
      return "\(codeName) (\(codeHex)): the object is write-protected."
    case 0x200E:
      return "\(codeName) (\(codeHex)): the device storage is read-only."
    case 0x200F:
      return "\(codeName) (\(codeHex)): access to the object was denied by the device."
    case 0x2019:
      return "\(codeName) (\(codeHex)): the device is busy processing another request."
    case 0x201A:
      return "\(codeName) (\(codeHex)): the specified parent object is invalid."
    case 0x201E:
      return "\(codeName) (\(codeHex)): an MTP session is already open on this device."
    case 0x201F:
      return "\(codeName) (\(codeHex)): the transaction was cancelled."
    default:
      return "\(codeName) (\(codeHex))"
    }
  }

  private static func protocolCodeName(for code: UInt16) -> String {
    switch code {
    case 0x2001: return "OK"
    case 0x2002: return "GeneralError"
    case 0x2003: return "SessionNotOpen"
    case 0x2004: return "InvalidTransactionID"
    case 0x2005: return "OperationNotSupported"
    case 0x2006: return "ParameterNotSupported"
    case 0x2007: return "IncompleteTransfer"
    case 0x2008: return "InvalidStorageID"
    case 0x2009: return "InvalidObjectHandle"
    case 0x200A: return "DevicePropNotSupported"
    case 0x200B: return "InvalidObjectFormatCode"
    case 0x200C: return "StoreFull"
    case 0x200D: return "ObjectWriteProtected"
    case 0x200E: return "StoreReadOnly"
    case 0x200F: return "AccessDenied"
    case 0x2019: return "DeviceBusy"
    case 0x201A: return "InvalidParentObject"
    case 0x201D: return "InvalidParameter"
    case 0x201E: return "SessionAlreadyOpen"
    case 0x201F: return "TransactionCancelled"
    default: return "UnknownResponse"
    }
  }

  private func protocolFailureReason(for code: UInt16) -> String {
    switch code {
    case 0x201D:
      return "This device rejected invalid write parameters."
    case 0x2003:
      return "The MTP session was closed or never opened."
    case 0x2008:
      return "The storage ID sent to the device does not match any available storage."
    case 0x2009:
      return "The object handle was deleted or invalidated on the device."
    case 0x2019:
      return "The device is processing a prior request and cannot accept a new one."
    case 0x201E:
      return "A session is already open; MTP allows only one session per connection."
    default:
      return "The device response indicates a protocol error."
    }
  }

  private func protocolRecoverySuggestion(for code: UInt16) -> String {
    switch code {
    case 0x201D:
      return
        "Write to a writable folder (for example Download, DCIM, or a nested folder) instead of root."
    case 0x2003:
      return "Re-open the MTP session (disconnect and reconnect if needed), then retry."
    case 0x2005:
      return "This operation is not supported by the device firmware. Try an alternative approach."
    case 0x2007:
      return "Retry the transfer. If it fails repeatedly, try a smaller file or check the cable."
    case 0x2008:
      return "Refresh the storage list and retry with a valid storage ID."
    case 0x2009:
      return "Refresh the object listing and retry with a valid object handle."
    case 0x200C:
      return "Free space on the device, then retry."
    case 0x200E:
      return "Check the device for a read-only lock (e.g. SD card switch) and remount as writable."
    case 0x2019:
      return "Wait a moment for the device to finish its current task, then retry."
    case 0x201E:
      return "Close the existing session first, or disconnect and reconnect the device."
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
