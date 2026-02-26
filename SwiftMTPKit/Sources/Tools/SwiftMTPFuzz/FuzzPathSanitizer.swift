// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import SwiftMTPCore

/// libFuzzer-compatible harness for PathSanitizer.sanitize(_:).
///
/// Called from the SwiftMTPFuzz runner and also compilable as a standalone
/// libFuzzer binary (rename to LLVMFuzzerTestOneInput for that use).
func fuzzPathSanitizer(_ data: UnsafePointer<UInt8>, _ size: Int) -> Int32 {
  let bytes = Data(bytes: data, count: size)
  let str = String(data: bytes, encoding: .utf8) ?? ""
  _ = PathSanitizer.sanitize(str)
  return 0
}
