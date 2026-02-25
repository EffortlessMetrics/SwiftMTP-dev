// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import SwiftUI
import SwiftMTPUI

@main
struct SwiftMTPApp: App {
  @State private var coordinator = DeviceLifecycleCoordinator()

  var body: some Scene {
    WindowGroup {
      DeviceBrowserView(coordinator: coordinator)
        .frame(minWidth: 800, minHeight: 500)
    }
    .windowStyle(.hiddenTitleBar)
  }
}
