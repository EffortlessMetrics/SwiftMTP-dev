// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import XCTest
@testable import SwiftMTPSync
@testable import SwiftMTPCore
@testable import SwiftMTPIndex
@testable import SwiftMTPTestKit

final class SyncErrorHandlingTests: XCTestCase {
    private var tempDirectory: URL!
    private var dbPath: String!
    private var mirrorEngine: MirrorEngine!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        dbPath = tempDirectory.appendingPathComponent("error-tests.sqlite").path

        let snapshotter = try Snapshotter(dbPath: dbPath)
        let diffEngine = try DiffEngine(dbPath: dbPath)
        let journal = try SQLiteTransferJournal(dbPath: dbPath)
        mirrorEngine = MirrorEngine(snapshotter: snapshotter, diffEngine: diffEngine, journal: journal)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDirectory)
        mirrorEngine = nil
        dbPath = nil
        tempDirectory = nil
        try super.tearDownWithError()
    }

    func testMirrorHandlesEmptyDevice() async throws {
        let device = VirtualMTPDevice(config: .emptyDevice)
        let deviceId = await device.id

        let report = try await mirrorEngine.mirror(
            device: device,
            deviceId: deviceId,
            to: tempDirectory
        )

        XCTAssertEqual(report.downloaded, 0)
        XCTAssertEqual(report.failed, 0)
    }

    func testMirrorCountsFailuresWhenDestinationIsInvalid() async throws {
        let device = createDeviceWithSingleFile()
        let deviceId = await device.id

        let invalidRoot = tempDirectory.appendingPathComponent("not-a-directory")
        try Data([0x01]).write(to: invalidRoot)

        let report = try await mirrorEngine.mirror(
            device: device,
            deviceId: deviceId,
            to: invalidRoot
        )

        XCTAssertGreaterThanOrEqual(report.failed, 1)
    }

    func testMirrorIncludeFilterSkipsNonMatchingFiles() async throws {
        let device = createDeviceWithSingleFile(name: "song.mp3")
        let deviceId = await device.id

        let report = try await mirrorEngine.mirror(
            device: device,
            deviceId: deviceId,
            to: tempDirectory
        ) { row in
            row.pathKey.hasSuffix(".jpg")
        }

        XCTAssertEqual(report.downloaded, 0)
        XCTAssertEqual(report.skipped, 1)
    }

    private func createDeviceWithSingleFile(name: String = "photo.jpg") -> VirtualMTPDevice {
        let config = VirtualDeviceConfig.emptyDevice
            .withObject(
                VirtualObjectConfig(
                    handle: 100,
                    storage: MTPStorageID(raw: 0x0001_0001),
                    parent: nil,
                    name: name,
                    sizeBytes: 16,
                    formatCode: 0x3004,
                    data: Data(repeating: 0xAA, count: 16)
                )
            )
        return VirtualMTPDevice(config: config)
    }
}
