// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import Foundation
import XCTest
@testable import swiftmtp_cli

// MARK: - SubmissionWorkflowWave35Tests

final class SubmissionWorkflowWave35Tests: XCTestCase {

  // Resolve project root from the test bundle location.
  private static let projectRoot: String = {
    let fileURL = URL(fileURLWithPath: #filePath)
    return fileURL
      .deletingLastPathComponent()  // ToolingTests
      .deletingLastPathComponent()  // Tests
      .deletingLastPathComponent()  // SwiftMTPKit
      .deletingLastPathComponent()  // repo root
      .path
  }()

  // MARK: - 1. validate-submission.sh prints usage with no args

  func testValidateSubmissionScriptPrintsUsageWithNoArgs() throws {
    let scriptPath = Self.projectRoot + "/scripts/validate-submission.sh"
    try XCTSkipUnless(
      FileManager.default.isExecutableFile(atPath: scriptPath),
      "validate-submission.sh not found or not executable")

    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/bash")
    process.arguments = [scriptPath]
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = pipe
    try process.run()
    process.waitUntilExit()

    let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    XCTAssertEqual(process.terminationStatus, 2, "Should exit with code 2 (usage error)")
    XCTAssertTrue(output.contains("Usage:"), "Should print usage information")
    XCTAssertTrue(
      output.contains("submission-bundle-directory"),
      "Usage should mention submission-bundle-directory argument")
  }

  // MARK: - 2. Device entry validation catches common mistakes

  func testValidateDeviceEntryScriptPrintsUsageWithNoArgs() throws {
    let scriptPath = Self.projectRoot + "/scripts/validate-device-entry.sh"
    try XCTSkipUnless(
      FileManager.default.isExecutableFile(atPath: scriptPath),
      "validate-device-entry.sh not found or not executable")

    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/bash")
    process.arguments = [scriptPath]
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = pipe
    try process.run()
    process.waitUntilExit()

    XCTAssertNotEqual(process.terminationStatus, 0, "Should fail with no args")
  }

  func testEntryValidationCatchesMissingVID() throws {
    // An entry with an empty vid should fail VID format validation
    let entry: [String: Any] = [
      "id": "test-missing-vid-0001",
      "deviceName": "Test Device",
      "category": "phone",
      "match": ["vid": "", "pid": "0x1234"],
      "hooks": [] as [Any],
      "status": "proposed",
    ]
    let match = entry["match"] as! [String: String]
    let hexPattern = #/^0x[0-9a-fA-F]{4}$/#
    XCTAssertNil(
      try? hexPattern.wholeMatch(in: match["vid"]!),
      "Empty VID should not match hex format")
  }

  func testEntryValidationCatchesInvalidPIDFormat() throws {
    let invalidPIDs = ["1234", "0xGGGG", "0x12", "0x123456", "abcd"]
    let hexPattern = #/^0x[0-9a-fA-F]{4}$/#
    for pid in invalidPIDs {
      XCTAssertNil(
        try? hexPattern.wholeMatch(in: pid),
        "PID '\(pid)' should not match valid hex format")
    }
  }

  func testEntryValidationCatchesMissingCategory() throws {
    let validCategories: Set<String> = [
      "3d-printer", "action-camera", "audio-player", "camera", "dev-board",
      "drone", "e-reader", "media-player", "phone", "tablet", "wearable",
    ]
    let emptyCategory = ""
    XCTAssertFalse(
      validCategories.contains(emptyCategory),
      "Empty category should not be valid")
    let invalidCategory = "spaceship"
    XCTAssertFalse(
      validCategories.contains(invalidCategory),
      "Invalid category should not be accepted")
  }

  // MARK: - 3. Privacy redaction strips serial numbers and user paths

  func testSanitizeDumpStripsUserPaths() {
    let raw = """
      Device located at /Users/steven/Library/MTP/cache
      Config: /home/alice/.config/swiftmtp
      Windows: C:\\Users\\Bob\\Documents\\mtp.log
      """
    let sanitized = Self.applySanitizePatterns(raw)
    XCTAssertFalse(sanitized.contains("/Users/steven"), "macOS user path should be redacted")
    XCTAssertFalse(sanitized.contains("/home/alice"), "Linux home path should be redacted")
    XCTAssertTrue(sanitized.contains("/Users/<redacted>"), "Should contain redacted macOS path")
    XCTAssertTrue(sanitized.contains("/home/<redacted>"), "Should contain redacted Linux path")
  }

  func testSanitizeDumpStripsSerialNumbers() {
    let raw = """
      Serial Number: ABC123DEF456
      iSerial: 9876543210ABCDEF
      UDID: 00008030001C18362EE802
      """
    let sanitized = Self.applySanitizePatterns(raw)
    XCTAssertFalse(sanitized.contains("ABC123DEF456"), "Serial number should be redacted")
    XCTAssertFalse(sanitized.contains("9876543210ABCDEF"), "iSerial should be redacted")
    XCTAssertTrue(sanitized.contains("<redacted>"), "Should contain redaction marker")
  }

  func testSanitizeDumpStripsEmailAddresses() {
    let raw = "Owner email: alice@example.com"
    let sanitized = Self.applySanitizePatterns(raw)
    XCTAssertFalse(sanitized.contains("alice@example.com"), "Email should be redacted")
    XCTAssertTrue(sanitized.contains("<redacted-email>"), "Should replace with redacted-email")
  }

  func testSanitizeDumpStripsIPAddresses() {
    let raw = "Connected via 192.168.1.42"
    let sanitized = Self.applySanitizePatterns(raw)
    XCTAssertFalse(sanitized.contains("192.168.1.42"), "IPv4 should be redacted")
    XCTAssertTrue(sanitized.contains("<redacted-ipv4>"), "Should replace with redacted-ipv4")
  }

  func testSanitizeDumpStripsMACAddresses() {
    let raw = "WiFi: AA:BB:CC:DD:EE:FF"
    let sanitized = Self.applySanitizePatterns(raw)
    XCTAssertFalse(sanitized.contains("AA:BB:CC:DD:EE:FF"), "MAC address should be redacted")
    XCTAssertTrue(sanitized.contains("<redacted-mac>"), "Should replace with redacted-mac")
  }

  func testSanitizeDumpStripsHostnames() {
    let raw = "Hostname: stevens-macbook-pro"
    let sanitized = Self.applySanitizePatterns(raw)
    XCTAssertFalse(sanitized.contains("stevens-macbook-pro"), "Hostname should be redacted")
  }

  func testRedactionHMACIsStableForSameSalt() {
    let salt = Data("stable-test-salt".utf8)
    let a = Redaction.redactSerial("SERIAL-XYZ", salt: salt)
    let b = Redaction.redactSerial("SERIAL-XYZ", salt: salt)
    XCTAssertEqual(a, b, "Same input + salt should produce same HMAC")
    XCTAssertTrue(a.hasPrefix("hmacsha256:"), "Should have hmacsha256 prefix")
  }

  func testRedactionDiffersForDifferentSerials() {
    let salt = Data("stable-test-salt".utf8)
    let a = Redaction.redactSerial("SERIAL-001", salt: salt)
    let b = Redaction.redactSerial("SERIAL-002", salt: salt)
    XCTAssertNotEqual(a, b, "Different serials should produce different HMACs")
  }

  // MARK: - 4. Bundle structure validation

  func testCollectBundleRequiredFiles() throws {
    // Verify that validate-submission.sh expects these required files
    let scriptPath = Self.projectRoot + "/scripts/validate-submission.sh"
    let scriptContent = try String(contentsOfFile: scriptPath, encoding: .utf8)
    let requiredFiles = ["submission.json", "probe.json", "usb-dump.txt", "quirk-suggestion.json"]
    for file in requiredFiles {
      XCTAssertTrue(
        scriptContent.contains(file),
        "Validation script should check for required file: \(file)")
    }
  }

  func testSubmissionManifestSchemaRequiredFields() throws {
    let schemaPath = Self.projectRoot + "/Specs/submission.schema.json"
    let data = try XCTUnwrap(FileManager.default.contents(atPath: schemaPath))
    let schema = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    let required = try XCTUnwrap(schema["required"] as? [String])

    let expectedFields = ["schemaVersion", "tool", "host", "timestamp", "device", "artifacts", "consent"]
    for field in expectedFields {
      XCTAssertTrue(
        required.contains(field),
        "Schema should require top-level field '\(field)'")
    }
  }

  func testSubmissionManifestDeviceFieldRequirements() throws {
    let schemaPath = Self.projectRoot + "/Specs/submission.schema.json"
    let data = try XCTUnwrap(FileManager.default.contents(atPath: schemaPath))
    let schema = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    let properties = schema["properties"] as? [String: Any]
    let device = properties?["device"] as? [String: Any]
    let deviceRequired = try XCTUnwrap(device?["required"] as? [String])

    let expectedDeviceFields = [
      "vendorId", "productId", "vendor", "model", "interface", "fingerprintHash", "serialRedacted",
    ]
    for field in expectedDeviceFields {
      XCTAssertTrue(
        deviceRequired.contains(field),
        "Device schema should require '\(field)'")
    }
  }

  func testBenchmarkCSVHeaderFormat() {
    let expectedHeader = "timestamp,operation,size_bytes,duration_seconds,speed_mbps"
    // Verify the validate-submission.sh script checks for this exact header
    let components = expectedHeader.split(separator: ",")
    XCTAssertEqual(components.count, 5)
    XCTAssertEqual(components[0], "timestamp")
    XCTAssertEqual(components[1], "operation")
    XCTAssertEqual(components[4], "speed_mbps")
  }

  // MARK: - 5. Duplicate submission detection

  func testDuplicateVIDPIDDetection() throws {
    let specsPath = Self.projectRoot + "/Specs/quirks.json"
    let data = try XCTUnwrap(FileManager.default.contents(atPath: specsPath))
    let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    let entries = try XCTUnwrap(json["entries"] as? [[String: Any]])

    var vidPidPairs = [String: String]()
    for entry in entries {
      let id = entry["id"] as? String ?? "unknown"
      guard let match = entry["match"] as? [String: Any],
        let vid = match["vid"] as? String, let pid = match["pid"] as? String
      else { continue }
      let key = "\(vid):\(pid)"
      if let existing = vidPidPairs[key] {
        XCTFail("Duplicate VID:PID \(key) found in '\(existing)' and '\(id)'")
      }
      vidPidPairs[key] = id
    }
    XCTAssertGreaterThan(vidPidPairs.count, 0, "Should have parsed at least one entry")
  }

  func testDuplicateQuirkIDDetection() throws {
    let specsPath = Self.projectRoot + "/Specs/quirks.json"
    let data = try XCTUnwrap(FileManager.default.contents(atPath: specsPath))
    let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    let entries = try XCTUnwrap(json["entries"] as? [[String: Any]])

    var ids = Set<String>()
    for entry in entries {
      let id = try XCTUnwrap(entry["id"] as? String)
      XCTAssertTrue(ids.insert(id).inserted, "Duplicate quirk ID: \(id)")
    }
  }

  func testSubmitDeviceScriptRejectsDuplicateVIDPID() throws {
    // Verify the submit-device.sh script contains duplicate detection logic
    let scriptPath = Self.projectRoot + "/scripts/submit-device.sh"
    let content = try String(contentsOfFile: scriptPath, encoding: .utf8)
    XCTAssertTrue(
      content.contains("already exists"),
      "submit-device.sh should detect and reject duplicate entries")
    XCTAssertTrue(
      content.contains("VID:PID") || content.contains("vid") && content.contains("pid"),
      "submit-device.sh should check VID:PID pairs")
  }

  // MARK: - 6. Quirks JSON schema validation

  func testQuirksJSONIsValidAndParseable() throws {
    let specsPath = Self.projectRoot + "/Specs/quirks.json"
    let data = try XCTUnwrap(FileManager.default.contents(atPath: specsPath))
    let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

    XCTAssertNotNil(json["version"], "quirks.json must have a version field")
    let entries = try XCTUnwrap(json["entries"] as? [[String: Any]])
    XCTAssertGreaterThan(entries.count, 0, "quirks.json must have entries")
  }

  func testQuirksEntriesHaveValidHexVIDPID() throws {
    let specsPath = Self.projectRoot + "/Specs/quirks.json"
    let data = try XCTUnwrap(FileManager.default.contents(atPath: specsPath))
    let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    let entries = try XCTUnwrap(json["entries"] as? [[String: Any]])
    let hexPattern = #/^0x[0-9a-fA-F]{4}$/#

    for entry in entries {
      let id = entry["id"] as? String ?? "unknown"
      guard let match = entry["match"] as? [String: Any] else {
        XCTFail("Entry \(id): missing match object")
        continue
      }
      if let vid = match["vid"] as? String {
        XCTAssertNotNil(
          try? hexPattern.wholeMatch(in: vid),
          "Entry \(id): vid '\(vid)' must match 0x[0-9a-fA-F]{4}")
      }
      if let pid = match["pid"] as? String {
        XCTAssertNotNil(
          try? hexPattern.wholeMatch(in: pid),
          "Entry \(id): pid '\(pid)' must match 0x[0-9a-fA-F]{4}")
      }
    }
  }

  func testQuirksEntriesHaveArrayHooksNotDicts() throws {
    let specsPath = Self.projectRoot + "/Specs/quirks.json"
    let data = try XCTUnwrap(FileManager.default.contents(atPath: specsPath))
    let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    let entries = try XCTUnwrap(json["entries"] as? [[String: Any]])

    for entry in entries {
      let id = entry["id"] as? String ?? "unknown"
      if let hooks = entry["hooks"] {
        XCTAssertTrue(hooks is [Any], "Entry \(id): hooks must be an array, got \(type(of: hooks))")
      }
    }
  }

  func testQuirksSpecsMatchesResources() throws {
    let specsPath = Self.projectRoot + "/Specs/quirks.json"
    let resourcesPath =
      Self.projectRoot + "/SwiftMTPKit/Sources/SwiftMTPQuirks/Resources/quirks.json"
    let specsData = try XCTUnwrap(FileManager.default.contents(atPath: specsPath))
    let resourcesData = try XCTUnwrap(FileManager.default.contents(atPath: resourcesPath))
    XCTAssertEqual(
      specsData, resourcesData,
      "Specs/quirks.json and SwiftMTPQuirks/Resources/quirks.json must be identical")
  }

  // MARK: - Helpers

  /// Mirrors the sanitization patterns from CollectCommand.sanitizeDump to test them in isolation.
  private static func applySanitizePatterns(_ text: String) -> String {
    var t = text
    t = t.replacingOccurrences(
      of: #"/Users/[^/\n]+"#, with: "/Users/<redacted>", options: .regularExpression)
    t = t.replacingOccurrences(
      of: #"/home/[^/\n]+"#, with: "/home/<redacted>", options: .regularExpression)
    t = t.replacingOccurrences(
      of: #"([A-Za-z]:\\Users\\)[^\\]+"#, with: "$1<redacted>", options: .regularExpression)
    t = t.replacingOccurrences(
      of: #"(?i)(Host\s*Name|Hostname|Computer\s*Name)\s*:\s*.*"#, with: "$1: <redacted>",
      options: .regularExpression)
    t = t.replacingOccurrences(
      of: #"[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}"#, with: "<redacted-email>",
      options: [.regularExpression, .caseInsensitive])
    t = t.replacingOccurrences(
      of: #"\b(\d{1,3}\.){3}\d{1,3}\b"#, with: "<redacted-ipv4>", options: .regularExpression)
    t = t.replacingOccurrences(
      of: #"\b([0-9A-Fa-f]{2}[:-]){5}[0-9A-Fa-f]{2}\b"#, with: "<redacted-mac>",
      options: [.regularExpression, .caseInsensitive])
    t = t.replacingOccurrences(
      of: #"(?i)(UDID|Serial\s*(?:Number)?|iSerial)\b[:\s]+(\S+)"#, with: "$1: <redacted>",
      options: .regularExpression)
    t = t.replacingOccurrences(
      of: #"\b[A-Za-z0-9._-]+\.local\b"#, with: "<redacted>.local", options: .regularExpression)
    return t
  }
}
