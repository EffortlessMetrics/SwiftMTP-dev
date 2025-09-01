import Foundation
public struct MTPDeviceID: Hashable, Sendable { public let raw: String }
public struct MTPStorageID: Hashable, Sendable { public let raw: UInt32 }
public typealias MTPObjectHandle = UInt32
public struct MTPDeviceInfo: Sendable {
  public let manufacturer, model, version: String
  public let serialNumber: String?
  public let operationsSupported: Set<UInt16>
  public let eventsSupported: Set<UInt16>
}
public struct MTPStorageInfo: Sendable {
  public let id: MTPStorageID, description: String
  public let capacityBytes, freeBytes: UInt64
  public let isReadOnly: Bool
}
public struct MTPObjectInfo: Sendable {
  public let handle: MTPObjectHandle
  public let storage: MTPStorageID
  public let parent: MTPObjectHandle?
  public let name: String
  public let sizeBytes: UInt64?
  public let modified: Date?
  public let formatCode: UInt16
  public let properties: [UInt16: Any]
}
