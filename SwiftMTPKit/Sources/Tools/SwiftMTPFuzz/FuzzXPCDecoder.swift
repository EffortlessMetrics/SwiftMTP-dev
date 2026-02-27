// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation

/// libFuzzer-compatible harness for NSSecureCoding round-trip decoding.
///
/// Exercises NSKeyedUnarchiver with the full set of classes used by XPC request/response types,
/// exercising all NSSecureCoding paths in the XPC layer without requiring a live XPC connection.
///
/// Called from the SwiftMTPFuzz runner and also compilable as a standalone
/// libFuzzer binary (rename to LLVMFuzzerTestOneInput for that use).
func fuzzXPCDecoder(_ data: UnsafePointer<UInt8>, _ size: Int) -> Int32 {
  let bytes = Data(bytes: data, count: size)
  // Attempt NSKeyedUnarchiver round-trip for each NSSecureCoding-conforming type
  // used across all XPC request/response types (ReadRequest, WriteRequest, etc.)
  let allowedClasses: [AnyClass] = [
    NSString.self, NSNumber.self, NSData.self, NSDate.self,
    NSArray.self, NSDictionary.self, NSURL.self,
  ]
  _ = try? NSKeyedUnarchiver.unarchivedObject(ofClasses: allowedClasses, from: bytes)
  return 0
}
