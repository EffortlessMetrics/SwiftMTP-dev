// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

//
//  SwiftMTPUITests.swift
//  SwiftMTPUITests
//
//  Created by Steven Zimmerman on 2025-09-01.
//

import XCTest

final class SwiftMTPUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testHarnessLaunchesInMockMode() throws {
        let appRobot = AppRobot(testName: "harness_launch_mock")
        appRobot.launch(scenario: "mock-default", demoMode: true)

        DeviceBrowserRobot(app: appRobot.app)
            .waitForBrowser()
            .waitForAnyDeviceRow()
    }
}
