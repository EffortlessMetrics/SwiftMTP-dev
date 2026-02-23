// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import XCTest

struct AppRobot {
    let app = XCUIApplication()
    let artifactsDirectory: URL

    init(testName: String) {
        let runID = Self.timestamp()
        let baseDirectory: URL
        if let override = ProcessInfo.processInfo.environment["SWIFTMTP_UI_TEST_ARTIFACT_BASE_DIR"], !override.isEmpty {
            baseDirectory = URL(fileURLWithPath: override, isDirectory: true)
        } else {
            baseDirectory = FileManager.default.temporaryDirectory
                .appendingPathComponent("swiftmtp-ui-tests", isDirectory: true)
        }

        let dir = baseDirectory.appendingPathComponent("\(runID)-\(testName)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.artifactsDirectory = dir
    }

    func launch(
        scenario: String,
        demoMode: Bool = true,
        mockProfile: String = "pixel7"
    ) {
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES"]
        app.launchEnvironment["SWIFTMTP_UI_TEST"] = "1"
        app.launchEnvironment["SWIFTMTP_UI_SCENARIO"] = scenario
        app.launchEnvironment["SWIFTMTP_DEMO_MODE"] = demoMode ? "1" : "0"
        app.launchEnvironment["SWIFTMTP_MOCK_PROFILE"] = mockProfile
        app.launchEnvironment["SWIFTMTP_UI_TEST_ARTIFACT_DIR"] = artifactsDirectory.path
        app.launchEnvironment["SWIFTMTP_UI_TEST_RUN_ID"] = Self.timestamp()
        app.launch()
    }

    func screenshot(named name: String) {
        let shot = app.screenshot()
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        XCTContext.runActivity(named: "Screenshot: \(name)") { activity in
            activity.add(attachment)
        }

        let data = shot.pngRepresentation
        let file = artifactsDirectory.appendingPathComponent("\(name).png")
        try? data.write(to: file)
    }

    func waitForLoggedEvent(
        flow: String,
        result: String? = nil,
        timeout: TimeInterval = 10
    ) -> Bool {
        let eventsURL = artifactsDirectory.appendingPathComponent("ux-events.jsonl")
        let deadline = Date().addingTimeInterval(timeout)

        while Date() < deadline {
            if let data = try? Data(contentsOf: eventsURL),
               let text = String(data: data, encoding: .utf8),
               text.contains("\"flow\":\"\(flow)\"") {
                if let result {
                    if text.contains("\"result\":\"\(result)\"") {
                        return true
                    }
                } else {
                    return true
                }
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }

        return false
    }

    private static func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss-SSS"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.string(from: Date())
    }
}
