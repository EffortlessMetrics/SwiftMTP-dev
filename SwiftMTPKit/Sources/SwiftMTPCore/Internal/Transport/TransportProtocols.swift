// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation

public struct PTPResponseResult: Sendable {
    public let code: UInt16
    public let txid: UInt32
    public let params: [UInt32]
    public let data: Data?
    
    public init(code: UInt16, txid: UInt32, params: [UInt32] = [], data: Data? = nil) {
        self.code = code
        self.txid = txid
        self.params = params
        self.data = data
    }
    
    public var isOK: Bool { code == 0x2001 }
}

public protocol MTPTransport: Sendable {
    func open(_ summary: MTPDeviceSummary, config: SwiftMTPConfig) async throws -> MTPLink
    func close() async throws
}

/// Bundles USB interface metadata discovered during transport probing.
public struct MTPLinkDescriptor: Sendable, Codable, Hashable {
    public let interfaceNumber: UInt8
    public let interfaceClass: UInt8
    public let interfaceSubclass: UInt8
    public let interfaceProtocol: UInt8
    public let bulkInEndpoint: UInt8
    public let bulkOutEndpoint: UInt8
    public let interruptEndpoint: UInt8?

    public init(interfaceNumber: UInt8, interfaceClass: UInt8, interfaceSubclass: UInt8,
                interfaceProtocol: UInt8, bulkInEndpoint: UInt8, bulkOutEndpoint: UInt8,
                interruptEndpoint: UInt8? = nil) {
        self.interfaceNumber = interfaceNumber
        self.interfaceClass = interfaceClass
        self.interfaceSubclass = interfaceSubclass
        self.interfaceProtocol = interfaceProtocol
        self.bulkInEndpoint = bulkInEndpoint
        self.bulkOutEndpoint = bulkOutEndpoint
        self.interruptEndpoint = interruptEndpoint
    }
}

public protocol MTPLink: Sendable {
    /// Raw device-info bytes cached during interface probing. Default: nil.
    var cachedDeviceInfo: MTPDeviceInfo? { get }

    /// USB interface/endpoint metadata from transport probing. Default: nil.
    var linkDescriptor: MTPLinkDescriptor? { get }

    /// Interface probe result containing selection reason and skipped alternatives.
    /// Default: nil.
    var interfaceProbeResult: InterfaceProbeResult? { get }

    func openUSBIfNeeded() async throws
    func openSession(id: UInt32) async throws
    func closeSession() async throws
    func close() async

    func getDeviceInfo() async throws -> MTPDeviceInfo
    func getStorageIDs() async throws -> [MTPStorageID]
    func getStorageInfo(id: MTPStorageID) async throws -> MTPStorageInfo
    func getObjectHandles(storage: MTPStorageID, parent: MTPObjectHandle?) async throws -> [MTPObjectHandle]
    func getObjectInfos(_ handles: [MTPObjectHandle]) async throws -> [MTPObjectInfo]
    func getObjectInfos(storage: MTPStorageID, parent: MTPObjectHandle?, format: UInt16?) async throws -> [MTPObjectInfo]

    func resetDevice() async throws

    func deleteObject(handle: MTPObjectHandle) async throws
    func moveObject(handle: MTPObjectHandle, to storage: MTPStorageID, parent: MTPObjectHandle?) async throws

    func executeCommand(_ command: PTPContainer) async throws -> PTPResponseResult

    // Streaming data transfer methods for file operations
    func executeStreamingCommand(
        _ command: PTPContainer,
        dataPhaseLength: UInt64?,
        dataInHandler: MTPDataIn?,
        dataOutHandler: MTPDataOut?
    ) async throws -> PTPResponseResult
}

/// Default implementations for optional MTPLink properties.
public extension MTPLink {
  var cachedDeviceInfo: MTPDeviceInfo? { nil }
  var linkDescriptor: MTPLinkDescriptor? { nil }
  var interfaceProbeResult: InterfaceProbeResult? { nil }
}

public protocol TransportFactory {
    static func createTransport() -> MTPTransport
}