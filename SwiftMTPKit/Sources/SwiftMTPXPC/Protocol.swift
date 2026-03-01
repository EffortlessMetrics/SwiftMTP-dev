// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation

/// Request/Response types for XPC communication
/// These must be classes conforming to NSSecureCoding and Sendable to be used in @objc XPC protocols

@objc(ReadRequest)
public final class ReadRequest: NSObject, NSSecureCoding, Sendable {
  public static let supportsSecureCoding: Bool = true

  public let deviceId: String
  public let objectHandle: UInt32
  public let bookmark: Data?

  public init(deviceId: String, objectHandle: UInt32, bookmark: Data? = nil) {
    self.deviceId = deviceId
    self.objectHandle = objectHandle
    self.bookmark = bookmark
    super.init()
  }

  public func encode(with coder: NSCoder) {
    coder.encode(deviceId, forKey: "deviceId")
    coder.encode(Int64(objectHandle), forKey: "objectHandle")
    coder.encode(bookmark, forKey: "bookmark")
  }

  public init?(coder: NSCoder) {
    guard let deviceId = coder.decodeObject(of: NSString.self, forKey: "deviceId") as String? else {
      return nil
    }
    self.deviceId = deviceId
    self.objectHandle = UInt32(coder.decodeInt64(forKey: "objectHandle"))
    self.bookmark = coder.decodeObject(of: NSData.self, forKey: "bookmark") as Data?
  }
}

@objc(ReadResponse)
public final class ReadResponse: NSObject, NSSecureCoding, Sendable {
  public static let supportsSecureCoding: Bool = true

  public let success: Bool
  public let errorMessage: String?
  public let tempFileURL: URL?
  public let fileSize: UInt64?

  public init(
    success: Bool, errorMessage: String? = nil, tempFileURL: URL? = nil, fileSize: UInt64? = nil
  ) {
    self.success = success
    self.errorMessage = errorMessage
    self.tempFileURL = tempFileURL
    self.fileSize = fileSize
    super.init()
  }

  public func encode(with coder: NSCoder) {
    coder.encode(success, forKey: "success")
    coder.encode(errorMessage, forKey: "errorMessage")
    coder.encode(tempFileURL, forKey: "tempFileURL")
    if let fileSize = fileSize { coder.encode(Int64(bitPattern: fileSize), forKey: "fileSize") }
  }

  public init?(coder: NSCoder) {
    self.success = coder.decodeBool(forKey: "success")
    self.errorMessage = coder.decodeObject(of: NSString.self, forKey: "errorMessage") as String?
    self.tempFileURL = coder.decodeObject(of: NSURL.self, forKey: "tempFileURL") as URL?
    if coder.containsValue(forKey: "fileSize") {
      self.fileSize = UInt64(bitPattern: coder.decodeInt64(forKey: "fileSize"))
    } else {
      self.fileSize = nil
    }
  }
}

@objc(StorageInfo)
public final class StorageInfo: NSObject, NSSecureCoding, Sendable {
  public static let supportsSecureCoding: Bool = true

  public let storageId: UInt32
  public let storageDescription: String
  public let capacityBytes: UInt64
  public let freeBytes: UInt64

  public init(storageId: UInt32, description: String, capacityBytes: UInt64, freeBytes: UInt64) {
    self.storageId = storageId
    self.storageDescription = description
    self.capacityBytes = capacityBytes
    self.freeBytes = freeBytes
    super.init()
  }

  public func encode(with coder: NSCoder) {
    coder.encode(Int64(bitPattern: UInt64(storageId)), forKey: "storageId")
    coder.encode(storageDescription, forKey: "storageDescription")
    coder.encode(Int64(bitPattern: capacityBytes), forKey: "capacityBytes")
    coder.encode(Int64(bitPattern: freeBytes), forKey: "freeBytes")
  }

  public init?(coder: NSCoder) {
    self.storageId = UInt32(UInt64(bitPattern: coder.decodeInt64(forKey: "storageId")))
    guard
      let description = coder.decodeObject(of: NSString.self, forKey: "storageDescription")
        as String?
    else { return nil }
    self.storageDescription = description
    self.capacityBytes = UInt64(bitPattern: coder.decodeInt64(forKey: "capacityBytes"))
    self.freeBytes = UInt64(bitPattern: coder.decodeInt64(forKey: "freeBytes"))
  }
}

@objc(StorageListRequest)
public final class StorageListRequest: NSObject, NSSecureCoding, Sendable {
  public static let supportsSecureCoding: Bool = true
  public let deviceId: String
  public init(deviceId: String) {
    self.deviceId = deviceId
    super.init()
  }
  public func encode(with coder: NSCoder) { coder.encode(deviceId, forKey: "deviceId") }
  public init?(coder: NSCoder) {
    guard let deviceId = coder.decodeObject(of: NSString.self, forKey: "deviceId") as String? else {
      return nil
    }
    self.deviceId = deviceId
  }
}

@objc(StorageListResponse)
public final class StorageListResponse: NSObject, NSSecureCoding, Sendable {
  public static let supportsSecureCoding: Bool = true
  public let success: Bool
  public let errorMessage: String?
  public let storages: [StorageInfo]?

  public init(success: Bool, errorMessage: String? = nil, storages: [StorageInfo]? = nil) {
    self.success = success
    self.errorMessage = errorMessage
    self.storages = storages
    super.init()
  }

  public func encode(with coder: NSCoder) {
    coder.encode(success, forKey: "success")
    coder.encode(errorMessage, forKey: "errorMessage")
    coder.encode(storages, forKey: "storages")
  }

  public init?(coder: NSCoder) {
    self.success = coder.decodeBool(forKey: "success")
    self.errorMessage = coder.decodeObject(of: NSString.self, forKey: "errorMessage") as String?
    self.storages =
      coder.decodeObject(of: [NSArray.self, StorageInfo.self], forKey: "storages") as? [StorageInfo]
  }
}

@objc(ObjectInfo)
public final class ObjectInfo: NSObject, NSSecureCoding, Sendable {
  public static let supportsSecureCoding: Bool = true
  public let handle: UInt32
  public let name: String
  public let sizeBytes: UInt64?
  public let isDirectory: Bool
  public let modifiedDate: Date?

  public init(
    handle: UInt32, name: String, sizeBytes: UInt64?, isDirectory: Bool, modifiedDate: Date?
  ) {
    self.handle = handle
    self.name = name
    self.sizeBytes = sizeBytes
    self.isDirectory = isDirectory
    self.modifiedDate = modifiedDate
    super.init()
  }

  public func encode(with coder: NSCoder) {
    coder.encode(Int64(handle), forKey: "handle")
    coder.encode(name, forKey: "name")
    if let sizeBytes = sizeBytes { coder.encode(Int64(bitPattern: sizeBytes), forKey: "sizeBytes") }
    coder.encode(isDirectory, forKey: "isDirectory")
    coder.encode(modifiedDate, forKey: "modifiedDate")
  }

  public init?(coder: NSCoder) {
    self.handle = UInt32(coder.decodeInt64(forKey: "handle"))
    guard let name = coder.decodeObject(of: NSString.self, forKey: "name") as String? else {
      return nil
    }
    self.name = name
    if coder.containsValue(forKey: "sizeBytes") {
      self.sizeBytes = UInt64(bitPattern: coder.decodeInt64(forKey: "sizeBytes"))
    } else {
      self.sizeBytes = nil
    }
    self.isDirectory = coder.decodeBool(forKey: "isDirectory")
    self.modifiedDate = coder.decodeObject(of: NSDate.self, forKey: "modifiedDate") as Date?
  }
}

@objc(ObjectListRequest)
public final class ObjectListRequest: NSObject, NSSecureCoding, Sendable {
  public static let supportsSecureCoding: Bool = true
  public let deviceId: String
  public let storageId: UInt32
  public let parentHandle: UInt32?

  public init(deviceId: String, storageId: UInt32, parentHandle: UInt32? = nil) {
    self.deviceId = deviceId
    self.storageId = storageId
    self.parentHandle = parentHandle
    super.init()
  }

  public func encode(with coder: NSCoder) {
    coder.encode(deviceId, forKey: "deviceId")
    coder.encode(Int64(storageId), forKey: "storageId")
    if let parentHandle = parentHandle { coder.encode(Int64(parentHandle), forKey: "parentHandle") }
  }

  public init?(coder: NSCoder) {
    guard let deviceId = coder.decodeObject(of: NSString.self, forKey: "deviceId") as String? else {
      return nil
    }
    self.deviceId = deviceId
    self.storageId = UInt32(coder.decodeInt64(forKey: "storageId"))
    if coder.containsValue(forKey: "parentHandle") {
      self.parentHandle = UInt32(coder.decodeInt64(forKey: "parentHandle"))
    } else {
      self.parentHandle = nil
    }
  }
}

@objc(ObjectListResponse)
public final class ObjectListResponse: NSObject, NSSecureCoding, Sendable {
  public static let supportsSecureCoding: Bool = true
  public let success: Bool
  public let errorMessage: String?
  public let objects: [ObjectInfo]?

  public init(success: Bool, errorMessage: String? = nil, objects: [ObjectInfo]? = nil) {
    self.success = success
    self.errorMessage = errorMessage
    self.objects = objects
    super.init()
  }

  public func encode(with coder: NSCoder) {
    coder.encode(success, forKey: "success")
    coder.encode(errorMessage, forKey: "errorMessage")
    coder.encode(objects, forKey: "objects")
  }

  public init?(coder: NSCoder) {
    self.success = coder.decodeBool(forKey: "success")
    self.errorMessage = coder.decodeObject(of: NSString.self, forKey: "errorMessage") as String?
    self.objects =
      coder.decodeObject(of: [NSArray.self, ObjectInfo.self], forKey: "objects") as? [ObjectInfo]
  }
}

/// XPC service protocol that the File Provider extension calls
@MainActor
@objc public protocol MTPXPCService {
  func ping(reply: @escaping (String) -> Void)
  func readObject(_ request: ReadRequest, withReply reply: @escaping (ReadResponse) -> Void)
  func listStorages(
    _ request: StorageListRequest, withReply reply: @escaping (StorageListResponse) -> Void)
  func listObjects(
    _ request: ObjectListRequest, withReply reply: @escaping (ObjectListResponse) -> Void)
  func getObjectInfo(
    deviceId: String, storageId: UInt32, objectHandle: UInt32,
    withReply reply: @escaping (ReadResponse) -> Void)

  // Write API (Phase 4)
  func writeObject(_ request: WriteRequest, withReply reply: @escaping (WriteResponse) -> Void)
  func deleteObject(_ request: DeleteRequest, withReply reply: @escaping (WriteResponse) -> Void)
  func createFolder(
    _ request: CreateFolderRequest, withReply reply: @escaping (WriteResponse) -> Void)
  func renameObject(_ request: RenameRequest, withReply reply: @escaping (WriteResponse) -> Void)
  func moveObject(_ request: MoveObjectRequest, withReply reply: @escaping (WriteResponse) -> Void)

  // Cache-first API (Phase 3)
  func requestCrawl(
    _ request: CrawlTriggerRequest, withReply reply: @escaping (CrawlTriggerResponse) -> Void)
  func deviceStatus(
    _ request: DeviceStatusRequest, withReply reply: @escaping (DeviceStatusResponse) -> Void)
}

/// XPC service name for the host app
public let MTPXPCServiceName = "com.effortlessmetrics.swiftmtp.xpc"

// MARK: - Write Request/Response

@objc(WriteRequest)
public final class WriteRequest: NSObject, NSSecureCoding, Sendable {
  public static let supportsSecureCoding: Bool = true

  public let deviceId: String
  public let storageId: UInt32
  public let parentHandle: UInt32?
  public let name: String
  public let size: UInt64
  /// Bookmark data for the source file URL (cross-process accessible).
  public let bookmark: Data?

  public init(
    deviceId: String, storageId: UInt32, parentHandle: UInt32?, name: String, size: UInt64,
    bookmark: Data?
  ) {
    self.deviceId = deviceId
    self.storageId = storageId
    self.parentHandle = parentHandle
    self.name = name
    self.size = size
    self.bookmark = bookmark
    super.init()
  }

  public func encode(with coder: NSCoder) {
    coder.encode(deviceId, forKey: "deviceId")
    coder.encode(Int64(storageId), forKey: "storageId")
    if let ph = parentHandle { coder.encode(Int64(ph), forKey: "parentHandle") }
    coder.encode(name, forKey: "name")
    coder.encode(Int64(bitPattern: size), forKey: "size")
    coder.encode(bookmark, forKey: "bookmark")
  }

  public init?(coder: NSCoder) {
    guard let deviceId = coder.decodeObject(of: NSString.self, forKey: "deviceId") as String?,
      let name = coder.decodeObject(of: NSString.self, forKey: "name") as String?
    else { return nil }
    self.deviceId = deviceId
    self.storageId = UInt32(coder.decodeInt64(forKey: "storageId"))
    self.parentHandle =
      coder.containsValue(forKey: "parentHandle")
      ? UInt32(coder.decodeInt64(forKey: "parentHandle")) : nil
    self.name = name
    self.size = UInt64(bitPattern: coder.decodeInt64(forKey: "size"))
    self.bookmark = coder.decodeObject(of: NSData.self, forKey: "bookmark") as Data?
  }
}

@objc(DeleteRequest)
public final class DeleteRequest: NSObject, NSSecureCoding, Sendable {
  public static let supportsSecureCoding: Bool = true

  public let deviceId: String
  public let objectHandle: UInt32
  public let recursive: Bool

  public init(deviceId: String, objectHandle: UInt32, recursive: Bool = true) {
    self.deviceId = deviceId
    self.objectHandle = objectHandle
    self.recursive = recursive
    super.init()
  }

  public func encode(with coder: NSCoder) {
    coder.encode(deviceId, forKey: "deviceId")
    coder.encode(Int64(objectHandle), forKey: "objectHandle")
    coder.encode(recursive, forKey: "recursive")
  }

  public init?(coder: NSCoder) {
    guard let deviceId = coder.decodeObject(of: NSString.self, forKey: "deviceId") as String? else {
      return nil
    }
    self.deviceId = deviceId
    self.objectHandle = UInt32(coder.decodeInt64(forKey: "objectHandle"))
    self.recursive = coder.decodeBool(forKey: "recursive")
  }
}

@objc(CreateFolderRequest)
public final class CreateFolderRequest: NSObject, NSSecureCoding, Sendable {
  public static let supportsSecureCoding: Bool = true

  public let deviceId: String
  public let storageId: UInt32
  public let parentHandle: UInt32?
  public let name: String

  public init(deviceId: String, storageId: UInt32, parentHandle: UInt32?, name: String) {
    self.deviceId = deviceId
    self.storageId = storageId
    self.parentHandle = parentHandle
    self.name = name
    super.init()
  }

  public func encode(with coder: NSCoder) {
    coder.encode(deviceId, forKey: "deviceId")
    coder.encode(Int64(storageId), forKey: "storageId")
    if let ph = parentHandle { coder.encode(Int64(ph), forKey: "parentHandle") }
    coder.encode(name, forKey: "name")
  }

  public init?(coder: NSCoder) {
    guard let deviceId = coder.decodeObject(of: NSString.self, forKey: "deviceId") as String?,
      let name = coder.decodeObject(of: NSString.self, forKey: "name") as String?
    else { return nil }
    self.deviceId = deviceId
    self.storageId = UInt32(coder.decodeInt64(forKey: "storageId"))
    self.parentHandle =
      coder.containsValue(forKey: "parentHandle")
      ? UInt32(coder.decodeInt64(forKey: "parentHandle")) : nil
    self.name = name
  }
}

@objc(WriteResponse)
public final class WriteResponse: NSObject, NSSecureCoding, Sendable {
  public static let supportsSecureCoding: Bool = true

  public let success: Bool
  public let errorMessage: String?
  /// The handle of the newly created object (for write/createFolder).
  public let newHandle: UInt32?

  public init(success: Bool, errorMessage: String? = nil, newHandle: UInt32? = nil) {
    self.success = success
    self.errorMessage = errorMessage
    self.newHandle = newHandle
    super.init()
  }

  public func encode(with coder: NSCoder) {
    coder.encode(success, forKey: "success")
    coder.encode(errorMessage, forKey: "errorMessage")
    if let h = newHandle { coder.encode(Int64(h), forKey: "newHandle") }
  }

  public init?(coder: NSCoder) {
    self.success = coder.decodeBool(forKey: "success")
    self.errorMessage = coder.decodeObject(of: NSString.self, forKey: "errorMessage") as String?
    self.newHandle =
      coder.containsValue(forKey: "newHandle")
      ? UInt32(coder.decodeInt64(forKey: "newHandle")) : nil
  }
}

// MARK: - Rename / Move Request

@objc(RenameRequest)
public final class RenameRequest: NSObject, NSSecureCoding, Sendable {
  public static let supportsSecureCoding: Bool = true

  public let deviceId: String
  public let objectHandle: UInt32
  public let newName: String

  public init(deviceId: String, objectHandle: UInt32, newName: String) {
    self.deviceId = deviceId
    self.objectHandle = objectHandle
    self.newName = newName
    super.init()
  }

  public func encode(with coder: NSCoder) {
    coder.encode(deviceId, forKey: "deviceId")
    coder.encode(Int64(objectHandle), forKey: "objectHandle")
    coder.encode(newName, forKey: "newName")
  }

  public init?(coder: NSCoder) {
    guard let deviceId = coder.decodeObject(of: NSString.self, forKey: "deviceId") as String?,
      let newName = coder.decodeObject(of: NSString.self, forKey: "newName") as String?
    else { return nil }
    self.deviceId = deviceId
    self.objectHandle = UInt32(coder.decodeInt64(forKey: "objectHandle"))
    self.newName = newName
  }
}

@objc(MoveObjectRequest)
public final class MoveObjectRequest: NSObject, NSSecureCoding, Sendable {
  public static let supportsSecureCoding: Bool = true

  public let deviceId: String
  public let objectHandle: UInt32
  public let newParentHandle: UInt32?
  public let newStorageId: UInt32

  public init(
    deviceId: String, objectHandle: UInt32, newParentHandle: UInt32?, newStorageId: UInt32
  ) {
    self.deviceId = deviceId
    self.objectHandle = objectHandle
    self.newParentHandle = newParentHandle
    self.newStorageId = newStorageId
    super.init()
  }

  public func encode(with coder: NSCoder) {
    coder.encode(deviceId, forKey: "deviceId")
    coder.encode(Int64(objectHandle), forKey: "objectHandle")
    if let ph = newParentHandle { coder.encode(Int64(ph), forKey: "newParentHandle") }
    coder.encode(Int64(newStorageId), forKey: "newStorageId")
  }

  public init?(coder: NSCoder) {
    guard let deviceId = coder.decodeObject(of: NSString.self, forKey: "deviceId") as String? else {
      return nil
    }
    self.deviceId = deviceId
    self.objectHandle = UInt32(coder.decodeInt64(forKey: "objectHandle"))
    self.newParentHandle =
      coder.containsValue(forKey: "newParentHandle")
      ? UInt32(coder.decodeInt64(forKey: "newParentHandle")) : nil
    self.newStorageId = UInt32(coder.decodeInt64(forKey: "newStorageId"))
  }
}

// MARK: - Crawl Trigger Request/Response

@objc(CrawlTriggerRequest)
public final class CrawlTriggerRequest: NSObject, NSSecureCoding, Sendable {
  public static let supportsSecureCoding: Bool = true

  public let deviceId: String
  public let storageId: UInt32
  public let parentHandle: UInt32?

  public init(deviceId: String, storageId: UInt32, parentHandle: UInt32? = nil) {
    self.deviceId = deviceId
    self.storageId = storageId
    self.parentHandle = parentHandle
    super.init()
  }

  public func encode(with coder: NSCoder) {
    coder.encode(deviceId, forKey: "deviceId")
    coder.encode(Int64(storageId), forKey: "storageId")
    if let ph = parentHandle { coder.encode(Int64(ph), forKey: "parentHandle") }
  }

  public init?(coder: NSCoder) {
    guard let deviceId = coder.decodeObject(of: NSString.self, forKey: "deviceId") as String? else {
      return nil
    }
    self.deviceId = deviceId
    self.storageId = UInt32(coder.decodeInt64(forKey: "storageId"))
    self.parentHandle =
      coder.containsValue(forKey: "parentHandle")
      ? UInt32(coder.decodeInt64(forKey: "parentHandle")) : nil
  }
}

@objc(CrawlTriggerResponse)
public final class CrawlTriggerResponse: NSObject, NSSecureCoding, Sendable {
  public static let supportsSecureCoding: Bool = true

  public let accepted: Bool
  public let errorMessage: String?

  public init(accepted: Bool, errorMessage: String? = nil) {
    self.accepted = accepted
    self.errorMessage = errorMessage
    super.init()
  }

  public func encode(with coder: NSCoder) {
    coder.encode(accepted, forKey: "accepted")
    coder.encode(errorMessage, forKey: "errorMessage")
  }

  public init?(coder: NSCoder) {
    self.accepted = coder.decodeBool(forKey: "accepted")
    self.errorMessage = coder.decodeObject(of: NSString.self, forKey: "errorMessage") as String?
  }
}

// MARK: - Device Status Request/Response

@objc(DeviceStatusRequest)
public final class DeviceStatusRequest: NSObject, NSSecureCoding, Sendable {
  public static let supportsSecureCoding: Bool = true

  public let deviceId: String

  public init(deviceId: String) {
    self.deviceId = deviceId
    super.init()
  }

  public func encode(with coder: NSCoder) { coder.encode(deviceId, forKey: "deviceId") }

  public init?(coder: NSCoder) {
    guard let deviceId = coder.decodeObject(of: NSString.self, forKey: "deviceId") as String? else {
      return nil
    }
    self.deviceId = deviceId
  }
}

@objc(DeviceStatusResponse)
public final class DeviceStatusResponse: NSObject, NSSecureCoding, Sendable {
  public static let supportsSecureCoding: Bool = true

  public let connected: Bool
  public let sessionOpen: Bool
  public let lastCrawlTimestamp: Int64

  public init(connected: Bool, sessionOpen: Bool, lastCrawlTimestamp: Int64 = 0) {
    self.connected = connected
    self.sessionOpen = sessionOpen
    self.lastCrawlTimestamp = lastCrawlTimestamp
    super.init()
  }

  public func encode(with coder: NSCoder) {
    coder.encode(connected, forKey: "connected")
    coder.encode(sessionOpen, forKey: "sessionOpen")
    coder.encode(lastCrawlTimestamp, forKey: "lastCrawlTimestamp")
  }

  public init?(coder: NSCoder) {
    self.connected = coder.decodeBool(forKey: "connected")
    self.sessionOpen = coder.decodeBool(forKey: "sessionOpen")
    self.lastCrawlTimestamp = coder.decodeInt64(forKey: "lastCrawlTimestamp")
  }
}
