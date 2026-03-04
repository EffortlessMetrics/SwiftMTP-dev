// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation

/// Structured diagnostic output for an MTP error, including a summary,
/// likely cause, suggested next-step CLI commands, and optional verbose detail.
public struct ErrorDiagnostic: Sendable, Equatable {
  /// One-line summary of what happened.
  public let summary: String
  /// Likely cause of the error.
  public let cause: String
  /// Actionable next step (may include CLI commands).
  public let suggestion: String
  /// Related CLI command the user can run for more info.
  public let relatedCommand: String?

  public init(
    summary: String, cause: String, suggestion: String, relatedCommand: String? = nil
  ) {
    self.summary = summary
    self.cause = cause
    self.suggestion = suggestion
    self.relatedCommand = relatedCommand
  }

  /// Render the diagnostic as a multi-line string for terminal display.
  public func formatted(verbose: Bool = false, underlyingError: Error? = nil) -> String {
    var lines = [String]()
    lines.append("  Error:   \(summary)")
    lines.append("  Cause:   \(cause)")
    lines.append("  Try:     \(suggestion)")
    if let cmd = relatedCommand {
      lines.append("  Run:     \(cmd)")
    }
    if verbose, let error = underlyingError {
      lines.append("")
      lines.append("  Detail:  \(String(describing: error))")
      if let localized = error as? LocalizedError {
        if let reason = localized.failureReason {
          lines.append("  Reason:  \(reason)")
        }
        if let recovery = localized.recoverySuggestion {
          lines.append("  Recover: \(recovery)")
        }
      }
    }
    return lines.joined(separator: "\n")
  }
}

/// Maps MTP errors to structured diagnostics with actionable next-step suggestions.
public enum DiagnosticFormatter {

  /// Produce a structured diagnostic for the given error.
  public static func diagnose(_ error: Error) -> ErrorDiagnostic {
    if let mtpError = error as? MTPError {
      return diagnoseMTP(mtpError)
    }
    if let transportError = error as? TransportError {
      return diagnoseTransport(transportError)
    }
    return ErrorDiagnostic(
      summary: error.localizedDescription,
      cause: "An unexpected error occurred.",
      suggestion: "Retry the operation. If it persists, file a bug report."
    )
  }

  /// Format a user-friendly diagnostic block for terminal display.
  public static func format(_ error: Error, verbose: Bool = false) -> String {
    let diag = diagnose(error)
    return diag.formatted(verbose: verbose, underlyingError: error)
  }

  // MARK: - MTPError diagnostics

  private static func diagnoseMTP(_ error: MTPError) -> ErrorDiagnostic {
    switch error {
    case .deviceDisconnected:
      return ErrorDiagnostic(
        summary: "Device disconnected during the operation.",
        cause: "The USB cable may have been unplugged or the device powered off.",
        suggestion: "Reconnect the device, unlock the screen, and retry.",
        relatedCommand: "swiftmtp probe"
      )
    case .permissionDenied:
      return ErrorDiagnostic(
        summary: "USB device access was denied.",
        cause: "macOS requires explicit permission for USB device access.",
        suggestion:
          "Accept the 'Trust This Computer' prompt on the device, or check System Settings > Privacy & Security.",
        relatedCommand: "swiftmtp health"
      )
    case .notSupported(let msg):
      return ErrorDiagnostic(
        summary: "Operation not supported: \(msg).",
        cause: "The device firmware does not implement this MTP operation.",
        suggestion: "Check device capabilities or try a different approach.",
        relatedCommand: "swiftmtp info --device"
      )
    case .transport(let te):
      return diagnoseTransport(te)
    case .protocolError(let code, let message):
      return diagnoseProtocol(code: code, message: message)
    case .objectNotFound:
      return ErrorDiagnostic(
        summary: "The requested object was not found on the device.",
        cause: "The file may have been moved or deleted on the device since the last listing.",
        suggestion: "Refresh the file listing and verify the object handle.",
        relatedCommand: "swiftmtp ls <storage>"
      )
    case .objectWriteProtected:
      return ErrorDiagnostic(
        summary: "The target object is write-protected.",
        cause: "The file or folder is marked as read-only by the device.",
        suggestion: "Remove write protection on the device, or choose a different target."
      )
    case .storageFull:
      return ErrorDiagnostic(
        summary: "Device storage is full.",
        cause: "No free space remains on the target storage volume.",
        suggestion: "Free space on the device, then retry the transfer.",
        relatedCommand: "swiftmtp storages"
      )
    case .readOnly:
      return ErrorDiagnostic(
        summary: "Storage is read-only.",
        cause: "The storage volume is mounted read-only (e.g. SD card write-protect switch).",
        suggestion: "Check for a physical write-protect switch and remount as writable.",
        relatedCommand: "swiftmtp storages"
      )
    case .timeout:
      return ErrorDiagnostic(
        summary: "The operation timed out.",
        cause: "The device did not respond within the timeout window.",
        suggestion:
          "Ensure the device is unlocked. Increase timeout with SWIFTMTP_IO_TIMEOUT_MS env var.",
        relatedCommand: "swiftmtp probe"
      )
    case .busy:
      return ErrorDiagnostic(
        summary: "The device is busy.",
        cause: "The device is processing another request or is in a locked state.",
        suggestion:
          "Unlock the screen, dismiss any prompts, wait a moment, and retry."
      )
    case .sessionBusy:
      return ErrorDiagnostic(
        summary: "A protocol transaction is already in progress.",
        cause: "Only one MTP transaction can be in-flight per session at a time.",
        suggestion: "Wait for the current operation to complete, then retry."
      )
    case .preconditionFailed(let reason):
      return ErrorDiagnostic(
        summary: "Precondition failed: \(reason).",
        cause: "A required condition was not met before the operation could proceed.",
        suggestion: "Verify the device session is open and storage IDs are valid.",
        relatedCommand: "swiftmtp probe"
      )
    case .verificationFailed(let expected, let actual):
      return ErrorDiagnostic(
        summary:
          "Write verification failed: remote size \(actual) != expected \(expected).",
        cause: "The file may have been truncated or corrupted during transfer.",
        suggestion: "Re-send the file and verify the transfer completes without interruption."
      )
    }
  }

  // MARK: - TransportError diagnostics

  private static func diagnoseTransport(_ error: TransportError) -> ErrorDiagnostic {
    switch error {
    case .noDevice:
      return ErrorDiagnostic(
        summary: "No MTP-capable USB device found.",
        cause:
          "The device may not be connected, or USB mode may not be set to File Transfer (MTP).",
        suggestion:
          "Check the cable, unlock the device, and set USB mode to File Transfer.",
        relatedCommand: "swiftmtp probe"
      )
    case .timeout:
      return ErrorDiagnostic(
        summary: "USB transfer timed out.",
        cause: "The device did not complete the USB request within the timeout.",
        suggestion:
          "Ensure the device screen is on. Increase timeout with SWIFTMTP_IO_TIMEOUT_MS.",
        relatedCommand: "swiftmtp health"
      )
    case .busy:
      return ErrorDiagnostic(
        summary: "USB access is temporarily busy.",
        cause: "The USB bus is contended by another transfer or process.",
        suggestion: "Close other USB-intensive applications and retry."
      )
    case .accessDenied:
      return ErrorDiagnostic(
        summary: "USB device access denied.",
        cause:
          "Another process may own the USB interface (Android File Transfer, adb, Smart Switch).",
        suggestion:
          "Close competing USB tools, then check System Settings > Privacy & Security.",
        relatedCommand: "swiftmtp diag"
      )
    case .stall:
      return ErrorDiagnostic(
        summary: "USB endpoint stalled.",
        cause:
          "The device endpoint halted due to an unsupported command or protocol mismatch.",
        suggestion: "Disconnect and reconnect the device. Try a different USB port if it persists.",
        relatedCommand: "swiftmtp probe"
      )
    case .timeoutInPhase(let phase):
      return ErrorDiagnostic(
        summary: "USB transfer timed out during \(phase.description) phase.",
        cause: "The device stopped responding during the \(phase.description) phase.",
        suggestion:
          "Check the cable connection, ensure the device is unlocked, and retry.",
        relatedCommand: "swiftmtp health"
      )
    case .io(let msg):
      return ErrorDiagnostic(
        summary: "USB I/O error: \(msg).",
        cause: "A low-level USB communication error occurred.",
        suggestion: "Try a different USB port or cable. Reconnect the device and retry."
      )
    }
  }

  // MARK: - Protocol code diagnostics

  private static func diagnoseProtocol(code: UInt16, message: String?) -> ErrorDiagnostic {
    let codeHex = String(format: "0x%04X", code)
    let codeName = message ?? PTPResponseCode.name(for: code) ?? "UnknownResponse"
    let label = "\(codeName) (\(codeHex))"

    switch code {
    case 0x2001:
      return ErrorDiagnostic(
        summary: "Device returned an undefined error (\(codeHex)).",
        cause: "The device could not classify the error.",
        suggestion: "Retry the operation. If it persists, reconnect the device.",
        relatedCommand: "swiftmtp probe"
      )
    case 0x2002:
      return ErrorDiagnostic(
        summary: "General device error (\(codeHex)).",
        cause: "The device encountered an internal error it could not classify.",
        suggestion: "Retry the operation. If it persists, reconnect the device.",
        relatedCommand: "swiftmtp probe"
      )
    case 0x2003:
      return ErrorDiagnostic(
        summary: "MTP session is not open (\(codeHex)).",
        cause: "The session was closed or never opened.",
        suggestion: "Reconnect the device to start a new session.",
        relatedCommand: "swiftmtp probe"
      )
    case 0x2005:
      return ErrorDiagnostic(
        summary: "Operation not supported by device (\(codeHex)).",
        cause: "The device firmware does not implement this MTP operation.",
        suggestion: "Check device capabilities.",
        relatedCommand: "swiftmtp info --device"
      )
    case 0x2008:
      return ErrorDiagnostic(
        summary: "Invalid storage ID (\(codeHex)).",
        cause: "The storage ID does not match any available storage on the device.",
        suggestion: "Refresh the storage list and retry.",
        relatedCommand: "swiftmtp storages"
      )
    case 0x2009:
      return ErrorDiagnostic(
        summary: "Invalid object handle (\(codeHex)).",
        cause: "The object was deleted or invalidated on the device.",
        suggestion: "Refresh the file listing and retry with a valid handle.",
        relatedCommand: "swiftmtp ls <storage>"
      )
    case 0x200C:
      return ErrorDiagnostic(
        summary: "Device storage is full (\(codeHex)).",
        cause: "No free space remains on the device.",
        suggestion: "Free space on the device, then retry.",
        relatedCommand: "swiftmtp storages"
      )
    case 0x201D:
      return ErrorDiagnostic(
        summary: "Invalid parameter rejected by device (\(codeHex)).",
        cause: "This may be a device quirk — some devices reject writes to certain folders.",
        suggestion:
          "Write to a subfolder (Download, DCIM) instead of root. Check device quirks.",
        relatedCommand: "swiftmtp quirks"
      )
    case 0x201E:
      return ErrorDiagnostic(
        summary: "Session already open (\(codeHex)).",
        cause: "MTP allows only one session per connection.",
        suggestion: "Disconnect and reconnect the device.",
        relatedCommand: "swiftmtp probe"
      )
    case 0x2019:
      return ErrorDiagnostic(
        summary: "Device is busy (\(codeHex)).",
        cause: "The device is processing a prior request.",
        suggestion: "Wait a moment for the device to finish, then retry."
      )
    default:
      let userMsg = PTPResponseCode.userMessage(for: code)
      return ErrorDiagnostic(
        summary: "Protocol error: \(label).",
        cause: userMsg,
        suggestion: "Retry the operation. If the error persists, reconnect the device.",
        relatedCommand: "swiftmtp quirks"
      )
    }
  }
}
