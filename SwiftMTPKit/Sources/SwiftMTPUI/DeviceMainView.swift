// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import SwiftUI
import SwiftMTPCore

public struct DeviceMainView: View {
    let device: any MTPDevice
    @State private var storages: [MTPStorageInfo] = []
    @State private var files: [MTPObjectInfo] = []
    @State private var isLoading = true
    @State private var isFilesLoading = false
    
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
                        
                        // Files Section
                        HStack {
                            Text("Root Files")
                                .font(.headline)
                            if isFilesLoading {
                                ProgressView().controlSize(.small)
                            }
                        }
                        .padding(.horizontal)
                        
                        if files.isEmpty && !isFilesLoading {
                            Text("No files found or storage empty.")
                                .foregroundStyle(.secondary)
                                .padding()
                        } else {
                            VStack(spacing: 0) {
                                ForEach(files, id: \.handle) { file in
                                    FileRow(file: file)
                                    Divider().padding(.leading, 44)
                                }
                            }
                            .background(Color.secondary.opacity(0.05))
                            .cornerRadius(10)
                            .padding(.horizontal)
                        }
                        
                        Divider()
                        
                        // Actions
                        HStack {
                            Button(action: {
                                Task { await loadFiles() }
                            }) {
                                Label("Refresh Files", systemImage: "arrow.clockwise")
                            }
                            .buttonStyle(.bordered)
                            
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
            await loadFiles()
        }
    }
    
    @MainActor
    private func loadFiles() async {
        guard let storage = storages.first else { return }
        isFilesLoading = true
        files.removeAll()
        
        do {
            let stream = device.list(parent: nil, in: storage.id)
            for try await batch in stream {
                files.append(contentsOf: batch)
            }
        } catch {
            print("Failed to load files: \(error)")
        }
        isFilesLoading = false
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

struct FileRow: View {
    let file: MTPObjectInfo
    
    var body: some View {
        HStack {
            Image(systemName: file.formatCode == 0x3001 ? "folder.fill" : "doc.fill")
                .foregroundStyle(file.formatCode == 0x3001 ? .yellow : .secondary)
                .frame(width: 24)
            
            VStack(alignment: .leading) {
                Text(file.name)
                    .font(.body)
                if let size = file.sizeBytes {
                    Text(formatBytes(size))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding(.vertical, 8)
        .padding(.horizontal)
    }
    
    func formatBytes(_ bytes: UInt64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useKB, .useBytes]
        formatter.countStyle = .binary
        return formatter.string(fromByteCount: Int64(bytes))
    }
}