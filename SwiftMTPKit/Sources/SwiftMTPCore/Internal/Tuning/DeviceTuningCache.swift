// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import SwiftMTPObservability

/// Device fingerprint for identifying unique devices
struct DeviceFingerprint: Hashable, Codable, Sendable {
    let vendorId: UInt16
    let productId: UInt16
    let usbSpeed: String?
    let product: String?
    let serialNumber: String?

    var key: String {
        let components = [
            String(format: "%04x:%04x", vendorId, productId),
            usbSpeed ?? "unknown",
            product ?? "unknown",
            serialNumber ?? "unknown"
        ]
        return components.joined(separator: ":")
    }

    init(vendorId: UInt16, productId: UInt16, usbSpeed: String? = nil, product: String? = nil, serialNumber: String? = nil) {
        self.vendorId = vendorId
        self.productId = productId
        self.usbSpeed = usbSpeed
        self.product = product
        self.serialNumber = serialNumber
    }
}

/// Cached tuning settings for a device
struct DeviceTuningSettings: Codable, Sendable {
    var bestReadChunkBytes: Int?
    var bestWriteChunkBytes: Int?
    var bestEnumBudgetBytes: Int?
    var ioTimeoutMs: Int?
    var lastUpdated: Date
    var sampleCount: Int

    init() {
        self.lastUpdated = Date()
        self.sampleCount = 0
    }

    mutating func update(readChunk: Int? = nil, writeChunk: Int? = nil, enumBudget: Int? = nil, timeout: Int? = nil) {
        if let readChunk = readChunk { self.bestReadChunkBytes = readChunk }
        if let writeChunk = writeChunk { self.bestWriteChunkBytes = writeChunk }
        if let enumBudget = enumBudget { self.bestEnumBudgetBytes = enumBudget }
        if let timeout = timeout { self.ioTimeoutMs = timeout }
        self.lastUpdated = Date()
        self.sampleCount += 1
    }

    var isValid: Bool {
        // Consider valid if updated within last 30 days and has at least 5 samples
        let thirtyDays: TimeInterval = 30 * 24 * 60 * 60
        return Date().timeIntervalSince(lastUpdated) < thirtyDays && sampleCount >= 5
    }
}

/// Manages per-device tuning cache persisted to disk
actor DeviceTuningCache {
    private let cacheFileURL: URL
    private var cache: [String: DeviceTuningSettings] = [:]
    private let fileManager: FileManager

    init(cacheDirectory: URL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!) {
        self.fileManager = FileManager.default
        self.cacheFileURL = cacheDirectory.appendingPathComponent("swiftmtp-tuning-cache.json")
        Task { await loadFromDisk() }
    }

    /// Load cached settings for a device
    func loadSettings(for fingerprint: DeviceFingerprint) async -> DeviceTuningSettings? {
        await loadFromDisk() // Ensure fresh data
        let key = fingerprint.key
        guard let settings = cache[key], settings.isValid else {
            return nil
        }
        return settings
    }

    /// Save tuning settings for a device
    func saveSettings(_ settings: DeviceTuningSettings, for fingerprint: DeviceFingerprint) async {
        let key = fingerprint.key
        cache[key] = settings
        await saveToDisk()
    }

    /// Update specific settings for a device
    func updateSettings(for fingerprint: DeviceFingerprint,
                              readChunk: Int? = nil,
                              writeChunk: Int? = nil,
                              enumBudget: Int? = nil,
                              timeout: Int? = nil) async {
        let key = fingerprint.key
        var settings = cache[key] ?? DeviceTuningSettings()
        settings.update(readChunk: readChunk, writeChunk: writeChunk, enumBudget: enumBudget, timeout: timeout)
        cache[key] = settings
        await saveToDisk()
    }

    /// Get all cached devices (for diagnostics)
    func allCachedDevices() async -> [String: DeviceTuningSettings] {
        await loadFromDisk()
        return cache
    }

    /// Clear cache (useful for testing or resetting)
    func clearCache() async {
        cache.removeAll()
        try? fileManager.removeItem(at: cacheFileURL)
    }

    private func loadFromDisk() async {
        do {
            let data = try Data(contentsOf: cacheFileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let loadedCache = try decoder.decode([String: DeviceTuningSettings].self, from: data)

            // Clean up invalid entries
            var cleanedCache = [String: DeviceTuningSettings]()
            for (key, settings) in loadedCache {
                if settings.isValid {
                    cleanedCache[key] = settings
                }
            }

            self.cache = cleanedCache
        } catch {
            // File doesn't exist or is corrupted, start with empty cache
            MTPLog.perf.info("Failed to load tuning cache: \(error.localizedDescription)")
            self.cache = [:]
        }
    }

    private func saveToDisk() async {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(cache)
            try data.write(to: cacheFileURL, options: .atomic)
        } catch {
            MTPLog.perf.error("Failed to save tuning cache: \(error.localizedDescription)")
        }
    }
}

/// Global tuning cache instance
let globalTuningCache = DeviceTuningCache()
