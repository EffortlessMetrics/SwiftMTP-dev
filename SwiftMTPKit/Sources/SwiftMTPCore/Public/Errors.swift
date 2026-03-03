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
    case .protocolError(let code, _):
      if code == 0x201D {
        return "This device rejected invalid write parameters."
      }
      if code == 0x201E {
        return "The device reports a session is already open (SessionAlreadyOpen 0x201E)."
      }
      return "The transport response indicates a protocol error."
    case .transport(let transportError):
      return transportError.failureReason
    case .deviceDisconnected:
      return "The USB connection to the device was lost during the operation."
    case .permissionDenied:
      return "The operating system denied access to the USB device."
    case .timeout:
      return "The device did not respond within the configured timeout period."
    case .busy:
      return "The device is processing another request and cannot accept new commands."
    case .sessionBusy:
      return "A prior MTP transaction has not yet completed on this session."
    case .storageFull:
      return "The device's storage has no remaining free space for the requested write."
    case .verificationFailed(let expected, let actual):
      return
        "After writing, the remote object is \(actual) bytes but \(expected) bytes were expected."
    case .notSupported, .objectNotFound, .objectWriteProtected,
      .readOnly, .preconditionFailed:
      return nil
    }
  }

  public var recoverySuggestion: String? {
    switch self {
    case .deviceDisconnected:
      return "Reconnect the device and retry the operation."
    case .permissionDenied:
      return
        "Check System Settings > Privacy & Security > USB, grant access, then retry."
    case .notSupported:
      return "Check the device's supported MTP operations via `swiftmtp probe`."
    case .transport(let transportError):
      return transportError.recoverySuggestion
    case .protocolError(let code, _):
      if code == 0x201D {
        return
          "Write to a writable folder (for example Download, DCIM, or a nested folder) instead of root."
      }
      if code == 0x201E {
        return "Close the existing session before opening a new one, or reuse the current session."
      }
      return "Retry with corrected request details."
    case .objectNotFound:
      return "Verify the object handle is valid; the file may have been deleted on the device."
    case .objectWriteProtected:
      return "Choose a different file or change its permissions on the device."
    case .storageFull:
      return "Free space on the device or choose a different storage."
    case .readOnly:
      return "Choose a writable storage or check the device's USB transfer mode."
    case .timeout:
      return
        "Increase timeout values (`SWIFTMTP_IO_TIMEOUT_MS`) or retry when the device is less busy."
    case .busy:
      return "Wait a moment and retry; another operation may be in progress."
    case .sessionBusy:
      return "Wait for the current transaction to complete before starting a new one."
    case .preconditionFailed:
      return nil
    case .verificationFailed:
      return "Retry the transfer; if the problem persists the device may have storage issues."
    }
  }

  private func protocolMessage(for code: UInt16, message: String?) -> String {
    if code == 0x201D {
      let codeName = message ?? "InvalidParameter (0x201D)"
      return "Protocol error \(codeName): write request rejected by device."
    }
    let codeHex = String(format: "0x%04x", code)
    if let message {
      return "\(message) (\(codeHex))"
    }
    return "Protocol error (\(codeHex))"
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
      return "The USB bus or host controller reported contention on the device endpoint."
    case .stall:
      return
        "The USB endpoint halted, indicating the device rejected the transfer or encountered an internal error."
    case .timeoutInPhase(let phase):
      return
        "The device did not respond during the \(phase.description) phase of the USB transfer."
    case .io(let message):
      return "A low-level USB I/O error occurred: \(message)"
    }
  }

  public var recoverySuggestion: String? {
    switch self {
    case .noDevice:
      return "Unplug and replug the device, confirm screen unlocked and trust prompt accepted."
    case .accessDenied:
      return "Close competing USB tools, then retry."
    case .timeout:
      return
        "Retry after increasing timeout values (`SWIFTMTP_MAX_CHUNK_BYTES`, `SWIFTMTP_IO_TIMEOUT_MS`)."
    case .busy:
      return "Retry briefly if bus or host contention is expected."
    case .stall:
      return "Disconnect and reconnect the device, then retry."
    case .timeoutInPhase:
      return
        "Retry after increasing timeout values (`SWIFTMTP_MAX_CHUNK_BYTES`, `SWIFTMTP_IO_TIMEOUT_MS`)."
    case .io:
      return nil
    }
  }
}
