// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation

public enum MTPError: Error, Sendable, Equatable {
  case deviceDisconnected, permissionDenied
  case notSupported(String)
  case transport(TransportError)
  case protocolError(code: UInt16, message: String?)
  case objectNotFound, objectWriteProtected, storageFull, readOnly, timeout, busy
  case preconditionFailed(String)
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

public extension MTPError: LocalizedError {
  var errorDescription: String? {
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
    case .preconditionFailed(let reason):
      return "Precondition failed: \(reason)"
    }
  }

  var failureReason: String? {
    switch self {
    case .protocolError(let code, _):
      if code == 0x201D {
        return "This device rejected invalid write parameters."
      }
      return "The transport response indicates a protocol error."
    case .transport(let transportError):
      return transportError.failureReason
    case .deviceDisconnected, .permissionDenied, .notSupported, .objectNotFound, .objectWriteProtected,
         .storageFull, .readOnly, .timeout, .busy, .preconditionFailed:
      return nil
    }
  }

  var recoverySuggestion: String? {
    switch self {
    case .protocolError(let code, _):
      if code == 0x201D {
        return "Write to a writable folder (for example Download, DCIM, or a nested folder) instead of root."
      }
      return "Retry with corrected request details."
    case .transport(let transportError):
      return transportError.recoverySuggestion
    default:
      return nil
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

public enum TransportError: Error, Sendable, Equatable {
  case noDevice, timeout, busy, accessDenied
  case io(String)
}

public extension TransportError: LocalizedError {
  var errorDescription: String? {
    switch self {
    case .noDevice:
      return "No MTP-capable USB device found. Ensure the phone is in File Transfer (MTP) mode and still connected."
    case .timeout:
      return "The USB transfer timed out."
    case .busy:
      return "USB access is temporarily busy."
    case .accessDenied:
      return "The USB device is currently unavailable due to access/claim restrictions."
    case .io(let message):
      return message
    }
  }

  var failureReason: String? {
    switch self {
    case .noDevice:
      return "No matching USB interface was claimed for MTP operations."
    case .accessDenied:
      return "Another process may own the interface (Android File Transfer, adb, browsers)."
    case .timeout:
      return "The device did not complete the USB request on time."
    default:
      return nil
    }
  }

  var recoverySuggestion: String? {
    switch self {
    case .noDevice:
      return "Unplug and replug the device, confirm screen unlocked and trust prompt accepted."
    case .accessDenied:
      return "Close competing USB tools, then retry."
    case .timeout:
      return "Retry after increasing timeout values (`SWIFTMTP_MAX_CHUNK_BYTES`, `SWIFTMTP_IO_TIMEOUT_MS`)."
    case .busy:
      return "Retry briefly if bus or host contention is expected."
    case .io:
      return nil
    }
  }
}
