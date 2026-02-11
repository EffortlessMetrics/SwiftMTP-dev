//
//  SwiftMTPApp.swift
//  SwiftMTP
//
//  Created by Steven Zimmerman on 9/6/25.
//

import SwiftUI
#if canImport(SwiftMTPCore) && canImport(SwiftMTPStore)
import SwiftMTPCore
import SwiftMTPStore
#endif

@main
struct SwiftMTPApp: App {
    init() {
        #if canImport(SwiftMTPCore) && canImport(SwiftMTPStore)
        // Initialize persistence
        Task {
            await MTPDeviceManager.shared.setPersistence(SwiftMTPStoreAdapter())
        }
        #endif
    }
    
    var body: some Scene {
        WindowGroup {
            #if canImport(SwiftMTPStore)
            ContentView()
                .modelContainer(SwiftMTPStore.shared.container)
            #else
            ContentView()
            #endif
        }
    }
}
