// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

/// Sanitizes device-provided filenames for safe use as local filesystem path components.
///
/// MTP devices can return arbitrary filenames, including names with path traversal sequences
/// (e.g. `../`) or other characters that could escape an intended directory. This utility
/// normalizes names to safe local filesystem components.
public enum PathSanitizer {

  /// Maximum allowed file name length from device (prevents FS attacks).
  public static let maxNameLength = 255

  /// Remove path traversal sequences and normalize the name for local FS use.
  ///
  /// - Parameter deviceName: Raw filename as reported by the MTP device.
  /// - Returns: A sanitized name safe for use as a local path component,
  ///   or `nil` if the name is invalid (empty, only dots, etc.).
  public static func sanitize(_ deviceName: String) -> String? {
    // Remove leading/trailing whitespace
    var name = deviceName.trimmingCharacters(in: .whitespaces)

    // Strip null bytes
    name = name.replacingOccurrences(of: "\0", with: "")

    // Strip path separator characters (/ and \)
    name = name.filter { $0 != "/" && $0 != "\\" }

    // Reject ".." and "." components entirely
    guard name != ".." && name != "." else { return nil }

    // Also reject names that are only dots (e.g. "...")
    guard !name.allSatisfy({ $0 == "." }) else { return nil }

    // Truncate to maxNameLength (Unicode scalar-aware)
    if name.count > maxNameLength {
      name = String(name.prefix(maxNameLength))
    }

    // Return nil if result is empty
    return name.isEmpty ? nil : name
  }
}
