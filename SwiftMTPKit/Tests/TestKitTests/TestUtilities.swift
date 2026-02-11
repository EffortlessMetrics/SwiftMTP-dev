// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
@testable import SwiftMTPCore
@testable import SwiftMTPTestKit

/// Test utilities and helpers for SwiftMTP testing
enum TestUtilities {
    
    /// Creates a temporary directory for testing
    static func createTempDirectory(prefix: String = "swiftmtp-test") throws -> URL {
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
        let uniqueDir = tempDir.appendingPathComponent("\(prefix)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: uniqueDir, withIntermediateDirectories: true)
        return uniqueDir
    }
    
    /// Creates a temporary file with given content
    static func createTempFile(directory: URL, filename: String, content: Data) throws -> URL {
        let fileURL = directory.appendingPathComponent(filename)
        try content.write(to: fileURL)
        return fileURL
    }
    
    /// Creates a temporary file with given size (random content)
    static func createTempFile(directory: URL, filename: String, size: Int) throws -> URL {
        var content = Data(count: size)
        for i in 0..<size {
            content[i] = UInt8.random(in: 0...255)
        }
        return try createTempFile(directory: directory, filename: filename, content: content)
    }
    
    /// Cleans up a temporary directory
    static func cleanupTempDirectory(_ directory: URL) throws {
        try? FileManager.default.removeItem(at: directory)
    }
}

/// Mock data for testing
enum MockDeviceData {
    /// Pixel 7 mock data
    static let pixel7 = MockDeviceDataHolder(
        deviceSummary: MTPDeviceSummary(
            id: MTPDeviceID(raw: "18d1:4ee1@1:2"),
            manufacturer: "Google",
            model: "Pixel 7",
            vendorID: 0x18D1,
            productID: 0x4EE1
        ),
        storageInfo: [
            MTPStorageInfo(
                id: MTPStorageID(raw: 0x00010001),
                description: "Internal Storage",
                capacityBytes: 128_000_000_000,
                freeBytes: 64_000_000_000,
                isReadOnly: false
            )
        ],
        operationsSupported: [
            PTPOp.getDeviceInfo.rawValue,
            PTPOp.openSession.rawValue,
            PTPOp.closeSession.rawValue,
            PTPOp.getStorageIDs.rawValue,
            PTPOp.getStorageInfo.rawValue,
            PTPOp.getObjectHandles.rawValue,
            PTPOp.getObjectInfo.rawValue,
            PTPOp.getObject.rawValue,
            PTPOp.sendObjectInfo.rawValue,
            PTPOp.sendObject.rawValue,
            PTPOp.deleteObject.rawValue,
            PTPOp.getPartialObject64.rawValue,
            PTPOp.sendPartialObject.rawValue,
        ]
    )
    
    /// OnePlus 3T mock data
    static let onePlus3T = MockDeviceDataHolder(
        deviceSummary: MTPDeviceSummary(
            id: MTPDeviceID(raw: "2a70:f003@3:2"),
            manufacturer: "OnePlus",
            model: "ONEPLUS A3010",
            vendorID: 0x2A70,
            productID: 0xF003
        ),
        storageInfo: [
            MTPStorageInfo(
                id: MTPStorageID(raw: 0x00010001),
                description: "Internal Storage",
                capacityBytes: 64_000_000_000,
                freeBytes: 32_000_000_000,
                isReadOnly: false
            )
        ],
        operationsSupported: [
            PTPOp.getDeviceInfo.rawValue,
            PTPOp.openSession.rawValue,
            PTPOp.closeSession.rawValue,
            PTPOp.getStorageIDs.rawValue,
            PTPOp.getStorageInfo.rawValue,
            PTPOp.getObjectHandles.rawValue,
            PTPOp.getObjectInfo.rawValue,
            PTPOp.getObject.rawValue,
            PTPOp.sendObjectInfo.rawValue,
            PTPOp.sendObject.rawValue,
            PTPOp.deleteObject.rawValue,
        ]
    )
}

/// Mock device data holder
struct MockDeviceDataHolder {
    let deviceSummary: MTPDeviceSummary
    let storageInfo: [MTPStorageInfo]
    let operationsSupported: [UInt16]
}

/// Test fixtures for common scenarios
enum TestFixtures {
    /// Small file fixture (~1KB)
    static func smallFile() -> Data {
        var data = Data(count: 1024)
        for i in 0..<1024 {
            data[i] = UInt8(i % 256)
        }
        return data
    }
    
    /// Medium file fixture (~1MB)
    static func mediumFile() -> Data {
        var data = Data(count: 1_048_576)
        for i in 0..<1_048_576 {
            data[i] = UInt8(i % 256)
        }
        return data
    }
    
    /// Large file fixture (~10MB)
    static func largeFile() -> Data {
        var data = Data(count: 10_485_760)
        for i in 0..<10_485_760 {
            data[i] = UInt8(i % 256)
        }
        return data
    }
    
    /// Text file content
    static func textContent() -> String {
        """
        This is a test file for SwiftMTP.
        It contains multiple lines of text.
        Testing file transfer functionality.
        """
    }
}
