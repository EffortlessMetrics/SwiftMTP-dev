// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import XCTest

private enum A11yID {
    static let discoveryState = "swiftmtp.discovery.state"
    static let noDevicesState = "swiftmtp.device.empty"
    static let noSelectionState = "swiftmtp.selection.empty"
    static let discoveryErrorBanner = "swiftmtp.discovery.error"
    static let demoModeButton = "swiftmtp.demo.button"
    static let refreshFilesButton = "swiftmtp.files.refresh"
    static let filesOutcomeState = "swiftmtp.files.outcome"
    static let fileRowPrefix = "swiftmtp.file.row."
}

private enum UILabelText {
    static let demoMode = "Demo Mode"
    static let noDevices = "No Devices Found"
    static let noSelection = "No Device Selected"
    static let storageHeader = "Storages"
    static let filesHeader = "Root Files"
    static let filesEmpty = "No files found or storage empty."
}

struct DeviceBrowserRobot {
    let app: XCUIApplication

    private let knownDeviceLabels = [
        "Google Pixel 7",
        "Samsung Galaxy S21",
        "OnePlus 3T",
        "Apple iPhone",
        "Canon EOS",
    ]

    @discardableResult
    func waitForBrowser(timeout: TimeInterval = 10) -> DeviceBrowserRobot {
        let success = waitUntil(timeout: timeout) {
            app.buttons[UILabelText.demoMode].exists
                || app.buttons[A11yID.demoModeButton].exists
                || app.staticTexts[UILabelText.noDevices].exists
                || app.staticTexts[UILabelText.noSelection].exists
        }
        XCTAssertTrue(success)
        return self
    }

    @discardableResult
    func assertNoDevicesState(timeout: TimeInterval = 10) -> DeviceBrowserRobot {
        let visible = waitUntil(timeout: timeout) {
            app.staticTexts[UILabelText.noDevices].exists || app.otherElements[A11yID.noDevicesState].exists
        }
        XCTAssertTrue(visible)
        return self
    }

    @discardableResult
    func assertNoSelectionState(timeout: TimeInterval = 10) -> DeviceBrowserRobot {
        let visible = waitUntil(timeout: timeout) {
            app.staticTexts[UILabelText.noSelection].exists || app.otherElements[A11yID.noSelectionState].exists
        }
        XCTAssertTrue(visible)
        return self
    }

    @discardableResult
    func assertDiscoveryErrorContains(_ text: String, timeout: TimeInterval = 10) -> DeviceBrowserRobot {
        let hasErrorText = waitUntil(timeout: timeout) {
            let matchingElements = app.descendants(matching: .any)
                .matching(NSPredicate(format: "label CONTAINS[c] %@", text))
            return matchingElements.count > 0
        }
        XCTAssertTrue(hasErrorText)
        return self
    }

    @discardableResult
    func toggleDemoMode() -> DeviceBrowserRobot {
        let identifiedButton = app.buttons[A11yID.demoModeButton]
        if identifiedButton.exists {
            identifiedButton.tap()
            return self
        }

        let labeledButton = app.buttons[UILabelText.demoMode]
        XCTAssertTrue(labeledButton.waitForExistence(timeout: 10))
        labeledButton.tap()
        return self
    }

    @discardableResult
    func waitForAnyDeviceRow(timeout: TimeInterval = 10) -> DeviceBrowserRobot {
        let found = waitUntil(timeout: timeout) {
            for label in knownDeviceLabels where app.staticTexts[label].exists {
                return true
            }
            let idMatch = app.descendants(matching: .any)
                .matching(NSPredicate(format: "identifier BEGINSWITH %@", "swiftmtp.device.row."))
                .firstMatch
            return idMatch.exists
        }
        XCTAssertTrue(found)
        return self
    }

    @discardableResult
    func waitForNoDeviceRows(timeout: TimeInterval = 10) -> DeviceBrowserRobot {
        let gone = waitUntil(timeout: timeout) {
            for label in knownDeviceLabels where app.staticTexts[label].exists {
                return false
            }
            let idCount = app.descendants(matching: .any)
                .matching(NSPredicate(format: "identifier BEGINSWITH %@", "swiftmtp.device.row."))
                .count
            return idCount == 0
        }
        XCTAssertTrue(gone)
        return self
    }

    @discardableResult
    func tapFirstDeviceRow(timeout: TimeInterval = 10) -> DeviceBrowserRobot {
        let appeared = waitUntil(timeout: timeout) {
            knownDeviceLabels.contains(where: { app.staticTexts[$0].exists })
        }

        if appeared {
            for label in knownDeviceLabels where app.staticTexts[label].exists {
                app.staticTexts[label].tap()
                return self
            }
        }

        let row = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "swiftmtp.device.row."))
            .firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: timeout))
        row.tap()
        return self
    }

    @discardableResult
    func waitForStorageRender(timeout: TimeInterval = 10) -> DeviceBrowserRobot {
        XCTAssertTrue(app.staticTexts[UILabelText.storageHeader].waitForExistence(timeout: timeout))
        return self
    }

    @discardableResult
    func tapRefreshFiles(timeout: TimeInterval = 10) -> DeviceBrowserRobot {
        let identifiedButton = app.buttons[A11yID.refreshFilesButton]
        if identifiedButton.exists {
            identifiedButton.tap()
            return self
        }

        let labeledButton = app.buttons["Refresh Files"]
        XCTAssertTrue(labeledButton.waitForExistence(timeout: timeout))
        labeledButton.tap()
        return self
    }

    @discardableResult
    func waitForFilesOutcome(timeout: TimeInterval = 10) -> DeviceBrowserRobot {
        XCTAssertTrue(app.staticTexts[UILabelText.filesHeader].waitForExistence(timeout: timeout))
        let loadingIndicator = app.progressIndicators["swiftmtp.files.loading"]
        _ = loadingIndicator.waitForExistence(timeout: 2)
        let completed = waitUntil(timeout: timeout) { !loadingIndicator.exists }
        XCTAssertTrue(completed)
        return self
    }

    @discardableResult
    func waitForDetachReset(timeout: TimeInterval = 10) -> DeviceBrowserRobot {
        assertNoSelectionState(timeout: timeout)
        assertNoDevicesState(timeout: timeout)
        return self
    }

    @discardableResult
    func assertDiscoveryState(_ expected: String, timeout: TimeInterval = 10) -> DeviceBrowserRobot {
        let marker = app.descendants(matching: .any).matching(identifier: A11yID.discoveryState).firstMatch
        XCTAssertTrue(marker.waitForExistence(timeout: timeout))
        let label = marker.label.trimmingCharacters(in: .whitespacesAndNewlines)
        if !label.isEmpty {
            XCTAssertEqual(label, expected)
            return self
        }

        let value = (marker.value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        XCTAssertEqual(value, expected)
        return self
    }

    @discardableResult
    func assertDeviceListVisible(timeout: TimeInterval = 10) -> DeviceBrowserRobot {
        XCTAssertTrue(waitUntil(timeout: timeout) {
            knownDeviceLabels.contains(where: { app.staticTexts[$0].exists })
                || app.otherElements[A11yID.noDevicesState].exists
                || app.staticTexts[UILabelText.noDevices].exists
        })
        return self
    }

    private func waitUntil(timeout: TimeInterval, poll: TimeInterval = 0.2, condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(poll))
        }
        return condition()
    }
}
