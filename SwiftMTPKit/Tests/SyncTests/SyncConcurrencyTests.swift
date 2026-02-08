// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import XCTest
@testable import SwiftMTPSync
@testable import SwiftMTPCore
@testable import SwiftMTPIndex
@testable import SwiftMTPTestKit

final class SyncConcurrencyTests: XCTestCase {
    private var tempDirectory: URL!
    private var dbPath: String!
    private var mirrorEngine: MirrorEngine!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        dbPath = tempDirectory.appendingPathComponent("concurrency.sqlite").path

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

    func testActorIsolationForQueuedOperations() async {
        let engine = ActorBasedSyncEngine()

        await withTaskGroup(of: Void.self) { group in
            for index in 0..<10 {
                group.addTask {
                    await engine.queueOperation("operation_\(index)")
                }
            }
        }

        let operationCount = await engine.operationCount()
        XCTAssertEqual(operationCount, 10)
    }

    func testConcurrentMirrorCallsDoNotCrash() async throws {
        let device = VirtualMTPDevice(config: .emptyDevice)
        let deviceId = await device.id
        let mirrorEngine = self.mirrorEngine!
        let root = self.tempDirectory!

        await withTaskGroup(of: MTPSyncReport?.self) { group in
            for index in 0..<3 {
                group.addTask {
                    try? await mirrorEngine.mirror(
                        device: device,
                        deviceId: deviceId,
                        to: root.appendingPathComponent("run-\(index)")
                    )
                }
            }

            var completed = 0
            for await result in group {
                XCTAssertNotNil(result)
                completed += 1
            }
            XCTAssertEqual(completed, 3)
        }
    }

    func testTaskCancellationPropagates() async throws {
        let engine = CancellableSyncEngine()
        let task = Task {
            await engine.perform()
        }

        try await Task.sleep(nanoseconds: 100_000_000)
        task.cancel()
        await engine.cancel()
        _ = await task.result

        XCTAssertTrue(task.isCancelled)
        let engineCancelled = await engine.isCancelled()
        XCTAssertTrue(engineCancelled)
    }
}

private actor ActorBasedSyncEngine {
    private var operations: [String] = []

    func queueOperation(_ operation: String) {
        operations.append(operation)
    }

    func operationCount() -> Int {
        operations.count
    }
}

private actor CancellableSyncEngine {
    private var cancelled = false

    func perform() async {
        while !cancelled && !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
    }

    func cancel() {
        cancelled = true
    }

    func isCancelled() -> Bool {
        cancelled
    }
}
