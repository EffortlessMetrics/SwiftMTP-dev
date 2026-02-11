// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import XCTest
@testable import SwiftMTPCore

/// Integration tests for FileProvider with LiveIndex.
/// These tests require the FileProvider sandbox and are skipped in normal CI.
@available(macOS 15.0, *)
final class FileProviderIntegrationTests: XCTestCase {

  // MARK: - LiveIndex Integration Tests

  func testLiveIndexIntegration() async throws {
    // TODO: Correct API: SQLiteLiveIndex.appGroupIndex(readOnly:)
    throw XCTSkip("Requires FileProvider sandbox")
  }

  func testNSFileProviderExtensionAPI() async throws {
    // TODO: MTPFileProviderExtension is only available inside the extension target
    throw XCTSkip("Requires FileProvider sandbox")
  }

  func testChangeSignaling() async throws {
    // TODO: ChangeSignaler requires a valid domain; correct API is via MTPFileProviderManager
    throw XCTSkip("Requires FileProvider sandbox")
  }

  func testContainerMounting() async throws {
    // TODO: MTPFileProviderManager.shared.registerDomain(identity:) is the real API
    throw XCTSkip("Requires FileProvider sandbox")
  }

  // MARK: - Domain Enumeration Tests

  func testDomainEnumeration() async throws {
    throw XCTSkip("Requires FileProvider sandbox")
  }

  func testItemEnumeration() async throws {
    throw XCTSkip("Requires FileProvider sandbox")
  }
}

// MARK: - Change Signaler Tests

@available(macOS 15.0, *)
final class ChangeSignalerTests: XCTestCase {

  func testChangeBatchProcessing() async throws {
    throw XCTSkip("Requires FileProvider sandbox")
  }

  func testChangeAcknowledgment() async throws {
    throw XCTSkip("Requires FileProvider sandbox")
  }
}

// MARK: - File Provider Manager Tests

@available(macOS 15.0, *)
final class FileProviderManagerTests: XCTestCase {

  func testMultipleDeviceManagement() async throws {
    throw XCTSkip("Requires FileProvider sandbox")
  }

  func testDeviceServiceLifecycle() async throws {
    throw XCTSkip("Requires FileProvider sandbox")
  }
}
