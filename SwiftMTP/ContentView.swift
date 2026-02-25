// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import SwiftUI
#if canImport(SwiftMTPUI)
import SwiftMTPUI
#endif

struct ContentView: View {
    #if canImport(SwiftMTPUI)
    @State private var coordinator = DeviceLifecycleCoordinator()
    #endif

    var body: some View {
        Group {
            #if canImport(SwiftMTPUI)
            DeviceBrowserView(coordinator: coordinator)
            #else
            VStack(spacing: 12) {
                Text("SwiftMTP")
                    .font(.title)
                Text("SwiftMTPKit UI modules are unavailable in this build configuration.")
                    .font(.callout)
                    .multilineTextAlignment(.center)
            }
            #endif
        }
        .frame(minWidth: 800, minHeight: 500)
    }
}

#Preview {
    ContentView()
}
