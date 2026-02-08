// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import XCTest
@testable import SwiftMTPFileProvider
import SwiftMTPCore
import FileProvider

final class FileProviderChangeSignalingTests: XCTestCase {

    func testParseStorageRootIdentifier() {
        let identifier = NSFileProviderItemIdentifier("device1:1")
        let parsed = MTPFileProviderItem.parseItemIdentifier(identifier)

        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed?.deviceId, "device1")
        XCTAssertEqual(parsed?.storageId, 1)
        XCTAssertNil(parsed?.objectHandle)
    }

    func testParseObjectIdentifier() {
        let identifier = NSFileProviderItemIdentifier("device1:1:100")
        let parsed = MTPFileProviderItem.parseItemIdentifier(identifier)

        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed?.deviceId, "device1")
        XCTAssertEqual(parsed?.storageId, 1)
        XCTAssertEqual(parsed?.objectHandle, 100)
    }

    func testWorkingSetIdentifierValue() {
        XCTAssertFalse(NSFileProviderItemIdentifier.workingSet.rawValue.isEmpty)
    }

    func testParentHandleIdentifierMapping() {
        let parentHandles: Set<MTPObjectHandle?> = [nil, 100, 200, 300]
        let identifiers = parentHandles.map { parentHandle -> NSFileProviderItemIdentifier in
            if let parentHandle {
                return NSFileProviderItemIdentifier("device1:1:\(parentHandle)")
            }
            return NSFileProviderItemIdentifier("device1:1")
        }

        XCTAssertEqual(identifiers.count, 4)
        XCTAssertTrue(identifiers.contains(NSFileProviderItemIdentifier("device1:1")))
        XCTAssertTrue(identifiers.contains(NSFileProviderItemIdentifier("device1:1:100")))
        XCTAssertTrue(identifiers.contains(NSFileProviderItemIdentifier("device1:1:200")))
        XCTAssertTrue(identifiers.contains(NSFileProviderItemIdentifier("device1:1:300")))
    }

    func testChangeSignalerInitialization() {
        if #available(macOS 11.0, *) {
            let signaler = ChangeSignaler(domainIdentifier: NSFileProviderDomainIdentifier("initialize-test-domain"))
            XCTAssertNotNil(signaler)
        }
    }
}
