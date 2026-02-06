// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import SwiftUI
import SwiftMTPCore

public struct DeviceMainView: View {
    let device: any MTPDevice
    @State private var storages: [MTPStorageInfo] = []
    @State private var isLoading = true
    
    public init(device: any MTPDevice) {
        self.device = device
    }
    
    public var body: some View {
        VStack {
            if isLoading {
                ProgressView("Loading device info...")
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        // Device Header
                        HStack {
                            Image(systemName: "externaldrive.badge.checkmark")
                                .font(.system(size: 40))
                                .foregroundStyle(.blue)
                            
                            VStack(alignment: .leading) {
                                Text(device.id.raw)
                                    .font(.title)
                                    .bold()
                                Text("Connected via USB")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding()
                        
                        Divider()
                        
                        // Storage Section
                        Text("Storages")
                            .font(.headline)
                            .padding(.horizontal)
                        
                        ForEach(storages, id: \.id) { storage in
                            StorageRow(storage: storage)
                        }
                        
                        Divider()
                        
                        // Actions
                        HStack {
                            Button(action: {}) {
                                Label("Browse Files", systemImage: "folder.fill")
                            }
                            .buttonStyle(.borderedProminent)
                            
                            Button(action: {}) {
                                Label("Eject", systemImage: "eject.fill")
                            }
                            .buttonStyle(.bordered)
                        }
                        .padding()
                    }
                }
            }
        }
        .task {
            storages = (try? await device.storages()) ?? []
            isLoading = false
        }
    }
}

struct StorageRow: View {
    let storage: MTPStorageInfo
    
    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Image(systemName: "sdcard.fill")
                Text(storage.description)
                Spacer()
                Text("\(formatBytes(storage.freeBytes)) free / \(formatBytes(storage.capacityBytes))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            ProgressView(value: Double(storage.capacityBytes - storage.freeBytes), total: Double(storage.capacityBytes))
                .tint(storage.freeBytes < 1_000_000_000 ? .red : .blue)
        }
        .padding()
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(10)
        .padding(.horizontal)
    }
    
    func formatBytes(_ bytes: UInt64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useGB, .useMB]
        formatter.countStyle = .binary
        return formatter.string(fromByteCount: Int64(bytes))
    }
}
