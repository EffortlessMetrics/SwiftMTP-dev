import Foundation
import SwiftMTPObservability

/// Auto-tunes transfer chunk sizes based on observed throughput
/// Uses candidate sizes from 512KiB to 8MiB, promoting/demoting based on performance
struct ChunkTuner: Sendable {
    /// Candidate chunk sizes in bytes (512KiB to 8MiB)
    static let candidates = [
        512 * 1024,      // 512KiB
        1 * 1024 * 1024, // 1MiB
        2 * 1024 * 1024, // 2MiB
        4 * 1024 * 1024, // 4MiB
        8 * 1024 * 1024  // 8MiB
    ]

    private var currentIndex: Int
    private var throughputHistory: ThroughputRingBuffer
    private var samplesSinceLastChange: Int
    private var lastChangeTime: Date?
    private var isStabilized: Bool

    /// Initialize tuner starting at 1MiB (index 1)
    init() {
        self.currentIndex = 1 // Start at 1MiB
        self.throughputHistory = ThroughputRingBuffer(maxSamples: 20)
        self.samplesSinceLastChange = 0
        self.lastChangeTime = Date()
        self.isStabilized = false
    }

    /// Get current chunk size in bytes
    var currentSize: Int {
        Self.candidates[currentIndex]
    }

    /// Get current chunk size in human-readable format
    var currentSizeDescription: String {
        formatBytes(Int64(currentSize))
    }

    /// Record a transfer sample and potentially adjust chunk size
    /// - Parameters:
    ///   - bytesTransferred: Number of bytes transferred in this chunk
    ///   - duration: Time taken for the transfer
    ///   - hadTimeout: Whether the transfer timed out
    ///   - hadError: Whether the transfer encountered an error
    /// - Returns: New chunk size if changed, nil if unchanged
    mutating func recordSample(bytesTransferred: Int, duration: TimeInterval, hadTimeout: Bool, hadError: Bool) -> Int? {
        let currentThroughput = Double(bytesTransferred) / duration
        throughputHistory.addSample(currentThroughput)
        samplesSinceLastChange += 1

        // Don't change size if we had errors or timeouts
        if hadTimeout || hadError {
            demote()
            return currentSize
        }

        // Need at least 8 samples to make a decision
        guard samplesSinceLastChange >= 8 else {
            return nil
        }

        // Check if we should promote (improve performance)
        if shouldPromote() {
            promote()
            return currentSize
        }

        // Check if we should demote (degraded performance)
        if shouldDemote() {
            demote()
            return currentSize
        }

        return nil
    }

    /// Force promotion to next larger size
    mutating func promote() {
        if currentIndex + 1 < Self.candidates.count {
            currentIndex += 1
            resetAfterChange()
        }
    }

    /// Force demotion to next smaller size
    mutating func demote() {
        if currentIndex > 0 {
            currentIndex -= 1
            resetAfterChange()
        }
    }

    /// Check if tuner has stabilized (no changes for extended period)
    var stabilized: Bool {
        guard let lastChange = lastChangeTime else { return false }
        let timeSinceChange = Date().timeIntervalSince(lastChange)
        return timeSinceChange > 60 && samplesSinceLastChange >= 16 // 1 minute and 16 samples
    }

    /// Get performance statistics
    var stats: ChunkTunerStats {
        ChunkTunerStats(
            currentSizeBytes: currentSize,
            samplesCount: throughputHistory.count,
            averageThroughput: throughputHistory.average ?? 0,
            p95Throughput: throughputHistory.p95 ?? 0,
            stabilized: stabilized
        )
    }

    private mutating func resetAfterChange() {
        samplesSinceLastChange = 0
        lastChangeTime = Date()
        throughputHistory.reset()
        isStabilized = false
    }

    private func shouldPromote() -> Bool {
        guard currentIndex + 1 < Self.candidates.count else { return false }
        guard let _ = throughputHistory.average,
              let p95 = throughputHistory.p95 else { return false }

        // Promote if average throughput improved by at least 8%
        // Simple heuristic: promote if we have stable good performance
        return p95 > (throughputHistory.average ?? 0) * 1.08 && samplesSinceLastChange >= 12
    }

    private func shouldDemote() -> Bool {
        guard currentIndex > 0 else { return false }
        guard throughputHistory.average != nil else { return false }

        // Demote if average throughput dropped by more than 15%
        // This is a simplified check - in practice we'd compare to historical data
        return false // For now, only demote on explicit errors/timeouts
    }

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

/// Statistics for chunk tuner performance
struct ChunkTunerStats: Sendable {
    let currentSizeBytes: Int
    let samplesCount: Int
    let averageThroughput: Double
    let p95Throughput: Double
    let stabilized: Bool

    var currentSizeDescription: String {
        formatBytes(Int64(currentSizeBytes))
    }

    var averageMbps: Double {
        averageThroughput / (1024 * 1024)
    }

    var p95Mbps: Double {
        p95Throughput / (1024 * 1024)
    }

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
