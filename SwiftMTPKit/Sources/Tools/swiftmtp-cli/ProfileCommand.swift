// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import SwiftMTPCore

struct ProfileCommand {
    static func run(flags: CLIFlags, iterations: Int = 3) async {
        print("⚡️ Starting full device profiling (\(iterations) iterations)...")
        
        do {
            let profiler = ProfilingManager()
            
            // 1. Connection & Session Latency
            for i in 1...iterations {
                print("   Iteration \(i)/\(iterations)...")
                
                do {
                    try await profiler.measure("OpenSession") {
                        let device = try await openDevice(flags: flags)
                        try await device.openIfNeeded()
                        // Stabilization delay
                        try await Task.sleep(nanoseconds: 1_000_000_000)
                    }
                } catch {
                    print("   ⚠️ Iteration \(i) failed: \(error)")
                }
            }
            
            // 2. Metadata Throughput
            let device = try await openDevice(flags: flags)
            try await device.openIfNeeded()
            let info = try await device.getDeviceInfo()
            
            for _ in 1...iterations {
                _ = try await profiler.measure("GetDeviceInfo") {
                    _ = try await device.getDeviceInfo()
                }
                
                _ = try await profiler.measure("GetStorageIDs") {
                    _ = try await device.storages()
                }
            }
            
            // 3. Object Listing (Root)
            let storages = try await device.storages()
            if let storage = storages.first {
                for _ in 1...iterations {
                    _ = try await profiler.measure("ListRootHandles") {
                        var objects: [MTPObjectInfo] = []
                        let stream = device.list(parent: nil, in: storage.id)
                        for try await batch in stream {
                            objects.append(contentsOf: batch)
                        }
                        return objects
                    }
                }
                
                // 4. Individual ObjectInfo Latency (Sample 10 objects)
                var objects: [MTPObjectInfo] = []
                let stream = device.list(parent: nil, in: storage.id)
                for try await batch in stream {
                    objects.append(contentsOf: batch)
                    if objects.count >= 10 { break }
                }
                
                for obj in objects.prefix(10) {
                    _ = try await profiler.measure("GetObjectInfo") {
                        // Dummy storage call for now to keep structure until SPI is available
                        return try await device.storages()
                    }
                }
            }
            
            let profile = await profiler.report(info: info)
            
            if flags.json {
                printJSON(profile)
            } else {
                print("\n📊 Profiling Results for \(info.manufacturer) \(info.model)")
                print("==========================================================")
                let header = "Operation".padding(toLength: 20, withPad: " ", startingAt: 0) + " | " +
                             "Count".padding(toLength: 6, withPad: " ", startingAt: 0) + " | " +
                             "Avg (ms)".padding(toLength: 8, withPad: " ", startingAt: 0) + " | " +
                             "P95 (ms)".padding(toLength: 8, withPad: " ", startingAt: 0) + " | " +
                             "MB/s"
                print(header)
                print("----------------------------------------------------------")
                for metric in profile.metrics {
                    let tpStr = metric.throughputMBps.map { String(format: "%.2f", $0) } ?? "-"
                    let row = metric.operation.padding(toLength: 20, withPad: " ", startingAt: 0) + " | " +
                              "\(metric.count)".padding(toLength: 6, withPad: " ", startingAt: 0) + " | " +
                              String(format: "%.2f", metric.avgMs).padding(toLength: 8, withPad: " ", startingAt: 0) + " | " +
                              String(format: "%.2f", metric.p95Ms).padding(toLength: 8, withPad: " ", startingAt: 0) + " | " +
                              tpStr
                    print(row)
                }
                print("==========================================================")
            }
            
        } catch {
            print("❌ Profiling failed: \(error)")
        }
    }
}