// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import XCTest

@testable import SwiftMTPUI
import SwiftMTPCore
import SwiftMTPTestKit
import SwiftUI

// MARK: - AccessibilityID Extended Tests

final class AccessibilityIDExtendedTests: XCTestCase {

  func testDeviceRowSpecialCharacters() {
    let id = AccessibilityID.deviceRow("a@b#c$d%e")
    XCTAssertTrue(id.hasPrefix("swiftmtp.device.row."))
    XCTAssertFalse(id.contains("@"))
    XCTAssertFalse(id.contains("#"))
    XCTAssertFalse(id.contains("$"))
    XCTAssertFalse(id.contains("%"))
  }

  func testDeviceRowUnicodeCharacters() {
    let id = AccessibilityID.deviceRow("日本語デバイス")
    XCTAssertTrue(id.hasPrefix("swiftmtp.device.row."))
    // Unicode chars should be sanitized to underscores
    XCTAssertFalse(id.contains("日"))
  }

  func testDeviceRowLongString() {
    let longId = String(repeating: "a", count: 256)
    let id = AccessibilityID.deviceRow(longId)
    XCTAssertTrue(id.hasPrefix("swiftmtp.device.row."))
    XCTAssertTrue(id.count > 20)
  }

  func testDeviceRowPreservesHyphens() {
    let id = AccessibilityID.deviceRow("usb-device-001")
    XCTAssertEqual(id, "swiftmtp.device.row.usb-device-001")
  }

  func testDeviceRowPreservesDots() {
    let id = AccessibilityID.deviceRow("v1.2.3")
    XCTAssertEqual(id, "swiftmtp.device.row.v1.2.3")
  }

  func testStorageRowMaxValue() {
    let id = AccessibilityID.storageRow(UInt32.max)
    XCTAssertEqual(id, "swiftmtp.storage.row.\(UInt32.max)")
  }

  func testFileRowMaxHandle() {
    let id = AccessibilityID.fileRow(UInt32.max)
    XCTAssertEqual(id, "swiftmtp.file.row.\(UInt32.max)")
  }

  func testAllStaticIdentifiersAreUnique() {
    let ids = [
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
    XCTAssertEqual(ids.count, Set(ids).count, "Duplicate accessibility IDs detected")
  }

  func testAllStaticIdentifiersHavePrefix() {
    let ids = [
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
    for id in ids {
      XCTAssertTrue(id.hasPrefix("swiftmtp."), "ID '\(id)' missing 'swiftmtp.' prefix")
    }
  }

  func testDeviceRowWithColonSeparator() {
    let id = AccessibilityID.deviceRow("18d1:4ee1")
    XCTAssertEqual(id, "swiftmtp.device.row.18d1_4ee1")
  }

  func testStorageRowConsecutiveValues() {
    let id1 = AccessibilityID.storageRow(1)
    let id2 = AccessibilityID.storageRow(2)
    XCTAssertNotEqual(id1, id2)
  }
}

// MARK: - UXFlowID Extended Tests

final class UXFlowIDExtendedTests: XCTestCase {

  func testSpecificFlowValues() {
    XCTAssertEqual(UXFlowID.discoveryStateMarker.rawValue, "ux.discovery.state.marker")
    XCTAssertEqual(
      UXFlowID.selectionPlaceholderVisible.rawValue, "ux.selection.placeholder.visible")
    XCTAssertEqual(UXFlowID.deviceLoadingPhase.rawValue, "ux.device.loading.phase")
    XCTAssertEqual(UXFlowID.detailContainerVisible.rawValue, "ux.detail.container.visible")
    XCTAssertEqual(UXFlowID.filesLoadingPhase.rawValue, "ux.files.loading.phase")
    XCTAssertEqual(UXFlowID.filesEmptyPhase.rawValue, "ux.files.empty.phase")
    XCTAssertEqual(UXFlowID.filesErrorPhase.rawValue, "ux.files.error.phase")
    XCTAssertEqual(UXFlowID.filesOutcomeMarker.rawValue, "ux.files.outcome.marker")
    XCTAssertEqual(UXFlowID.deviceRowRender.rawValue, "ux.device.row.render")
    XCTAssertEqual(UXFlowID.storageRowRender.rawValue, "ux.storage.row.render")
    XCTAssertEqual(UXFlowID.fileRowRender.rawValue, "ux.file.row.render")
  }

  func testFlowCountMatchesExpectation() {
    // Ensure all 19 flows exist
    XCTAssertEqual(UXFlowID.allCases.count, 19)
  }

  func testRawValuesContainNoDuplicatePrefixes() {
    // Each raw value should have at least 3 dot-separated segments
    for flow in UXFlowID.allCases {
      let segments = flow.rawValue.split(separator: ".")
      XCTAssertGreaterThanOrEqual(segments.count, 3, "Flow \(flow) has too few segments")
    }
  }

  func testAllFlowsStartWithUXPrefix() {
    for flow in UXFlowID.allCases {
      XCTAssertTrue(flow.rawValue.hasPrefix("ux."), "\(flow) missing ux. prefix")
    }
  }

  func testFlowIDHashableConformance() {
    var set = Set<UXFlowID>()
    for flow in UXFlowID.allCases {
      set.insert(flow)
    }
    XCTAssertEqual(set.count, UXFlowID.allCases.count)
  }
}

// MARK: - UITestConfiguration Extended Tests

final class UITestConfigurationExtendedTests: XCTestCase {

  func testConfigurationDemoModeDefaultTrue() {
    let config = UITestConfiguration.current
    // Default demoModeEnabled is true when env var not set
    XCTAssertTrue(config.demoModeEnabled)
  }

  func testConfigurationRunIdentifierFormat() {
    let config = UITestConfiguration.current
    // Should be a date-based identifier like "20250101-120000"
    XCTAssertTrue(config.runIdentifier.count >= 8)
  }

  func testConfigurationArtifactDirectoryContainsRunId() {
    let config = UITestConfiguration.current
    XCTAssertTrue(config.artifactDirectory.path.contains(config.runIdentifier))
  }

  func testConfigurationScenarioIsNotEmpty() {
    let config = UITestConfiguration.current
    XCTAssertFalse(config.scenario.isEmpty)
  }

  func testConfigurationMockProfileIsNotEmpty() {
    let config = UITestConfiguration.current
    XCTAssertFalse(config.mockProfile.isEmpty)
  }

  func testConfigurationEnabledDefaultFalse() {
    let config = UITestConfiguration.current
    XCTAssertFalse(config.enabled)
  }

  func testMultipleCurrentCallsReturnConsistentValues() {
    let config1 = UITestConfiguration.current
    let config2 = UITestConfiguration.current
    XCTAssertEqual(config1.enabled, config2.enabled)
    XCTAssertEqual(config1.scenario, config2.scenario)
    XCTAssertEqual(config1.mockProfile, config2.mockProfile)
  }
}

// MARK: - DeviceViewModel Extended Tests

final class DeviceViewModelExtendedTests: XCTestCase {

  @MainActor
  func testViewModelErrorSettingMultipleTimes() {
    let coordinator = DeviceLifecycleCoordinator()
    let vm = DeviceViewModel(coordinator: coordinator)

    vm.error = "Error 1"
    XCTAssertEqual(vm.error, "Error 1")
    vm.error = "Error 2"
    XCTAssertEqual(vm.error, "Error 2")
    vm.error = nil
    XCTAssertNil(vm.error)
  }

  @MainActor
  func testViewModelIsConnectingInitiallyFalse() {
    let coordinator = DeviceLifecycleCoordinator()
    let vm = DeviceViewModel(coordinator: coordinator)
    XCTAssertFalse(vm.isConnecting)
  }

  @MainActor
  func testViewModelSelectedDeviceInitiallyNil() {
    let coordinator = DeviceLifecycleCoordinator()
    let vm = DeviceViewModel(coordinator: coordinator)
    XCTAssertNil(vm.selectedDevice)
  }

  @MainActor
  func testViewModelDevicesEmptyOnInit() {
    let coordinator = DeviceLifecycleCoordinator()
    let vm = DeviceViewModel(coordinator: coordinator)
    XCTAssertEqual(vm.devices.count, 0)
  }

  @MainActor
  func testViewModelCoordinatorErrorPropagation() {
    let coordinator = DeviceLifecycleCoordinator()
    let vm = DeviceViewModel(coordinator: coordinator)
    coordinator.error = "Coordinator error"
    XCTAssertEqual(vm.error, "Coordinator error")
  }

  @MainActor
  func testViewModelErrorClearViaCoordinator() {
    let coordinator = DeviceLifecycleCoordinator()
    let vm = DeviceViewModel(coordinator: coordinator)
    coordinator.error = "Error"
    coordinator.error = nil
    XCTAssertNil(vm.error)
  }

  @MainActor
  func testViewModelEmptyErrorString() {
    let coordinator = DeviceLifecycleCoordinator()
    let vm = DeviceViewModel(coordinator: coordinator)
    vm.error = ""
    XCTAssertEqual(vm.error, "")
    XCTAssertNotNil(vm.error)
  }

  @MainActor
  func testViewModelLongErrorMessage() {
    let coordinator = DeviceLifecycleCoordinator()
    let vm = DeviceViewModel(coordinator: coordinator)
    let longError = String(repeating: "Error occurred. ", count: 100)
    vm.error = longError
    XCTAssertEqual(vm.error, longError)
  }
}

// MARK: - DeviceLifecycleCoordinator Extended Tests

final class DeviceLifecycleCoordinatorExtendedTests: XCTestCase {

  @MainActor
  func testCoordinatorErrorCanBeSet() {
    let coordinator = DeviceLifecycleCoordinator()
    coordinator.error = "Test error"
    XCTAssertEqual(coordinator.error, "Test error")
  }

  @MainActor
  func testCoordinatorErrorCanBeCleared() {
    let coordinator = DeviceLifecycleCoordinator()
    coordinator.error = "Some error"
    coordinator.error = nil
    XCTAssertNil(coordinator.error)
  }

  @MainActor
  func testCoordinatorSelectedDeviceCanBeCleared() {
    let coordinator = DeviceLifecycleCoordinator()
    coordinator.selectedDevice = nil
    XCTAssertNil(coordinator.selectedDevice)
  }

  @MainActor
  func testCoordinatorDiscoveredDevicesInitiallyEmpty() {
    let coordinator = DeviceLifecycleCoordinator()
    XCTAssertTrue(coordinator.discoveredDevices.isEmpty)
  }

  @MainActor
  func testCoordinatorOpenedDevicesInitiallyEmpty() {
    let coordinator = DeviceLifecycleCoordinator()
    XCTAssertTrue(coordinator.openedDevices.isEmpty)
  }

  @MainActor
  func testCoordinatorIsConnectingInitiallyFalse() {
    let coordinator = DeviceLifecycleCoordinator()
    XCTAssertFalse(coordinator.isConnecting)
  }

  @MainActor
  func testShutdownClearsError() async {
    let coordinator = DeviceLifecycleCoordinator()
    coordinator.error = "Error before shutdown"
    await coordinator.shutdown()
    // After shutdown, devices are cleared; error may persist
    XCTAssertTrue(coordinator.discoveredDevices.isEmpty)
    XCTAssertTrue(coordinator.openedDevices.isEmpty)
    XCTAssertNil(coordinator.selectedDevice)
  }

  @MainActor
  func testDoubleShutdownIsIdempotent() async {
    let coordinator = DeviceLifecycleCoordinator()
    coordinator.error = "Error"
    await coordinator.shutdown()
    await coordinator.shutdown()
    XCTAssertTrue(coordinator.discoveredDevices.isEmpty)
    XCTAssertNil(coordinator.selectedDevice)
  }

  @MainActor
  func testServiceRegistryAccessible() {
    let coordinator = DeviceLifecycleCoordinator()
    let registry = coordinator.serviceRegistry
    XCTAssertNotNil(registry)
  }
}

// MARK: - View Instantiation Extended Tests

final class ViewInstantiationExtendedTests: XCTestCase {

  @MainActor
  func testDeviceMainViewWithSamsungConfig() async throws {
    let config = VirtualDeviceConfig.samsungGalaxy
    let device = VirtualMTPDevice(config: config)
    let view = DeviceMainView(device: device)
    XCTAssertNotNil(view)
  }

  @MainActor
  func testDeviceMainViewWithCanonConfig() async throws {
    let config = VirtualDeviceConfig.canonEOSR5
    let device = VirtualMTPDevice(config: config)
    let view = DeviceMainView(device: device)
    XCTAssertNotNil(view)
  }

  @MainActor
  func testDeviceMainViewWithEmptyDevice() async throws {
    let config = VirtualDeviceConfig.emptyDevice
    let device = VirtualMTPDevice(config: config)
    let view = DeviceMainView(device: device)
    XCTAssertNotNil(view)
  }

  @MainActor
  func testDeviceListViewBodyRendersWithoutCrash() {
    let coordinator = DeviceLifecycleCoordinator()
    let vm = DeviceViewModel(coordinator: coordinator)
    let view = DeviceListView(viewModel: vm)
    _ = view.body
  }

  @MainActor
  func testDeviceBrowserViewBodyRendersWithoutCrash() {
    let view = DeviceBrowserView()
    _ = view.body
  }

  @MainActor
  func testMultipleCoordinatorViewModelsIndependent() {
    let coord1 = DeviceLifecycleCoordinator()
    let coord2 = DeviceLifecycleCoordinator()
    let vm1 = DeviceViewModel(coordinator: coord1)
    let vm2 = DeviceViewModel(coordinator: coord2)

    vm1.error = "Error in VM1"
    XCTAssertNil(vm2.error)
  }
}

// MARK: - StorageRow Extended Tests

final class StorageRowExtendedTests: XCTestCase {

  @MainActor
  func testStorageRowReadOnly() {
    let storage = MTPStorageInfo(
      id: MTPStorageID(raw: 0x0001_0001),
      description: "SD Card (Read Only)",
      capacityBytes: 32_000_000_000,
      freeBytes: 16_000_000_000,
      isReadOnly: true
    )
    let row = StorageRow(storage: storage, accessibilityID: "test.storage.readonly")
    _ = row.body
  }

  @MainActor
  func testStorageRowFullStorage() {
    let storage = MTPStorageInfo(
      id: MTPStorageID(raw: 0x0001_0001),
      description: "Full Storage",
      capacityBytes: 64_000_000_000,
      freeBytes: 0,
      isReadOnly: false
    )
    let row = StorageRow(storage: storage, accessibilityID: "test.storage.full")
    _ = row.body
  }

  @MainActor
  func testStorageRowLargeCapacity() {
    let storage = MTPStorageInfo(
      id: MTPStorageID(raw: 0x0002_0001),
      description: "2TB External",
      capacityBytes: 2_000_000_000_000,
      freeBytes: 1_500_000_000_000,
      isReadOnly: false
    )
    let row = StorageRow(storage: storage, accessibilityID: "test.storage.large")
    _ = row.body
  }

  @MainActor
  func testStorageRowSmallCapacity() {
    let storage = MTPStorageInfo(
      id: MTPStorageID(raw: 0x0001_0001),
      description: "Tiny Storage",
      capacityBytes: 1_000_000,
      freeBytes: 500_000,
      isReadOnly: false
    )
    let row = StorageRow(storage: storage, accessibilityID: "test.storage.tiny")
    _ = row.body
  }

  @MainActor
  func testStorageRowEmptyDescription() {
    let storage = MTPStorageInfo(
      id: MTPStorageID(raw: 0x0001_0001),
      description: "",
      capacityBytes: 64_000_000_000,
      freeBytes: 32_000_000_000,
      isReadOnly: false
    )
    let row = StorageRow(storage: storage, accessibilityID: "test.storage.nolabel")
    _ = row.body
  }

  @MainActor
  func testStorageRowAlmostFull() {
    let storage = MTPStorageInfo(
      id: MTPStorageID(raw: 0x0001_0001),
      description: "Almost Full",
      capacityBytes: 128_000_000_000,
      freeBytes: 100_000_000,  // 100MB free of 128GB
      isReadOnly: false
    )
    let row = StorageRow(storage: storage, accessibilityID: "test.storage.almostfull")
    _ = row.body
  }
}

// MARK: - FileRow Extended Tests

final class FileRowExtendedTests: XCTestCase {

  @MainActor
  func testFileRowLargeFile() {
    let file = MTPObjectInfo(
      handle: 100,
      storage: MTPStorageID(raw: 0x0001_0001),
      parent: nil,
      name: "large_video.mp4",
      sizeBytes: 4_000_000_000,
      modified: nil,
      formatCode: 0x300B,
      properties: [:]
    )
    let row = FileRow(file: file, accessibilityID: "test.file.large")
    _ = row.body
  }

  @MainActor
  func testFileRowWithParentHandle() {
    let file = MTPObjectInfo(
      handle: 50,
      storage: MTPStorageID(raw: 0x0001_0001),
      parent: 1,
      name: "nested_photo.jpg",
      sizeBytes: 2_500_000,
      modified: nil,
      formatCode: 0x3801,
      properties: [:]
    )
    let row = FileRow(file: file, accessibilityID: "test.file.nested")
    _ = row.body
  }

  @MainActor
  func testFileRowWithModifiedDate() {
    let file = MTPObjectInfo(
      handle: 60,
      storage: MTPStorageID(raw: 0x0001_0001),
      parent: nil,
      name: "dated_file.txt",
      sizeBytes: 1024,
      modified: Date(timeIntervalSince1970: 1_700_000_000),
      formatCode: 0x3000,
      properties: [:]
    )
    let row = FileRow(file: file, accessibilityID: "test.file.dated")
    _ = row.body
  }

  @MainActor
  func testFileRowWithProperties() {
    let file = MTPObjectInfo(
      handle: 70,
      storage: MTPStorageID(raw: 0x0001_0001),
      parent: nil,
      name: "props_file.jpg",
      sizeBytes: 3_000_000,
      modified: nil,
      formatCode: 0x3801,
      properties: [0xDC01: "photo.jpg", 0xDC02: "image/jpeg"]
    )
    let row = FileRow(file: file, accessibilityID: "test.file.props")
    _ = row.body
  }

  @MainActor
  func testFileRowNilSize() {
    let file = MTPObjectInfo(
      handle: 80,
      storage: MTPStorageID(raw: 0x0001_0001),
      parent: nil,
      name: "unknown_size.bin",
      sizeBytes: nil,
      modified: nil,
      formatCode: 0x3000,
      properties: [:]
    )
    let row = FileRow(file: file, accessibilityID: "test.file.nilsize")
    _ = row.body
  }

  @MainActor
  func testFileRowLongFileName() {
    let longName = String(repeating: "a", count: 255) + ".txt"
    let file = MTPObjectInfo(
      handle: 90,
      storage: MTPStorageID(raw: 0x0001_0001),
      parent: nil,
      name: longName,
      sizeBytes: 100,
      modified: nil,
      formatCode: 0x3000,
      properties: [:]
    )
    let row = FileRow(file: file, accessibilityID: "test.file.longname")
    _ = row.body
  }

  @MainActor
  func testFileRowUnicodeFileName() {
    let file = MTPObjectInfo(
      handle: 91,
      storage: MTPStorageID(raw: 0x0001_0001),
      parent: nil,
      name: "写真_2025.jpg",
      sizeBytes: 2_000_000,
      modified: nil,
      formatCode: 0x3801,
      properties: [:]
    )
    let row = FileRow(file: file, accessibilityID: "test.file.unicode")
    _ = row.body
  }

  @MainActor
  func testFileRowEmptyName() {
    let file = MTPObjectInfo(
      handle: 92,
      storage: MTPStorageID(raw: 0x0001_0001),
      parent: nil,
      name: "",
      sizeBytes: 0,
      modified: nil,
      formatCode: 0x3000,
      properties: [:]
    )
    let row = FileRow(file: file, accessibilityID: "test.file.emptyname")
    _ = row.body
  }
}

// MARK: - Device Summary Display Tests

final class DeviceSummaryDisplayTests: XCTestCase {

  func testDeviceSummaryFingerprintFormat() {
    let summary = MTPDeviceSummary(
      id: MTPDeviceID(raw: "test"),
      manufacturer: "Google",
      model: "Pixel 7",
      vendorID: 0x18d1,
      productID: 0x4ee1
    )
    XCTAssertEqual(summary.fingerprint, "18d1:4ee1")
  }

  func testDeviceSummaryFingerprintNilIDs() {
    let summary = MTPDeviceSummary(
      id: MTPDeviceID(raw: "test"),
      manufacturer: "Unknown",
      model: "Device"
    )
    XCTAssertEqual(summary.fingerprint, "unknown")
  }

  func testDeviceSummaryFingerprintLeadingZeros() {
    let summary = MTPDeviceSummary(
      id: MTPDeviceID(raw: "test"),
      manufacturer: "Test",
      model: "Device",
      vendorID: 0x0001,
      productID: 0x0002
    )
    XCTAssertEqual(summary.fingerprint, "0001:0002")
  }

  func testDeviceSummaryManufacturerModel() {
    let summary = MTPDeviceSummary(
      id: MTPDeviceID(raw: "test"),
      manufacturer: "Samsung",
      model: "Galaxy S24"
    )
    let display = "\(summary.manufacturer) \(summary.model)"
    XCTAssertEqual(display, "Samsung Galaxy S24")
  }

  func testDeviceSummaryEmptyManufacturer() {
    let summary = MTPDeviceSummary(
      id: MTPDeviceID(raw: "test"),
      manufacturer: "",
      model: "Unknown"
    )
    XCTAssertTrue(summary.manufacturer.isEmpty)
  }

  func testDeviceSummaryWithUSBSerial() {
    let summary = MTPDeviceSummary(
      id: MTPDeviceID(raw: "test"),
      manufacturer: "Google",
      model: "Pixel",
      vendorID: 0x18d1,
      productID: 0x4ee1,
      usbSerial: "ABC123"
    )
    XCTAssertEqual(summary.usbSerial, "ABC123")
  }

  func testDeviceSummaryBusAndAddress() {
    let summary = MTPDeviceSummary(
      id: MTPDeviceID(raw: "test"),
      manufacturer: "Test",
      model: "Device",
      bus: 2,
      address: 5
    )
    XCTAssertEqual(summary.bus, 2)
    XCTAssertEqual(summary.address, 5)
  }
}

// MARK: - FeatureFlags UI Tests

final class FeatureFlagsUITests: XCTestCase {

  func testMockProfileDefault() {
    let profile = FeatureFlags.shared.mockProfile
    // Default when no env var → "pixel7"
    XCTAssertFalse(profile.isEmpty)
  }

  func testFeatureFlagSetAndGet() {
    let key = "SWIFTMTP_TEST_UI_FLAG_\(UUID().uuidString)"
    FeatureFlags.shared.set(key, enabled: true)
    XCTAssertTrue(FeatureFlags.shared.isEnabled(key))
    FeatureFlags.shared.set(key, enabled: false)
    XCTAssertFalse(FeatureFlags.shared.isEnabled(key))
  }

  func testUnknownFlagDefaultsFalse() {
    let key = "SWIFTMTP_NONEXISTENT_\(UUID().uuidString)"
    XCTAssertFalse(FeatureFlags.shared.isEnabled(key))
  }
}
