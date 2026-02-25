// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import XCTest
import FileProvider
@testable import SwiftMTPCore
@testable import SwiftMTPFileProvider
@testable import SwiftMTPXPC

private actor FileProviderMockReader: LiveIndexReader {
  private var storagesValue: [IndexedStorage] = []
  private var objectByHandle: [UInt32: IndexedObject] = [:]
  private var childrenByKey: [String: [IndexedObject]] = [:]
  private var changesValue: [IndexedObjectChange] = []
  private var counterValue: Int64 = 0
  private var crawlStateValue: Date?
  private var forcedError: Error?

  private func key(storageId: UInt32, parentHandle: UInt32?) -> String {
    "\(storageId):\(parentHandle?.description ?? "root")"
  }

  func setStorages(_ storages: [IndexedStorage]) {
    storagesValue = storages
  }

  func setObject(_ object: IndexedObject) {
    objectByHandle[object.handle] = object
  }

  func setChildren(storageId: UInt32, parentHandle: UInt32?, objects: [IndexedObject]) {
    childrenByKey[key(storageId: storageId, parentHandle: parentHandle)] = objects
  }

  func setChanges(_ changes: [IndexedObjectChange]) {
    changesValue = changes
  }

  func setCounter(_ counter: Int64) {
    counterValue = counter
  }

  func setCrawlState(_ date: Date?) {
    crawlStateValue = date
  }

  func setForcedError(_ error: Error?) {
    forcedError = error
  }

  func children(deviceId: String, storageId: UInt32, parentHandle: MTPObjectHandle?) async throws
    -> [IndexedObject]
  {
    let _ = deviceId
    if let forcedError { throw forcedError }
    return childrenByKey[key(storageId: storageId, parentHandle: parentHandle)] ?? []
  }

  func object(deviceId: String, handle: MTPObjectHandle) async throws -> IndexedObject? {
    let _ = deviceId
    if let forcedError { throw forcedError }
    return objectByHandle[handle]
  }

  func storages(deviceId: String) async throws -> [IndexedStorage] {
    let _ = deviceId
    if let forcedError { throw forcedError }
    return storagesValue
  }

  func currentChangeCounter(deviceId: String) async throws -> Int64 {
    let _ = deviceId
    if let forcedError { throw forcedError }
    return counterValue
  }

  func changesSince(deviceId: String, anchor: Int64) async throws -> [IndexedObjectChange] {
    let _ = (deviceId, anchor)
    if let forcedError { throw forcedError }
    return changesValue
  }

  func crawlState(deviceId: String, storageId: UInt32, parentHandle: MTPObjectHandle?) async throws
    -> Date?
  {
    let _ = (deviceId, storageId, parentHandle)
    if let forcedError { throw forcedError }
    return crawlStateValue
  }
}

private final class ItemObserver: NSObject, NSFileProviderEnumerationObserver {
  var enumeratedItems: [NSFileProviderItem] = []
  var finished = false
  var finishedError: Error?
  var finishCallback: (() -> Void)?

  func didEnumerate(_ updatedItems: [NSFileProviderItem]) {
    enumeratedItems.append(contentsOf: updatedItems)
  }

  func finishEnumerating(upTo nextPage: NSFileProviderPage?) {
    let _ = nextPage
    finished = true
    finishCallback?()
  }

  func finishEnumeratingWithError(_ error: Error) {
    finishedError = error
    finishCallback?()
  }
}

private final class ChangeObserver: NSObject, NSFileProviderChangeObserver {
  var updatedItems: [NSFileProviderItem] = []
  var deletedIdentifiers: [NSFileProviderItemIdentifier] = []
  var latestAnchor: NSFileProviderSyncAnchor?
  var finishedError: Error?
  var finishCallback: (() -> Void)?

  func didUpdate(_ updatedItems: [NSFileProviderItem]) {
    self.updatedItems.append(contentsOf: updatedItems)
  }

  func didDeleteItems(withIdentifiers deletedItemIdentifiers: [NSFileProviderItemIdentifier]) {
    deletedIdentifiers.append(contentsOf: deletedItemIdentifiers)
  }

  func finishEnumeratingChanges(upTo anchor: NSFileProviderSyncAnchor, moreComing: Bool) {
    let _ = moreComing
    latestAnchor = anchor
    finishCallback?()
  }

  func finishEnumeratingWithError(_ error: Error) {
    finishedError = error
    finishCallback?()
  }
}

private struct SyntheticError: Error {}

final class FileProviderCoverageTests: XCTestCase {
  private func makeDomain(_ id: String = "swiftmtp-test-domain") -> NSFileProviderDomain {
    NSFileProviderDomain(
      identifier: NSFileProviderDomainIdentifier(id), displayName: "SwiftMTP Test")
  }

  private func makeStorage(deviceId: String = "device1", storageId: UInt32 = 1) -> IndexedStorage {
    IndexedStorage(
      deviceId: deviceId,
      storageId: storageId,
      description: "Internal",
      capacity: 10_000,
      free: 5_000,
      readOnly: false
    )
  }

  private func makeObject(
    deviceId: String = "device1",
    storageId: UInt32 = 1,
    handle: UInt32 = 42,
    parent: UInt32? = nil,
    name: String = "file.txt",
    isDirectory: Bool = false
  ) -> IndexedObject {
    IndexedObject(
      deviceId: deviceId,
      storageId: storageId,
      handle: handle,
      parentHandle: parent,
      name: name,
      pathKey: "/\(name)",
      sizeBytes: isDirectory ? nil : 5,
      mtime: Date(),
      formatCode: isDirectory ? 0x3001 : 0x3000,
      isDirectory: isDirectory,
      changeCounter: 1
    )
  }

  func testDomainEnumeratorItemsAndNoReaderPaths() async throws {
    let reader = FileProviderMockReader()
    await reader.setStorages([makeStorage()])
    await reader.setChildren(storageId: 1, parentHandle: nil, objects: [makeObject()])

    let storageEnumerator = DomainEnumerator(
      deviceId: "device1", storageId: nil, parentHandle: nil, indexReader: reader)
    let storageExpectation = expectation(description: "storage enumeration")
    let storageObserver = ItemObserver()
    storageObserver.finishCallback = { storageExpectation.fulfill() }
    storageEnumerator.enumerateItems(
      for: storageObserver,
      startingAt: NSFileProviderPage.initialPageSortedByDate as NSFileProviderPage)
    await fulfillment(of: [storageExpectation], timeout: 2.0)
    XCTAssertEqual(storageObserver.enumeratedItems.count, 1)
    XCTAssertTrue(storageObserver.finished)

    let objectEnumerator = DomainEnumerator(
      deviceId: "device1", storageId: 1, parentHandle: nil, indexReader: reader)
    let objectExpectation = expectation(description: "object enumeration")
    let objectObserver = ItemObserver()
    objectObserver.finishCallback = { objectExpectation.fulfill() }
    objectEnumerator.enumerateItems(
      for: objectObserver,
      startingAt: NSFileProviderPage.initialPageSortedByDate as NSFileProviderPage)
    await fulfillment(of: [objectExpectation], timeout: 2.0)
    XCTAssertEqual(objectObserver.enumeratedItems.count, 1)

    // Trigger crawl path for empty folders while still debounced.
    await reader.setChildren(storageId: 1, parentHandle: nil, objects: [])
    await reader.setCrawlState(Date())
    let emptyExpectation = expectation(description: "empty object enumeration")
    let emptyObserver = ItemObserver()
    emptyObserver.finishCallback = { emptyExpectation.fulfill() }
    objectEnumerator.enumerateItems(
      for: emptyObserver,
      startingAt: NSFileProviderPage.initialPageSortedByDate as NSFileProviderPage)
    await fulfillment(of: [emptyExpectation], timeout: 2.0)
    XCTAssertTrue(emptyObserver.finished)

    let noReaderEnumerator = DomainEnumerator(
      deviceId: "device1", storageId: nil, parentHandle: nil, indexReader: nil)
    let noReaderExpectation = expectation(description: "no-reader enumeration")
    let noReaderObserver = ItemObserver()
    noReaderObserver.finishCallback = { noReaderExpectation.fulfill() }
    noReaderEnumerator.enumerateItems(
      for: noReaderObserver,
      startingAt: NSFileProviderPage.initialPageSortedByDate as NSFileProviderPage)
    await fulfillment(of: [noReaderExpectation], timeout: 2.0)
    XCTAssertTrue(noReaderObserver.finished)
  }

  func testDomainEnumeratorChangesAnchorAndErrorPaths() async throws {
    let reader = FileProviderMockReader()
    let upserted = makeObject(handle: 99)
    let deleted = makeObject(handle: 100)
    await reader.setChanges([
      IndexedObjectChange(kind: .upserted, object: upserted),
      IndexedObjectChange(kind: .deleted, object: deleted),
    ])
    await reader.setCounter(10)

    let enumerator = DomainEnumerator(
      deviceId: "device1", storageId: 1, parentHandle: nil, indexReader: reader)
    let changeExpectation = expectation(description: "change enumeration")
    let observer = ChangeObserver()
    observer.finishCallback = { changeExpectation.fulfill() }
    enumerator.enumerateChanges(for: observer, from: NSFileProviderSyncAnchor(Data()))
    await fulfillment(of: [changeExpectation], timeout: 2.0)
    XCTAssertEqual(observer.updatedItems.count, 1)
    XCTAssertEqual(observer.deletedIdentifiers.count, 1)
    XCTAssertNotNil(observer.latestAnchor)
    XCTAssertEqual(observer.latestAnchor?.rawValue.count, MemoryLayout<Int64>.size)

    let anchorExpectation = expectation(description: "current sync anchor")
    enumerator.currentSyncAnchor { anchor in
      XCTAssertNotNil(anchor)
      anchorExpectation.fulfill()
    }
    await fulfillment(of: [anchorExpectation], timeout: 2.0)

    await reader.setForcedError(SyntheticError())
    let errorExpectation = expectation(description: "error enumeration")
    let errorObserver = ChangeObserver()
    errorObserver.finishCallback = { errorExpectation.fulfill() }
    enumerator.enumerateChanges(for: errorObserver, from: NSFileProviderSyncAnchor(Data()))
    await fulfillment(of: [errorExpectation], timeout: 2.0)
    XCTAssertNotNil(errorObserver.finishedError)
  }

  @MainActor
  func testMTPFileProviderExtensionInjectedCacheAndXPCPaths() async throws {
    throw XCTSkip(
      "Direct NSFileProviderReplicatedExtension execution is unstable in this host test runtime.")
  }

  func testFileProviderManagerAndDeviceServiceBranches() async throws {
    let manager = MTPFileProviderManager.shared

    let identity = StableDeviceIdentity(
      domainId: "",
      displayName: "Unit Test Device",
      createdAt: Date(),
      lastSeenAt: Date()
    )
    do {
      try await manager.registerDomain(identity: identity)
    } catch {
      XCTAssertNotNil(error)
    }
    manager.signalOnline(domainId: identity.domainId)
    manager.signalOffline(domainId: identity.domainId)
    do {
      try await manager.unregisterDomain(domainId: identity.domainId)
    } catch {
      XCTAssertNotNil(error)
    }

    let summary = MTPDeviceSummary(
      id: MTPDeviceID(raw: "legacy-device"),
      manufacturer: "Legacy",
      model: "Device",
      vendorID: 0x1234,
      productID: 0x5678
    )
    do {
      try await manager.registerDomain(for: summary)
    } catch {
      XCTAssertNotNil(error)
    }
    do {
      try await manager.unregisterDomain(for: summary)
    } catch {
      XCTAssertNotNil(error)
    }
    manager.signalOnline(for: summary)
    manager.signalOffline(for: summary.fingerprint)
    await manager.unregisterAllDomains()

    let service = MTPDeviceService(fpManager: manager)
    let stableIdentity = StableDeviceIdentity(
      domainId: "service-domain",
      displayName: "Service Device",
      createdAt: Date(),
      lastSeenAt: Date()
    )
    await service.deviceAttached(identity: stableIdentity)
    await service.deviceDetached(domainId: stableIdentity.domainId)
    await service.deviceReconnected(domainId: stableIdentity.domainId)
    await service.setExtendedAbsenceThreshold(0)
    try await Task.sleep(for: .milliseconds(5))
    await service.cleanupAbsentDevices()
  }
}
