// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation

/// Utility for handling device-not-ready responses with exponential backoff and jitter.
///
/// Some devices (particularly Xiaomi) return SessionNotOpen (0x2003) immediately after
/// session open or when storage operations are first attempted, using it as a "not ready"
/// signal. DeviceBusy is actually 0x2019. This utility provides a standardized way to
/// retry these operations with progressive backoff.
enum BusyBackoff {
    /// Execute an async operation with DEVICE_BUSY retry logic.
    ///
    /// - Parameters:
    ///   - maxRetries: Maximum number of retries (default: 3)
    ///   - baseMs: Base delay in milliseconds (default: 200)
    ///   - jitterPct: Jitter percentage (0.0-1.0, default: 0.2 for 20% jitter)
    ///   - operation: The async operation to execute
    /// - Returns: The result of the operation if successful
    /// - Throws: The last error encountered, or the original error if not DEVICE_BUSY
    static func onDeviceBusy<T: Sendable>(
        retries: Int = 3,
        baseMs: Int = 200,
        jitterPct: Double = 0.2,
        _ op: @Sendable () async throws -> T
    ) async throws -> T {
        var attempt = 0
        while true {
            do {
                return try await op()
            } catch let e as MTPError {
                guard case .protocolError(let code, _) = e, code == 0x2003, attempt < retries else { throw e }
                attempt += 1
                let base = Double(baseMs) * pow(2.0, Double(attempt-1))
                let jitter = base * (1.0 + Double.random(in: -jitterPct...jitterPct))
                let delayMs = max(50, Int(jitter)) // Minimum 50ms delay

                let debugEnabled = ProcessInfo.processInfo.environment["SWIFTMTP_DEBUG"] == "1"
                if debugEnabled {
                    print("⏳ DEVICE_BUSY detected, retrying in \(delayMs)ms (attempt \(attempt)/\(retries))")
                }
                try? await Task.sleep(nanoseconds: UInt64(delayMs) * 1_000_000)
            }
        }
    }
}
