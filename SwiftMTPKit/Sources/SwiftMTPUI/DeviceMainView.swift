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
    @State private var filesError: String?
    
    public init(device: any MTPDevice) {
        self.device = device
    }

    private var filesOutcomeLabel: String {
        if isFilesLoading {
            return "loading"
        }
        if filesError != nil {
            return "error"
        }
        return files.isEmpty ? "empty" : "ready"
    }
    
    public var body: some View {
        VStack {
            if isLoading {
                ProgressView("Loading device info...")
                    .accessibilityIdentifier(AccessibilityID.deviceLoadingIndicator)
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
                            .accessibilityIdentifier(AccessibilityID.storageSection)
                        
                        ForEach(storages, id: \.id) { storage in
                            StorageRow(
                                storage: storage,
                                accessibilityID: AccessibilityID.storageRow(storage.id.raw)
                            )
                        }
                        
                        Divider()
                        
                        // Files Section
                        HStack {
                            Text("Root Files")
                                .font(.headline)
                                .accessibilityIdentifier(AccessibilityID.filesSection)
                            if isFilesLoading {
                                ProgressView()
                                    .controlSize(.small)
                                    .accessibilityIdentifier(AccessibilityID.filesLoadingIndicator)
                            }
                        }
                        .padding(.horizontal)
                        
                        if let filesError {
                            Text(filesError)
                                .foregroundStyle(.red)
                                .padding()
                                .accessibilityIdentifier(AccessibilityID.filesErrorState)
                        } else if files.isEmpty && !isFilesLoading {
                            Text("No files found or storage empty.")
                                .foregroundStyle(.secondary)
                                .padding()
                                .accessibilityIdentifier(AccessibilityID.filesEmptyState)
                        } else {
                            VStack(spacing: 0) {
                                ForEach(files, id: \.handle) { file in
                                    FileRow(
                                        file: file,
                                        accessibilityID: AccessibilityID.fileRow(file.handle)
                                    )
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
                                Task { await loadFiles(trigger: "refresh_button") }
                            }) {
                                Label("Refresh Files", systemImage: "arrow.clockwise")
                            }
                            .buttonStyle(.bordered)
                            .accessibilityIdentifier(AccessibilityID.refreshFilesButton)
                            
                            Button(action: {}) {
                                Label("Eject", systemImage: "eject.fill")
                            }
                            .buttonStyle(.bordered)
                        }
                        .padding()
                    }
                }
                .accessibilityIdentifier(AccessibilityID.detailContainer)
            }

            Color.clear
                .frame(width: 1, height: 1)
                .accessibilityElement()
                .accessibilityIdentifier(AccessibilityID.filesOutcomeState)
                .accessibilityLabel(filesOutcomeLabel)
        }
        .task {
            do {
                storages = try await device.storages()
                UITestEventLogger.emit(
                    flow: .storageRender,
                    step: "load_storages",
                    result: "completed",
                    metadata: ["storageCount": "\(storages.count)"]
                )
            } catch {
                storages = []
                filesError = "Failed to load storages: \(error.localizedDescription)"
                UITestEventLogger.emit(
                    flow: .storageRender,
                    step: "load_storages",
                    result: "failed",
                    metadata: ["error": error.localizedDescription]
                )
            }
            isLoading = false
            await loadFiles(trigger: "initial_load")
        }
    }
    
    @MainActor
    private func loadFiles(trigger: String) async {
        UITestEventLogger.emit(
            flow: .filesRefresh,
            step: trigger,
            result: "started",
            metadata: ["storageCount": "\(storages.count)"]
        )

        guard let storage = storages.first else {
            filesError = "No storage available for listing."
            UITestEventLogger.emit(
                flow: .filesRefresh,
                step: trigger,
                result: "failed",
                metadata: ["reason": "no_storage"]
            )
            return
        }

        isFilesLoading = true
        filesError = nil
        files.removeAll()
        
        do {
            let stream = device.list(parent: nil, in: storage.id)
            for try await batch in stream {
                files.append(contentsOf: batch)
            }
            UITestEventLogger.emit(
                flow: .filesRefresh,
                step: trigger,
                result: "completed",
                metadata: ["fileCount": "\(files.count)"]
            )
        } catch {
            filesError = "Failed to load files: \(error.localizedDescription)"
            UITestEventLogger.emit(
                flow: .filesRefresh,
                step: trigger,
                result: "failed",
                metadata: ["error": error.localizedDescription]
            )
        }
        isFilesLoading = false
    }
}

struct StorageRow: View {
    let storage: MTPStorageInfo
    let accessibilityID: String
    
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
        .accessibilityIdentifier(accessibilityID)
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
    let accessibilityID: String
    
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
        .accessibilityIdentifier(accessibilityID)
    }
    
    func formatBytes(_ bytes: UInt64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useKB, .useBytes]
        formatter.countStyle = .binary
        return formatter.string(fromByteCount: Int64(bytes))
    }
}
