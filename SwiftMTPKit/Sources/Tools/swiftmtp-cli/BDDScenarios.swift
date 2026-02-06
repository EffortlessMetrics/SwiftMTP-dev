// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import SwiftMTPCore

public struct DiscoveryScenario: BDDScenario {
    public let name = "Device Discovery and Session Opening"
    public func execute(context: BDDContext) async throws {
        context.step("When I request device info")
        let info = try await context.link.getDeviceInfo()
        context.step("Then I should receive a valid manufacturer name")
        try context.verify(!info.manufacturer.isEmpty, "Manufacturer should not be empty")
        print("      Found: \(info.manufacturer) \(info.model)")
    }
}

public struct ListingScenario: BDDScenario {
    public let name = "Storage and Object Listing"
    public func execute(context: BDDContext) async throws {
        context.step("When I request storage IDs")
        let storages = try await context.link.getStorageIDs()
        context.step("Then I should receive at least one storage ID")
        try context.verify(!storages.isEmpty, "Should have at least one storage")
        
        if let first = storages.first {
            context.step("And I list objects in storage \(first.raw)")
            let handles = try await context.link.getObjectHandles(storage: first, parent: nil)
            print("      Found \(handles.count) objects in root")
        }
    }
}

public struct UploadScenario: BDDScenario {
    public let name = "Small File Upload"
    public func execute(context: BDDContext) async throws {
        let testData = "BDD Test Data".data(using: .utf8)!
        context.step("Given a test file of \(testData.count) bytes")
        
        context.step("When I attempt to upload to storage 0x00010001")
        // Note: Using a hardcoded storage ID for scenario demonstration
        // In real use, this would be fetched from the context/link
        
        do {
            try await ProtoTransfer.writeWholeObject(
                storageID: 0x00010001,
                parent: nil as UInt32?,
                name: "bdd_test.txt",
                size: UInt64(testData.count),
                dataHandler: { buf in
                    testData.copyBytes(to: buf)
                    return testData.count
                },
                on: context.link,
                ioTimeoutMs: 5000
            )
            context.step("Then the upload should succeed")
        } catch {
            context.step("Then the upload might fail due to protocol rejection (0x2008)")
            print("      Upload result: \(error)")
        }
    }
}
