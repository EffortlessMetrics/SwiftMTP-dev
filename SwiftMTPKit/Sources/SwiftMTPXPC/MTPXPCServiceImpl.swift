// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import SwiftMTPCore
import SwiftMTPTransportLibUSB

/// Implementation of the XPC service that handles File Provider requests
/// This runs in the host app and bridges to the MTP device manager
@MainActor
public final class MTPXPCServiceImpl: NSObject, MTPXPCService {
    private let deviceManager: MTPDeviceManager
    private let tempDirectory: URL

    public init(deviceManager: MTPDeviceManager = .shared) {
        self.deviceManager = deviceManager

        // Use app group container for temp files that File Provider can access
        let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.example.SwiftMTP")
        self.tempDirectory = containerURL?.appendingPathComponent("FileProviderTemp") ?? FileManager.default.temporaryDirectory.appendingPathComponent("SwiftMTP-FP")

        super.init()

        // Ensure temp directory exists
        try? FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    public func ping(reply: @escaping (String) -> Void) {
        reply("MTP XPC Service is running")
    }

    public func readObject(_ request: ReadRequest, withReply reply: @escaping (ReadResponse) -> Void) {
        Task {
            do {
                let deviceId = MTPDeviceID(raw: request.deviceId)

                // Find the device (this would need to be enhanced to track active devices)
                // For now, we'll assume the device is already connected
                guard let device = try await findDevice(with: deviceId) else {
                    reply(ReadResponse(success: false, errorMessage: "Device not found or not connected"))
                    return
                }

                // Create a temp file for the download
                let tempURL = tempDirectory.appendingPathComponent(UUID().uuidString)

                // Read the object to temp file
                _ = try await device.read(handle: request.objectHandle, range: nil, to: tempURL)
                
                // Wait for the download by polling progress or using a better sync mechanism
                // For simplicity in this refactor, we wait a bit or check file existence
                // In real implementation, the device.read returns a MTPProgress which we can await
                
                // Get file size
                let attributes = try FileManager.default.attributesOfItem(atPath: tempURL.path)
                let fileSize = attributes[.size] as? UInt64

                reply(ReadResponse(success: true, tempFileURL: tempURL, fileSize: fileSize))

            } catch {
                reply(ReadResponse(success: false, errorMessage: error.localizedDescription))
            }
        }
    }

    public func listStorages(_ request: StorageListRequest, withReply reply: @escaping (StorageListResponse) -> Void) {
        Task {
            do {
                let deviceId = MTPDeviceID(raw: request.deviceId)

                guard let device = try await findDevice(with: deviceId) else {
                    reply(StorageListResponse(success: false, errorMessage: "Device not found or not connected"))
                    return
                }

                let storages = try await device.storages()
                let storageInfos = storages.map { storage in
                    StorageInfo(
                        storageId: storage.id.raw,
                        description: storage.description,
                        capacityBytes: storage.capacityBytes,
                        freeBytes: storage.freeBytes
                    )
                }

                reply(StorageListResponse(success: true, storages: storageInfos))

            } catch {
                reply(StorageListResponse(success: false, errorMessage: error.localizedDescription))
            }
        }
    }

    public func listObjects(_ request: ObjectListRequest, withReply reply: @escaping (ObjectListResponse) -> Void) {
        Task {
            do {
                let deviceId = MTPDeviceID(raw: request.deviceId)

                guard let device = try await findDevice(with: deviceId) else {
                    reply(ObjectListResponse(success: false, errorMessage: "Device not found or not connected"))
                    return
                }

                let storageId = MTPStorageID(raw: request.storageId)
                let stream = device.list(parent: request.parentHandle, in: storageId)

                var objects: [ObjectInfo] = []
                for try await objectInfos in stream {
                    for objectInfo in objectInfos {
                        let object = ObjectInfo(
                            handle: objectInfo.handle,
                            name: objectInfo.name,
                            sizeBytes: objectInfo.sizeBytes,
                            isDirectory: objectInfo.formatCode == 0x3001,
                            modifiedDate: objectInfo.modified
                        )
                        objects.append(object)
                    }
                }

                reply(ObjectListResponse(success: true, objects: objects))

            } catch {
                reply(ObjectListResponse(success: false, errorMessage: error.localizedDescription))
            }
        }
    }

    public func getObjectInfo(deviceId: String, storageId: UInt32, objectHandle: UInt32, withReply reply: @escaping (ReadResponse) -> Void) {
        Task {
            do {
                let deviceId = MTPDeviceID(raw: deviceId)

                guard let device = try await findDevice(with: deviceId) else {
                    reply(ReadResponse(success: false, errorMessage: "Device not found or not connected"))
                    return
                }

                let objectInfo = try await device.getInfo(handle: objectHandle)

                // For getObjectInfo, we return metadata in the response
                // The tempFileURL would be nil since we're not downloading
                reply(ReadResponse(
                    success: true,
                    tempFileURL: nil,
                    fileSize: objectInfo.sizeBytes
                ))

            } catch {
                reply(ReadResponse(success: false, errorMessage: error.localizedDescription))
            }
        }
    }

    // Helper method to find a connected device
    private func findDevice(with deviceId: MTPDeviceID) async throws -> MTPDevice? {
        let devices = try await deviceManager.currentRealDevices()
        return devices.first { $0.summary.id == deviceId }
    }

    /// Clean up old temp files to prevent disk space issues
    public func cleanupOldTempFiles(olderThan hours: Double = 24) {
        let cutoffDate = Date(timeIntervalSinceNow: -hours * 3600)

        guard let enumerator = FileManager.default.enumerator(at: tempDirectory, includingPropertiesForKeys: [.creationDateKey]) else {
            return
        }

        for case let url as URL in enumerator {
            do {
                let attributes = try url.resourceValues(forKeys: [.creationDateKey])
                if let creationDate = attributes.creationDate, creationDate < cutoffDate {
                    try FileManager.default.removeItem(at: url)
                }
            } catch {
                // Ignore cleanup errors
                continue
            }
        }
    }
}
