// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation

public enum ExitCode: Int32, Sendable {
  case ok = 0
  case usage = 64        // EX_USAGE
  case unavailable = 69  // EX_UNAVAILABLE
  case software = 70     // EX_SOFTWARE
  case tempfail = 75     // EX_TEMPFAIL
}

@inline(__always) public func exitNow(_ code: ExitCode) -> Never {
  #if canImport(Darwin)
  Darwin.exit(code.rawValue)
  #else
  Glibc.exit(code.rawValue)
  #endif
}
