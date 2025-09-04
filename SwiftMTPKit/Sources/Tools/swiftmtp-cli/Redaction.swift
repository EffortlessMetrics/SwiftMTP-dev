// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import CommonCrypto

/// Utility for redacting sensitive data using HMAC-SHA256
struct Redaction {
    /// Redacts a serial number using HMAC-SHA256 with a random salt
    /// - Parameters:
    ///   - serial: The serial number to redact
    ///   - salt: Random salt for HMAC (must be saved separately for consistency)
    /// - Returns: Redacted serial in format "hmacsha256:<hex>"
    static func redactSerial(_ serial: String, salt: Data) -> String {
        let data = (serial + String(data: salt, encoding: .utf8)!).data(using: .utf8) ?? Data()
        let hmac = hmacSHA256(data: data, key: salt)
        return "hmacsha256:" + hmac.hexString
    }

    /// Generates a random salt for HMAC operations
    /// - Parameter count: Number of random bytes to generate
    /// - Returns: Random data to use as salt
    static func generateSalt(count: Int = 32) -> Data {
        var bytes = [UInt8](repeating: 0, count: count)
        _ = SecRandomCopyBytes(kSecRandomDefault, count, &bytes)
        return Data(bytes)
    }

    /// Computes HMAC-SHA256
    /// - Parameters:
    ///   - data: Data to hash
    ///   - key: Key for HMAC
    /// - Returns: HMAC digest
    private static func hmacSHA256(data: Data, key: Data) -> Data {
        var hmac = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        key.withUnsafeBytes { keyBuffer in
            data.withUnsafeBytes { dataBuffer in
                CCHmac(CCHmacAlgorithm(kCCHmacAlgSHA256), keyBuffer.baseAddress, key.count, dataBuffer.baseAddress, data.count, &hmac)
            }
        }
        return Data(hmac)
    }
}

extension Data {
    /// Converts Data to hexadecimal string
    func hexString() -> String {
        return self.map { String(format: "%02x", $0) }.joined()
    }
}
