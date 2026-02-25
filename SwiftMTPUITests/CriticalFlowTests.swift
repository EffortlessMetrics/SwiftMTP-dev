// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import XCTest

final class CriticalFlowTests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func test_ux_launch_empty_state() throws {
        let appRobot = AppRobot(testName: "ux_launch_empty_state")
        appRobot.launch(scenario: "empty-state", demoMode: true)

        let browser = DeviceBrowserRobot(app: appRobot.app)
        browser.waitForBrowser()
            .assertNoDevicesState()
            .assertNoSelectionState()

        XCTAssertTrue(
            appRobot.waitForLoggedEvent(flow: "ux.launch.empty_state"),
            "Expected ux.launch.empty_state event in ux-events.jsonl"
        )

        appRobot.screenshot(named: "ux_launch_empty_state")
    }

    @MainActor
    func test_ux_demo_toggle() throws {
        let appRobot = AppRobot(testName: "ux_demo_toggle")
        appRobot.launch(scenario: "mock-default", demoMode: true)

        let browser = DeviceBrowserRobot(app: appRobot.app)
        browser.waitForBrowser()
            .waitForAnyDeviceRow()
            .toggleDemoMode()
            .waitForNoDeviceRows()
            .assertNoDevicesState()
            .toggleDemoMode()
            .waitForAnyDeviceRow()

        XCTAssertTrue(
            appRobot.waitForLoggedEvent(flow: "ux.demo.toggle"),
            "Expected ux.demo.toggle event in ux-events.jsonl"
        )

        appRobot.screenshot(named: "ux_demo_toggle")
    }

    @MainActor
    func test_ux_device_list_visible() throws {
        let appRobot = AppRobot(testName: "ux_device_list_visible")
        appRobot.launch(scenario: "mock-default", demoMode: true, mockProfile: "pixel7")

        let browser = DeviceBrowserRobot(app: appRobot.app)
        browser.waitForBrowser()
            .assertDeviceListVisible()
            .waitForAnyDeviceRow()

        XCTAssertTrue(appRobot.app.staticTexts["Google Pixel 7"].waitForExistence(timeout: 10))
        XCTAssertTrue(
            appRobot.waitForLoggedEvent(flow: "ux.device.list.visible"),
            "Expected ux.device.list.visible event in ux-events.jsonl"
        )
        appRobot.screenshot(named: "ux_device_list_visible")
    }

    @MainActor
    func test_ux_device_select() throws {
        let appRobot = AppRobot(testName: "ux_device_select")
        appRobot.launch(scenario: "mock-default", demoMode: true)

        let browser = DeviceBrowserRobot(app: appRobot.app)
        browser.waitForBrowser()
            .waitForAnyDeviceRow()
            .tapFirstDeviceRow()
            .waitForStorageRender()

        XCTAssertFalse(appRobot.app.otherElements["swiftmtp.selection.empty"].exists)
        XCTAssertTrue(
            appRobot.waitForLoggedEvent(flow: "ux.device.select"),
            "Expected ux.device.select event in ux-events.jsonl"
        )
        appRobot.screenshot(named: "ux_device_select")
    }

    @MainActor
    func test_ux_storage_render() throws {
        let appRobot = AppRobot(testName: "ux_storage_render")
        appRobot.launch(scenario: "mock-default", demoMode: true)

        let browser = DeviceBrowserRobot(app: appRobot.app)
        browser.waitForBrowser()
            .waitForAnyDeviceRow()
            .tapFirstDeviceRow()
            .waitForStorageRender()

        XCTAssertTrue(
            appRobot.waitForLoggedEvent(flow: "ux.storage.render"),
            "Expected ux.storage.render event in ux-events.jsonl"
        )
        appRobot.screenshot(named: "ux_storage_render")
    }

    @MainActor
    func test_ux_files_refresh() throws {
        let appRobot = AppRobot(testName: "ux_files_refresh")
        appRobot.launch(scenario: "mock-default", demoMode: true)

        let browser = DeviceBrowserRobot(app: appRobot.app)
        browser.waitForBrowser()
            .waitForAnyDeviceRow()
            .tapFirstDeviceRow()
            .waitForStorageRender()
            .tapRefreshFiles()
            .waitForFilesOutcome()

        XCTAssertTrue(
            appRobot.waitForLoggedEvent(flow: "ux.files.refresh"),
            "Expected ux.files.refresh event in ux-events.jsonl"
        )
        appRobot.screenshot(named: "ux_files_refresh")
    }

    @MainActor
    func test_ux_error_discovery() throws {
        let appRobot = AppRobot(testName: "ux_error_discovery")
        appRobot.launch(scenario: "error-discovery", demoMode: true)

        let browser = DeviceBrowserRobot(app: appRobot.app)
        browser.waitForBrowser()
            .assertNoDevicesState()

        XCTAssertTrue(
            appRobot.waitForLoggedEvent(flow: "ux.error.discovery", result: "forced_error"),
            "Expected ux.error.discovery forced_error event in ux-events.jsonl"
        )

        appRobot.screenshot(named: "ux_error_discovery")
    }

    @MainActor
    func test_ux_detach_selection_reset() throws {
        let appRobot = AppRobot(testName: "ux_detach_selection_reset")
        appRobot.launch(scenario: "detach-on-select", demoMode: true)

        let browser = DeviceBrowserRobot(app: appRobot.app)
        browser.waitForBrowser()
            .waitForAnyDeviceRow()
            .tapFirstDeviceRow()
            .waitForDetachReset()

        XCTAssertTrue(
            appRobot.waitForLoggedEvent(flow: "ux.detach.selection_reset"),
            "Expected ux.detach.selection_reset event in ux-events.jsonl"
        )
        appRobot.screenshot(named: "ux_detach_selection_reset")
    }
}
