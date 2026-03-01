// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import XCTest

@testable import SwiftMTPUI
import SwiftMTPCore
import SwiftMTPTestKit
import SwiftUI

// MARK: - AccessibilityID Tests

final class AccessibilityIDTests: XCTestCase {

  func testStaticIdentifiers() {
    XCTAssertEqual(AccessibilityID.browserRoot, "swiftmtp.browser.root")
    XCTAssertEqual(AccessibilityID.discoveryState, "swiftmtp.discovery.state")
    XCTAssertEqual(AccessibilityID.demoModeButton, "swiftmtp.demo.button")
    XCTAssertEqual(AccessibilityID.discoveryErrorBanner, "swiftmtp.discovery.error")
    XCTAssertEqual(AccessibilityID.deviceList, "swiftmtp.device.list")
    XCTAssertEqual(AccessibilityID.noDevicesState, "swiftmtp.device.empty")
    XCTAssertEqual(AccessibilityID.noSelectionState, "swiftmtp.selection.empty")
  }

  func testDetailIdentifiers() {
    XCTAssertEqual(AccessibilityID.detailContainer, "swiftmtp.detail.container")
    XCTAssertEqual(AccessibilityID.deviceLoadingIndicator, "swiftmtp.device.loading")
    XCTAssertEqual(AccessibilityID.storageSection, "swiftmtp.storage.section")
    XCTAssertEqual(AccessibilityID.filesSection, "swiftmtp.files.section")
    XCTAssertEqual(AccessibilityID.filesLoadingIndicator, "swiftmtp.files.loading")
    XCTAssertEqual(AccessibilityID.filesEmptyState, "swiftmtp.files.empty")
    XCTAssertEqual(AccessibilityID.filesErrorState, "swiftmtp.files.error")
    XCTAssertEqual(AccessibilityID.filesOutcomeState, "swiftmtp.files.outcome")
    XCTAssertEqual(AccessibilityID.refreshFilesButton, "swiftmtp.files.refresh")
  }

  func testDeviceRowIdentifier() {
    let id = AccessibilityID.deviceRow("18d1:4ee1@1:2")
    XCTAssertEqual(id, "swiftmtp.device.row.18d1_4ee1_1_2")
  }

  func testDeviceRowSanitization() {
    let id = AccessibilityID.deviceRow("foo/bar baz!@#$%")
    // Non-alphanumeric (except ._-) chars become _
    XCTAssertFalse(id.contains("/"))
    XCTAssertFalse(id.contains(" "))
    XCTAssertFalse(id.contains("!"))
    XCTAssertTrue(id.hasPrefix("swiftmtp.device.row."))
  }

  func testDeviceRowAlphanumericPassthrough() {
    let id = AccessibilityID.deviceRow("abc-123_test.ok")
    XCTAssertEqual(id, "swiftmtp.device.row.abc-123_test.ok")
  }

  func testStorageRowIdentifier() {
    let id = AccessibilityID.storageRow(0x0001_0001)
    XCTAssertEqual(id, "swiftmtp.storage.row.65537")
  }

  func testFileRowIdentifier() {
    let id = AccessibilityID.fileRow(42)
    XCTAssertEqual(id, "swiftmtp.file.row.42")
  }

  func testFileRowZeroHandle() {
    let id = AccessibilityID.fileRow(0)
    XCTAssertEqual(id, "swiftmtp.file.row.0")
  }

  func testDeviceRowEmptyString() {
    let id = AccessibilityID.deviceRow("")
    XCTAssertEqual(id, "swiftmtp.device.row.")
  }
}

// MARK: - UXFlowID Tests

final class UXFlowIDTests: XCTestCase {

  func testAllCasesExist() {
    // Ensure we have all expected flows
    XCTAssertGreaterThanOrEqual(UXFlowID.allCases.count, 19)
  }

  func testRawValuePrefix() {
    for flow in UXFlowID.allCases {
      XCTAssertTrue(flow.rawValue.hasPrefix("ux."), "Flow \(flow) missing 'ux.' prefix")
    }
  }

  func testKnownFlowRawValues() {
    XCTAssertEqual(UXFlowID.launchEmptyState.rawValue, "ux.launch.empty_state")
    XCTAssertEqual(UXFlowID.demoToggle.rawValue, "ux.demo.toggle")
    XCTAssertEqual(UXFlowID.deviceListVisible.rawValue, "ux.device.list.visible")
    XCTAssertEqual(UXFlowID.deviceSelect.rawValue, "ux.device.select")
    XCTAssertEqual(UXFlowID.storageRender.rawValue, "ux.storage.render")
    XCTAssertEqual(UXFlowID.filesRefresh.rawValue, "ux.files.refresh")
    XCTAssertEqual(UXFlowID.errorDiscovery.rawValue, "ux.error.discovery")
    XCTAssertEqual(UXFlowID.detachSelectionReset.rawValue, "ux.detach.selection_reset")
  }

  func testUniqueRawValues() {
    let rawValues = UXFlowID.allCases.map(\.rawValue)
    XCTAssertEqual(rawValues.count, Set(rawValues).count, "Duplicate raw values detected")
  }
}

// MARK: - UITestConfiguration Tests

final class UITestConfigurationTests: XCTestCase {

  func testDefaultConfiguration() {
    let config = UITestConfiguration.current
    // Without env vars, UI test should be disabled
    XCTAssertFalse(config.enabled)
    XCTAssertFalse(config.scenario.isEmpty)
    XCTAssertFalse(config.mockProfile.isEmpty)
  }

  func testDefaultMockProfile() {
    let config = UITestConfiguration.current
    // Default profile when no env var set
    XCTAssertEqual(config.mockProfile, "pixel7")
  }

  func testDefaultScenario() {
    let config = UITestConfiguration.current
    XCTAssertEqual(config.scenario, "mock-default")
  }

  func testArtifactDirectoryIsDefined() {
    let config = UITestConfiguration.current
    XCTAssertFalse(config.artifactDirectory.path.isEmpty)
  }

  func testRunIdentifierIsNonEmpty() {
    let config = UITestConfiguration.current
    XCTAssertFalse(config.runIdentifier.isEmpty)
  }
}

// MARK: - DeviceViewModel Tests

final class DeviceViewModelTests: XCTestCase {

  @MainActor
  func testInitialState() {
    let coordinator = DeviceLifecycleCoordinator()
    let viewModel = DeviceViewModel(coordinator: coordinator)

    XCTAssertTrue(viewModel.devices.isEmpty)
    XCTAssertNil(viewModel.selectedDevice)
    XCTAssertFalse(viewModel.isConnecting)
    XCTAssertNil(viewModel.error)
  }

  @MainActor
  func testErrorCanBeSet() {
    let coordinator = DeviceLifecycleCoordinator()
    let viewModel = DeviceViewModel(coordinator: coordinator)

    viewModel.error = "Test error"
    XCTAssertEqual(viewModel.error, "Test error")
  }

  @MainActor
  func testErrorCanBeCleared() {
    let coordinator = DeviceLifecycleCoordinator()
    let viewModel = DeviceViewModel(coordinator: coordinator)

    viewModel.error = "Something went wrong"
    viewModel.error = nil
    XCTAssertNil(viewModel.error)
  }

  @MainActor
  func testDevicesReflectsCoordinator() {
    let coordinator = DeviceLifecycleCoordinator()
    let viewModel = DeviceViewModel(coordinator: coordinator)
    // Fresh coordinator has no devices
    XCTAssertEqual(viewModel.devices.count, 0)
  }
}

// MARK: - View Instantiation Tests

final class ViewInstantiationTests: XCTestCase {

  @MainActor
  func testDeviceBrowserViewDefaultInit() {
    // Verify default initializer doesn't crash
    let view = DeviceBrowserView()
    XCTAssertNotNil(view)
    _ = view.body
  }

  @MainActor
  func testDeviceBrowserViewCoordinatorInit() {
    let coordinator = DeviceLifecycleCoordinator()
    let view = DeviceBrowserView(coordinator: coordinator)
    XCTAssertNotNil(view)
    _ = view.body
  }

  @MainActor
  func testDeviceListViewInit() {
    let coordinator = DeviceLifecycleCoordinator()
    let viewModel = DeviceViewModel(coordinator: coordinator)
    let view = DeviceListView(viewModel: viewModel)
    XCTAssertNotNil(view)
    _ = view.body
  }

  @MainActor
  func testDeviceMainViewInit() async throws {
    let config = VirtualDeviceConfig.pixel7
    let device = VirtualMTPDevice(config: config)
    let view = DeviceMainView(device: device)
    XCTAssertNotNil(view)
  }

  @MainActor
  func testDeviceListViewEmptyDevices() {
    let coordinator = DeviceLifecycleCoordinator()
    let viewModel = DeviceViewModel(coordinator: coordinator)
    let view = DeviceListView(viewModel: viewModel)
    // Empty devices → should render without crash
    _ = view.body
    XCTAssertTrue(viewModel.devices.isEmpty)
  }
}

// MARK: - StorageRow / FileRow Tests

final class StorageAndFileRowTests: XCTestCase {

  @MainActor
  func testStorageRowInit() {
    let storage = MTPStorageInfo(
      id: MTPStorageID(raw: 0x0001_0001),
      description: "Internal Storage",
      capacityBytes: 128_000_000_000,
      freeBytes: 64_000_000_000,
      isReadOnly: false
    )
    let row = StorageRow(storage: storage, accessibilityID: "test.storage.row")
    XCTAssertNotNil(row)
    _ = row.body
  }

  @MainActor
  func testFileRowInitForFile() {
    let file = MTPObjectInfo(
      handle: 1,
      storage: MTPStorageID(raw: 0x0001_0001),
      parent: nil,
      name: "photo.jpg",
      sizeBytes: 4_500_000,
      modified: nil,
      formatCode: 0x3801,
      properties: [:]
    )
    let row = FileRow(file: file, accessibilityID: "test.file.row")
    XCTAssertNotNil(row)
    _ = row.body
  }

  @MainActor
  func testFileRowInitForFolder() {
    let folder = MTPObjectInfo(
      handle: 2,
      storage: MTPStorageID(raw: 0x0001_0001),
      parent: nil,
      name: "DCIM",
      sizeBytes: nil,
      modified: nil,
      formatCode: 0x3001,
      properties: [:]
    )
    let row = FileRow(file: folder, accessibilityID: "test.folder.row")
    XCTAssertNotNil(row)
    _ = row.body
  }

  @MainActor
  func testStorageRowLowFreeSpace() {
    let storage = MTPStorageInfo(
      id: MTPStorageID(raw: 0x0001_0001),
      description: "Full Storage",
      capacityBytes: 128_000_000_000,
      freeBytes: 500_000_000,  // < 1GB → triggers red tint path
      isReadOnly: false
    )
    let row = StorageRow(storage: storage, accessibilityID: "test.storage.low")
    _ = row.body
  }

  @MainActor
  func testFileRowZeroSizeFile() {
    let file = MTPObjectInfo(
      handle: 10,
      storage: MTPStorageID(raw: 0x0001_0001),
      parent: nil,
      name: "empty.txt",
      sizeBytes: 0,
      modified: nil,
      formatCode: 0x3000,
      properties: [:]
    )
    let row = FileRow(file: file, accessibilityID: "test.file.zero")
    _ = row.body
  }
}

// MARK: - DeviceLifecycleCoordinator Tests

final class DeviceLifecycleCoordinatorTests: XCTestCase {

  @MainActor
  func testInitialCoordinatorState() {
    let coordinator = DeviceLifecycleCoordinator()
    XCTAssertTrue(coordinator.discoveredDevices.isEmpty)
    XCTAssertTrue(coordinator.openedDevices.isEmpty)
    XCTAssertNil(coordinator.selectedDevice)
    XCTAssertFalse(coordinator.isConnecting)
    XCTAssertNil(coordinator.error)
  }

  @MainActor
  func testShutdownClearsState() async {
    let coordinator = DeviceLifecycleCoordinator()
    coordinator.error = "some error"
    await coordinator.shutdown()
    XCTAssertNil(coordinator.selectedDevice)
    XCTAssertTrue(coordinator.discoveredDevices.isEmpty)
    XCTAssertTrue(coordinator.openedDevices.isEmpty)
  }
}
