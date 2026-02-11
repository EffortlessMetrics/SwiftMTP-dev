// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import SwiftMTPCore

/// Factory for creating mock transports with different device profiles
public enum MockTransportFactory {
    /// Available mock device profiles
    public enum DeviceProfile {
        case androidPixel7
        case androidGalaxyS21
        case androidOnePlus3T
        case iosDevice
        case canonCamera
        case failureTimeout
        case failureBusy
        case failureDisconnected
        case custom(MockDeviceData)
    }

    /// Create a mock transport with the specified profile
    public static func createTransport(profile: DeviceProfile = .androidPixel7) -> any MTPTransport {
        let deviceData = deviceData(for: profile)
        return MockTransport(deviceData: deviceData)
    }

    /// Get the device data for a profile
    public static func deviceData(for profile: DeviceProfile) -> MockDeviceData {
        switch profile {
        case .androidPixel7:
            return MockDeviceData.androidPixel7
        case .androidGalaxyS21:
            return MockDeviceData.androidGalaxyS21
        case .androidOnePlus3T:
            return MockDeviceData.androidOnePlus3T
        case .iosDevice:
            return MockDeviceData.iosDevice
        case .canonCamera:
            return MockDeviceData.canonCamera
        case .failureTimeout:
            return MockDeviceData.failureTimeout
        case .failureBusy:
            return MockDeviceData.failureBusy
        case .failureDisconnected:
            return MockDeviceData.failureDisconnected
        case .custom(let data):
            return data
        }
    }
}

/// Mock device data containing all the information needed to simulate a device
public struct MockDeviceData: Sendable {
    public let deviceSummary: MTPDeviceSummary
    public let deviceInfo: MTPDeviceInfo
    public let storages: [MTPStorageInfo]
    public let objects: [MockObjectData]
    public let operationsSupported: [UInt16]
    public let eventsSupported: [UInt16]
    public let failureMode: MockFailureMode?

    public init(
        deviceSummary: MTPDeviceSummary,
        deviceInfo: MTPDeviceInfo,
        storages: [MTPStorageInfo],
        objects: [MockObjectData],
        operationsSupported: [UInt16],
        eventsSupported: [UInt16],
        failureMode: MockFailureMode? = nil
    ) {
        self.deviceSummary = deviceSummary
        self.deviceInfo = deviceInfo
        self.storages = storages
        self.objects = objects
        self.operationsSupported = operationsSupported
        self.eventsSupported = eventsSupported
        self.failureMode = failureMode
    }
}

/// Mock object data for simulating files/directories
public struct MockObjectData: Sendable {
    public let handle: MTPObjectHandle
    public let storage: MTPStorageID
    public let parent: MTPObjectHandle?
    public let name: String
    public let size: UInt64?
    public let formatCode: UInt16
    public let data: Data?

    public init(
        handle: MTPObjectHandle,
        storage: MTPStorageID,
        parent: MTPObjectHandle? = nil,
        name: String,
        size: UInt64? = nil,
        formatCode: UInt16 = 0x3000, // Undefined object
        data: Data? = nil
    ) {
        self.handle = handle
        self.storage = storage
        self.parent = parent
        self.name = name
        self.size = size
        self.formatCode = formatCode
        self.data = data
    }
}

/// Different failure modes for testing error conditions
public enum MockFailureMode: Sendable {
    case timeout
    case busy
    case accessDenied
    case deviceDisconnected
    case protocolError(code: UInt16)
}
