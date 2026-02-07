// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import SwiftMTPCore

@MainActor
struct TransferCommands {
    static func runPull(flags: CLIFlags, args: [String]) async {
        guard args.count >= 2, let handle = UInt32(args[0]) else {
            print("❌ Usage: pull <handle> <destination>")
            exitNow(.usage)
        }

        let destPath = args[1]
        let destURL = URL(fileURLWithPath: destPath)
        print("⬇️  Downloading object \(handle) to \(destPath)...")

        do {
            let device = try await openDevice(flags: flags)
            let progress = try await device.read(handle: handle, range: nil, to: destURL)
            while !progress.isFinished { try await Task.sleep(nanoseconds: 100_000_000) }
            print("✅ Downloaded successfully")
        } catch {
            print("❌ Failed to download: \(error)")
            if let mtpError = error as? MTPError {
                switch mtpError {
                case .notSupported:
                    exitNow(.unavailable)
                case .transport(let te):
                    if case .noDevice = te { exitNow(.unavailable) }
                default:
                    break
                }
            }
            exitNow(.tempfail)
        }
    }

    static func runPush(flags: CLIFlags, args: [String]) async {
        guard args.count >= 2 else {
            print("❌ Usage: push <source> <parent-handle>")
            exitNow(.usage)
        }

        let srcPath = args[0]
        let parentHandleStr = args[1]
        let parentHandle = UInt32(parentHandleStr, radix: 16) ?? UInt32(parentHandleStr) ?? 0
        let srcURL = URL(fileURLWithPath: srcPath)
        
        guard FileManager.default.fileExists(atPath: srcPath) else {
            print("❌ Source file not found: \(srcPath)")
            exitNow(.usage)
        }
        
        let attrs = try? FileManager.default.attributesOfItem(atPath: srcPath)
        let size = attrs?[.size] as? UInt64 ?? 0
        print("⬆️  Uploading \(srcPath) (\(formatBytes(size))) to parent \(parentHandle)...")

        do {
            let device = try await openDevice(flags: flags)
            let progress = try await device.write(parent: parentHandle == 0 ? nil : parentHandle, name: srcURL.lastPathComponent, size: size, from: srcURL)
            while !progress.isFinished { try await Task.sleep(nanoseconds: 100_000_000) }
            print("✅ Uploaded successfully")
        } catch {
            print("❌ Failed to upload: \(error)")
            if let mtpError = error as? MTPError {
                switch mtpError {
                case .notSupported:
                    exitNow(.unavailable)
                case .transport(let te):
                    if case .noDevice = te { exitNow(.unavailable) }
                default:
                    break
                }
            }
            exitNow(.tempfail)
        }
    }

    static func runBench(flags: CLIFlags, args: [String]) async {
        guard let sizeStr = args.first else {
            print("❌ Usage: bench <size> (e.g., 100M, 1G)")
            exitNow(.usage)
        }

        let sizeBytes = parseSize(sizeStr)
        guard sizeBytes > 0 else {
            print("❌ Invalid size format: \(sizeStr)")
            exitNow(.usage)
        }

        print("🏃 Benchmarking with \(formatBytes(sizeBytes))...")

        do {
            let device = try await openDevice(flags: flags)
            let storages = try await device.storages()
            guard let storage = storages.first else {
                print("❌ No storage available")
                exitNow(.tempfail)
            }

            let tempURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("swiftmtp-bench.tmp")
            let testData = Data(repeating: 0xAA, count: Int(min(sizeBytes, 1024*1024)))
            FileManager.default.createFile(atPath: tempURL.path, contents: nil)
            let fileHandle = try FileHandle(forWritingTo: tempURL)
            var written: UInt64 = 0
            while written < sizeBytes {
                let toWrite = min(UInt64(testData.count), sizeBytes - written)
                try fileHandle.write(contentsOf: testData.prefix(Int(toWrite)))
                written += toWrite
            }
            try fileHandle.close()

            print("   Starting upload...")
            let startTime = Date()
            let progress = try await device.write(parent: nil, name: "swiftmtp-bench.tmp", size: sizeBytes, from: tempURL)
            while !progress.isFinished { try await Task.sleep(nanoseconds: 100_000_000) }

            let duration = Date().timeIntervalSince(startTime)
            let speedMBps = Double(sizeBytes) / duration / 1_000_000
            print(String(format: "✅ Upload: %.2f MB/s (%.2f seconds)", speedMBps, duration))
            try? FileManager.default.removeItem(at: tempURL)
        } catch {
            print("❌ Benchmark failed: \(error)")
            if let mtpError = error as? MTPError {
                switch mtpError {
                case .notSupported:
                    exitNow(.unavailable)
                case .transport(let te):
                    if case .noDevice = te { exitNow(.unavailable) }
                default:
                    break
                }
            }
            exitNow(.tempfail)
        }
    }

    static func runMirror(flags: CLIFlags, args: [String]) async {
        guard let destPath = args.first else {
            print("❌ Usage: mirror <destination>")
            exitNow(.usage)
        }
        print("🔄 Mirroring device to \(destPath)...")
        do {
            let device = try await openDevice(flags: flags)
            let storages = try await device.storages()
            guard let firstStorage = storages.first else {
                print("❌ No storage available")
                exitNow(.tempfail)
            }
            let rootStream = device.list(parent: nil as MTPObjectHandle?, in: firstStorage.id)
            var count = 0
            for try await batch in rootStream {
                for item in batch { print("   Found: \(item.name)"); count += 1 }
            }
            print("✅ Found \(count) items in root.")
        } catch {
            print("❌ Mirror failed: \(error)")
            if let mtpError = error as? MTPError {
                switch mtpError {
                case .notSupported:
                    exitNow(.unavailable)
                case .transport(let te):
                    if case .noDevice = te { exitNow(.unavailable) }
                default:
                    break
                }
            }
            exitNow(.tempfail)
        }
    }
}
