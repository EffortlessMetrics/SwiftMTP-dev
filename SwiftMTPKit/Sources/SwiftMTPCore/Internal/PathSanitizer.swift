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

  /// Sanitize a filename for sending to an MTP device.
  ///
  /// Applies standard sanitization plus device-specific restrictions:
  /// - When `only7Bit` is true, strips characters with code points > 0x7F
  ///   (libmtp `DEVICE_FLAG_ONLY_7BIT_FILENAMES`).
  ///
  /// - Parameter deviceName: Raw filename to send.
  /// - Parameter only7Bit: Restrict to 7-bit ASCII characters.
  /// - Returns: A sanitized name, or `nil` if the name is invalid after sanitization.
  public static func sanitizeForMTP(_ deviceName: String, only7Bit: Bool = false) -> String? {
    guard var name = sanitize(deviceName) else { return nil }
    if only7Bit {
      name = String(name.unicodeScalars.filter { $0.value <= 0x7F })
    }
    return name.isEmpty ? nil : name
  }
}
