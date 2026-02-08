// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

public enum MTPError: Error, Sendable, Equatable {
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
    return .notSupported(message)
  }

  /// True when the device reports SessionAlreadyOpen (0x201E).
  var isSessionAlreadyOpen: Bool {
    if case .protocolError(let code, _) = self, code == 0x201E { return true }
    return false
  }
}
public enum TransportError: Error, Sendable, Equatable {
  case noDevice, timeout, busy, accessDenied
  case io(String)
}
