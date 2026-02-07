// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation

/// Centralized feature flag management for SwiftMTP.
public final class FeatureFlags: @unchecked Sendable {
    public static let shared = FeatureFlags()
    
    private var flags: [String: Bool] = [:]
    private let lock = NSLock()
    
    // MARK: - Known Flags
    
    /// Enable using the in-memory Mock Transport instead of real USB.
    /// Use "SWIFTMTP_DEMO_MODE=1" environment variable.
    public var useMockTransport: Bool {
        get { isEnabled("SWIFTMTP_DEMO_MODE") }
        set { set("SWIFTMTP_DEMO_MODE", enabled: newValue) }
    }
    
    /// The profile to use for mock transport (e.g. "pixel7", "s21", "iphone", "canon").
    /// Use "SWIFTMTP_MOCK_PROFILE=pixel7" environment variable.
    public var mockProfile: String {
        get { ProcessInfo.processInfo.environment["SWIFTMTP_MOCK_PROFILE"] ?? "pixel7" }
    }
    
    /// Enable the "Storybook" UI catalog tab in the app.
    /// Use "SWIFTMTP_SHOW_STORYBOOK=1" environment variable.
    public var showStorybook: Bool {
        get { isEnabled("SWIFTMTP_SHOW_STORYBOOK") }
        set { set("SWIFTMTP_SHOW_STORYBOOK", enabled: newValue) }
    }
    
    /// Enable verbose logging for USB transport.
    public var traceUSB: Bool {
        get { isEnabled("SWIFTMTP_TRACE_USB") }
        set { set("SWIFTMTP_TRACE_USB", enabled: newValue) }
    }

    private init() {
        // Load initial values from Environment
        for (key, value) in ProcessInfo.processInfo.environment {
            if key.starts(with: "SWIFTMTP_") {
                flags[key] = (value == "1" || value.lowercased() == "true")
            }
        }
        
        // Load from arguments (useful for XCTest / CLI flags like --demo-mode)
        let args = ProcessInfo.processInfo.arguments
        if args.contains("--demo-mode") { flags["SWIFTMTP_DEMO_MODE"] = true }
        if args.contains("--storybook") { flags["SWIFTMTP_SHOW_STORYBOOK"] = true }
        if args.contains("--trace-usb") { flags["SWIFTMTP_TRACE_USB"] = true }
    }
    
    public func isEnabled(_ key: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return flags[key] ?? false
    }
    
    public func set(_ key: String, enabled: Bool) {
        lock.lock()
        defer { lock.unlock() }
        flags[key] = enabled
    }
}
