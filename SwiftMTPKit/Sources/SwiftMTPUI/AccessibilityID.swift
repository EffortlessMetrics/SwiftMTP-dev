// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation

/// Shared accessibility identifiers used by app code and UI automation.
public enum AccessibilityID {
    public static let browserRoot = "swiftmtp.browser.root"
    public static let discoveryState = "swiftmtp.discovery.state"
    public static let demoModeButton = "swiftmtp.demo.button"
    public static let discoveryErrorBanner = "swiftmtp.discovery.error"
    public static let deviceList = "swiftmtp.device.list"
    public static let noDevicesState = "swiftmtp.device.empty"
    public static let noSelectionState = "swiftmtp.selection.empty"

    public static let detailContainer = "swiftmtp.detail.container"
    public static let deviceLoadingIndicator = "swiftmtp.device.loading"
    public static let storageSection = "swiftmtp.storage.section"
    public static let filesSection = "swiftmtp.files.section"
    public static let filesLoadingIndicator = "swiftmtp.files.loading"
    public static let filesEmptyState = "swiftmtp.files.empty"
    public static let filesErrorState = "swiftmtp.files.error"
    public static let filesOutcomeState = "swiftmtp.files.outcome"
    public static let refreshFilesButton = "swiftmtp.files.refresh"

    public static func deviceRow(_ deviceId: String) -> String {
        "swiftmtp.device.row.\(sanitize(deviceId))"
    }

    public static func storageRow(_ storageId: UInt32) -> String {
        "swiftmtp.storage.row.\(storageId)"
    }

    public static func fileRow(_ handle: UInt32) -> String {
        "swiftmtp.file.row.\(handle)"
    }

    private static func sanitize(_ text: String) -> String {
        let pattern = "[^A-Za-z0-9._-]"
        return text.replacingOccurrences(of: pattern, with: "_", options: .regularExpression)
    }
}
