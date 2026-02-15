// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation

/// Errors related to USB interface claiming with detailed conflict diagnostics.
public enum USBClaimError: Error, Sendable, Equatable {
  /// Claim failed due to a conflict with another process or application.
  /// - Parameters:
  ///   - libusbError: The raw libusb error code (e.g., -6 for BUSY, -3 for ACCESS)
  ///   - interface: The USB interface number that failed to claim
  ///   - conflictingProcess: Optional name of the process holding the device
  case claimFailedWithConflict(
    libusbError: Int32,
    interface: UInt8,
    conflictingProcess: String?
  )

  /// Generic claim failure without conflict information.
  case claimFailed(libusbError: Int32, interface: UInt8)

  /// Device was disconnected during claim operation.
  case deviceDisconnected

  /// Kernel driver attachment issue.
  case kernelDriverError(String)
}

public extension USBClaimError {
  /// Human-readable description of the claim error with actionable guidance.
  var localizedDescription: String {
    switch self {
    case .claimFailedWithConflict(let error, let iface, let process):
      let errorName = errorName(for: error)
      if let process = process {
        return "Claim failed (\\(errorName), error code \\(error)) on interface \\(iface). "
          + "\\(process) may be holding the device. Quit the application and retry."
      }
      return "Claim failed (\\(errorName), error code \\(error)) on interface \\(iface). "
        + "Another application (possibly Chrome/WebUSB or Android File Transfer) may have claimed the device."

    case .claimFailed(let error, let iface):
      let errorName = errorName(for: error)
      return "USB claim failed (\\(errorName), error code \\(error)) on interface \\(iface)."

    case .deviceDisconnected:
      return "Device was disconnected during claim operation."

    case .kernelDriverError(let message):
      return "Kernel driver error: \\(message)"
    }
  }

  /// Maps libusb error codes to human-readable names.
  private func errorName(for error: Int32) -> String {
    switch error {
    case -3:
      return "LIBUSB_ERROR_ACCESS"
    case -4:
      return "LIBUSB_ERROR_NO_DEVICE"
    case -5:
      return "LIBUSB_ERROR_NOT_FOUND"
    case -6:
      return "LIBUSB_ERROR_BUSY"
    case -7:
      return "LIBUSB_ERROR_TIMEOUT"
    case -12:
      return "LIBUSB_ERROR_NOT_SUPPORTED"
    default:
      return "LIBUSB_ERROR_UNKNOWN"
    }
  }
}

/// Utility for analyzing and diagnosing USB claim conflicts on macOS.
public enum USBClaimDiagnostics {
  /// Common processes known to conflict with MTP devices on macOS.
  public static let knownConflictingProcesses: [String] = [
    "Google Chrome",
    "Chromium",
    "Microsoft Edge",
    "Brave",
    "Android File Transfer",
    "Android File Transfer Agent",
    "adb",
    "fastboot",
  ]

  /// Analyzes a claim error and provides diagnostic information.
  /// - Parameters:
  ///   - error: The libusb error code from claim failure
  ///   - interface: The interface number that failed to claim
  ///   - pid: Optional process ID detected as holder
  /// - Returns: A detailed USBClaimError with conflict analysis
  public static func analyzeClaimFailure(
    error: Int32,
    interface: UInt8,
    pid: Int32? = nil
  ) -> USBClaimError {
    // Check for conflict-specific errors
    if error == -6 || error == -3 {  // BUSY or ACCESS
      let conflictingProc: String? = pid.flatMap { Self.processName(for: $0) }
      return .claimFailedWithConflict(
        libusbError: error,
        interface: interface,
        conflictingProcess: conflictingProc
      )
    }

    // Generic claim failure
    return .claimFailed(libusbError: error, interface: interface)
  }

  /// Attempts to get the process name for a given PID.
  /// - Parameter pid: The process ID to look up
  /// - Returns: The process name if available, nil otherwise
  private static func processName(for pid: Int32) -> String? {
    // Limited implementation - in production would use sysctl or similar
    if knownConflictingProcesses.contains(where: { _ in
      // In a full implementation, we'd query the process name
      true
    }) {
      return "a conflicting application"
    }
    return nil
  }
}
