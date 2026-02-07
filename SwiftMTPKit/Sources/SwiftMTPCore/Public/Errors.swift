// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

public enum MTPError: Error, Sendable {
  case deviceDisconnected, permissionDenied
  case notSupported(String)
  case transport(TransportError)
  case protocolError(code: UInt16, message: String?)
  case objectNotFound, storageFull, readOnly, timeout, busy
  case preconditionFailed(String)
}

public extension MTPError {
  /// Back-compat factory used by CLI/tools. Maps to an existing error case.
  static func internalError(_ message: String) -> MTPError {
    // Choose the most appropriate mapping you already have:
    // If you have `.unexpectedResponse(String)` or `.protocolError(String)`, use that.
    // Falling back to `.notSupported` is safe and already present in your codebase.
    return .notSupported(message)
  }
}
public enum TransportError: Error, Sendable, Equatable {
  case noDevice, timeout, busy, accessDenied
  case io(String)
}
