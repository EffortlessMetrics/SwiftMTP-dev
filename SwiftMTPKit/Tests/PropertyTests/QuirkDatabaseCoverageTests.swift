// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import XCTest
@testable import SwiftMTPQuirks

final class QuirkDatabaseCoverageTests: XCTestCase {
    func testQuirkHookBusyBackoffRoundTrip() throws {
        let backoff = QuirkHook.BusyBackoff(retries: 3, baseMs: 250, jitterPct: 0.25)
        let hook = QuirkHook(phase: .onDeviceBusy, delayMs: 50, busyBackoff: backoff)

        let data = try JSONEncoder().encode(hook)
        let decoded = try JSONDecoder().decode(QuirkHook.self, from: data)

        XCTAssertEqual(decoded.phase, .onDeviceBusy)
        XCTAssertEqual(decoded.delayMs, 50)
        XCTAssertEqual(decoded.busyBackoff?.retries, 3)
        XCTAssertEqual(decoded.busyBackoff?.baseMs, 250)
        XCTAssertNotNil(decoded.busyBackoff?.jitterPct)
        XCTAssertEqual(decoded.busyBackoff?.jitterPct ?? 0, 0.25, accuracy: 0.0001)
    }

    func testDeviceQuirkEncodeIncludesStableFields() throws {
        let hook = QuirkHook(phase: .beforeTransfer, delayMs: 10)
        let quirk = DeviceQuirk(
            id: "encode-device",
            vid: 0x18d1,
            pid: 0x4ee1,
            operations: ["supportsGetPartialObject64": true],
            hooks: [hook],
            status: "stable",
            confidence: "high"
        )

        let data = try JSONEncoder().encode(quirk)
        let payload = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        XCTAssertEqual(payload?["id"] as? String, "encode-device")
        XCTAssertEqual(payload?["status"] as? String, "stable")
        XCTAssertEqual(payload?["confidence"] as? String, "high")
        XCTAssertNotNil(payload?["hooks"])
        XCTAssertNotNil(payload?["ops"])
    }

    func testDeviceQuirkDecodeRejectsInvalidHex() {
        let invalidJSON = """
        {
          "id": "invalid-hex",
          "match": {
            "vid": "0xZZZZ",
            "pid": "0x0001"
          }
        }
        """

        XCTAssertThrowsError(try JSONDecoder().decode(DeviceQuirk.self, from: Data(invalidJSON.utf8))) { error in
            let nsError = error as NSError
            XCTAssertEqual(nsError.domain, "QuirkParsing")
        }
    }

    func testQuirkDatabaseEncodeIncludesSchemaAndEntries() throws {
        let quirk = DeviceQuirk(id: "db-entry", vid: 0x1111, pid: 0x2222)
        let database = QuirkDatabase(schemaVersion: "1.0", entries: [quirk])

        let data = try JSONEncoder().encode(database)
        let payload = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let entries = payload?["entries"] as? [[String: Any]]

        XCTAssertEqual(payload?["schemaVersion"] as? String, "1.0")
        XCTAssertEqual(entries?.count, 1)
        XCTAssertEqual(entries?.first?["id"] as? String, "db-entry")
    }

    func testMatchFallsBackWhenBCDRequirementNotMet() {
        let strict = DeviceQuirk(id: "strict", vid: 0x1111, pid: 0x2222, bcdDevice: 0x0300)
        let generic = DeviceQuirk(id: "generic", vid: 0x1111, pid: 0x2222)
        let database = QuirkDatabase(schemaVersion: "1.0", entries: [strict, generic])

        let matched = database.match(
            vid: 0x1111,
            pid: 0x2222,
            bcdDevice: nil,
            ifaceClass: nil,
            ifaceSubclass: nil,
            ifaceProtocol: nil
        )

        XCTAssertEqual(matched?.id, "generic")
    }

    func testLoadThrowsWhenNoCandidateFileExists() throws {
        let fileManager = FileManager.default
        let originalDirectory = fileManager.currentDirectoryPath
        let isolatedDirectory = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)

        try fileManager.createDirectory(at: isolatedDirectory, withIntermediateDirectories: true)
        XCTAssertTrue(fileManager.changeCurrentDirectoryPath(isolatedDirectory.path))

        defer {
            _ = fileManager.changeCurrentDirectoryPath(originalDirectory)
            try? fileManager.removeItem(at: isolatedDirectory)
        }

        let missing = isolatedDirectory.appendingPathComponent("missing-quirks.json").path
        XCTAssertThrowsError(try QuirkDatabase.load(pathEnv: missing)) { error in
            let nsError = error as NSError
            XCTAssertEqual(nsError.domain, "QuirkDatabase")
        }
    }
}
