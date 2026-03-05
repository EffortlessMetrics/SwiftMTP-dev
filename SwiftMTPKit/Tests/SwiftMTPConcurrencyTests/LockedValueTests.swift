// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import SwiftMTPConcurrency
import Testing

@Suite("LockedValue")
struct LockedValueTests {
  @Test("serializes concurrent increments")
  func concurrentIncrement() async {
    let counter = LockedValue<Int>(0)

    await withTaskGroup(of: Void.self) { group in
      for _ in 0..<32 {
        group.addTask {
          for _ in 0..<500 {
            counter.withLock { $0 += 1 }
          }
        }
      }
    }

    let total = counter.read { $0 }
    #expect(total == 16_000)
  }

  @Test("supports read-only access")
  func readAccess() {
    let value = LockedValue<[String: Bool]>(["enabled": true])
    let enabled = value.read { $0["enabled"] }
    #expect(enabled == true)
  }
}
