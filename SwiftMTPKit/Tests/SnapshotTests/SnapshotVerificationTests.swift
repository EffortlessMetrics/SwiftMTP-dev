// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import XCTest
import SwiftMTPCore

final class SnapshotVerificationTests: XCTestCase {
    func testLoadSnapshot() throws {
        let filename = "snapshot-OnePlus-ONEPLUS_A3010.json"
        let fileURL = URL(fileURLWithPath: filename)
        
        guard FileManager.default.fileExists(atPath: filename) else {
            print("⚠️ Skipping snapshot test: \(filename) not found")
            return
        }
        
        let data = try Data(contentsOf: fileURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        let snapshot = try decoder.decode(MTPSnapshot.self, from: data)
        
        XCTAssertEqual(snapshot.deviceInfo.manufacturer, "OnePlus")
        XCTAssertEqual(snapshot.deviceInfo.model, "ONEPLUS A3010")
        XCTAssertGreaterThan(snapshot.objects.count, 0)
        
        // Verify re-serialization
        let reSerialized = try snapshot.jsonString()
        XCTAssertFalse(reSerialized.isEmpty)
    }
}
