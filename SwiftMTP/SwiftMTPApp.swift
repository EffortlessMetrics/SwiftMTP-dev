//
//  SwiftMTPApp.swift
//  SwiftMTP
//
//  Created by Steven Zimmerman on 9/6/25.
//

import SwiftUI
import SwiftMTPCore
import SwiftMTPStore

@main
struct SwiftMTPApp: App {
    init() {
        // Initialize persistence
        Task {
            await MTPDeviceManager.shared.setPersistence(SwiftMTPStoreAdapter())
        }
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .modelContainer(SwiftMTPStore.shared.container)
        }
    }
}
