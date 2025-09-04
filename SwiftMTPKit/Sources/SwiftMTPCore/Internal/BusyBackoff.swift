// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation

/// Utility for handling DEVICE_BUSY responses with exponential backoff and jitter.
///
/// Some devices (particularly Xiaomi) return DEVICE_BUSY (0x2003) immediately after
/// session open or when storage operations are first attempted. This utility provides
/// a standardized way to retry these operations with progressive backoff.
enum BusyBackoff {
    /// Execute an operation with DEVICE_BUSY retry logic.
    ///
    /// - Parameters:
    ///   - maxRetries: Maximum number of retries (default: 3)
    ///   - baseMs: Base delay in milliseconds (default: 200)
    ///   - jitterPct: Jitter percentage (0.0-1.0, default: 0.2 for 20% jitter)
    ///   - operation: The operation to execute
    /// - Returns: The result of the operation if successful
    /// - Throws: The last error encountered, or the original error if not DEVICE_BUSY
    nonisolated static func onDeviceBusy<T>(
        maxRetries: Int = 3,
        baseMs: Int = 200,
        jitterPct: Double = 0.2,
        _ operation: () throws -> T
    ) throws -> T {
        var attempt = 0
        var lastError: Error?

        while attempt <= maxRetries {
            do {
                return try operation()
            } catch let e as MTPError {
                lastError = e
                if case .protocolError(let code, _) = e, code == 0x2003 { // DEVICE_BUSY
                    if attempt < maxRetries {
                        attempt += 1
                        let baseDelay = Double(baseMs) * pow(2.0, Double(attempt - 1))
                        let jitter = baseDelay * (1.0 + (Double.random(in: -jitterPct...jitterPct)))
                        let delayMs = max(50, Int(jitter)) // Minimum 50ms delay

                        print("DEVICE_BUSY detected, retrying in \(delayMs)ms (attempt \(attempt)/\(maxRetries))")
                        Thread.sleep(forTimeInterval: Double(delayMs) / 1000.0)
                        continue
                    }
                }
                throw e
            } catch {
                lastError = error
                throw error
            }
        }

        // Should never reach here, but just in case
        throw lastError ?? MTPError.timeout
    }

    /// Execute an async operation with DEVICE_BUSY retry logic.
    ///
    /// - Parameters:
    ///   - maxRetries: Maximum number of retries (default: 3)
    ///   - baseMs: Base delay in milliseconds (default: 200)
    ///   - jitterPct: Jitter percentage (0.0-1.0, default: 0.2 for 20% jitter)
    ///   - operation: The async operation to execute
    /// - Returns: The result of the operation if successful
    /// - Throws: The last error encountered, or the original error if not DEVICE_BUSY
    nonisolated static func onDeviceBusy<T>(
        maxRetries: Int = 3,
        baseMs: Int = 200,
        jitterPct: Double = 0.2,
        _ operation: @escaping () async throws -> T
    ) async throws -> T {
        var attempt = 0
        var lastError: Error?

        while attempt <= maxRetries {
            do {
                return try await operation()
            } catch let e as MTPError {
                lastError = e
                if case .protocolError(let code, _) = e, code == 0x2003 { // DEVICE_BUSY
                    if attempt < maxRetries {
                        attempt += 1
                        let baseDelay = Double(baseMs) * pow(2.0, Double(attempt - 1))
                        let jitter = baseDelay * (1.0 + (Double.random(in: -jitterPct...jitterPct)))
                        let delayMs = max(50, Int(jitter)) // Minimum 50ms delay

                        print("DEVICE_BUSY detected, retrying in \(delayMs)ms (attempt \(attempt)/\(maxRetries))")
                        try? await Task.sleep(nanoseconds: UInt64(delayMs) * 1_000_000)
                        continue
                    }
                }
                throw e
            } catch {
                lastError = error
                throw error
            }
        }

        // Should never reach here, but just in case
        throw lastError ?? MTPError.timeout
    }
}
