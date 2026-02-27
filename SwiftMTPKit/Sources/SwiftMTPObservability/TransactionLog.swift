// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation

// MARK: - Transaction Outcome

public enum TransactionOutcome: String, Sendable, Codable {
  case ok
  case deviceError  // device returned non-OK response code
  case timeout  // transfer timed out
  case stall  // endpoint stall
  case ioError  // generic IO
  case cancelled
}

// MARK: - Transaction Record

public struct TransactionRecord: Sendable, Codable {
  public let txID: UInt32
  public let opcode: UInt16
  public let opcodeLabel: String
  public let sessionID: UInt32
  public let startedAt: Date
  public let duration: TimeInterval
  public let bytesIn: Int
  public let bytesOut: Int
  public let outcomeClass: TransactionOutcome
  public let errorDescription: String?

  public init(
    txID: UInt32,
    opcode: UInt16,
    opcodeLabel: String,
    sessionID: UInt32,
    startedAt: Date,
    duration: TimeInterval,
    bytesIn: Int,
    bytesOut: Int,
    outcomeClass: TransactionOutcome,
    errorDescription: String? = nil
  ) {
    self.txID = txID
    self.opcode = opcode
    self.opcodeLabel = opcodeLabel
    self.sessionID = sessionID
    self.startedAt = startedAt
    self.duration = duration
    self.bytesIn = bytesIn
    self.bytesOut = bytesOut
    self.outcomeClass = outcomeClass
    self.errorDescription = errorDescription
  }
}

// MARK: - Transaction Log

public actor TransactionLog {
  public static let shared = TransactionLog()

  private var records: [TransactionRecord] = []
  private let maxRecords = 1000

  public init() {}

  public func append(_ record: TransactionRecord) {
    records.append(record)
    if records.count > maxRecords {
      records.removeFirst(records.count - maxRecords)
    }
  }

  /// Returns the most recent `limit` records (oldest first).
  public func recent(limit: Int) -> [TransactionRecord] {
    let start = max(0, records.count - limit)
    return Array(records[start...])
  }

  /// JSON dump of all records. When `redacting` is true, hex sequences ≥8 chars
  /// in `errorDescription` (e.g. device serial numbers) are replaced with `<redacted>`.
  public func dump(redacting: Bool) -> String {
    var snapshot = records
    if redacting {
      snapshot = snapshot.map { r in
        guard let desc = r.errorDescription else { return r }
        let redacted = desc.replacingOccurrences(
          of: #"[0-9A-Fa-f]{8,}"#, with: "<redacted>", options: .regularExpression)
        return TransactionRecord(
          txID: r.txID, opcode: r.opcode, opcodeLabel: r.opcodeLabel,
          sessionID: r.sessionID, startedAt: r.startedAt, duration: r.duration,
          bytesIn: r.bytesIn, bytesOut: r.bytesOut, outcomeClass: r.outcomeClass,
          errorDescription: redacted)
      }
    }
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    guard let data = try? encoder.encode(snapshot),
      let json = String(data: data, encoding: .utf8)
    else { return "[]" }
    return json
  }

  public func clear() {
    records.removeAll()
  }
}

// MARK: - MTP Opcode Labels

public enum MTPOpcodeLabel {
  private static let labels: [UInt16: String] = [
    0x1001: "GetDeviceInfo",
    0x1002: "OpenSession",
    0x1003: "CloseSession",
    0x1004: "GetStorageIDs",
    0x1005: "GetStorageInfo",
    0x1006: "GetNumObjects",
    0x1007: "GetObjectHandles",
    0x1008: "GetObjectInfo",
    0x1009: "GetObject",
    0x100A: "GetThumb",
    0x100B: "DeleteObject",
    0x100C: "SendObjectInfo",
    0x100D: "SendObject",
    0x100E: "MoveObject",
    0x1014: "GetDevicePropDesc",
    0x1015: "GetDevicePropValue",
    0x1016: "SetDevicePropValue",
    0x1017: "ResetDevicePropValue",
    0x101B: "GetPartialObject",
    0x95C1: "SendPartialObject",
    0x95C4: "GetPartialObject64",
  ]

  /// Human-readable name for an MTP opcode, e.g. `0x1001` → `"GetDeviceInfo"`.
  /// Returns `"Unknown(0xXXXX)"` for unrecognised codes.
  public static func label(for opcode: UInt16) -> String {
    labels[opcode] ?? String(format: "Unknown(0x%04X)", opcode)
  }
}

// MARK: - Actionable Error Descriptions

/// Errors that provide a concise, user-facing actionable description.
public protocol ActionableError: Error {
  var actionableDescription: String { get }
}

/// Returns a concise, actionable description for `error` suitable for display in UI or logs.
/// Prefers `ActionableError.actionableDescription`, then `LocalizedError.errorDescription`,
/// then `error.localizedDescription` as a final fallback.
public func actionableDescription(for error: Error) -> String {
  if let actionable = error as? ActionableError {
    return actionable.actionableDescription
  }
  return (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
}
