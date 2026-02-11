// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import XCTest
@testable import SwiftMTPFileProvider
import SwiftMTPCore
import FileProvider

final class FileProviderDomainTests: XCTestCase {

    func testStableDeviceIdentityProperties() {
        let createdAt = Date(timeIntervalSince1970: 1_700_000_000)
        let lastSeenAt = Date(timeIntervalSince1970: 1_700_000_060)
        let identity = StableDeviceIdentity(
            domainId: "device-123",
            displayName: "My Device",
            createdAt: createdAt,
            lastSeenAt: lastSeenAt
        )

        XCTAssertEqual(identity.domainId, "device-123")
        XCTAssertEqual(identity.displayName, "My Device")
        XCTAssertEqual(identity.createdAt, createdAt)
        XCTAssertEqual(identity.lastSeenAt, lastSeenAt)
    }

    func testDomainIdentifierConstruction() {
        let domainId = "mtp-device-abc123"
        let domainIdentifier = NSFileProviderDomainIdentifier(domainId)

        XCTAssertEqual(domainIdentifier.rawValue, domainId)
    }

    func testDomainWithDisplayName() {
        let domainId = "named-device"
        let displayName = "Google Pixel 7"
        let domain = NSFileProviderDomain(
            identifier: NSFileProviderDomainIdentifier(domainId),
            displayName: displayName
        )

        XCTAssertEqual(domain.identifier.rawValue, domainId)
        XCTAssertEqual(domain.displayName, displayName)
    }

    func testDomainFromStableIdentity() {
        let identity = StableDeviceIdentity(
            domainId: "test-device-001",
            displayName: "Test Device",
            createdAt: Date(),
            lastSeenAt: Date()
        )

        let domainID = NSFileProviderDomainIdentifier(identity.domainId)
        let domain = NSFileProviderDomain(identifier: domainID, displayName: identity.displayName)

        XCTAssertEqual(domain.identifier.rawValue, "test-device-001")
        XCTAssertEqual(domain.displayName, "Test Device")
    }
}
