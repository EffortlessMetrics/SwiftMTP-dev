// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import SwiftMTPCore
import CryptoKit

/// Handles privacy-safe redaction of MTP data while preserving protocol structure
public struct Redactor {
  private let bundleKey: SymmetricKey

  public init(bundleKey: String = UUID().uuidString) {
    // Use SHA256 of the input string to create a consistent 256-bit key
    let keyData = Data(bundleKey.utf8)
    let hash = SHA256.hash(data: keyData)
    self.bundleKey = SymmetricKey(data: hash)
  }

  /// Redacts a PTP string by replacing characters with '*' but keeping length and null terminator
  public func redactPTPString(_ string: String) -> String {
    if string.isEmpty { return "" }
    return String(repeating: "*", count: string.count)
  }

  /// Tokenizes a filename using a stable HMAC-SHA256 to allow correlation without leaking the name
  public func tokenizeFilename(_ name: String) -> String {
    let ext = (name as NSString).pathExtension
    let nameData = Data(name.utf8)
    let authenticationCode = HMAC<SHA256>.authenticationCode(for: nameData, using: bundleKey)
    let token = Data(authenticationCode).prefix(6).map { String(format: "%02hhx", $0) }.joined()

    guard ext.isEmpty else {
      return "file_\(token).\(ext)"
    }
    return "file_\(token)"
  }

  /// Redacts an entire ObjectInfo dataset by redacting its string fields
  public func redactObjectInfo(_ info: MTPObjectInfo) -> MTPObjectInfo {
    var redactedProps: [UInt16: String] = [:]
    for (k, v) in info.properties {
      redactedProps[k] = redactPTPString(v)
    }

    return MTPObjectInfo(
      handle: info.handle,
      storage: info.storage,
      parent: info.parent,
      name: tokenizeFilename(info.name),
      sizeBytes: info.sizeBytes,
      modified: info.modified != nil ? Date(timeIntervalSince1970: 1735689600) : nil,  // 2025-01-01
      formatCode: info.formatCode,
      properties: redactedProps
    )
  }
}
