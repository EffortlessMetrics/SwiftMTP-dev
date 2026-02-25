// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import SwiftMTPCore

// MARK: - Operation Kinds

/// The kind of MTP link operation a fault trigger can match.
public enum LinkOperationType: String, Sendable, CaseIterable {
  case openUSB
  case openSession
  case closeSession
  case getDeviceInfo
  case getStorageIDs
  case getStorageInfo
  case getObjectHandles
  case getObjectInfos
  case deleteObject
  case moveObject
  case executeCommand
  case executeStreamingCommand
}

// MARK: - Fault Trigger

/// Describes when a fault should fire.
public enum FaultTrigger: Sendable {
  /// Fire on a specific operation type.
  case onOperation(LinkOperationType)
  /// Fire on the Nth call to any operation (0-indexed).
  case atCallIndex(Int)
  /// Fire when a streaming transfer reaches a specific byte offset.
  case atByteOffset(Int64)
  /// Fire after a delay from the start of the operation.
  case afterDelay(TimeInterval)
}

// MARK: - Fault Error

/// The error to inject when a fault fires.
public enum FaultError: Sendable {
  /// MTP transport-level errors.
  case timeout
  case busy
  case disconnected
  case accessDenied
  case io(String)
  /// MTP protocol-level error.
  case protocolError(code: UInt16)

  /// Convert to the corresponding `TransportError`.
  public var transportError: TransportError {
    switch self {
    case .timeout: return .timeout
    case .busy: return .busy
    case .disconnected: return .noDevice
    case .accessDenied: return .accessDenied
    case .io(let msg): return .io(msg)
    case .protocolError: return .io("Protocol error injected by fault")
    }
  }
}

// MARK: - Scheduled Fault

/// A fault scheduled to fire under specific conditions.
public struct ScheduledFault: Sendable {
  public let trigger: FaultTrigger
  public let error: FaultError
  /// Number of times this fault should fire. 0 = unlimited.
  public let repeatCount: Int
  /// Optional label for debugging.
  public let label: String?

  public init(trigger: FaultTrigger, error: FaultError, repeatCount: Int = 1, label: String? = nil)
  {
    self.trigger = trigger
    self.error = error
    self.repeatCount = repeatCount
    self.label = label
  }

  // MARK: Predefined Patterns

  /// Stall the USB pipe on a specific operation.
  public static func pipeStall(on op: LinkOperationType) -> ScheduledFault {
    ScheduledFault(
      trigger: .onOperation(op), error: .io("USB pipe stall"), label: "pipeStall(\(op))")
  }

  /// Disconnect at a specific byte offset during a streaming transfer.
  public static func disconnectAtOffset(_ offset: Int64) -> ScheduledFault {
    ScheduledFault(
      trigger: .atByteOffset(offset), error: .disconnected, label: "disconnect@\(offset)")
  }

  /// Return busy for N retries, then succeed.
  public static func busyForRetries(_ count: Int) -> ScheduledFault {
    ScheduledFault(
      trigger: .onOperation(.executeCommand), error: .busy, repeatCount: count,
      label: "busy×\(count)")
  }

  /// Timeout once on a specific operation.
  public static func timeoutOnce(on op: LinkOperationType) -> ScheduledFault {
    ScheduledFault(
      trigger: .onOperation(op), error: .timeout, repeatCount: 1, label: "timeout(\(op))")
  }
}

// MARK: - Fault Schedule

/// Mutable collection of faults that can be dynamically managed.
public final class FaultSchedule: @unchecked Sendable {
  private let lock = NSLock()
  private var faults: [(fault: ScheduledFault, remaining: Int)] = []

  public init(_ faults: [ScheduledFault] = []) {
    self.faults = faults.map { ($0, $0.repeatCount) }
  }

  /// Add a fault dynamically.
  public func add(_ fault: ScheduledFault) {
    lock.withLock { faults.append((fault, fault.repeatCount)) }
  }

  /// Check for a matching fault and consume one use. Returns the error to throw, or nil.
  public func check(operation: LinkOperationType, callIndex: Int, byteOffset: Int64?) -> FaultError?
  {
    lock.withLock {
      for i in faults.indices {
        let entry = faults[i]
        let matches: Bool
        switch entry.fault.trigger {
        case .onOperation(let op): matches = op == operation
        case .atCallIndex(let idx): matches = idx == callIndex
        case .atByteOffset(let offset): matches = byteOffset == offset
        case .afterDelay: matches = false  // handled externally
        }

        if matches {
          if entry.remaining == 0 {  // unlimited
            return entry.fault.error
          }
          faults[i].remaining -= 1
          if faults[i].remaining <= 0 { faults.remove(at: i) }
          return entry.fault.error
        }
      }
      return nil
    }
  }

  /// Remove all faults.
  public func clear() {
    lock.withLock { faults.removeAll() }
  }
}
