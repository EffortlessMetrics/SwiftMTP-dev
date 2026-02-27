// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import SwiftMTPCore

/// libFuzzer-compatible harness for GetObjectPropList response decoding.
///
/// Called from the SwiftMTPFuzz runner and also compilable as a standalone
/// libFuzzer binary (rename to LLVMFuzzerTestOneInput for that use).
func fuzzPropListDecoder(_ data: UnsafePointer<UInt8>, _ size: Int) -> Int32 {
  let bytes = Data(bytes: data, count: size)
  _ = PTPPropList.parse(from: bytes)
  return 0
}
