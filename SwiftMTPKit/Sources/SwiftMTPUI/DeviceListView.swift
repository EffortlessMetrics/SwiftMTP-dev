// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import SwiftUI
import SwiftMTPCore

public struct DeviceListView: View {
    @Bindable var viewModel: DeviceViewModel
    
    public init(viewModel: DeviceViewModel) {
        self.viewModel = viewModel
    }
    
    public var body: some View {
        List(viewModel.devices, id: \.id) { device in
            HStack {
                Image(systemName: "externaldrive.fill")
                    .foregroundStyle(.tint)
                
                VStack(alignment: .leading) {
                    Text("\(device.manufacturer) \(device.model)")
                        .font(.headline)
                    Text(device.id.raw)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                if viewModel.isConnecting && viewModel.selectedDevice?.id == device.id {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .contentShape(Rectangle())
            .accessibilityIdentifier(AccessibilityID.deviceRow(device.id.raw))
            .onTapGesture {
                UITestEventLogger.emit(
                    flow: .deviceSelect,
                    step: "tap_row",
                    result: "started",
                    metadata: ["deviceId": device.id.raw]
                )
                Task {
                    await viewModel.connect(to: device)
                }
            }
        }
        .accessibilityIdentifier(AccessibilityID.deviceList)
        .navigationTitle("MTP Devices")
        .overlay {
            if viewModel.devices.isEmpty {
                ContentUnavailableView(
                    "No Devices Found",
                    systemImage: "usb.fill",
                    description: Text("Connect an MTP device to your Mac.")
                )
                .accessibilityIdentifier(AccessibilityID.noDevicesState)
            }
        }
    }
}
