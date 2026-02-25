// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import Testing
@testable import SwiftMTPCore

@Suite("Transfer IO Tests")
struct TransferIOTests {

  @Test("FileSink writes data correctly")
  func testFileSink() async throws {
    // Create a temporary file URL
    let tempURL = URL(fileURLWithPath: NSTemporaryDirectory())
      .appendingPathComponent("test_sink.tmp")

    // Remove if exists
    try? FileManager.default.removeItem(at: tempURL)

    do {
      // Test writing data
      let sink = try FileSink(url: tempURL)
      let testData: [UInt8] = [1, 2, 3, 4, 5]
      try testData.withUnsafeBytes { buffer in
        try sink.write(buffer)
      }
      try sink.close()

      // Verify file contents
      let fileData = try Data(contentsOf: tempURL)
      #expect(fileData == Data(testData))
    } catch {
      Issue.record("FileSink test failed: \(error)")
    }

    // Cleanup
    try? FileManager.default.removeItem(at: tempURL)
  }

  @Test("FileSource reads data correctly")
  func testFileSource() async throws {
    // Create a temporary file with known content
    let tempURL = URL(fileURLWithPath: NSTemporaryDirectory())
      .appendingPathComponent("test_source.tmp")
    let testData: [UInt8] = [10, 20, 30, 40, 50]
    try Data(testData).write(to: tempURL)

    do {
      // Test reading data
      let source = try FileSource(url: tempURL)
      var buffer = [UInt8](repeating: 0, count: 10)

      let bytesRead = try buffer.withUnsafeMutableBytes { buf in
        try source.read(into: buf)
      }

      #expect(bytesRead == testData.count)
      #expect(Array(buffer.prefix(bytesRead)) == testData)
      #expect(source.fileSize == UInt64(testData.count))

      try source.close()
    } catch {
      Issue.record("FileSource test failed: \(error)")
    }

    // Cleanup
    try? FileManager.default.removeItem(at: tempURL)
  }

  @Test("Atomic replace works correctly")
  func testAtomicReplace() async throws {
    let tempURL = URL(fileURLWithPath: NSTemporaryDirectory())
      .appendingPathComponent("temp_file.tmp")
    let finalURL = URL(fileURLWithPath: NSTemporaryDirectory())
      .appendingPathComponent("final_file.tmp")

    // Create temp file with content
    let tempData: [UInt8] = [100, 101, 102]
    try Data(tempData).write(to: tempURL)

    // Create final file with different content
    let finalData: [UInt8] = [200, 201, 202]
    try Data(finalData).write(to: finalURL)

    do {
      // Perform atomic replace
      try atomicReplace(temp: tempURL, final: finalURL)

      // Verify final file has temp content
      let resultData = try Data(contentsOf: finalURL)
      #expect(resultData == Data(tempData))

      // Verify temp file is gone
      #expect(!FileManager.default.fileExists(atPath: tempURL.path))
    } catch {
      Issue.record("Atomic replace test failed: \(error)")
    }

    // Cleanup
    try? FileManager.default.removeItem(at: finalURL)
  }
}
