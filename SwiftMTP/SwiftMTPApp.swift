//
//  SwiftMTPApp.swift
//  SwiftMTP
//
//  Created by Steven Zimmerman, CPA on 9/6/25.
//

import Foundation
import SwiftUI
#if canImport(SwiftMTPCore) && canImport(SwiftMTPStore)
import SwiftMTPCore
import SwiftMTPStore
#endif

@main
struct SwiftMTPApp: App {
    init() {
        #if canImport(SwiftMTPCore) && canImport(SwiftMTPStore)
        configureUITestLaunchContractIfNeeded()

        // Initialize persistence
        Task {
            await MTPDeviceManager.shared.setPersistence(SwiftMTPStoreAdapter())
        }
        #endif
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }

    #if canImport(SwiftMTPCore)
    private func configureUITestLaunchContractIfNeeded() {
        let env = ProcessInfo.processInfo.environment
        let isUITest = parseBool(env["SWIFTMTP_UI_TEST"]) ?? false
        guard isUITest else { return }

        let demoMode = parseBool(env["SWIFTMTP_DEMO_MODE"]) ?? true
        FeatureFlags.shared.useMockTransport = demoMode

        if let profile = env["SWIFTMTP_MOCK_PROFILE"], !profile.isEmpty {
            setenv("SWIFTMTP_MOCK_PROFILE", profile, 1)
        } else {
            setenv("SWIFTMTP_MOCK_PROFILE", "pixel7", 1)
        }

        if let scenario = env["SWIFTMTP_UI_SCENARIO"], !scenario.isEmpty {
            setenv("SWIFTMTP_UI_SCENARIO", scenario, 1)
        } else {
            setenv("SWIFTMTP_UI_SCENARIO", "mock-default", 1)
        }
    }

    private func parseBool(_ raw: String?) -> Bool? {
        guard let raw else { return nil }
        switch raw.lowercased() {
        case "1", "true", "yes":
            return true
        case "0", "false", "no":
            return false
        default:
            return nil
        }
    }
    #endif
}
