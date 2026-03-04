// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import CryptoKit
import Foundation

/// Redacts sensitive information from device submission artifacts.
///
/// This type centralises privacy-safe transformations so that both the CLI
/// collect/submit flow and any future automation can strip PII from MTP
/// artifacts without losing protocol-relevant structure.
///
/// **Safe to keep** (never redacted): VID:PID, interface descriptors,
/// MTP response/event codes, object format codes.
public struct PrivacyRedactor: Sendable {

  // MARK: - Serial Numbers

  /// Redacts a USB serial number, preserving a short recognisable prefix
  /// followed by a deterministic hash fragment so that distinct serials
  /// still produce distinct outputs.
  ///
  /// - Parameter serial: Raw serial string (e.g. from `iSerialNumber`).
  /// - Returns: `"ABCD…a1b2c3d4"` — first 4 chars + "…" + 8-char SHA-256 prefix.
  public static func redactSerial(_ serial: String) -> String {
    guard !serial.isEmpty else { return "" }
    let prefix = String(serial.prefix(4))
    let hash = SHA256.hash(data: Data(serial.utf8))
    let hashPrefix = hash.prefix(4).map { String(format: "%02x", $0) }.joined()
    return "\(prefix)…\(hashPrefix)"
  }

  // MARK: - File Paths

  /// Redacts user-specific segments in file paths while preserving directory
  /// structure and depth.
  ///
  /// Handles macOS (`/Users/…`), Linux (`/home/…`), and Windows (`C:\Users\…`)
  /// home directories.
  public static func redactPath(_ path: String) -> String {
    guard !path.isEmpty else { return "" }
    var result = path
    // macOS
    result = result.replacingOccurrences(
      of: #"/Users/[^/\n]+"#, with: "/Users/[redacted]", options: .regularExpression)
    // Linux
    result = result.replacingOccurrences(
      of: #"/home/[^/\n]+"#, with: "/home/[redacted]", options: .regularExpression)
    // Windows
    result = result.replacingOccurrences(
      of: #"([A-Za-z]:\\Users\\)[^\\\n]+"#, with: "$1[redacted]", options: .regularExpression)
    return result
  }

  // MARK: - Filenames

  /// Redacts a filename while keeping the extension so format information
  /// is preserved.
  ///
  /// - Parameter name: Original filename (e.g. `vacation-photo.jpg`).
  /// - Returns: `"file_<hash>.jpg"` where `<hash>` is 8 hex chars of SHA-256.
  public static func redactFilename(_ name: String) -> String {
    guard !name.isEmpty else { return "" }
    let ext = (name as NSString).pathExtension
    let hash = SHA256.hash(data: Data(name.utf8))
    let token = hash.prefix(4).map { String(format: "%02x", $0) }.joined()
    if ext.isEmpty {
      return "file_\(token)"
    }
    return "file_\(token).\(ext)"
  }

  // MARK: - Owner / Possessive Names

  /// Strips possessive owner patterns such as "John's iPhone" → "[Owner]'s iPhone".
  public static func redactOwnerName(_ text: String) -> String {
    guard !text.isEmpty else { return "" }
    return text.replacingOccurrences(
      of: #"\b[\p{L}\p{N}][\p{L}\p{N}._ -]*(?='s\b)"#,
      with: "[Owner]",
      options: [.regularExpression, .caseInsensitive])
  }

  // MARK: - Submission Artifact (Dictionary)

  /// Applies all redaction rules to a JSON-style submission dictionary.
  ///
  /// Walks the dictionary recursively and redacts values whose **keys**
  /// match known-sensitive fields.  Protocol-relevant keys (vid, pid,
  /// formatCode, responseCode, eventCode, interface, etc.) are never touched.
  public static func redactSubmission(_ json: [String: Any]) -> [String: Any] {
    var result = [String: Any]()
    for (key, value) in json {
      result[key] = redactValue(value, forKey: key)
    }
    return result
  }

  // MARK: - Internal helpers

  /// Keys whose string values should be serial-redacted.
  private static let serialKeys: Set<String> = [
    "serial", "serialNumber", "serial_number", "iSerial",
    "serialRedacted", "serial_redacted", "udid", "UDID",
  ]

  /// Keys whose string values should be path-redacted.
  private static let pathKeys: Set<String> = [
    "path", "filePath", "file_path", "directory", "folder",
    "bundlePath", "bundle_path", "location",
  ]

  /// Keys whose string values should be filename-redacted.
  private static let filenameKeys: Set<String> = [
    "filename", "fileName", "file_name", "name", "objectName", "object_name",
  ]

  /// Keys whose string values should be owner-redacted.
  private static let ownerKeys: Set<String> = [
    "deviceName", "device_name", "friendlyName", "friendly_name",
    "model", "label",
  ]

  /// Keys that must **never** be redacted (protocol data).
  private static let safeKeys: Set<String> = [
    "vendorId", "vendor_id", "vid", "productId", "product_id", "pid",
    "formatCode", "format_code", "responseCode", "response_code",
    "eventCode", "event_code", "interface", "class", "subclass",
    "protocol", "bcdDevice", "bcd_device", "in", "out", "evt",
    "fingerprintHash", "fingerprint_hash",
  ]

  private static func redactValue(_ value: Any, forKey key: String) -> Any {
    // Never touch safe keys
    if safeKeys.contains(key) { return value }

    switch value {
    case let dict as [String: Any]:
      return redactSubmission(dict)
    case let array as [Any]:
      return array.map { redactValue($0, forKey: key) }
    case let string as String:
      if serialKeys.contains(key) { return redactSerial(string) }
      if pathKeys.contains(key) { return redactPath(string) }
      if filenameKeys.contains(key) { return redactFilename(string) }
      if ownerKeys.contains(key) { return redactOwnerName(string) }
      return string
    default:
      return value
    }
  }
}
