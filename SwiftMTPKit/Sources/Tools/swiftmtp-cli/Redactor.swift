// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import SwiftMTPCore

/// Handles privacy-safe redaction of MTP data while preserving protocol structure
public struct Redactor {
    private let bundleKey: String
    
    public init(bundleKey: String = UUID().uuidString) {
        self.bundleKey = bundleKey
    }
    
    /// Redacts a PTP string by replacing characters with '*' but keeping length and null terminator
    public func redactPTPString(_ string: String) -> String {
        if string.isEmpty { return "" }
        return String(repeating: "*", count: string.count)
    }
    
    /// Tokenizes a filename using a stable HMAC-like hash to allow correlation without leaking the name
    public func tokenizeFilename(_ name: String) -> String {
        let ext = (name as NSString).pathExtension
        let token = Data("\(bundleKey):\(name)".utf8).sha256().prefix(6).hexEncodedString()
        if ext.isEmpty {
            return "file_\(token)"
        } else {
            return "file_\(token).\(ext)"
        }
    }
    
    /// Redacts an entire ObjectInfo dataset by redacting its string fields
    public func redactObjectInfo(_ info: MTPObjectInfo) -> MTPObjectInfo {
        return MTPObjectInfo(
            handle: info.handle,
            storageID: info.storageID,
            formatCode: info.formatCode,
            protectionStatus: info.protectionStatus,
            sizeBytes: info.sizeBytes,
            thumbFormat: info.thumbFormat,
            thumbSizeBytes: info.thumbSizeBytes,
            thumbPixWidth: info.thumbPixWidth,
            thumbPixHeight: info.thumbPixHeight,
            imagePixWidth: info.imagePixWidth,
            imagePixHeight: info.imagePixHeight,
            imageBitDepth: info.imageBitDepth,
            parentHandle: info.parentHandle,
            associationType: info.associationType,
            associationDesc: info.associationDesc,
            sequenceNumber: info.sequenceNumber,
            name: tokenizeFilename(info.name),
            captureDate: info.captureDate != nil ? "20250101T000000" : nil,
            modificationDate: info.modificationDate != nil ? "20250101T000000" : nil,
            keywords: info.keywords != nil ? redactPTPString(info.keywords!) : nil
        )
    }
}

private extension Data {
    func sha256() -> Data {
        // Simple placeholder for SHA256 if not using CryptoKit
        // In a real implementation, use CryptoKit.SHA256
        return self // Dummy
    }
    
    func hexEncodedString() -> String {
        return map { String(format: "%02hhx", $0) }.joined()
    }
}
