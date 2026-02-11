// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import XCTest
@testable import SwiftMTPCore
@testable import SwiftMTPTestKit

final class TestKitCoverageTests: XCTestCase {
    private func makeConfig() -> VirtualDeviceConfig {
        var config = VirtualDeviceConfig.emptyDevice
        let storage = config.storages[0].id
        config = config.withObject(
            VirtualObjectConfig(
                handle: 10,
                storage: storage,
                parent: nil,
                name: "folder",
                formatCode: 0x3001
            )
        )
        config = config.withObject(
            VirtualObjectConfig(
                handle: 11,
                storage: storage,
                parent: 10,
                name: "file.txt",
                data: Data("hello world".utf8)
            )
        )
        return config
    }

    func testVirtualMTPLinkCoversHappyAndErrorPaths() async throws {
        let config = makeConfig()
        let storage = config.storages[0].id
        let link = VirtualMTPLink(config: config)

        try await link.openUSBIfNeeded()
        try await link.openSession(id: 1)
        try await link.closeSession()
        await link.close()

        let info = try await link.getDeviceInfo()
        XCTAssertEqual(info.manufacturer, "Virtual")

        let storageIDs = try await link.getStorageIDs()
        XCTAssertEqual(storageIDs, [storage])

        let storageInfo = try await link.getStorageInfo(id: storage)
        XCTAssertEqual(storageInfo.description, "Internal storage")
        do {
            _ = try await link.getStorageInfo(id: MTPStorageID(raw: 999))
            XCTFail("Expected missing storage to throw")
        } catch {
            XCTAssertTrue("\(error)".contains("not found"))
        }

        let rootHandles = try await link.getObjectHandles(storage: storage, parent: nil)
        XCTAssertEqual(rootHandles, [10])
        let childHandles = try await link.getObjectHandles(storage: storage, parent: 10)
        XCTAssertEqual(childHandles, [11])

        let infosByHandle = try await link.getObjectInfos([10, 11])
        XCTAssertEqual(infosByHandle.count, 2)
        let infosByFilter = try await link.getObjectInfos(storage: storage, parent: 10, format: 0x3000)
        XCTAssertEqual(infosByFilter.count, 1)
        XCTAssertEqual(infosByFilter[0].handle, 11)

        try await link.deleteObject(handle: 11)
        do {
            try await link.deleteObject(handle: 9999)
            XCTFail("Expected missing object to throw")
        } catch {
            XCTAssertTrue("\(error)".contains("not found"))
        }

        try await link.moveObject(handle: 10, to: storage, parent: nil)
        do {
            try await link.moveObject(handle: 9999, to: storage, parent: nil)
            XCTFail("Expected missing object to throw")
        } catch {
            XCTAssertTrue("\(error)".contains("not found"))
        }

        let commandResponse = try await link.executeCommand(
            PTPContainer(type: 1, code: 0x1001, txid: 42, params: [])
        )
        XCTAssertEqual(commandResponse.code, 0x2001)
        XCTAssertEqual(commandResponse.txid, 42)

        let streamingResponse = try await link.executeStreamingCommand(
            PTPContainer(type: 1, code: 0x1009, txid: 43, params: []),
            dataPhaseLength: 16,
            dataInHandler: nil,
            dataOutHandler: nil
        )
        XCTAssertEqual(streamingResponse.code, 0x2001)
        XCTAssertEqual(streamingResponse.txid, 43)

        try await link.resetDevice()
    }

    func testFaultInjectingLinkCoversInjectionAndForwarding() async throws {
        let config = makeConfig()
        let storage = config.storages[0].id
        let base = VirtualMTPLink(config: config)
        let schedule = FaultSchedule([
            .timeoutOnce(on: .openSession),
            .pipeStall(on: .getStorageIDs),
        ])
        let link = FaultInjectingLink(wrapping: base, schedule: schedule)

        XCTAssertNil(link.cachedDeviceInfo)
        XCTAssertNil(link.linkDescriptor)

        try await link.openUSBIfNeeded()
        do {
            try await link.openSession(id: 7)
            XCTFail("Expected scheduled fault")
        } catch {
            XCTAssertTrue("\(error)".contains("timeout"))
        }
        // Fault consumed; second call should succeed.
        try await link.openSession(id: 7)

        do {
            _ = try await link.getStorageIDs()
            XCTFail("Expected scheduled pipe stall")
        } catch {
            XCTAssertTrue("\(error)".contains("pipe") || "\(error)".contains("stall"))
        }
        let storageIDs = try await link.getStorageIDs()
        XCTAssertEqual(storageIDs, [storage])

        link.scheduleFault(.timeoutOnce(on: .executeCommand))
        do {
            _ = try await link.executeCommand(PTPContainer(type: 1, code: 0x1001, txid: 1, params: []))
            XCTFail("Expected injected executeCommand timeout")
        } catch {
            XCTAssertTrue("\(error)".contains("timeout"))
        }

        _ = try await link.executeStreamingCommand(
            PTPContainer(type: 1, code: 0x1009, txid: 2, params: []),
            dataPhaseLength: nil,
            dataInHandler: nil,
            dataOutHandler: nil
        )
        try await link.closeSession()
        await link.close()
    }

    func testTranscriptRecorderAndReplayRoundTrip() async throws {
        let link = VirtualMTPLink(config: makeConfig())
        let recorder = TranscriptRecorder(wrapping: link)

        try await recorder.openUSBIfNeeded()
        try await recorder.openSession(id: 5)
        _ = try await recorder.getDeviceInfo()
        _ = try await recorder.getStorageIDs()
        do {
            try await recorder.deleteObject(handle: 9999)
            XCTFail("Expected recorder to capture thrown error")
        } catch {
            XCTAssertTrue("\(error)".contains("not found"))
        }
        await recorder.close()

        let transcript = recorder.transcript()
        XCTAssertEqual(transcript.count, 6)
        XCTAssertEqual(transcript[0].operation, "openUSBIfNeeded")

        let json = try recorder.exportJSON()
        let replay = try TranscriptReplayLink(json: json)

        try await replay.openUSBIfNeeded()
        try await replay.openSession(id: 5)
        _ = try await replay.getDeviceInfo()
        let storageIDs = try await replay.getStorageIDs()
        XCTAssertEqual(storageIDs.count, 1)
        do {
            try await replay.deleteObject(handle: 9999)
            XCTFail("Expected replayed error")
        } catch {
            XCTAssertTrue("\(error)".contains("Replayed error"))
        }
        await replay.close()
        do {
            _ = try await replay.getStorageIDs()
            XCTFail("Expected transcript exhaustion")
        } catch {
            XCTAssertTrue("\(error)".contains("Transcript exhausted"))
        }
    }

    func testTranscriptReplayCoversAllOperations() async throws {
        let entries: [TranscriptEntry] = [
            TranscriptEntry(operation: "openUSBIfNeeded"),
            TranscriptEntry(operation: "openSession"),
            TranscriptEntry(operation: "getStorageInfo"),
            TranscriptEntry(operation: "getObjectHandles", response: TranscriptData(dataSize: 2)),
            TranscriptEntry(operation: "getObjectInfos", response: TranscriptData(dataSize: 2)),
            TranscriptEntry(operation: "getObjectInfos", response: TranscriptData(dataSize: 1)),
            TranscriptEntry(operation: "executeCommand", response: TranscriptData(code: 0x2001, params: [1, 2])),
            TranscriptEntry(operation: "executeStreamingCommand", response: TranscriptData(code: 0x2001, params: [3, 4])),
            TranscriptEntry(operation: "moveObject"),
            TranscriptEntry(operation: "resetDevice"),
            TranscriptEntry(operation: "closeSession"),
            TranscriptEntry(operation: "close"),
        ]

        let replay = TranscriptReplayLink(transcript: entries)
        try await replay.openUSBIfNeeded()
        try await replay.openSession(id: 9)
        let storageInfo = try await replay.getStorageInfo(id: MTPStorageID(raw: 7))
        XCTAssertEqual(storageInfo.id.raw, 7)

        let handles = try await replay.getObjectHandles(storage: MTPStorageID(raw: 1), parent: nil)
        XCTAssertEqual(handles, [1, 2])
        let infosByHandles = try await replay.getObjectInfos([100, 200])
        XCTAssertEqual(infosByHandles.count, 2)
        XCTAssertEqual(infosByHandles[0].handle, 100)
        let infosByFilter = try await replay.getObjectInfos(storage: MTPStorageID(raw: 1), parent: 10, format: 0x3001)
        XCTAssertEqual(infosByFilter.count, 1)
        XCTAssertEqual(infosByFilter[0].parent, 10)

        let execute = try await replay.executeCommand(PTPContainer(type: 1, code: 0x1001, txid: 3, params: []))
        XCTAssertEqual(execute.code, 0x2001)
        XCTAssertEqual(execute.params, [1, 2])
        let executeStreaming = try await replay.executeStreamingCommand(
            PTPContainer(type: 1, code: 0x1009, txid: 4, params: []),
            dataPhaseLength: 4,
            dataInHandler: nil,
            dataOutHandler: nil
        )
        XCTAssertEqual(executeStreaming.code, 0x2001)
        XCTAssertEqual(executeStreaming.params, [3, 4])

        try await replay.moveObject(handle: 1, to: MTPStorageID(raw: 1), parent: nil)
        try await replay.resetDevice()
        try await replay.closeSession()
        await replay.close()
    }

    func testVirtualMTPDeviceMutationReadWriteAndEvents() async throws {
        let device = VirtualMTPDevice(config: makeConfig())
        let storages = try await device.storages()
        let storageId = try XCTUnwrap(storages.first?.id)

        try await device.openIfNeeded()
        let createdFolder = try await device.createFolder(parent: nil, name: "Created", storage: storageId)
        XCTAssertGreaterThan(createdFolder, 0)

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("swiftmtp-testkit-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let sourceURL = tempDir.appendingPathComponent("upload.txt")
        try Data("payload".utf8).write(to: sourceURL)
        _ = try await device.write(parent: createdFolder, name: "upload.txt", size: 7, from: sourceURL)

        var listedChildren: [MTPObjectInfo] = []
        for try await batch in device.list(parent: createdFolder, in: storageId) {
            listedChildren.append(contentsOf: batch)
        }
        let uploaded = try XCTUnwrap(listedChildren.first)
        XCTAssertEqual(uploaded.name, "upload.txt")

        let downloadURL = tempDir.appendingPathComponent("download.bin")
        _ = try await device.read(handle: uploaded.handle, range: 0..<4, to: downloadURL)
        XCTAssertEqual(try Data(contentsOf: downloadURL), Data("payl".utf8))

        try await device.move(uploaded.handle, to: nil)
        try await device.delete(uploaded.handle, recursive: false)
        do {
            _ = try await device.getInfo(handle: uploaded.handle)
            XCTFail("Expected deleted object lookup to fail")
        } catch let error as MTPError {
            XCTAssertEqual(error, .objectNotFound)
        }

        let added = VirtualObjectConfig(
            handle: 777,
            storage: storageId,
            parent: nil,
            name: "runtime.bin",
            data: Data([1, 2, 3, 4])
        )
        await device.addObject(added)
        _ = try await device.devGetObjectInfoUncached(handle: 777)
        await device.removeObject(handle: 777)
        do {
            _ = try await device.devGetObjectInfoUncached(handle: 777)
            XCTFail("Expected removed object to be missing")
        } catch let error as MTPError {
            XCTAssertEqual(error, .objectNotFound)
        }

        let rootHandles = try await device.devGetRootHandlesUncached(storage: storageId)
        XCTAssertFalse(rootHandles.isEmpty)
        let storageIDs = try await device.devGetStorageIDsUncached()
        XCTAssertEqual(storageIDs, [storageId])
        _ = try await device.devGetDeviceInfoUncached()

        await device.injectEvent(.objectAdded(1234))
        let eventTask = Task { () -> MTPEvent? in
            for await event in device.events {
                return event
            }
            return nil
        }
        let event = await eventTask.value
        if case .objectAdded(let handle)? = event {
            XCTAssertEqual(handle, 1234)
        } else {
            XCTFail("Expected injected objectAdded event")
        }

        let operations = await device.operations
        XCTAssertFalse(operations.isEmpty)
        await device.clearOperations()
        let operationLogIsEmpty = await device.operations.isEmpty
        XCTAssertTrue(operationLogIsEmpty)

        try await device.devClose()
    }
}
