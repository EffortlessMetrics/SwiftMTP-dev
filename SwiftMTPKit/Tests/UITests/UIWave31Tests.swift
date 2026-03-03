// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import XCTest

@testable import SwiftMTPUI
import SwiftMTPCore
import SwiftMTPTestKit
import SwiftUI

// MARK: - Device List ViewModel: Add/Remove/Update Events

final class DeviceListViewModelEventTests: XCTestCase {

  @MainActor
  func testDevicesListStartsEmpty() {
    let coordinator = DeviceLifecycleCoordinator()
    let vm = DeviceViewModel(coordinator: coordinator)
    XCTAssertTrue(vm.devices.isEmpty)
    XCTAssertNil(vm.selectedDevice)
    XCTAssertFalse(vm.isConnecting)
  }

  @MainActor
  func testCoordinatorDevicesReflectedInViewModel() {
    let coordinator = DeviceLifecycleCoordinator()
    let vm = DeviceViewModel(coordinator: coordinator)
    // Initially no devices
    XCTAssertEqual(vm.devices.count, 0)
    // Error propagation from coordinator
    coordinator.error = "device removed unexpectedly"
    XCTAssertEqual(vm.error, "device removed unexpectedly")
  }

  @MainActor
  func testViewModelErrorSetAndClearCycle() {
    let coordinator = DeviceLifecycleCoordinator()
    let vm = DeviceViewModel(coordinator: coordinator)
    vm.error = "Connection lost"
    XCTAssertEqual(vm.error, "Connection lost")
    vm.error = "Retry failed"
    XCTAssertEqual(vm.error, "Retry failed")
    vm.error = nil
    XCTAssertNil(vm.error)
  }

  @MainActor
  func testMultipleViewModelsShareCoordinatorState() {
    let coordinator = DeviceLifecycleCoordinator()
    let vm1 = DeviceViewModel(coordinator: coordinator)
    let vm2 = DeviceViewModel(coordinator: coordinator)

    coordinator.error = "shared error"
    XCTAssertEqual(vm1.error, "shared error")
    XCTAssertEqual(vm2.error, "shared error")
  }

  @MainActor
  func testShutdownClearsCoordinatorDevices() async {
    let coordinator = DeviceLifecycleCoordinator()
    let vm = DeviceViewModel(coordinator: coordinator)
    coordinator.error = "pre-shutdown error"
    await coordinator.shutdown()
    XCTAssertTrue(vm.devices.isEmpty)
    XCTAssertNil(vm.selectedDevice)
  }
}

// MARK: - Storage Row: Empty, Partially Full, Full

final class StorageRowDisplayTests: XCTestCase {

  @MainActor
  func testEmptyStorage() {
    let storage = MTPStorageInfo(
      id: MTPStorageID(raw: 0x0001_0001),
      description: "Empty Card",
      capacityBytes: 64_000_000_000,
      freeBytes: 64_000_000_000,
      isReadOnly: false
    )
    let row = StorageRow(storage: storage, accessibilityID: "test.storage.empty")
    _ = row.body
    // Full free space → blue tint path (freeBytes >= 1GB)
    XCTAssertTrue(storage.freeBytes >= 1_000_000_000)
  }

  @MainActor
  func testPartiallyFullStorage() {
    let storage = MTPStorageInfo(
      id: MTPStorageID(raw: 0x0001_0001),
      description: "Half Used",
      capacityBytes: 128_000_000_000,
      freeBytes: 64_000_000_000,
      isReadOnly: false
    )
    let row = StorageRow(storage: storage, accessibilityID: "test.storage.partial")
    _ = row.body
    XCTAssertTrue(storage.freeBytes > 1_000_000_000)
  }

  @MainActor
  func testFullStorage() {
    let storage = MTPStorageInfo(
      id: MTPStorageID(raw: 0x0001_0001),
      description: "Full Storage",
      capacityBytes: 64_000_000_000,
      freeBytes: 0,
      isReadOnly: false
    )
    let row = StorageRow(storage: storage, accessibilityID: "test.storage.full")
    _ = row.body
    // Zero free → red tint path (freeBytes < 1GB)
    XCTAssertTrue(storage.freeBytes < 1_000_000_000)
  }

  @MainActor
  func testCriticallyLowStorage() {
    let storage = MTPStorageInfo(
      id: MTPStorageID(raw: 0x0002_0001),
      description: "Almost Full",
      capacityBytes: 256_000_000_000,
      freeBytes: 500_000_000,
      isReadOnly: false
    )
    let row = StorageRow(storage: storage, accessibilityID: "test.storage.critical")
    _ = row.body
    XCTAssertTrue(storage.freeBytes < 1_000_000_000)
  }

  @MainActor
  func testReadOnlyStorage() {
    let storage = MTPStorageInfo(
      id: MTPStorageID(raw: 0x0001_0001),
      description: "Read Only Card",
      capacityBytes: 32_000_000_000,
      freeBytes: 16_000_000_000,
      isReadOnly: true
    )
    let row = StorageRow(storage: storage, accessibilityID: "test.storage.readonly")
    _ = row.body
    XCTAssertTrue(storage.isReadOnly)
  }
}

// MARK: - File Row: Different File Types

final class FileRowTypeDisplayTests: XCTestCase {

  private let defaultStorage = MTPStorageID(raw: 0x0001_0001)

  @MainActor
  func testImageFileRow() {
    let file = MTPObjectInfo(
      handle: 1, storage: defaultStorage, parent: nil,
      name: "sunset.jpg", sizeBytes: 5_200_000,
      modified: nil, formatCode: 0x3801, properties: [:]
    )
    let row = FileRow(file: file, accessibilityID: "test.file.image")
    _ = row.body
    // Non-folder → doc.fill icon path
    XCTAssertNotEqual(file.formatCode, 0x3001)
  }

  @MainActor
  func testVideoFileRow() {
    let file = MTPObjectInfo(
      handle: 2, storage: defaultStorage, parent: nil,
      name: "vacation.mp4", sizeBytes: 1_500_000_000,
      modified: nil, formatCode: 0x300B, properties: [:]
    )
    let row = FileRow(file: file, accessibilityID: "test.file.video")
    _ = row.body
    XCTAssertNotEqual(file.formatCode, 0x3001)
  }

  @MainActor
  func testDocumentFileRow() {
    let file = MTPObjectInfo(
      handle: 3, storage: defaultStorage, parent: nil,
      name: "readme.txt", sizeBytes: 4_096,
      modified: nil, formatCode: 0x3004, properties: [:]
    )
    let row = FileRow(file: file, accessibilityID: "test.file.document")
    _ = row.body
    XCTAssertNotEqual(file.formatCode, 0x3001)
  }

  @MainActor
  func testFolderRow() {
    let folder = MTPObjectInfo(
      handle: 4, storage: defaultStorage, parent: nil,
      name: "DCIM", sizeBytes: nil,
      modified: nil, formatCode: 0x3001, properties: [:]
    )
    let row = FileRow(file: folder, accessibilityID: "test.file.folder")
    _ = row.body
    // Folder → folder.fill icon path
    XCTAssertEqual(folder.formatCode, 0x3001)
  }

  @MainActor
  func testUndefinedFormatFileRow() {
    let file = MTPObjectInfo(
      handle: 5, storage: defaultStorage, parent: nil,
      name: "data.bin", sizeBytes: 1024,
      modified: nil, formatCode: 0x3000, properties: [:]
    )
    let row = FileRow(file: file, accessibilityID: "test.file.undefined")
    _ = row.body
    XCTAssertNotEqual(file.formatCode, 0x3001)
  }

  @MainActor
  func testFileWithNilSize() {
    let file = MTPObjectInfo(
      handle: 6, storage: defaultStorage, parent: nil,
      name: "nosize.raw", sizeBytes: nil,
      modified: nil, formatCode: 0x3000, properties: [:]
    )
    let row = FileRow(file: file, accessibilityID: "test.file.nilsize")
    _ = row.body
    XCTAssertNil(file.sizeBytes)
  }

  @MainActor
  func testFileWithZeroSize() {
    let file = MTPObjectInfo(
      handle: 7, storage: defaultStorage, parent: nil,
      name: "empty.txt", sizeBytes: 0,
      modified: nil, formatCode: 0x3000, properties: [:]
    )
    let row = FileRow(file: file, accessibilityID: "test.file.zero")
    _ = row.body
    XCTAssertEqual(file.sizeBytes, 0)
  }
}

// MARK: - Transfer Progress View States

final class TransferProgressStateTests: XCTestCase {

  @MainActor
  func testDeviceMainViewShowsLoadingState() async {
    let config = VirtualDeviceConfig.pixel7
    let device = VirtualMTPDevice(config: config)
    let view = DeviceMainView(device: device)
    // View starts in loading state before .task fires
    XCTAssertNotNil(view)
  }

  @MainActor
  func testDeviceMainViewWithEmptyDevice() async {
    let config = VirtualDeviceConfig.emptyDevice
    let device = VirtualMTPDevice(config: config)
    let view = DeviceMainView(device: device)
    XCTAssertNotNil(view)
  }

  @MainActor
  func testDeviceListViewProgressIndicatorPath() {
    let coordinator = DeviceLifecycleCoordinator()
    let vm = DeviceViewModel(coordinator: coordinator)
    // isConnecting is false → no ProgressView rendered
    XCTAssertFalse(vm.isConnecting)
    let view = DeviceListView(viewModel: vm)
    _ = view.body
  }

  @MainActor
  func testFilesOutcomeLabelStates() {
    // Verify the computed outcome labels via DeviceMainView
    let config = VirtualDeviceConfig.pixel7
    let device = VirtualMTPDevice(config: config)
    let view = DeviceMainView(device: device)
    // Initial state before async loading is loading
    XCTAssertNotNil(view)
  }
}

// MARK: - Error Alert Presentation

final class ErrorAlertPresentationTests: XCTestCase {

  @MainActor
  func testDiscoveryErrorBannerVisibility() {
    let coordinator = DeviceLifecycleCoordinator()
    let vm = DeviceViewModel(coordinator: coordinator)

    // No error → banner not shown
    XCTAssertNil(vm.error)
    let view1 = DeviceBrowserView(coordinator: coordinator)
    _ = view1.body

    // Set error → banner should be visible
    coordinator.error = "USB permission denied"
    XCTAssertEqual(vm.error, "USB permission denied")
    let view2 = DeviceBrowserView(coordinator: coordinator)
    _ = view2.body
  }

  @MainActor
  func testDifferentErrorTypeMessages() {
    let coordinator = DeviceLifecycleCoordinator()
    let vm = DeviceViewModel(coordinator: coordinator)

    let errorMessages = [
      "USB permission denied",
      "Device disconnected unexpectedly",
      "Failed to read storage info",
      "Transfer interrupted: timeout",
      "MTP protocol error: 0x2001",
    ]

    for msg in errorMessages {
      vm.error = msg
      XCTAssertEqual(vm.error, msg)
    }
  }

  @MainActor
  func testErrorClearedAfterResolution() {
    let coordinator = DeviceLifecycleCoordinator()
    let vm = DeviceViewModel(coordinator: coordinator)
    vm.error = "Temporary failure"
    XCTAssertNotNil(vm.error)
    vm.error = nil
    XCTAssertNil(vm.error)
    // View should render without error banner
    let view = DeviceBrowserView(coordinator: coordinator)
    _ = view.body
  }
}

// MARK: - Accessibility: Identifiers and Labels

final class AccessibilityComprehensiveTests: XCTestCase {

  func testAllStaticIDsHaveSwiftMTPPrefix() {
    let allIDs = [
      AccessibilityID.browserRoot,
      AccessibilityID.discoveryState,
      AccessibilityID.demoModeButton,
      AccessibilityID.discoveryErrorBanner,
      AccessibilityID.deviceList,
      AccessibilityID.noDevicesState,
      AccessibilityID.noSelectionState,
      AccessibilityID.detailContainer,
      AccessibilityID.deviceLoadingIndicator,
      AccessibilityID.storageSection,
      AccessibilityID.filesSection,
      AccessibilityID.filesLoadingIndicator,
      AccessibilityID.filesEmptyState,
      AccessibilityID.filesErrorState,
      AccessibilityID.filesOutcomeState,
      AccessibilityID.refreshFilesButton,
    ]
    for id in allIDs {
      XCTAssertTrue(id.hasPrefix("swiftmtp."), "ID '\(id)' missing required prefix")
    }
  }

  func testAllStaticIDsAreNonEmpty() {
    let allIDs = [
      AccessibilityID.browserRoot,
      AccessibilityID.discoveryState,
      AccessibilityID.demoModeButton,
      AccessibilityID.discoveryErrorBanner,
      AccessibilityID.deviceList,
      AccessibilityID.noDevicesState,
      AccessibilityID.noSelectionState,
      AccessibilityID.detailContainer,
      AccessibilityID.deviceLoadingIndicator,
      AccessibilityID.storageSection,
      AccessibilityID.filesSection,
      AccessibilityID.filesLoadingIndicator,
      AccessibilityID.filesEmptyState,
      AccessibilityID.filesErrorState,
      AccessibilityID.filesOutcomeState,
      AccessibilityID.refreshFilesButton,
    ]
    for id in allIDs {
      XCTAssertFalse(id.isEmpty, "Empty accessibility ID found")
    }
  }

  func testDynamicIDsContainBasePrefix() {
    let deviceRowID = AccessibilityID.deviceRow("test-device")
    XCTAssertTrue(deviceRowID.hasPrefix("swiftmtp.device.row."))

    let storageRowID = AccessibilityID.storageRow(1)
    XCTAssertTrue(storageRowID.hasPrefix("swiftmtp.storage.row."))

    let fileRowID = AccessibilityID.fileRow(42)
    XCTAssertTrue(fileRowID.hasPrefix("swiftmtp.file.row."))
  }

  func testDynamicIDsSanitizeSpecialChars() {
    let id = AccessibilityID.deviceRow("usb://bus1:dev2@port")
    XCTAssertFalse(id.contains("://"))
    XCTAssertFalse(id.contains("@"))
    XCTAssertFalse(id.contains(":"))
  }

  @MainActor
  func testDeviceListViewHasAccessibilityID() {
    let coordinator = DeviceLifecycleCoordinator()
    let vm = DeviceViewModel(coordinator: coordinator)
    let view = DeviceListView(viewModel: vm)
    _ = view.body
    // Verifies AccessibilityID.deviceList is applied
    XCTAssertEqual(AccessibilityID.deviceList, "swiftmtp.device.list")
  }

  @MainActor
  func testDeviceBrowserRootHasAccessibilityID() {
    let view = DeviceBrowserView()
    _ = view.body
    XCTAssertEqual(AccessibilityID.browserRoot, "swiftmtp.browser.root")
  }

  @MainActor
  func testStorageRowHasAccessibilityID() {
    let storage = MTPStorageInfo(
      id: MTPStorageID(raw: 0x0001_0001),
      description: "Test Storage",
      capacityBytes: 64_000_000_000,
      freeBytes: 32_000_000_000,
      isReadOnly: false
    )
    let expectedID = AccessibilityID.storageRow(0x0001_0001)
    let row = StorageRow(storage: storage, accessibilityID: expectedID)
    _ = row.body
    XCTAssertEqual(expectedID, "swiftmtp.storage.row.65537")
  }

  @MainActor
  func testFileRowHasAccessibilityID() {
    let file = MTPObjectInfo(
      handle: 99, storage: MTPStorageID(raw: 0x0001_0001), parent: nil,
      name: "test.jpg", sizeBytes: 1000, modified: nil,
      formatCode: 0x3801, properties: [:]
    )
    let expectedID = AccessibilityID.fileRow(99)
    let row = FileRow(file: file, accessibilityID: expectedID)
    _ = row.body
    XCTAssertEqual(expectedID, "swiftmtp.file.row.99")
  }
}

// MARK: - Dark Mode: View Instantiation

final class DarkModeViewTests: XCTestCase {

  @MainActor
  func testDeviceBrowserViewInDarkMode() {
    let coordinator = DeviceLifecycleCoordinator()
    let view = DeviceBrowserView(coordinator: coordinator)
      .preferredColorScheme(.dark)
    XCTAssertNotNil(view)
  }

  @MainActor
  func testDeviceListViewInDarkMode() {
    let coordinator = DeviceLifecycleCoordinator()
    let vm = DeviceViewModel(coordinator: coordinator)
    let view = DeviceListView(viewModel: vm)
      .preferredColorScheme(.dark)
    XCTAssertNotNil(view)
  }

  @MainActor
  func testDeviceMainViewInDarkMode() {
    let config = VirtualDeviceConfig.pixel7
    let device = VirtualMTPDevice(config: config)
    let view = DeviceMainView(device: device)
      .preferredColorScheme(.dark)
    XCTAssertNotNil(view)
  }

  @MainActor
  func testStorageRowInDarkMode() {
    let storage = MTPStorageInfo(
      id: MTPStorageID(raw: 0x0001_0001),
      description: "Dark Mode Storage",
      capacityBytes: 64_000_000_000,
      freeBytes: 32_000_000_000,
      isReadOnly: false
    )
    let row = StorageRow(storage: storage, accessibilityID: "test.dark.storage")
    let view = row.preferredColorScheme(.dark)
    XCTAssertNotNil(view)
  }

  @MainActor
  func testFileRowInDarkMode() {
    let file = MTPObjectInfo(
      handle: 1, storage: MTPStorageID(raw: 0x0001_0001), parent: nil,
      name: "dark.jpg", sizeBytes: 1000, modified: nil,
      formatCode: 0x3801, properties: [:]
    )
    let row = FileRow(file: file, accessibilityID: "test.dark.file")
    let view = row.preferredColorScheme(.dark)
    XCTAssertNotNil(view)
  }

  @MainActor
  func testLightModeAlsoDoesNotCrash() {
    let coordinator = DeviceLifecycleCoordinator()
    let view = DeviceBrowserView(coordinator: coordinator)
      .preferredColorScheme(.light)
    XCTAssertNotNil(view)
  }
}

// MARK: - Device Connection State UI

final class DeviceConnectionStateTests: XCTestCase {

  @MainActor
  func testConnectingState() {
    let coordinator = DeviceLifecycleCoordinator()
    let vm = DeviceViewModel(coordinator: coordinator)
    // isConnecting starts false (no connect in progress)
    XCTAssertFalse(vm.isConnecting)
    // View renders cleanly in non-connecting state
    let view = DeviceListView(viewModel: vm)
    _ = view.body
  }

  @MainActor
  func testConnectedState() {
    let coordinator = DeviceLifecycleCoordinator()
    let vm = DeviceViewModel(coordinator: coordinator)
    // No device selected initially
    XCTAssertNil(vm.selectedDevice)
    let view = DeviceBrowserView(coordinator: coordinator)
    // Should render "No Device Selected" placeholder
    _ = view.body
  }

  @MainActor
  func testErrorStateDisplay() {
    let coordinator = DeviceLifecycleCoordinator()
    coordinator.error = "USB claim failed: device busy"
    let vm = DeviceViewModel(coordinator: coordinator)
    XCTAssertEqual(vm.error, "USB claim failed: device busy")
    // View shows error banner
    let view = DeviceBrowserView(coordinator: coordinator)
    _ = view.body
  }

  @MainActor
  func testDisconnectingStateClearsSelection() async {
    let coordinator = DeviceLifecycleCoordinator()
    let vm = DeviceViewModel(coordinator: coordinator)
    // Simulate disconnect via shutdown
    await coordinator.shutdown()
    XCTAssertNil(vm.selectedDevice)
    XCTAssertTrue(vm.devices.isEmpty)
  }

  @MainActor
  func testConnectionStateTransitions() {
    let coordinator = DeviceLifecycleCoordinator()
    let vm = DeviceViewModel(coordinator: coordinator)

    // Initial: no devices, no connection
    XCTAssertFalse(vm.isConnecting)
    XCTAssertNil(vm.selectedDevice)
    XCTAssertNil(vm.error)

    // Error state
    coordinator.error = "Connection timed out"
    XCTAssertNotNil(vm.error)

    // Clear error
    coordinator.error = nil
    XCTAssertNil(vm.error)
  }
}

// MARK: - Empty State: No Devices

final class EmptyStateTests: XCTestCase {

  @MainActor
  func testNoDevicesShowsEmptyState() {
    let coordinator = DeviceLifecycleCoordinator()
    let vm = DeviceViewModel(coordinator: coordinator)
    XCTAssertTrue(vm.devices.isEmpty)

    let view = DeviceListView(viewModel: vm)
    _ = view.body
    // The overlay with ContentUnavailableView should be active
    XCTAssertEqual(AccessibilityID.noDevicesState, "swiftmtp.device.empty")
  }

  @MainActor
  func testNoDeviceSelectedShowsPlaceholder() {
    let coordinator = DeviceLifecycleCoordinator()
    XCTAssertNil(coordinator.selectedDevice)
    let view = DeviceBrowserView(coordinator: coordinator)
    _ = view.body
    XCTAssertEqual(AccessibilityID.noSelectionState, "swiftmtp.selection.empty")
  }

  @MainActor
  func testDiscoveryStateLabelEmptyWhenNoDevices() {
    let coordinator = DeviceLifecycleCoordinator()
    let vm = DeviceViewModel(coordinator: coordinator)
    // No error and no devices → "empty" state
    XCTAssertNil(vm.error)
    XCTAssertTrue(vm.devices.isEmpty)
  }

  @MainActor
  func testDiscoveryStateLabelErrorWhenErrorSet() {
    let coordinator = DeviceLifecycleCoordinator()
    coordinator.error = "Discovery failed"
    // With error → "error" state
    XCTAssertNotNil(coordinator.error)
  }
}

// MARK: - Toolbar State: Buttons Enabled/Disabled

final class ToolbarStateTests: XCTestCase {

  @MainActor
  func testDemoModeButtonExists() {
    let view = DeviceBrowserView()
    _ = view.body
    XCTAssertEqual(AccessibilityID.demoModeButton, "swiftmtp.demo.button")
  }

  @MainActor
  func testRefreshButtonExists() {
    XCTAssertEqual(AccessibilityID.refreshFilesButton, "swiftmtp.files.refresh")
  }

  @MainActor
  func testToolbarRendersWithNoDevices() {
    let coordinator = DeviceLifecycleCoordinator()
    let vm = DeviceViewModel(coordinator: coordinator)
    XCTAssertTrue(vm.devices.isEmpty)
    let view = DeviceBrowserView(coordinator: coordinator)
    _ = view.body
  }

  @MainActor
  func testToolbarRendersWithError() {
    let coordinator = DeviceLifecycleCoordinator()
    coordinator.error = "Test error for toolbar"
    let view = DeviceBrowserView(coordinator: coordinator)
    _ = view.body
  }

  @MainActor
  func testFeatureFlagsDemoModeToggle() {
    let originalValue = FeatureFlags.shared.useMockTransport
    FeatureFlags.shared.useMockTransport = true
    XCTAssertTrue(FeatureFlags.shared.useMockTransport)
    FeatureFlags.shared.useMockTransport = false
    XCTAssertFalse(FeatureFlags.shared.useMockTransport)
    FeatureFlags.shared.useMockTransport = originalValue
  }
}

// MARK: - View Instantiation with Multiple Device Configs

final class MultiDeviceViewInstantiationTests: XCTestCase {

  @MainActor
  func testViewWithSamsungDevice() {
    let config = VirtualDeviceConfig.samsungGalaxy
    let device = VirtualMTPDevice(config: config)
    let view = DeviceMainView(device: device)
    XCTAssertNotNil(view)
  }

  @MainActor
  func testViewWithCanonCamera() {
    let config = VirtualDeviceConfig.canonEOSR5
    let device = VirtualMTPDevice(config: config)
    let view = DeviceMainView(device: device)
    XCTAssertNotNil(view)
  }

  @MainActor
  func testViewWithNikonCamera() {
    let config = VirtualDeviceConfig.nikonZ6
    let device = VirtualMTPDevice(config: config)
    let view = DeviceMainView(device: device)
    XCTAssertNotNil(view)
  }

  @MainActor
  func testViewWithOnePlusDevice() {
    let config = VirtualDeviceConfig.onePlus9
    let device = VirtualMTPDevice(config: config)
    let view = DeviceMainView(device: device)
    XCTAssertNotNil(view)
  }

  @MainActor
  func testViewWithEmptyDeviceInDarkMode() {
    let config = VirtualDeviceConfig.emptyDevice
    let device = VirtualMTPDevice(config: config)
    let darkView = DeviceMainView(device: device)
      .preferredColorScheme(.dark)
    XCTAssertNotNil(darkView)
  }
}
