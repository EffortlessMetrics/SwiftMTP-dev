// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

enum ExitCode: Int32 {
  case ok = 0
  case usage = 64  // EX_USAGE
  case unavailable = 69  // EX_UNAVAILABLE
  case software = 70  // EX_SOFTWARE
  case tempfail = 75  // EX_TEMPFAIL
}

enum Exit {
  static func software() -> Never { exit(70) }
  static func usage() -> Never { exit(64) }
  static func unavailable() -> Never { exit(69) }
}

@inline(__always) func exitNow(_ code: ExitCode) -> Never { exit(code.rawValue) }
