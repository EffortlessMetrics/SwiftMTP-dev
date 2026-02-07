// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import SwiftUI
import SwiftMTPUI

@main
struct SwiftMTPApp: App {
    var body: some Scene {
        WindowGroup {
            DeviceBrowserView()
                .frame(minWidth: 800, minHeight: 500)
        }
        .windowStyle(.hiddenTitleBar)
    }
}
