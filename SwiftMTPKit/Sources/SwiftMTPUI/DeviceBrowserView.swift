// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import SwiftUI
import SwiftMTPCore

public struct DeviceBrowserView: View {
    private let coordinator: DeviceLifecycleCoordinator
    @State private var viewModel: DeviceViewModel
    @State private var isDemoMode = FeatureFlags.shared.useMockTransport

    public init(coordinator: DeviceLifecycleCoordinator) {
        self.coordinator = coordinator
        self._viewModel = State(initialValue: DeviceViewModel(coordinator: coordinator))
    }

    public var body: some View {
        NavigationSplitView {
            DeviceListView(viewModel: viewModel)
                .toolbar {
                    ToolbarItem {
                        Button(action: {
                            isDemoMode.toggle()
                            FeatureFlags.shared.useMockTransport = isDemoMode
                            Task {
                                try? await viewModel.startDiscovery()
                            }
                        }) {
                            Label("Demo Mode", systemImage: isDemoMode ? "play.circle.fill" : "play.circle")
                                .foregroundStyle(isDemoMode ? .orange : .secondary)
                        }
                        .help("Toggle Simulation Mode")
                    }
                }
        } detail: {
            if let device = viewModel.selectedDevice {
                DeviceMainView(device: device)
            } else {
                ContentUnavailableView("No Device Selected", systemImage: "externaldrive", description: Text("Select a device from the sidebar to view details."))
            }
        }
        .onAppear {
            Task {
                try? await viewModel.startDiscovery()
            }
        }
    }
}
