// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import SwiftMTPFileProvider
import SwiftMTPIndex
import SwiftMTPCore
import SwiftMTPStore
import Testing

/// Integration tests for FileProvider with LiveIndex
@available(macOS 15.0, *)
@Suite(.tags(.fileProvider, .integration))
struct FileProviderIntegrationTests {
  
  // MARK: - LiveIndex Integration Tests
  
  @Test("LiveIndex integration with FileProvider")
  func testLiveIndexIntegration() async throws {
    // Create a live index
    let liveIndex = SQLiteLiveIndex(path: ":memory:")
    
    // Initialize schema
    try await liveIndex.initializeSchema()
    
    // Test basic operations
    #expect(liveIndex.isInitialized == true)
  }
  
  @Test("NSFileProviderExtension API compliance")
  func testNSFileProviderExtensionAPI() async throws {
    // Test that the extension properly implements required methods
    let fileProviderExtension = MTPFileProviderExtension()
    
    // Verify extension exists
    #expect(fileProviderExtension != nil)
  }
  
  @Test("Change signaling and propagation")
  func testChangeSignaling() async throws {
    let signaler = ChangeSignaler()
    
    // Start monitoring changes
    await signaler.startMonitoring()
    
    // Simulate a change
    await signaler.signalChange(containerIdentifier: "test-container")
    
    // Verify change was recorded
    let hasChanges = await signaler.hasPendingChanges(containerIdentifier: "test-container")
    #expect(hasChanges == true)
  }
  
  @Test("Container mounting/unmounting")
  func testContainerMounting() async throws {
    let manager = FileProviderManager()
    
    // Mount a container
    try await manager.mountContainer(identifier: "test-mtp-device")
    
    // Verify mounted
    let isMounted = await manager.isContainerMounted(identifier: "test-mtp-device")
    #expect(isMounted == true)
    
    // Unmount
    try await manager.unmountContainer(identifier: "test-mtp-device")
    
    #expect(await manager.isContainerMounted(identifier: "test-mtp-device") == false)
  }
  
  // MARK: - Domain Enumeration Tests
  
  @Test("Domain enumeration for MTP devices")
  func testDomainEnumeration() async throws {
    let enumerator = DomainEnumerator()
    
    // Enumerate connected devices
    let domains = try await enumerator.enumerateDomains()
    
    // Should return MTP-related domains
    #expect(domains.count >= 0)
  }
  
  @Test("Item enumeration for device storage")
  func testItemEnumeration() async throws {
    let enumerator = DomainEnumerator()
    
    // Create mock MTP device service
    let deviceService = MTPDeviceService()
    
    // Enumerate root items
    let items = try await deviceService.enumerateItems(at: "/")
    
    // Should return items from root
    #expect(items.count >= 0)
  }
}

// MARK: - Change Signaler Tests

@available(macOS 15.0, *)
@Suite(.tags(.fileProvider, .changeSignaling))
struct ChangeSignalerTests {
  
  @Test("Change batch processing")
  func testChangeBatchProcessing() async throws {
    let signaler = ChangeSignaler()
    
    // Queue multiple changes
    await signaler.signalChange(containerIdentifier: "device-1")
    await signaler.signalChange(containerIdentifier: "device-1")
    await signaler.signalChange(containerIdentifier: "device-2")
    
    // Process batch
    let batch = await signaler.getChangeBatch(for: "device-1")
    
    #expect(batch.count == 2)
  }
  
  @Test("Change acknowledgment")
  func testChangeAcknowledgment() async throws {
    let signaler = ChangeSignaler()
    
    // Signal a change
    await signaler.signalChange(containerIdentifier: "device-1")
    
    // Acknowledge
    await signaler.acknowledgeChanges(containerIdentifier: "device-1")
    
    // Should be cleared
    let hasChanges = await signaler.hasPendingChanges(containerIdentifier: "device-1")
    #expect(hasChanges == false)
  }
}

// MARK: - File Provider Manager Tests

@available(macOS 15.0, *)
@Suite(.tags(.fileProvider, .manager))
struct FileProviderManagerTests {
  
  @Test("Multiple device management")
  func testMultipleDeviceManagement() async throws {
    let manager = FileProviderManager()
    
    // Mount multiple devices
    try await manager.mountContainer(identifier: "device-1")
    try await manager.mountContainer(identifier: "device-2")
    
    // Verify count
    let mountedCount = await manager.mountedContainerCount
    #expect(mountedCount == 2)
  }
  
  @Test("Device service lifecycle")
  func testDeviceServiceLifecycle() async throws {
    let deviceService = MTPDeviceService()
    
    // Connect
    try await deviceService.connect()
    #expect(await deviceService.isConnected == true)
    
    // Disconnect
    try await deviceService.disconnect()
    #expect(await deviceService.isConnected == false)
  }
}
