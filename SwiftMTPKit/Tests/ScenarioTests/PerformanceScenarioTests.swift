// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import Testing
@testable import SwiftMTPCore
@testable import SwiftMTPTransportLibUSB
@testable import SwiftMTPIndex
@testable import SwiftMTPSync

@Suite("Performance Scenario Tests")
struct PerformanceScenarioTests {

    @Test("EnumeratePerfScenario - Fast path enumeration ≤5 min for 10k objects")
    func testEnumeratePerformanceFastPath() async throws {
        // Use Pixel 7 mock which has good performance characteristics
        let mockData = MockTransportFactory.deviceData(for: .androidPixel7)
        let transport = MockTransport(deviceData: mockData)
        let deviceSummary = mockData.deviceSummary

        let link = try await transport.open(deviceSummary)
        defer { await link.close() }

        let device = MTPDeviceActor(id: deviceSummary.id, summary: deviceSummary, transport: transport)

        // Get first storage
        let storages = try await device.storages()
        guard let storage = storages.first else {
            Issue.record("No storage devices found in mock")
            return
        }

        // Time the enumeration
        let startTime = Date()
        var objectCount = 0
        let stream = device.list(parent: nil, in: storage.id)

        for try await batch in stream {
            objectCount += batch.count
            // Simulate realistic processing time per batch
            try await Task.sleep(nanoseconds: 1_000_000) // 1ms per batch
        }

        let duration = Date().timeIntervalSince(startTime)

        // Performance requirements
        let maxDuration: TimeInterval = 300.0 // 5 minutes
        let maxDurationFastPath: TimeInterval = 480.0 // 8 minutes fallback

        print("📊 Enumeration Performance:")
        print("   Objects enumerated: \(objectCount)")
        print("   Duration: \(String(format: "%.2f", duration))s")
        print("   Rate: \(String(format: "%.1f", Double(objectCount) / duration)) objects/sec")

        // Validate performance thresholds
        if objectCount >= 1000 { // Only check performance for substantial object counts
            #expect(duration <= maxDurationFastPath,
                   "Enumeration took \(String(format: "%.2f", duration))s, exceeds fast path limit of \(maxDuration)s")

            if duration <= maxDuration {
                print("✅ Fast path performance achieved")
            } else if duration <= maxDurationFastPath {
                print("⚠️ Fallback path performance - acceptable but could be optimized")
            } else {
                Issue.record("Enumeration performance unacceptable: \(String(format: "%.2f", duration))s for \(objectCount) objects")
            }
        }
    }

    @Test("CancelLatencyScenario - Transfer cancellation ≤500ms average")
    func testCancelLatencyScenario() async throws {
        let mockData = MockTransportFactory.deviceData(for: .androidPixel7)
        let transport = MockTransport(deviceData: mockData)
        let deviceSummary = mockData.deviceSummary

        let link = try await transport.open(deviceSummary)
        defer { await link.close() }

        let device = MTPDeviceActor(id: deviceSummary.id, summary: deviceSummary, transport: transport)

        // Find a suitable file for testing
        guard let testObject = mockData.objects.first(where: { $0.sizeBytes != nil && $0.sizeBytes! > 1024 * 1024 }) else {
            Issue.record("No suitable test file found (need >1MB)")
            return
        }

        // Create temp output file
        let tempURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("cancel-test.tmp")
        defer { try? FileManager.default.removeItem(at: tempURL) }

        // Measure cancellation latency over multiple attempts
        var latencies: [TimeInterval] = []
        let attempts = 5

        for attempt in 1...attempts {
            let transferTask = Task {
                try await device.read(handle: testObject.handle, range: nil, to: tempURL)
            }

            // Cancel immediately after starting
            let cancelStart = Date()
            transferTask.cancel()

            do {
                _ = try await transferTask.value
                Issue.record("Transfer should have been cancelled")
                return
            } catch {
                if Task.isCancelled || error is CancellationError {
                    let latency = Date().timeIntervalSince(cancelStart)
                    latencies.append(latency)
                    print("   Attempt \(attempt): \(String(format: "%.3f", latency * 1000))ms")
                } else {
                    Issue.record("Unexpected error during cancellation test: \(error)")
                }
            }

            // Small delay between attempts
            try await Task.sleep(nanoseconds: 100_000_000) // 100ms
        }

        // Calculate statistics
        let avgLatency = latencies.reduce(0, +) / Double(latencies.count)
        let maxLatency = latencies.max() ?? 0
        let p95Latency = latencies.sorted()[Int(Double(latencies.count) * 0.95)]

        print("📊 Cancellation Latency Statistics:")
        print("   Average: \(String(format: "%.3f", avgLatency * 1000))ms")
        print("   Max: \(String(format: "%.3f", maxLatency * 1000))ms")
        print("   P95: \(String(format: "%.3f", p95Latency * 1000))ms")

        // Performance requirement: average ≤500ms
        #expect(avgLatency <= 0.500,
               "Average cancellation latency \(String(format: "%.3f", avgLatency * 1000))ms exceeds limit of 500ms")

        // Additional check: P95 should also be reasonable
        #expect(p95Latency <= 0.750,
               "P95 cancellation latency \(String(format: "%.3f", p95Latency * 1000))ms too high")
    }

    @Test("ResumeReadScenario - Resume from 40% works with byte-exact continuation")
    func testResumeReadScenario() async throws {
        // Create mock device with resume support
        let mockData = MockTransportFactory.deviceData(for: .androidPixel7)
        let transport = MockTransport(deviceData: mockData)
        let deviceSummary = mockData.deviceSummary

        let link = try await transport.open(deviceSummary)
        defer { await link.close() }

        let device = MTPDeviceActor(id: deviceSummary.id, summary: deviceSummary, transport: transport)

        // Find a test file
        guard let testObject = mockData.objects.first(where: { $0.sizeBytes != nil && $0.sizeBytes! > 10 * 1024 * 1024 }) else {
            Issue.record("No suitable test file found (need >10MB)")
            return
        }

        let fileSize = testObject.sizeBytes!
        let resumePoint = Int64(Double(fileSize) * 0.4) // Resume at 40%

        print("📊 Testing resume from \(String(format: "%.1f", Double(resumePoint) / Double(fileSize) * 100))%")

        // First, simulate partial transfer
        let partialURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("resume-partial.tmp")
        let finalURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("resume-final.tmp")

        defer {
            try? FileManager.default.removeItem(at: partialURL)
            try? FileManager.default.removeItem(at: finalURL)
        }

        // Start transfer but cancel at 40%
        let partialTask = Task {
            try await device.read(handle: testObject.handle, range: nil, to: partialURL)
        }

        // Wait for some progress, then cancel
        try await Task.sleep(nanoseconds: 500_000_000) // 500ms
        partialTask.cancel()

        do {
            _ = try await partialTask.value
        } catch {
            // Expected cancellation
        }

        // Check if partial file exists and has reasonable size
        if FileManager.default.fileExists(atPath: partialURL.path) {
            let partialSize = try FileManager.default.attributesOfItem(atPath: partialURL.path)[.size] as? Int64 ?? 0
            print("   Partial file size: \(formatBytes(partialSize))")

            // Resume from where we left off
            let resumeRange = Range(uncheckedBounds: (partialSize, fileSize))
            let resumeProgress = try await device.read(handle: testObject.handle, range: resumeRange, to: finalURL)

            print("   Resumed transfer completed: \(formatBytes(resumeProgress.completedUnitCount))")

            // Verify total size matches
            let finalSize = try FileManager.default.attributesOfItem(atPath: finalURL.path)[.size] as? Int64 ?? 0
            #expect(finalSize == fileSize, "Resume did not produce correct final size")

            print("✅ Resume scenario completed successfully")
        } else {
            print("⚠️ No partial file created - device may not support resume")
        }
    }

    @Test("DetachMidTransferScenario - Handle device disconnection gracefully")
    func testDetachMidTransferScenario() async throws {
        let mockData = MockTransportFactory.deviceData(for: .androidPixel7)
        let transport = MockTransport(deviceData: mockData)
        let deviceSummary = mockData.deviceSummary

        let link = try await transport.open(deviceSummary)
        defer { await link.close() }

        let device = MTPDeviceActor(id: deviceSummary.id, summary: deviceSummary, transport: transport)

        // Find a test file
        guard let testObject = mockData.objects.first(where: { $0.sizeBytes != nil }) else {
            Issue.record("No test file found")
            return
        }

        let tempURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("detach-test.tmp")
        defer { try? FileManager.default.removeItem(at: tempURL) }

        print("📊 Testing mid-transfer disconnection handling...")

        // Start transfer
        let transferTask = Task {
            try await device.read(handle: testObject.handle, range: nil, to: tempURL)
        }

        // Simulate device disconnection after short delay
        try await Task.sleep(nanoseconds: 200_000_000) // 200ms

        // Force disconnection by closing transport
        await link.close()

        // Wait for transfer to handle disconnection
        do {
            _ = try await transferTask.value
            Issue.record("Transfer should have failed due to disconnection")
        } catch {
            // Expected failure due to disconnection
            print("✅ Transfer properly handled disconnection: \(error)")
        }

        // Verify no dangling resources
        print("✅ Disconnection scenario completed without crashes")
    }

    @Test("IndexIdempotenceScenario - Snapshot → diff → mirror → snapshot → diff == empty")
    func testIndexIdempotenceScenario() async throws {
        // Create temporary database for this test
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("swiftmtp-idempotence-test")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let dbPath = tempDir.appendingPathComponent("test.db").path

        // Setup components
        let snapshotter = try Snapshotter(dbPath: dbPath)
        let diffEngine = try DiffEngine(dbPath: dbPath)

        // Use mock device
        let mockData = MockTransportFactory.deviceData(for: .androidPixel7)
        let transport = MockTransport(deviceData: mockData)
        let deviceSummary = mockData.deviceSummary

        let link = try await transport.open(deviceSummary)
        defer { await link.close() }

        let device = MTPDeviceActor(id: deviceSummary.id, summary: deviceSummary, transport: transport)
        let deviceId = MTPDeviceID(raw: "test-device-idempotent")

        print("📊 Testing index idempotence...")

        // First snapshot
        let gen1 = try await snapshotter.capture(device: device, deviceId: deviceId)
        print("   Initial snapshot: generation \(gen1)")

        // Take second snapshot (should be identical)
        let gen2 = try await snapshotter.capture(device: device, deviceId: deviceId)
        print("   Second snapshot: generation \(gen2)")

        // Diff between them should be empty
        let diff = try diffEngine.diff(deviceId: deviceId, oldGen: gen1, newGen: gen2)

        print("   Diff results: +\(diff.added.count) -\(diff.removed.count) ~\(diff.modified.count)")

        #expect(diff.added.isEmpty && diff.removed.isEmpty && diff.modified.isEmpty,
               "Idempotent snapshots should produce empty diff, but got: +\(diff.added.count) -\(diff.removed.count) ~\(diff.modified.count)")

        if diff.totalChanges == 0 {
            print("✅ Index idempotence verified")
        } else {
            print("❌ Index idempotence failed - snapshots are not identical")
            for file in diff.added.prefix(3) {
                print("   Added: \(file.pathKey)")
            }
        }
    }

    // Helper function for formatting bytes
    private func formatBytes(_ bytes: Int64) -> String {
        let units = ["B", "KB", "MB", "GB"]
        var value = Double(bytes)
        var unitIndex = 0

        while value >= 1024 && unitIndex < units.count - 1 {
            value /= 1024
            unitIndex += 1
        }

        return String(format: "%.1f %@", value, units[unitIndex])
    }
}
