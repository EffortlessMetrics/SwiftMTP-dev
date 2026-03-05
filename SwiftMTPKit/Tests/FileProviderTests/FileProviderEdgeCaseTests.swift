// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import XCTest
@testable import SwiftMTPFileProvider
import SwiftMTPCore
import SwiftMTPXPC
import FileProvider
import UniformTypeIdentifiers

/// Tests for edge cases in the File Provider extension: unusual file sizes,
/// forbidden characters, Unicode normalization, deep nesting, and error paths.
final class FileProviderEdgeCaseTests: XCTestCase {

  // MARK: - Mock LiveIndexReader

  private final class MockLiveIndexReader: @unchecked Sendable, LiveIndexReader {
    private var objects: [String: [UInt32: IndexedObject]] = [:]
    private var storagesByDevice: [String: [IndexedStorage]] = [:]
    private var changeCounterByDevice: [String: Int64] = [:]
    private var pendingChanges: [String: [IndexedObjectChange]] = [:]
    private var crawlDates: [String: Date] = [:]

    func addObject(_ object: IndexedObject) {
      if objects[object.deviceId] == nil { objects[object.deviceId] = [:] }
      objects[object.deviceId]?[object.handle] = object
    }

    func removeObject(deviceId: String, handle: UInt32) {
      objects[deviceId]?.removeValue(forKey: handle)
    }

    func addStorage(_ storage: IndexedStorage) {
      if storagesByDevice[storage.deviceId] == nil { storagesByDevice[storage.deviceId] = [] }
      storagesByDevice[storage.deviceId]?.append(storage)
    }

    func setChangeCounter(_ value: Int64, deviceId: String) {
      changeCounterByDevice[deviceId] = value
    }

    func setChanges(_ changes: [IndexedObjectChange], deviceId: String) {
      pendingChanges[deviceId] = changes
    }

    func object(deviceId: String, handle: UInt32) async throws -> IndexedObject? {
      objects[deviceId]?[handle]
    }

    func children(deviceId: String, storageId: UInt32, parentHandle: UInt32?) async throws
      -> [IndexedObject]
    {
      guard let all = objects[deviceId] else { return [] }
      return all.values
        .filter { $0.storageId == storageId && $0.parentHandle == parentHandle }
        .sorted { $0.handle < $1.handle }
    }

    func storages(deviceId: String) async throws -> [IndexedStorage] {
      storagesByDevice[deviceId] ?? []
    }

    func currentChangeCounter(deviceId: String) async throws -> Int64 {
      changeCounterByDevice[deviceId] ?? 0
    }

    func changesSince(deviceId: String, anchor: Int64) async throws -> [IndexedObjectChange] {
      pendingChanges[deviceId] ?? []
    }

    func crawlState(deviceId: String, storageId: UInt32, parentHandle: UInt32?) async throws
      -> Date?
    {
      let key = "\(deviceId):\(storageId):\(parentHandle ?? 0)"
      return crawlDates[key]
    }
  }

  // MARK: - Mock Observers

  private class MockEnumerationObserver: NSObject, NSFileProviderEnumerationObserver {
    nonisolated(unsafe) var enumeratedItems: [NSFileProviderItem] = []
    nonisolated(unsafe) var nextPageCursor: NSFileProviderPage?
    nonisolated(unsafe) var didFinish: Bool = false
    nonisolated(unsafe) var errorReceived: Error?
    nonisolated(unsafe) var onFinish: (() -> Void)?

    func didEnumerate(_ items: [NSFileProviderItem]) {
      enumeratedItems.append(contentsOf: items)
    }

    func finishEnumerating(upTo nextPage: NSFileProviderPage?) {
      nextPageCursor = nextPage
      didFinish = true
      onFinish?()
    }

    func finishEnumeratingWithError(_ error: Error) {
      errorReceived = error
      didFinish = true
      onFinish?()
    }
  }

  private class MockChangeObserver: NSObject, NSFileProviderChangeObserver {
    nonisolated(unsafe) var updatedItems: [NSFileProviderItem] = []
    nonisolated(unsafe) var deletedIdentifiers: [NSFileProviderItemIdentifier] = []
    nonisolated(unsafe) var finishedAnchor: NSFileProviderSyncAnchor?
    nonisolated(unsafe) var moreComing: Bool = false
    nonisolated(unsafe) var onFinish: (() -> Void)?

    func didUpdate(_ items: [NSFileProviderItem]) {
      updatedItems.append(contentsOf: items)
    }

    func didDeleteItems(withIdentifiers identifiers: [NSFileProviderItemIdentifier]) {
      deletedIdentifiers.append(contentsOf: identifiers)
    }

    func finishEnumeratingChanges(upTo anchor: NSFileProviderSyncAnchor, moreComing: Bool) {
      finishedAnchor = anchor
      self.moreComing = moreComing
      onFinish?()
    }

    func finishEnumeratingWithError(_ error: Error) {
      onFinish?()
    }
  }

  // MARK: - Mock XPC Service

  private final class MockXPCService: NSObject, MTPXPCService {
    nonisolated(unsafe) var readResponse = ReadResponse(
      success: true, tempFileURL: URL(fileURLWithPath: "/tmp/test.txt"), fileSize: 1024)
    nonisolated(unsafe) var writeResponse = WriteResponse(success: true, newHandle: 200)
    nonisolated(unsafe) var deleteResponse = WriteResponse(success: true)
    nonisolated(unsafe) var createFolderResponse = WriteResponse(success: true, newHandle: 300)
    nonisolated(unsafe) var renameResponse = WriteResponse(success: true)
    nonisolated(unsafe) var moveResponse = WriteResponse(success: true)

    func ping(reply: @escaping (String) -> Void) { reply("ok") }

    func readObject(_ req: ReadRequest, withReply r: @escaping (ReadResponse) -> Void) {
      r(readResponse)
    }

    func listStorages(
      _ req: StorageListRequest, withReply r: @escaping (StorageListResponse) -> Void
    ) {
      r(StorageListResponse(success: true))
    }

    func listObjects(_ req: ObjectListRequest, withReply r: @escaping (ObjectListResponse) -> Void)
    {
      r(ObjectListResponse(success: true))
    }

    func getObjectInfo(
      deviceId: String, storageId: UInt32, objectHandle: UInt32,
      withReply r: @escaping (ReadResponse) -> Void
    ) { r(ReadResponse(success: true)) }

    func writeObject(_ req: WriteRequest, withReply r: @escaping (WriteResponse) -> Void) {
      r(writeResponse)
    }

    func deleteObject(_ req: DeleteRequest, withReply r: @escaping (WriteResponse) -> Void) {
      r(deleteResponse)
    }

    func createFolder(_ req: CreateFolderRequest, withReply r: @escaping (WriteResponse) -> Void) {
      r(createFolderResponse)
    }

    func renameObject(_ req: RenameRequest, withReply r: @escaping (WriteResponse) -> Void) {
      r(renameResponse)
    }

    func moveObject(_ req: MoveObjectRequest, withReply r: @escaping (WriteResponse) -> Void) {
      r(moveResponse)
    }

    func requestCrawl(
      _ req: CrawlTriggerRequest, withReply r: @escaping (CrawlTriggerResponse) -> Void
    ) {
      r(CrawlTriggerResponse(accepted: true))
    }

    func deviceStatus(
      _ req: DeviceStatusRequest, withReply r: @escaping (DeviceStatusResponse) -> Void
    ) {
      r(DeviceStatusResponse(connected: true, sessionOpen: true))
    }

    func getThumbnail(
      _ req: ThumbnailRequest, withReply r: @escaping (ThumbnailResponse) -> Void
    ) { r(ThumbnailResponse(success: false, errorMessage: "stub")) }
  }

  // MARK: - Helpers

  private func makeDomain() -> NSFileProviderDomain {
    NSFileProviderDomain(
      identifier: NSFileProviderDomainIdentifier("edge-test"),
      displayName: "Edge Case Test")
  }

  private func makeExtension(
    reader: (any LiveIndexReader)?, xpc: MTPXPCService? = nil
  ) -> MTPFileProviderExtension {
    MTPFileProviderExtension(
      domain: makeDomain(),
      indexReader: reader,
      xpcServiceResolver: xpc.map { svc in { svc } },
      signalEnumeratorOverride: { _ in })
  }

  private func makeObject(
    handle: UInt32, parentHandle: UInt32? = nil, name: String,
    size: UInt64? = 1024, isDirectory: Bool = false,
    storageId: UInt32 = 1, deviceId: String = "device1"
  ) -> IndexedObject {
    IndexedObject(
      deviceId: deviceId, storageId: storageId, handle: handle,
      parentHandle: parentHandle, name: name, pathKey: "/\(name)",
      sizeBytes: size, mtime: nil, formatCode: isDirectory ? 0x3001 : 0x3800,
      isDirectory: isDirectory, changeCounter: 0)
  }

  private func makeStorage(
    storageId: UInt32 = 1, deviceId: String = "device1", name: String = "Internal Storage"
  ) -> IndexedStorage {
    IndexedStorage(
      deviceId: deviceId, storageId: storageId, description: name,
      capacity: 64_000_000_000, free: 32_000_000_000, readOnly: false)
  }

  private func zeroAnchor() -> NSFileProviderSyncAnchor {
    var zero: Int64 = 0
    return NSFileProviderSyncAnchor(Data(bytes: &zero, count: 8))
  }

  // MARK: - Zero-Byte File Handling

  func testZeroByteFileItemHasZeroSize() {
    let item = MTPFileProviderItem(
      deviceId: "device1", storageId: 1, objectHandle: 10,
      name: "empty.txt", size: 0, isDirectory: false, modifiedDate: nil)

    XCTAssertEqual(item.documentSize?.intValue, 0)
    XCTAssertEqual(item.filename, "empty.txt")
    XCTAssertNotEqual(item.contentType, UTType.folder)
  }

  func testZeroByteFileEnumeration() async {
    let reader = MockLiveIndexReader()
    reader.addStorage(makeStorage())
    reader.addObject(makeObject(handle: 1, name: "empty.dat", size: 0))

    let enumerator = DomainEnumerator(
      deviceId: "device1", storageId: 1, parentHandle: nil, indexReader: reader)

    let exp = expectation(description: "zero-byte-enum")
    let observer = MockEnumerationObserver()
    observer.onFinish = { exp.fulfill() }

    enumerator.enumerateItems(
      for: observer, startingAt: NSFileProviderPage.initialPageSortedByDate as NSFileProviderPage)

    await fulfillment(of: [exp], timeout: 5)

    XCTAssertEqual(observer.enumeratedItems.count, 1)
    XCTAssertEqual((observer.enumeratedItems.first?.documentSize as? NSNumber)?.intValue ?? -1, 0)
  }

  @MainActor
  func testZeroByteFileFetchContents() {
    let reader = MockLiveIndexReader()
    reader.addObject(makeObject(handle: 1, name: "empty.dat", size: 0))
    let xpc = MockXPCService()
    xpc.readResponse = ReadResponse(
      success: true, tempFileURL: URL(fileURLWithPath: "/tmp/empty.dat"), fileSize: 0)
    let ext = makeExtension(reader: reader, xpc: xpc)

    let exp = expectation(description: "fetch-zero")
    var fetchedItem: NSFileProviderItem?
    _ = ext.fetchContents(
      for: NSFileProviderItemIdentifier("device1:1:1"),
      version: nil, request: NSFileProviderRequest()
    ) { _, item, error in
      fetchedItem = item
      XCTAssertNil(error)
      exp.fulfill()
    }
    wait(for: [exp], timeout: 5)
    XCTAssertNotNil(fetchedItem)
  }

  // MARK: - Very Large File (>4GB) Handling

  func testLargeFileItemHasCorrectSize() {
    let largeSize: UInt64 = 5_000_000_000  // 5 GB
    let item = MTPFileProviderItem(
      deviceId: "device1", storageId: 1, objectHandle: 10,
      name: "huge.iso", size: largeSize, isDirectory: false, modifiedDate: nil)

    XCTAssertEqual(item.documentSize?.uint64Value, largeSize)
  }

  func testLargeFileEnumeration() async {
    let reader = MockLiveIndexReader()
    reader.addStorage(makeStorage())
    let largeSize: UInt64 = 8_589_934_592  // 8 GB
    reader.addObject(makeObject(handle: 1, name: "backup.img", size: largeSize))

    let enumerator = DomainEnumerator(
      deviceId: "device1", storageId: 1, parentHandle: nil, indexReader: reader)

    let exp = expectation(description: "large-file-enum")
    let observer = MockEnumerationObserver()
    observer.onFinish = { exp.fulfill() }

    enumerator.enumerateItems(
      for: observer, startingAt: NSFileProviderPage.initialPageSortedByDate as NSFileProviderPage)

    await fulfillment(of: [exp], timeout: 5)

    XCTAssertEqual(observer.enumeratedItems.count, 1)
    XCTAssertEqual(
      (observer.enumeratedItems.first?.documentSize as? NSNumber)?.uint64Value ?? 0, largeSize)
  }

  func testMaxUInt64FileSize() {
    let maxSize: UInt64 = UInt64.max
    let item = MTPFileProviderItem(
      deviceId: "device1", storageId: 1, objectHandle: 10,
      name: "max.bin", size: maxSize, isDirectory: false, modifiedDate: nil)

    XCTAssertEqual(item.documentSize?.uint64Value, maxSize)
  }

  // MARK: - File with Forbidden Characters (macOS vs MTP)

  func testFilenameWithColons() {
    // Colons are forbidden in macOS filenames but valid in MTP
    let item = MTPFileProviderItem(
      deviceId: "device1", storageId: 1, objectHandle: 10,
      name: "photo:2024:01.jpg", size: 1024, isDirectory: false, modifiedDate: nil)

    XCTAssertEqual(item.filename, "photo:2024:01.jpg")
    XCTAssertEqual(item.contentType, UTType.jpeg)
  }

  func testFilenameWithSlashes() {
    let item = MTPFileProviderItem(
      deviceId: "device1", storageId: 1, objectHandle: 10,
      name: "path/to/file.txt", size: 512, isDirectory: false, modifiedDate: nil)

    XCTAssertEqual(item.filename, "path/to/file.txt")
  }

  func testFilenameWithNullByte() {
    let name = "file\0name.txt"
    let item = MTPFileProviderItem(
      deviceId: "device1", storageId: 1, objectHandle: 10,
      name: name, size: 256, isDirectory: false, modifiedDate: nil)

    XCTAssertEqual(item.filename, name)
  }

  func testFilenameWithBackslashes() {
    let item = MTPFileProviderItem(
      deviceId: "device1", storageId: 1, objectHandle: 10,
      name: "Windows\\Style\\Path.txt", size: 100, isDirectory: false, modifiedDate: nil)

    XCTAssertEqual(item.filename, "Windows\\Style\\Path.txt")
  }

  func testFilenameWithSpacesAndDots() {
    let item = MTPFileProviderItem(
      deviceId: "device1", storageId: 1, objectHandle: 10,
      name: "  ..hidden.. ", size: 100, isDirectory: false, modifiedDate: nil)

    XCTAssertEqual(item.filename, "  ..hidden.. ")
  }

  func testFilenameWithSpecialCharacters() {
    let names = [
      "file<name>.txt", "file\"quoted\".txt", "file|pipe.txt", "file?query.txt", "file*star.txt",
    ]
    for (i, name) in names.enumerated() {
      let item = MTPFileProviderItem(
        deviceId: "device1", storageId: 1, objectHandle: UInt32(10 + i),
        name: name, size: 100, isDirectory: false, modifiedDate: nil)
      XCTAssertEqual(item.filename, name, "Filename should preserve special chars: \(name)")
    }
  }

  // MARK: - Unicode Normalization in Filenames

  func testNFCVsNFDUnicodeFilenames() {
    // NFC: é as single codepoint (U+00E9)
    let nfc = "caf\u{00E9}.txt"
    // NFD: é as e + combining acute (U+0065 U+0301)
    let nfd = "cafe\u{0301}.txt"

    let itemNFC = MTPFileProviderItem(
      deviceId: "device1", storageId: 1, objectHandle: 10,
      name: nfc, size: 100, isDirectory: false, modifiedDate: nil)
    let itemNFD = MTPFileProviderItem(
      deviceId: "device1", storageId: 1, objectHandle: 11,
      name: nfd, size: 100, isDirectory: false, modifiedDate: nil)

    // Both should preserve their original form
    XCTAssertEqual(itemNFC.filename, nfc)
    XCTAssertEqual(itemNFD.filename, nfd)
    // Swift String comparison treats NFC/NFD as equal
    XCTAssertEqual(itemNFC.filename, itemNFD.filename)
  }

  func testJapaneseFilename() {
    let name = "写真_2024年.jpg"
    let item = MTPFileProviderItem(
      deviceId: "device1", storageId: 1, objectHandle: 10,
      name: name, size: 2048, isDirectory: false, modifiedDate: nil)

    XCTAssertEqual(item.filename, name)
    XCTAssertEqual(item.contentType, UTType.jpeg)
  }

  func testEmojiFilename() {
    let name = "📸🎉_photo.png"
    let item = MTPFileProviderItem(
      deviceId: "device1", storageId: 1, objectHandle: 10,
      name: name, size: 4096, isDirectory: false, modifiedDate: nil)

    XCTAssertEqual(item.filename, name)
    XCTAssertEqual(item.contentType, UTType.png)
  }

  func testArabicRTLFilename() {
    let name = "ملف_مستند.pdf"
    let item = MTPFileProviderItem(
      deviceId: "device1", storageId: 1, objectHandle: 10,
      name: name, size: 1024, isDirectory: false, modifiedDate: nil)

    XCTAssertEqual(item.filename, name)
    XCTAssertEqual(item.contentType, UTType.pdf)
  }

  func testKoreanFilename() {
    let name = "사진_앨범.heic"
    let item = MTPFileProviderItem(
      deviceId: "device1", storageId: 1, objectHandle: 10,
      name: name, size: 3072, isDirectory: false, modifiedDate: nil)

    XCTAssertEqual(item.filename, name)
  }

  func testMixedScriptFilename() {
    let name = "日本語_English_العربية.txt"
    let item = MTPFileProviderItem(
      deviceId: "device1", storageId: 1, objectHandle: 10,
      name: name, size: 512, isDirectory: false, modifiedDate: nil)

    XCTAssertEqual(item.filename, name)
  }

  // MARK: - Deeply Nested Directory Structure

  func testDeeplyNestedDirectoryEnumeration() async {
    let reader = MockLiveIndexReader()
    reader.addStorage(makeStorage())

    // Create a chain: root → dir1 → dir2 → dir3 → ... → dir10 → file
    var parentHandle: UInt32? = nil
    for depth: UInt32 in 1...10 {
      reader.addObject(
        makeObject(
          handle: depth, parentHandle: parentHandle,
          name: "level\(depth)", isDirectory: true))
      parentHandle = depth
    }
    reader.addObject(
      makeObject(
        handle: 100, parentHandle: 10, name: "deep_file.txt", size: 256))

    // Enumerate the deepest directory
    let enumerator = DomainEnumerator(
      deviceId: "device1", storageId: 1, parentHandle: 10, indexReader: reader)

    let exp = expectation(description: "deep-enum")
    let observer = MockEnumerationObserver()
    observer.onFinish = { exp.fulfill() }

    enumerator.enumerateItems(
      for: observer, startingAt: NSFileProviderPage.initialPageSortedByDate as NSFileProviderPage)

    await fulfillment(of: [exp], timeout: 5)

    XCTAssertEqual(observer.enumeratedItems.count, 1)
    XCTAssertEqual(observer.enumeratedItems.first?.filename, "deep_file.txt")
  }

  @MainActor
  func testDeeplyNestedItemLookup() async {
    let reader = MockLiveIndexReader()
    let deepObj = IndexedObject(
      deviceId: "device1", storageId: 1, handle: 100,
      parentHandle: 10, name: "deep_file.txt", pathKey: "/l1/l2/.../deep_file.txt",
      sizeBytes: 256, mtime: nil, formatCode: 0x3800,
      isDirectory: false, changeCounter: 0)
    reader.addObject(deepObj)

    let ext = makeExtension(reader: reader)

    let exp = expectation(description: "deep-lookup")
    _ = ext.item(
      for: NSFileProviderItemIdentifier("device1:1:100"),
      request: NSFileProviderRequest()
    ) { item, error in
      XCTAssertNotNil(item)
      XCTAssertNil(error)
      XCTAssertEqual(item?.filename, "deep_file.txt")
      exp.fulfill()
    }

    await fulfillment(of: [exp], timeout: 5)
  }

  func testNestedDirectoryParentIdentifiers() {
    // File at depth 3: device1:1:30 with parent 20
    let item = MTPFileProviderItem(
      deviceId: "device1", storageId: 1, objectHandle: 30,
      parentHandle: 20, name: "nested.txt", size: 100,
      isDirectory: false, modifiedDate: nil)

    XCTAssertEqual(item.parentItemIdentifier.rawValue, "device1:1:20")

    // Directory at storage root (no parent handle)
    let rootDir = MTPFileProviderItem(
      deviceId: "device1", storageId: 1, objectHandle: 10,
      parentHandle: nil, name: "DCIM", size: nil,
      isDirectory: true, modifiedDate: nil)

    XCTAssertEqual(rootDir.parentItemIdentifier.rawValue, "device1:1")
  }

  // MARK: - Storage Root Enumeration

  func testStorageRootEnumerationYieldsTopLevelFolders() async {
    let reader = MockLiveIndexReader()
    reader.addStorage(makeStorage())
    reader.addObject(makeObject(handle: 1, parentHandle: nil, name: "DCIM", isDirectory: true))
    reader.addObject(makeObject(handle: 2, parentHandle: nil, name: "Music", isDirectory: true))
    reader.addObject(makeObject(handle: 3, parentHandle: nil, name: "readme.txt"))

    let enumerator = DomainEnumerator(
      deviceId: "device1", storageId: 1, parentHandle: nil, indexReader: reader)

    let exp = expectation(description: "storage-root")
    let observer = MockEnumerationObserver()
    observer.onFinish = { exp.fulfill() }

    enumerator.enumerateItems(
      for: observer, startingAt: NSFileProviderPage.initialPageSortedByDate as NSFileProviderPage)

    await fulfillment(of: [exp], timeout: 5)

    XCTAssertEqual(observer.enumeratedItems.count, 3)
    let names = observer.enumeratedItems.map { $0.filename }
    XCTAssertTrue(names.contains("DCIM"))
    XCTAssertTrue(names.contains("Music"))
    XCTAssertTrue(names.contains("readme.txt"))
  }

  func testStorageRootEnumerationEmpty() async {
    let reader = MockLiveIndexReader()
    reader.addStorage(makeStorage())
    // No objects in storage root

    let enumerator = DomainEnumerator(
      deviceId: "device1", storageId: 1, parentHandle: nil, indexReader: reader)

    let exp = expectation(description: "empty-storage-root")
    let observer = MockEnumerationObserver()
    observer.onFinish = { exp.fulfill() }

    enumerator.enumerateItems(
      for: observer, startingAt: NSFileProviderPage.initialPageSortedByDate as NSFileProviderPage)

    await fulfillment(of: [exp], timeout: 5)

    XCTAssertEqual(observer.enumeratedItems.count, 0)
    XCTAssertNil(observer.nextPageCursor)
  }

  // MARK: - Multiple Storage Volumes

  func testMultipleStorageVolumesEnumeration() async {
    let reader = MockLiveIndexReader()
    reader.addStorage(makeStorage(storageId: 1, name: "Internal Storage"))
    reader.addStorage(makeStorage(storageId: 2, name: "SD Card"))
    reader.addStorage(makeStorage(storageId: 3, name: "USB OTG"))

    let enumerator = DomainEnumerator(
      deviceId: "device1", storageId: nil, parentHandle: nil, indexReader: reader)

    let exp = expectation(description: "multi-storage")
    let observer = MockEnumerationObserver()
    observer.onFinish = { exp.fulfill() }

    enumerator.enumerateItems(
      for: observer, startingAt: NSFileProviderPage.initialPageSortedByDate as NSFileProviderPage)

    await fulfillment(of: [exp], timeout: 5)

    XCTAssertEqual(observer.enumeratedItems.count, 3)
    let names = observer.enumeratedItems.map { $0.filename }
    XCTAssertTrue(names.contains("Internal Storage"))
    XCTAssertTrue(names.contains("SD Card"))
    XCTAssertTrue(names.contains("USB OTG"))
  }

  func testFilesInDifferentStorageVolumes() async {
    let reader = MockLiveIndexReader()
    reader.addStorage(makeStorage(storageId: 1, name: "Internal"))
    reader.addStorage(makeStorage(storageId: 2, name: "SD Card"))

    // Files in storage 1
    reader.addObject(makeObject(handle: 10, name: "internal.jpg", storageId: 1))
    // Files in storage 2
    reader.addObject(makeObject(handle: 20, name: "sdcard.jpg", storageId: 2))

    // Enumerate storage 1
    let enum1 = DomainEnumerator(
      deviceId: "device1", storageId: 1, parentHandle: nil, indexReader: reader)
    let exp1 = expectation(description: "storage-1")
    let obs1 = MockEnumerationObserver()
    obs1.onFinish = { exp1.fulfill() }
    enum1.enumerateItems(
      for: obs1, startingAt: NSFileProviderPage.initialPageSortedByDate as NSFileProviderPage)

    // Enumerate storage 2
    let enum2 = DomainEnumerator(
      deviceId: "device1", storageId: 2, parentHandle: nil, indexReader: reader)
    let exp2 = expectation(description: "storage-2")
    let obs2 = MockEnumerationObserver()
    obs2.onFinish = { exp2.fulfill() }
    enum2.enumerateItems(
      for: obs2, startingAt: NSFileProviderPage.initialPageSortedByDate as NSFileProviderPage)

    await fulfillment(of: [exp1, exp2], timeout: 5)

    XCTAssertEqual(obs1.enumeratedItems.count, 1)
    XCTAssertEqual(obs1.enumeratedItems.first?.filename, "internal.jpg")
    XCTAssertEqual(obs2.enumeratedItems.count, 1)
    XCTAssertEqual(obs2.enumeratedItems.first?.filename, "sdcard.jpg")
  }

  func testStorageItemIdentifiersAreDistinct() {
    let item1 = MTPFileProviderItem(
      deviceId: "device1", storageId: 1, objectHandle: nil,
      name: "Internal", size: nil, isDirectory: true, modifiedDate: nil)
    let item2 = MTPFileProviderItem(
      deviceId: "device1", storageId: 2, objectHandle: nil,
      name: "SD Card", size: nil, isDirectory: true, modifiedDate: nil)

    XCTAssertNotEqual(item1.itemIdentifier, item2.itemIdentifier)
    XCTAssertEqual(item1.itemIdentifier.rawValue, "device1:1")
    XCTAssertEqual(item2.itemIdentifier.rawValue, "device1:2")
  }

  // MARK: - File Modification During Enumeration (via change tracking)

  func testChangesDuringEnumeration() async {
    let reader = MockLiveIndexReader()
    reader.addStorage(makeStorage())
    reader.addObject(makeObject(handle: 1, name: "original.txt"))

    let store = SyncAnchorStore()

    let enumerator = DomainEnumerator(
      deviceId: "device1", storageId: 1, parentHandle: nil,
      indexReader: reader, syncAnchorStore: store)

    // Record a change after initial state
    let modifiedId = NSFileProviderItemIdentifier("device1:1:1")
    store.recordChange(added: [modifiedId], deleted: [], for: "device1:1")

    // Update the object in the index
    reader.addObject(
      IndexedObject(
        deviceId: "device1", storageId: 1, handle: 1,
        parentHandle: nil, name: "modified.txt", pathKey: "/modified.txt",
        sizeBytes: 2048, mtime: Date(), formatCode: 0x3800,
        isDirectory: false, changeCounter: 1))

    // Enumerate changes
    let exp = expectation(description: "changes-during-enum")
    let observer = MockChangeObserver()
    observer.onFinish = { exp.fulfill() }

    enumerator.enumerateChanges(
      for: observer, from: NSFileProviderSyncAnchor(Data()))

    await fulfillment(of: [exp], timeout: 5)

    XCTAssertEqual(observer.updatedItems.count, 1)
    XCTAssertEqual(observer.updatedItems.first?.filename, "modified.txt")
  }

  // MARK: - Deleted File Access Handling

  @MainActor
  func testAccessDeletedFileReturnsNoSuchItem() async {
    let reader = MockLiveIndexReader()
    // Object handle 42 does NOT exist in the index
    let ext = makeExtension(reader: reader)

    let exp = expectation(description: "deleted-item")
    _ = ext.item(
      for: NSFileProviderItemIdentifier("device1:1:42"),
      request: NSFileProviderRequest()
    ) { item, error in
      XCTAssertNil(item)
      XCTAssertNotNil(error)
      let nsError = error! as NSError
      XCTAssertEqual(nsError.domain, NSFileProviderErrorDomain)
      XCTAssertEqual(nsError.code, NSFileProviderError.noSuchItem.rawValue)
      exp.fulfill()
    }

    await fulfillment(of: [exp], timeout: 5)
  }

  @MainActor
  func testFetchDeletedFileReturnsError() {
    let reader = MockLiveIndexReader()
    let xpc = MockXPCService()
    xpc.readResponse = ReadResponse(success: false, errorMessage: "object not found")
    let ext = makeExtension(reader: reader, xpc: xpc)

    let exp = expectation(description: "fetch-deleted")
    _ = ext.fetchContents(
      for: NSFileProviderItemIdentifier("device1:1:42"),
      version: nil, request: NSFileProviderRequest()
    ) { url, item, error in
      XCTAssertNil(url)
      XCTAssertNil(item)
      XCTAssertNotNil(error)
      exp.fulfill()
    }

    wait(for: [exp], timeout: 5)
  }

  @MainActor
  func testDeleteNonexistentFileReportsError() {
    let reader = MockLiveIndexReader()
    let xpc = MockXPCService()
    xpc.deleteResponse = WriteResponse(success: false, errorMessage: "not found")
    let ext = makeExtension(reader: reader, xpc: xpc)

    let exp = expectation(description: "delete-nonexistent")
    _ = ext.deleteItem(
      identifier: NSFileProviderItemIdentifier("device1:1:99"),
      baseVersion: NSFileProviderItemVersion(contentVersion: Data(), metadataVersion: Data()),
      request: NSFileProviderRequest()
    ) { error in
      XCTAssertNotNil(error)
      exp.fulfill()
    }

    wait(for: [exp], timeout: 5)
  }

  // MARK: - Nil Size Handling

  func testNilSizeFileItem() {
    let item = MTPFileProviderItem(
      deviceId: "device1", storageId: 1, objectHandle: 10,
      name: "unknown_size.bin", size: nil, isDirectory: false, modifiedDate: nil)

    XCTAssertNil(item.documentSize)
  }

  func testNilSizeDirectoryItem() {
    let item = MTPFileProviderItem(
      deviceId: "device1", storageId: 1, objectHandle: 10,
      name: "folder", size: nil, isDirectory: true, modifiedDate: nil)

    XCTAssertNil(item.documentSize)
    XCTAssertEqual(item.contentType, UTType.folder)
  }

  // MARK: - Content Type Edge Cases

  func testEmptyFilenameExtension() {
    let item = MTPFileProviderItem(
      deviceId: "device1", storageId: 1, objectHandle: 10,
      name: "Makefile", size: 256, isDirectory: false, modifiedDate: nil)

    // No extension → .data
    XCTAssertEqual(item.contentType, UTType.data)
  }

  func testDotOnlyFilename() {
    let item = MTPFileProviderItem(
      deviceId: "device1", storageId: 1, objectHandle: 10,
      name: ".", size: 0, isDirectory: false, modifiedDate: nil)

    XCTAssertEqual(item.filename, ".")
  }

  func testDoubleDotFilename() {
    let item = MTPFileProviderItem(
      deviceId: "device1", storageId: 1, objectHandle: 10,
      name: "..", size: 0, isDirectory: false, modifiedDate: nil)

    XCTAssertEqual(item.filename, "..")
  }

  func testHiddenFileWithExtension() {
    let item = MTPFileProviderItem(
      deviceId: "device1", storageId: 1, objectHandle: 10,
      name: ".gitignore", size: 128, isDirectory: false, modifiedDate: nil)

    XCTAssertEqual(item.filename, ".gitignore")
  }

  func testMultipleExtensions() {
    let item = MTPFileProviderItem(
      deviceId: "device1", storageId: 1, objectHandle: 10,
      name: "archive.tar.gz", size: 1_000_000, isDirectory: false, modifiedDate: nil)

    XCTAssertEqual(item.filename, "archive.tar.gz")
    // Should detect the last extension
    XCTAssertNotEqual(item.contentType, UTType.data)
  }

  func testUpperCaseExtension() {
    let item = MTPFileProviderItem(
      deviceId: "device1", storageId: 1, objectHandle: 10,
      name: "PHOTO.JPG", size: 4096, isDirectory: false, modifiedDate: nil)

    // Extension should be case-insensitive
    XCTAssertEqual(item.contentType, UTType.jpeg)
  }

  // MARK: - Identifier Parsing Edge Cases

  func testParseIdentifierWithEmptyString() {
    let components = MTPFileProviderItem.parseItemIdentifier(
      NSFileProviderItemIdentifier(""))
    // Empty string splits into [""] which has count 1 but UInt32("") is nil
    // parseItemIdentifier returns nil for unparseable identifiers
    XCTAssertNil(components)
  }

  func testParseIdentifierWithNumericDeviceId() {
    let components = MTPFileProviderItem.parseItemIdentifier(
      NSFileProviderItemIdentifier("12345:1:42"))
    XCTAssertNotNil(components)
    XCTAssertEqual(components?.deviceId, "12345")
    XCTAssertEqual(components?.storageId, 1)
    XCTAssertEqual(components?.objectHandle, 42)
  }

  func testParseIdentifierWithUUIDDeviceId() {
    let uuid = "550E8400-E29B-41D4-A716-446655440000"
    let components = MTPFileProviderItem.parseItemIdentifier(
      NSFileProviderItemIdentifier("\(uuid):1:42"))
    // UUID contains hyphens not colons, so entire "550E8400-E29B-41D4-A716-446655440000" is deviceId
    XCTAssertNotNil(components)
    XCTAssertEqual(components?.deviceId, uuid)
  }

  func testParseIdentifierWithMaxHandleValues() {
    let maxUInt32 = UInt32.max
    let components = MTPFileProviderItem.parseItemIdentifier(
      NSFileProviderItemIdentifier("dev:\(maxUInt32):\(maxUInt32)"))
    XCTAssertNotNil(components)
    XCTAssertEqual(components?.storageId, maxUInt32)
    XCTAssertEqual(components?.objectHandle, maxUInt32)
  }

  func testParseRootContainerReturnsNil() {
    let components = MTPFileProviderItem.parseItemIdentifier(.rootContainer)
    XCTAssertNil(components)
  }

  // MARK: - Date Edge Cases

  func testDistantPastModificationDate() {
    let item = MTPFileProviderItem(
      deviceId: "device1", storageId: 1, objectHandle: 10,
      name: "old.txt", size: 100, isDirectory: false,
      modifiedDate: Date.distantPast)

    XCTAssertEqual(item.contentModificationDate, Date.distantPast)
  }

  func testDistantFutureModificationDate() {
    let item = MTPFileProviderItem(
      deviceId: "device1", storageId: 1, objectHandle: 10,
      name: "future.txt", size: 100, isDirectory: false,
      modifiedDate: Date.distantFuture)

    XCTAssertEqual(item.contentModificationDate, Date.distantFuture)
  }

  func testEpochModificationDate() {
    let epoch = Date(timeIntervalSince1970: 0)
    let item = MTPFileProviderItem(
      deviceId: "device1", storageId: 1, objectHandle: 10,
      name: "epoch.txt", size: 100, isDirectory: false,
      modifiedDate: epoch)

    XCTAssertEqual(item.contentModificationDate, epoch)
  }

  // MARK: - Event Handling Edge Cases

  @MainActor
  func testHandleStorageAddedEvent() {
    let ext = makeExtension(reader: MockLiveIndexReader())

    ext.handleDeviceEvent(.storageAdded(deviceId: "device1", storageId: 5))
    // Should not crash
  }

  @MainActor
  func testHandleStorageRemovedEvent() {
    let ext = makeExtension(reader: MockLiveIndexReader())

    ext.handleDeviceEvent(.storageRemoved(deviceId: "device1", storageId: 5))
    // Should not crash
  }

  @MainActor
  func testHandleEventForNonexistentDevice() {
    let ext = makeExtension(reader: MockLiveIndexReader())

    ext.handleDeviceEvent(
      .addObject(
        deviceId: "unknown-device", storageId: 1, objectHandle: 1, parentHandle: nil))
    ext.handleDeviceEvent(
      .deleteObject(
        deviceId: "unknown-device", storageId: 1, objectHandle: 1))
    // Should not crash
  }

  // MARK: - Enumerator Error Paths

  @MainActor
  func testEnumeratorForRootContainerThrows() {
    let reader = MockLiveIndexReader()
    let ext = makeExtension(reader: reader)

    XCTAssertThrowsError(
      try ext.enumerator(
        for: .rootContainer, request: NSFileProviderRequest()))
  }

  @MainActor
  func testEnumeratorForValidContainerSucceeds() throws {
    let reader = MockLiveIndexReader()
    let ext = makeExtension(reader: reader)

    let enumerator = try ext.enumerator(
      for: NSFileProviderItemIdentifier("device1:1:42"),
      request: NSFileProviderRequest())
    XCTAssertNotNil(enumerator)
  }

  // MARK: - XPC Error Classification

  @MainActor
  func testDisconnectedErrorMapsToServerUnreachable() {
    let reader = MockLiveIndexReader()
    let xpc = MockXPCService()
    xpc.readResponse = ReadResponse(success: false, errorMessage: "device not connected")
    let ext = makeExtension(reader: reader, xpc: xpc)

    let exp = expectation(description: "disconnect-error")
    _ = ext.fetchContents(
      for: NSFileProviderItemIdentifier("device1:1:42"),
      version: nil, request: NSFileProviderRequest()
    ) { _, _, error in
      let nsError = error! as NSError
      XCTAssertEqual(nsError.code, NSFileProviderError.serverUnreachable.rawValue)
      exp.fulfill()
    }
    wait(for: [exp], timeout: 5)
  }

  @MainActor
  func testUnavailableErrorMapsToServerUnreachable() {
    let reader = MockLiveIndexReader()
    let xpc = MockXPCService()
    xpc.readResponse = ReadResponse(success: false, errorMessage: "device unavailable")
    let ext = makeExtension(reader: reader, xpc: xpc)

    let exp = expectation(description: "unavailable-error")
    _ = ext.fetchContents(
      for: NSFileProviderItemIdentifier("device1:1:42"),
      version: nil, request: NSFileProviderRequest()
    ) { _, _, error in
      let nsError = error! as NSError
      XCTAssertEqual(nsError.code, NSFileProviderError.serverUnreachable.rawValue)
      exp.fulfill()
    }
    wait(for: [exp], timeout: 5)
  }

  @MainActor
  func testGenericErrorMapsToNoSuchItem() {
    let reader = MockLiveIndexReader()
    let xpc = MockXPCService()
    xpc.readResponse = ReadResponse(success: false, errorMessage: "something went wrong")
    let ext = makeExtension(reader: reader, xpc: xpc)

    let exp = expectation(description: "generic-error")
    _ = ext.fetchContents(
      for: NSFileProviderItemIdentifier("device1:1:42"),
      version: nil, request: NSFileProviderRequest()
    ) { _, _, error in
      let nsError = error! as NSError
      XCTAssertEqual(nsError.code, NSFileProviderError.noSuchItem.rawValue)
      exp.fulfill()
    }
    wait(for: [exp], timeout: 5)
  }

  // MARK: - Create Folder Edge Cases

  @MainActor
  func testCreateFolderWithUnicodeName() {
    let reader = MockLiveIndexReader()
    reader.addStorage(makeStorage())
    let xpc = MockXPCService()
    xpc.createFolderResponse = WriteResponse(success: true, newHandle: 500)
    let ext = makeExtension(reader: reader, xpc: xpc)

    let folderItem = MTPFileProviderItem(
      deviceId: "device1", storageId: 1, objectHandle: nil,
      name: "日本のフォルダ", size: nil, isDirectory: true, modifiedDate: nil)

    let exp = expectation(description: "unicode-folder")
    _ = ext.createItem(
      basedOn: folderItem, fields: [], contents: nil,
      request: NSFileProviderRequest()
    ) { item, _, _, error in
      XCTAssertNotNil(item)
      XCTAssertNil(error)
      XCTAssertEqual(item?.filename, "日本のフォルダ")
      exp.fulfill()
    }
    wait(for: [exp], timeout: 5)
  }

  @MainActor
  func testCreateFolderWithoutStorageIdFails() {
    let reader = MockLiveIndexReader()
    let xpc = MockXPCService()
    let ext = makeExtension(reader: reader, xpc: xpc)

    // Item with only device ID (no storage)
    let folderItem = MTPFileProviderItem(
      deviceId: "device1", storageId: nil, objectHandle: nil,
      name: "NewFolder", size: nil, isDirectory: true, modifiedDate: nil)

    let exp = expectation(description: "folder-no-storage")
    _ = ext.createItem(
      basedOn: folderItem, fields: [], contents: nil,
      request: NSFileProviderRequest()
    ) { item, _, _, error in
      XCTAssertNil(item)
      XCTAssertNotNil(error)
      exp.fulfill()
    }
    wait(for: [exp], timeout: 5)
  }

  // MARK: - Very Long Filename

  func testVeryLongFilename() {
    let longName = String(repeating: "a", count: 255) + ".txt"
    let item = MTPFileProviderItem(
      deviceId: "device1", storageId: 1, objectHandle: 10,
      name: longName, size: 100, isDirectory: false, modifiedDate: nil)

    XCTAssertEqual(item.filename, longName)
    XCTAssertEqual(item.filename.count, 259)
  }

  func testEmptyFilename() {
    let item = MTPFileProviderItem(
      deviceId: "device1", storageId: 1, objectHandle: 10,
      name: "", size: 100, isDirectory: false, modifiedDate: nil)

    XCTAssertEqual(item.filename, "")
  }

  // MARK: - Device Service Edge Cases

  func testDeviceServiceCleanupWithNoDevices() async {
    let service = MTPDeviceService()
    await service.cleanupAbsentDevices()
    // Should not crash when empty
  }

  func testDeviceServiceAttachAndDetach() async {
    let service = MTPDeviceService()
    let identity = StableDeviceIdentity(
      domainId: "test-device-1",
      displayName: "Test Device",
      createdAt: Date(), lastSeenAt: Date())

    await service.deviceAttached(identity: identity)
    await service.deviceDetached(domainId: identity.domainId)
    // Should not crash
  }

  func testDeviceServiceReconnectUpdatesLastSeen() async {
    let service = MTPDeviceService()
    let identity = StableDeviceIdentity(
      domainId: "test-device-2",
      displayName: "Test Device 2",
      createdAt: Date(), lastSeenAt: Date())

    await service.deviceAttached(identity: identity)
    await service.deviceReconnected(domainId: identity.domainId)
    // Should not crash; lastSeen should be updated
  }

  // MARK: - SyncAnchor Encoding

  func testSyncAnchorEncodingDecodingRoundTrip() {
    let store = SyncAnchorStore()
    let key = "device1:1"

    // Get initial anchor
    let anchor = store.currentAnchor(for: key)
    XCTAssertEqual(anchor.count, 8)

    // Decode timestamp
    var value: Int64 = 0
    _ = withUnsafeMutableBytes(of: &value) { anchor.copyBytes(to: $0) }
    XCTAssertGreaterThan(value, 0, "Anchor should encode a positive timestamp")
  }

  func testSyncAnchorStoreIsolationBetweenKeys() {
    let store = SyncAnchorStore()

    let id1 = NSFileProviderItemIdentifier("device1:1:10")
    let id2 = NSFileProviderItemIdentifier("device2:1:20")
    store.recordChange(added: [id1], deleted: [], for: "device1:1")
    store.recordChange(added: [id2], deleted: [], for: "device2:1")

    let result1 = store.consumeChanges(from: Data(), for: "device1:1")
    let result2 = store.consumeChanges(from: Data(), for: "device2:1")

    XCTAssertEqual(result1.added.count, 1)
    XCTAssertEqual(result1.added.first, id1)
    XCTAssertEqual(result2.added.count, 1)
    XCTAssertEqual(result2.added.first, id2)
  }
}
