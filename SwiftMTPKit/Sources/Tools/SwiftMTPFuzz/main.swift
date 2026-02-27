// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import SwiftMTPCore

let args = CommandLine.arguments
let iters = args.count > 1 ? Int(args[1]) ?? 1000 : 1000

print("🧪 Starting MTP Substrate Fuzzer (\(iters) iterations)...")

for i in 1...iters {
  if i % 100 == 0 { print("   Progress: \(i)/\(iters)...") }

  let data = MTPFuzzer.randomData(length: Int.random(in: 1...1024))

  // Test 1: PTPString parsing
  var off = 0
  _ = PTPString.parse(from: data, at: &off)

  // Test 2: PTPReader primitives
  var r = PTPReader(data: data)
  _ = r.u8()
  _ = r.u16()
  _ = r.u32()
  _ = r.u64()
  _ = r.string()

  // Test 3: DeviceInfo parsing
  _ = PTPDeviceInfo.parse(from: data)

  // Test 4: PropList parsing
  _ = PTPPropList.parse(from: data)

  // Test 5: Mutation stress
  let mutated = MTPFuzzer.mutate(data)
  var r2 = PTPReader(data: mutated)
  _ = r2.u32()
  _ = r2.string()

  // Test 6: PropList decoder harness
  data.withUnsafeBytes { ptr in
    guard let base = ptr.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return }
    _ = fuzzPropListDecoder(base, data.count)
  }

  // Test 7: Path sanitizer harness
  data.withUnsafeBytes { ptr in
    guard let base = ptr.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return }
    _ = fuzzPathSanitizer(base, data.count)
  }

  // Test 8: XPC decoder harness
  data.withUnsafeBytes { ptr in
    guard let base = ptr.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return }
    _ = fuzzXPCDecoder(base, data.count)
  }
}

print("✅ Fuzzing complete. No crashes detected.")
