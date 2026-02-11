// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation

enum TestUtilities {
    static func createTempDirectory(prefix: String = "swiftmtp-scenario") throws -> URL {
        let base = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let dir = base.appendingPathComponent("\(prefix)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func createTempFile(directory: URL, filename: String, content: Data) throws -> URL {
        let fileURL = directory.appendingPathComponent(filename)
        try content.write(to: fileURL)
        return fileURL
    }

    static func cleanupTempDirectory(_ directory: URL) throws {
        try? FileManager.default.removeItem(at: directory)
    }
}

enum TestFixtures {
    static func smallFile() -> Data {
        Data((0..<1_024).map { UInt8($0 % 256) })
    }

    static func mediumFile() -> Data {
        Data((0..<1_048_576).map { UInt8($0 % 256) })
    }

    static func textContent() -> String {
        """
        This is a test file for SwiftMTP.
        It contains multiple lines of text.
        Testing file transfer functionality.
        """
    }
}
