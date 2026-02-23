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

    public init() {
        self.init(coordinator: DeviceLifecycleCoordinator())
    }

    private var discoveryStateLabel: String {
        if viewModel.error != nil {
            return "error"
        }
        return viewModel.devices.isEmpty ? "empty" : "ready"
    }

    private func handleDemoToggle() {
        isDemoMode.toggle()
        FeatureFlags.shared.useMockTransport = isDemoMode
        UITestEventLogger.emit(
            flow: .demoToggle,
            step: "toggle",
            result: isDemoMode ? "enabled" : "disabled",
            metadata: ["state": isDemoMode ? "on" : "off"]
        )
        Task {
            do {
                try await viewModel.startDiscovery()
                UITestEventLogger.emit(
                    flow: .demoToggle,
                    step: "rediscovery",
                    result: "completed",
                    metadata: ["state": isDemoMode ? "on" : "off"]
                )
            } catch {
                viewModel.error = "Failed to refresh discovery: \(error.localizedDescription)"
                UITestEventLogger.emit(
                    flow: .demoToggle,
                    step: "rediscovery",
                    result: "failed",
                    metadata: ["error": error.localizedDescription]
                )
            }
        }
    }

    public var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: handleDemoToggle) {
                    Label("Demo Mode", systemImage: isDemoMode ? "play.circle.fill" : "play.circle")
                        .foregroundStyle(isDemoMode ? .orange : .secondary)
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier(AccessibilityID.demoModeButton)
                .help("Toggle Simulation Mode")
                Spacer()
            }
            .padding(.horizontal)
            .padding(.top, 8)
            .padding(.bottom, 4)

            if let error = viewModel.error {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(Color.red.opacity(0.08))
                .accessibilityIdentifier(AccessibilityID.discoveryErrorBanner)
            }

            NavigationSplitView {
                DeviceListView(viewModel: viewModel)
                    .toolbar {
                        ToolbarItem {
                            Button(action: handleDemoToggle) {
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
                        .accessibilityIdentifier(AccessibilityID.noSelectionState)
                }
            }

            Color.clear
                .frame(width: 1, height: 1)
                .accessibilityElement()
                .accessibilityIdentifier(AccessibilityID.discoveryState)
                .accessibilityLabel(discoveryStateLabel)
        }
        .accessibilityIdentifier(AccessibilityID.browserRoot)
        .onAppear {
            Task {
                do {
                    try await viewModel.startDiscovery()
                    UITestEventLogger.emit(
                        flow: .launchEmptyState,
                        step: "on_appear",
                        result: "completed",
                        metadata: ["state": discoveryStateLabel]
                    )
                } catch {
                    viewModel.error = "Failed to start discovery: \(error.localizedDescription)"
                    UITestEventLogger.emit(
                        flow: .launchEmptyState,
                        step: "on_appear",
                        result: "failed",
                        metadata: ["error": error.localizedDescription]
                    )
                }
            }
        }
    }
}
