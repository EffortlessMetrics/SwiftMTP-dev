// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import SwiftMTPObservability

// MARK: - Recovery Strategy

/// Identifies which recovery strategy was applied.
public enum RecoveryStrategy: String, Sendable {
  case sessionRecovery = "session-recovery"
  case stallRecovery = "stall-recovery"
  case timeoutEscalation = "timeout-escalation"
  case disconnectRecovery = "disconnect-recovery"
}

// MARK: - Error Recovery Layer

/// Layered error recovery for MTP operations.
///
/// Provides four recovery strategies that can be composed:
/// - **Session recovery**: re-open session after SessionNotOpen / session loss
/// - **Stall recovery**: clear endpoint halt and retry after LIBUSB_ERROR_PIPE
/// - **Timeout escalation**: double timeout on each retry up to 60s
/// - **Disconnect recovery**: save journal state and emit disconnect event
public enum ErrorRecoveryLayer {

  /// Maximum retry attempts for session recovery.
  public static let maxSessionRetries = 3

  /// Maximum timeout in milliseconds for escalation.
  public static let maxTimeoutMs = 60_000

  // MARK: - Session Recovery

  /// Execute an operation with automatic session recovery.
  ///
  /// If the operation fails with SessionNotOpen (0x2003) or a session-related error,
  /// closes the session, re-opens it, and retries up to `maxRetries` times.
  public static func withSessionRecovery<T: Sendable>(
    link: any MTPLink,
    sessionId: UInt32 = 1,
    maxRetries: Int = maxSessionRetries,
    operation: @Sendable () async throws -> T
  ) async throws -> T {
    var lastError: Error?
    for attempt in 0..<(maxRetries + 1) {
      do {
        let result = try await operation()
        if attempt > 0 {
          await RecoveryLog.shared.record(RecoveryEvent(
            strategy: RecoveryStrategy.sessionRecovery.rawValue,
            attempt: attempt, maxAttempts: maxRetries,
            succeeded: true
          ))
        }
        return result
      } catch let error as MTPError {
        lastError = error
        guard isSessionRecoverable(error), attempt < maxRetries else {
          await RecoveryLog.shared.record(RecoveryEvent(
            strategy: RecoveryStrategy.sessionRecovery.rawValue,
            attempt: attempt + 1, maxAttempts: maxRetries,
            succeeded: false, errorDescription: "\(error)"
          ))
          throw error
        }
        MTPLog.recovery.info(
          "Session recovery: closing and re-opening session (attempt \(attempt + 1)/\(maxRetries))"
        )
        try? await link.closeSession()
        try await link.openSession(id: sessionId)
      } catch {
        lastError = error
        await RecoveryLog.shared.record(RecoveryEvent(
          strategy: RecoveryStrategy.sessionRecovery.rawValue,
          attempt: attempt + 1, maxAttempts: maxRetries,
          succeeded: false, errorDescription: "\(error)"
        ))
        throw error
      }
    }
    throw lastError ?? MTPError.preconditionFailed("Session recovery exhausted")
  }

  // MARK: - Stall Recovery

  /// Execute an operation with automatic stall (endpoint halt) recovery.
  ///
  /// If the operation fails with a stall/pipe error, sends a device reset
  /// to clear the halt condition and retries once.
  public static func withStallRecovery<T: Sendable>(
    link: any MTPLink,
    operation: @Sendable () async throws -> T
  ) async throws -> T {
    do {
      return try await operation()
    } catch let error as MTPError where isStallError(error) {
      MTPLog.recovery.warning(
        "Stall recovery: clearing endpoint halt via device reset"
      )
      do {
        try await link.resetDevice()
      } catch {
        MTPLog.recovery.error(
          "Stall recovery: device reset failed — \(error.localizedDescription, privacy: .public)"
        )
        await RecoveryLog.shared.record(RecoveryEvent(
          strategy: RecoveryStrategy.stallRecovery.rawValue,
          attempt: 1, maxAttempts: 1,
          succeeded: false, errorDescription: "\(error)"
        ))
        throw error
      }
      do {
        let result = try await operation()
        await RecoveryLog.shared.record(RecoveryEvent(
          strategy: RecoveryStrategy.stallRecovery.rawValue,
          attempt: 1, maxAttempts: 1,
          succeeded: true
        ))
        return result
      } catch {
        await RecoveryLog.shared.record(RecoveryEvent(
          strategy: RecoveryStrategy.stallRecovery.rawValue,
          attempt: 1, maxAttempts: 1,
          succeeded: false, errorDescription: "\(error)"
        ))
        throw error
      }
    }
  }

  // MARK: - Timeout Escalation

  /// Execute an operation with timeout escalation on repeated timeouts.
  ///
  /// Doubles the timeout on each retry, starting from `initialTimeoutMs`, up to 60s max.
  /// The `operation` closure receives the current timeout in milliseconds.
  public static func withTimeoutEscalation<T: Sendable>(
    initialTimeoutMs: Int = 5_000,
    maxRetries: Int = 3,
    operation: @Sendable (_ timeoutMs: Int) async throws -> T
  ) async throws -> T {
    var currentTimeoutMs = initialTimeoutMs
    var lastError: Error?
    for attempt in 0..<(maxRetries + 1) {
      do {
        let result = try await operation(currentTimeoutMs)
        if attempt > 0 {
          await RecoveryLog.shared.record(RecoveryEvent(
            strategy: RecoveryStrategy.timeoutEscalation.rawValue,
            attempt: attempt, maxAttempts: maxRetries,
            succeeded: true, timeoutMs: currentTimeoutMs
          ))
        }
        return result
      } catch let error as MTPError where isTimeoutError(error) {
        lastError = error
        guard attempt < maxRetries else {
          await RecoveryLog.shared.record(RecoveryEvent(
            strategy: RecoveryStrategy.timeoutEscalation.rawValue,
            attempt: attempt + 1, maxAttempts: maxRetries,
            succeeded: false, errorDescription: "\(error)",
            timeoutMs: currentTimeoutMs
          ))
          throw error
        }
        let previousTimeout = currentTimeoutMs
        currentTimeoutMs = min(currentTimeoutMs * 2, maxTimeoutMs)
        MTPLog.recovery.info(
          "Timeout escalation: \(previousTimeout)ms → \(currentTimeoutMs)ms (attempt \(attempt + 1)/\(maxRetries))"
        )
      } catch {
        throw error
      }
    }
    throw lastError ?? MTPError.timeout
  }

  // MARK: - Disconnect Detection

  /// Checks whether an error represents a device disconnection.
  ///
  /// When a disconnect is detected, logs the event and optionally persists
  /// the transfer journal state for later resume.
  public static func handleDisconnectIfNeeded(
    error: Error,
    journal: (any TransferJournal)?,
    transferId: String?
  ) async -> Bool {
    guard isDisconnectError(error) else { return false }

    MTPLog.recovery.error(
      "Device disconnected during operation"
    )

    if let journal = journal, let transferId = transferId {
      do {
        try await journal.fail(id: transferId, error: error)
        MTPLog.recovery.info(
          "Disconnect recovery: journal state saved for transfer \(transferId, privacy: .public)"
        )
      } catch {
        MTPLog.recovery.error(
          "Disconnect recovery: failed to save journal — \(error.localizedDescription, privacy: .public)"
        )
      }
    }

    await RecoveryLog.shared.record(RecoveryEvent(
      strategy: RecoveryStrategy.disconnectRecovery.rawValue,
      attempt: 1, maxAttempts: 1,
      succeeded: false, errorDescription: "\(error)"
    ))

    return true
  }

  // MARK: - Error Classification

  /// Returns `true` if the error is recoverable by re-opening the session.
  public static func isSessionRecoverable(_ error: MTPError) -> Bool {
    switch error {
    case .protocolError(let code, _):
      // 0x2003 = SessionNotOpen, 0x201E = SessionAlreadyOpen
      return code == 0x2003 || code == 0x201E
    case .sessionBusy:
      return true
    default:
      return false
    }
  }

  /// Returns `true` if the error is a USB endpoint stall.
  public static func isStallError(_ error: MTPError) -> Bool {
    if case .transport(let t) = error, t == .stall { return true }
    return false
  }

  /// Returns `true` if the error is a timeout.
  public static func isTimeoutError(_ error: MTPError) -> Bool {
    switch error {
    case .timeout: return true
    case .transport(let t):
      switch t {
      case .timeout, .timeoutInPhase: return true
      default: return false
      }
    default: return false
    }
  }

  /// Returns `true` if the error indicates the device has disconnected.
  public static func isDisconnectError(_ error: Error) -> Bool {
    if let mtp = error as? MTPError {
      switch mtp {
      case .deviceDisconnected: return true
      case .transport(.noDevice): return true
      default: return false
      }
    }
    if let t = error as? TransportError, t == .noDevice { return true }
    return false
  }
}
