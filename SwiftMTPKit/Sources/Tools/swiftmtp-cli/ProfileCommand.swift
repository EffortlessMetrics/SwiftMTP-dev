// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
@_spi(Dev) import SwiftMTPCore

struct ProfileCommand {
  static func run(flags: CLIFlags, iterations: Int = 3) async {
    print("⚡️ Starting full device profiling (\(iterations) iterations)...")

    do {
      let profiler = ProfilingManager()

      // 1. Connection & Session Latency (measured once for base)
      let device = try await openDevice(flags: flags)
      try await profiler.measure("OpenSession") {
        try await device.openIfNeeded()
      }

      // 2. Metadata Throughput
      let info = try await device.info

      for i in 1...iterations {
        print("   Iteration \(i)/\(iterations)...")

        _ = try await profiler.measure("GetDeviceInfo") {
          _ = try await device.devGetDeviceInfoUncached()
        }

        _ = try await profiler.measure("GetStorageIDs") {
          _ = try await device.devGetStorageIDsUncached()
        }

        // 3. Object Listing (Root)
        let storages = try await device.storages()
        if let storage = storages.first {
          let handles = try await profiler.measure("ListRootHandles") {
            return try await device.devGetRootHandlesUncached(storage: storage.id)
          }

          // 4. Individual ObjectInfo Latency (Sample first 10 objects)
          for h in handles.prefix(10) {
            _ = try await profiler.measure("GetObjectInfo") {
              return try await device.devGetObjectInfoUncached(handle: h)
            }
          }
        }
      }

      try await device.devClose()

      let profile = await profiler.report(info: info)

      if flags.json {
        printJSON(profile)
      } else {
        print("\n📊 Profiling Results for \(info.manufacturer) \(info.model)")
        print("==========================================================")
        let header =
          "Operation".padding(toLength: 20, withPad: " ", startingAt: 0) + " | "
          + "Count".padding(toLength: 6, withPad: " ", startingAt: 0) + " | "
          + "Avg (ms)".padding(toLength: 8, withPad: " ", startingAt: 0) + " | "
          + "P95 (ms)".padding(toLength: 8, withPad: " ", startingAt: 0) + " | " + "MB/s"
        print(header)
        print("----------------------------------------------------------")
        for metric in profile.metrics {
          let tpStr = metric.throughputMBps.map { String(format: "%.2f", $0) } ?? "-"
          let row =
            metric.operation.padding(toLength: 20, withPad: " ", startingAt: 0) + " | "
            + "\(metric.count)".padding(toLength: 6, withPad: " ", startingAt: 0) + " | "
            + String(format: "%.2f", metric.avgMs).padding(toLength: 8, withPad: " ", startingAt: 0)
            + " | "
            + String(format: "%.2f", metric.p95Ms).padding(toLength: 8, withPad: " ", startingAt: 0)
            + " | " + tpStr
          print(row)
        }
        print("==========================================================")
      }

    } catch {
      print("❌ Profiling failed: \(error)")
    }
  }

  /// Run the device lab harness to characterize capabilities.
  /// Produces a DeviceLabReport as JSON.
  static func runCollect(flags: CLIFlags) async {
    print("🔬 Running device lab harness...")
    do {
      let device = try await openDevice(flags: flags)
      let harness = DeviceLabHarness()
      let report = try await harness.collect(device: device)

      let encoder = JSONEncoder()
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
      encoder.dateEncodingStrategy = .iso8601
      let data = try encoder.encode(report)
      print(String(data: data, encoding: .utf8) ?? "{}")

      try await device.devClose()
    } catch {
      print("❌ Device lab harness failed: \(error)")
    }
  }
}
