// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import SwiftMTPCore

/// Mock transport that simulates libusb operations without physical hardware
public final class MockTransport: @unchecked Sendable, MTPTransport {
    private let deviceData: MockDeviceData
    private var sessionID: UInt32?
    private var isConnected = false

    public init(deviceData: MockDeviceData) {
        self.deviceData = deviceData
    }

    public func open(_ summary: MTPDeviceSummary) async throws -> MTPLink {
        // Simulate connection delay
        try await Task.sleep(nanoseconds: 100_000_000) // 100ms

        // Check if device matches our mock
        guard summary.id.raw == deviceData.deviceSummary.id.raw else {
            throw MTPError.notSupported("Mock device ID mismatch")
        }

        // Check for failure modes
        if let failureMode = deviceData.failureMode {
            switch failureMode {
            case .timeout:
                throw TransportError.timeout
            case .busy:
                throw TransportError.busy
            case .accessDenied:
                throw TransportError.accessDenied
            case .deviceDisconnected:
                throw MTPError.deviceDisconnected
            case .protocolError:
                throw MTPError.protocolError(code: 0, message: "Mock protocol error")
            }
        }

        isConnected = true
        return MockMTPLink(deviceData: deviceData, transport: self)
    }
}

/// Mock MTP link that simulates USB bulk transfers
final class MockMTPLink: @unchecked Sendable, MTPLink {
    private let deviceData: MockDeviceData
    private weak var transport: MockTransport?
    private var sessionID: UInt32?

    init(deviceData: MockDeviceData, transport: MockTransport) {
        self.deviceData = deviceData
        self.transport = transport
    }

    func close() async {
        // Simulate cleanup
        transport = nil
    }

    /// Handle MTP command execution
    func executeCommand(_ command: PTPContainer) throws -> Data? {
        switch command.code {
        case PTPOp.getDeviceInfo.rawValue:
            return try handleGetDeviceInfo()
        case PTPOp.openSession.rawValue:
            return try handleOpenSession(command.params.first ?? 0)
        case PTPOp.getStorageIDs.rawValue:
            return try handleGetStorageIDs()
        case PTPOp.getStorageInfo.rawValue:
            return try handleGetStorageInfo(command.params.first ?? 0)
        case PTPOp.getObjectHandles.rawValue:
            return try handleGetObjectHandles(storageID: command.params.first ?? 0,
                                             parentHandle: command.params.count > 1 ? command.params[1] : 0xFFFFFFFF)
        case PTPOp.getObjectInfo.rawValue:
            return try handleGetObjectInfo(command.params.first ?? 0)
        default:
            throw MTPError.protocolError(code: 0x2005, message: "Operation not supported: \(command.code)")
        }
    }

    /// Handle streaming MTP command execution for file transfers
    func executeStreamingCommand(
        _ command: PTPContainer,
        dataInHandler: MTPDataIn?,
        dataOutHandler: MTPDataOut?
    ) async throws -> Data? {
        switch command.code {
        case PTPOp.getObject.rawValue:
            return try await handleGetObject(command.params.first ?? 0, dataInHandler: dataInHandler)
        case PTPOp.sendObjectInfo.rawValue:
            return try await handleSendObjectInfo(dataOutHandler: dataOutHandler)
        case PTPOp.sendObject.rawValue:
            return try await handleSendObject(dataOutHandler: dataOutHandler)
        case PTPOp.getPartialObject64.rawValue:
            return try await handleGetPartialObject64(
                handle: command.params[0],
                offsetLow: command.params[1],
                offsetHigh: command.params[2],
                length: command.params[3],
                dataInHandler: dataInHandler
            )
        case PTPOp.sendPartialObject.rawValue:
            return try await handleSendPartialObject(
                handle: command.params[0],
                offsetLow: command.params[1],
                offsetHigh: command.params[2],
                dataOutHandler: dataOutHandler
            )
        default:
            throw MTPError.protocolError(code: 0x2005, message: "Streaming operation not supported: \(command.code)")
        }
    }

    private func handleGetDeviceInfo() throws -> Data {
        // Create MTP DeviceInfo dataset
        var data = Data()

        // Standard Version (2 bytes)
        data.append(contentsOf: withUnsafeBytes(of: deviceData.deviceInfo.operationsSupported.count == 0 ? UInt16(100) : UInt16(100)) { Data($0) })

        // Vendor Extension ID (4 bytes)
        data.append(contentsOf: withUnsafeBytes(of: UInt32(0x00000006)) { Data($0) }) // Microsoft

        // Vendor Extension Version (2 bytes)
        data.append(contentsOf: withUnsafeBytes(of: UInt16(100)) { Data($0) })

        // Vendor Extension Description (string)
        let vendorDesc = "Microsoft Device"
        data.append(PTPString.encode(vendorDesc))

        // Functional Mode (2 bytes)
        data.append(contentsOf: withUnsafeBytes(of: UInt16(0)) { Data($0) })

        // Operations Supported (array)
        let opsCount = UInt32(deviceData.operationsSupported.count)
        data.append(contentsOf: withUnsafeBytes(of: opsCount) { Data($0) })
        for op in deviceData.operationsSupported {
            data.append(contentsOf: withUnsafeBytes(of: op) { Data($0) })
        }

        // Events Supported (array)
        let eventsCount = UInt32(deviceData.eventsSupported.count)
        data.append(contentsOf: withUnsafeBytes(of: eventsCount) { Data($0) })
        for event in deviceData.eventsSupported {
            data.append(contentsOf: withUnsafeBytes(of: event) { Data($0) })
        }

        // Device Properties Supported (empty array)
        data.append(contentsOf: withUnsafeBytes(of: UInt32(0)) { Data($0) })

        // Capture Formats (empty array)
        data.append(contentsOf: withUnsafeBytes(of: UInt32(0)) { Data($0) })

        // Playback Formats (empty array)
        data.append(contentsOf: withUnsafeBytes(of: UInt32(0)) { Data($0) })

        // Manufacturer (string)
        data.append(PTPString.encode(deviceData.deviceInfo.manufacturer))

        // Model (string)
        data.append(PTPString.encode(deviceData.deviceInfo.model))

        // Device Version (string)
        data.append(PTPString.encode(deviceData.deviceInfo.version))

        // Serial Number (string)
        data.append(PTPString.encode(deviceData.deviceInfo.serialNumber ?? ""))

        return data
    }

    private func handleOpenSession(_ sessionID: UInt32) throws -> Data? {
        self.sessionID = sessionID
        // OpenSession has no data phase, just response
        return nil
    }

    private func handleGetStorageIDs() throws -> Data {
        var data = Data()
        let storageIDs = deviceData.storages.map { $0.id.raw }

        // Number of storages (4 bytes)
        data.append(contentsOf: withUnsafeBytes(of: UInt32(storageIDs.count)) { Data($0) })

        // Storage IDs
        for storageID in storageIDs {
            data.append(contentsOf: withUnsafeBytes(of: storageID) { Data($0) })
        }

        return data
    }

    private func handleGetStorageInfo(_ storageID: UInt32) throws -> Data {
        guard let storage = deviceData.storages.first(where: { $0.id.raw == storageID }) else {
            throw MTPError.objectNotFound
        }

        var data = Data()

        // Storage Type (2 bytes)
        data.append(contentsOf: withUnsafeBytes(of: UInt16(0x0003)) { Data($0) }) // Removable RAM

        // Filesystem Type (2 bytes)
        data.append(contentsOf: withUnsafeBytes(of: UInt16(0x0002)) { Data($0) }) // Generic Hierarchical

        // Access Capability (2 bytes)
        data.append(contentsOf: withUnsafeBytes(of: storage.isReadOnly ? UInt16(0x0001) : UInt16(0x0000)) { Data($0) })

        // Max Capacity (8 bytes)
        data.append(contentsOf: withUnsafeBytes(of: storage.capacityBytes) { Data($0) })

        // Free Space (8 bytes)
        data.append(contentsOf: withUnsafeBytes(of: storage.freeBytes) { Data($0) })

        // Free Space in Objects (4 bytes)
        data.append(contentsOf: withUnsafeBytes(of: UInt32(0xFFFFFFFF)) { Data($0) })

        // Storage Description (string)
        data.append(PTPString.encode(storage.description))

        // Volume Label (string)
        data.append(PTPString.encode("Mock Storage"))

        return data
    }

    private func handleGetObjectHandles(storageID: UInt32, parentHandle: UInt32) throws -> Data {
        let objects = deviceData.objects.filter { obj in
            obj.storage.raw == storageID &&
            (parentHandle == 0xFFFFFFFF ? obj.parent == nil : obj.parent == parentHandle)
        }

        var data = Data()

        // Number of objects (4 bytes)
        data.append(contentsOf: withUnsafeBytes(of: UInt32(objects.count)) { Data($0) })

        // Object handles
        for object in objects {
            data.append(contentsOf: withUnsafeBytes(of: object.handle) { Data($0) })
        }

        return data
    }

    private func handleGetObjectInfo(_ handle: UInt32) throws -> Data {
        guard let object = deviceData.objects.first(where: { $0.handle == handle }) else {
            throw MTPError.objectNotFound
        }

        var data = Data()

        // Storage ID (4 bytes)
        data.append(contentsOf: withUnsafeBytes(of: object.storage.raw) { Data($0) })

        // Format Code (2 bytes)
        data.append(contentsOf: withUnsafeBytes(of: object.formatCode) { Data($0) })

        // Protection Status (2 bytes)
        data.append(contentsOf: withUnsafeBytes(of: UInt16(0)) { Data($0) })

        // Object Compressed Size (4 bytes)
        data.append(contentsOf: withUnsafeBytes(of: UInt32(object.size ?? 0)) { Data($0) })

        // Thumb Format (2 bytes)
        data.append(contentsOf: withUnsafeBytes(of: UInt16(0)) { Data($0) })

        // Thumb Compressed Size (4 bytes)
        data.append(contentsOf: withUnsafeBytes(of: UInt32(0)) { Data($0) })

        // Thumb Width (4 bytes)
        data.append(contentsOf: withUnsafeBytes(of: UInt32(0)) { Data($0) })

        // Thumb Height (4 bytes)
        data.append(contentsOf: withUnsafeBytes(of: UInt32(0)) { Data($0) })

        // Image Width (4 bytes)
        data.append(contentsOf: withUnsafeBytes(of: UInt32(0)) { Data($0) })

        // Image Height (4 bytes)
        data.append(contentsOf: withUnsafeBytes(of: UInt32(0)) { Data($0) })

        // Image Bit Depth (4 bytes)
        data.append(contentsOf: withUnsafeBytes(of: UInt32(0)) { Data($0) })

        // Parent Object (4 bytes)
        data.append(contentsOf: withUnsafeBytes(of: object.parent ?? 0) { Data($0) })

        // Association Type (2 bytes)
        data.append(contentsOf: withUnsafeBytes(of: UInt16(0)) { Data($0) })

        // Association Description (4 bytes)
        data.append(contentsOf: withUnsafeBytes(of: UInt32(0)) { Data($0) })

        // Sequence Number (4 bytes)
        data.append(contentsOf: withUnsafeBytes(of: UInt32(0)) { Data($0) })

        // Filename (string)
        data.append(PTPString.encode(object.name))

        // Capture Date (string)
        data.append(PTPString.encode(""))

        // Modification Date (string)
        data.append(PTPString.encode(""))

        // Keywords (string)
        data.append(PTPString.encode(""))

        return data
    }

    private func handleGetObject(_ handle: UInt32, dataInHandler: ((UnsafeRawBufferPointer) -> Int)?) async throws -> Data? {
        guard let object = deviceData.objects.first(where: { $0.handle == handle }) else {
            throw MTPError.objectNotFound
        }

        // Generate mock file content based on object size
        let size = Int(object.size ?? 1024)
        var mockData = Data(count: size)
        for i in 0..<size {
            mockData[i] = UInt8(i % 256)
        }

        // Simulate streaming the data to the handler
        if let dataInHandler = dataInHandler {
            let chunkSize = 8192 // 8KB chunks
            var offset = 0
            while offset < mockData.count {
                let remaining = mockData.count - offset
                let chunkSizeActual = min(chunkSize, remaining)
                let chunk = mockData[offset..<offset + chunkSizeActual]
                chunk.withUnsafeBytes { buf in
                    _ = dataInHandler(UnsafeRawBufferPointer(buf))
                }
                offset += chunkSizeActual

                // Simulate some delay for realism
                try await Task.sleep(nanoseconds: 1_000_000) // 1ms delay
            }
        }

        return nil // No response data for GetObject
    }

    private func handleSendObjectInfo(dataOutHandler: ((UnsafeMutableRawBufferPointer) -> Int)?) async throws -> Data? {
        // For mock, we just simulate receiving object info data
        // In a real implementation, this would parse the ObjectInfo dataset
        if let dataOutHandler = dataOutHandler {
            // Mock: expect some data to be written
            var buffer = [UInt8](repeating: 0, count: 1024)
            _ = buffer.withUnsafeMutableBytes { buf in
                dataOutHandler(buf)
            }
            // Process the object info data here if needed
        }

        // Return new object handle (mock value)
        let newHandle: UInt32 = 0x00010001
        var responseData = Data()
        responseData.append(contentsOf: withUnsafeBytes(of: newHandle) { Data($0) })
        return responseData
    }

    private func handleSendObject(dataOutHandler: ((UnsafeMutableRawBufferPointer) -> Int)?) async throws -> Data? {
        // Simulate receiving file data
        if let dataOutHandler = dataOutHandler {
            var totalReceived = 0
            var buffer = [UInt8](repeating: 0, count: 8192)
            while true {
                let bytesRead = buffer.withUnsafeMutableBytes { buf in
                    dataOutHandler(buf)
                }
                if bytesRead == 0 { break }
                totalReceived += bytesRead
                // In real implementation, you'd store this data

                // Simulate processing delay
                try await Task.sleep(nanoseconds: 1_000_000) // 1ms delay
            }
        }
        return nil
    }

    private func handleGetPartialObject64(handle: UInt32, offsetLow: UInt32, offsetHigh: UInt32, length: UInt32, dataInHandler: MTPDataIn?) async throws -> Data? {
        let offset = UInt64(offsetLow) | (UInt64(offsetHigh) << 32)
        let requestedLength = Int(length)

        guard let object = deviceData.objects.first(where: { $0.handle == handle }) else {
            throw MTPError.objectNotFound
        }

        let totalSize = Int(object.size ?? 1024)
        let startOffset = Int(offset)
        let endOffset = min(startOffset + requestedLength, totalSize)
        let actualLength = endOffset - startOffset

        // Generate partial mock data
        var mockData = Data(count: actualLength)
        for i in 0..<actualLength {
            mockData[i] = UInt8((startOffset + i) % 256)
        }

        // Stream the partial data
        if let dataInHandler = dataInHandler {
            mockData.withUnsafeBytes { buf in
                _ = dataInHandler(buf)
            }
        }

        return nil
    }

    private func handleSendPartialObject(handle: UInt32, offsetLow: UInt32, offsetHigh: UInt32, dataOutHandler: MTPDataOut?) async throws -> Data? {
        _ = UInt64(offsetLow) | (UInt64(offsetHigh) << 32)

        // Simulate receiving partial data at the given offset
        if let dataOutHandler = dataOutHandler {
            var buffer = [UInt8](repeating: 0, count: 8192)
            _ = buffer.withUnsafeMutableBytes { buf in
                dataOutHandler(buf)
            }
            // In real implementation, you'd append this data at the offset
        }

        return nil
    }
}

// Extend MockMTPLink to implement the MTP protocol simulation
extension MockMTPLink {
    func getDeviceInfo(timeoutMs: Int = 10_000) throws -> Data {
        let cmd = PTPContainer(length: 12, type: PTPContainer.Kind.command.rawValue,
                               code: PTPOp.getDeviceInfo.rawValue, txid: 1, params: [])

        // Simulate command phase
        let _ = cmd.encode(into: UnsafeMutablePointer<UInt8>.allocate(capacity: 16))

        // Return data phase
        return try handleGetDeviceInfo()
    }

    func openSession(sessionID: UInt32, timeoutMs: Int = 10_000) throws {
        let cmd = PTPContainer(length: 16, type: PTPContainer.Kind.command.rawValue,
                               code: PTPOp.openSession.rawValue, txid: 1, params: [sessionID])

        // Simulate command phase
        let _ = cmd.encode(into: UnsafeMutablePointer<UInt8>.allocate(capacity: 16))

        // Handle session opening
        let _ = try handleOpenSession(sessionID)
    }
}
