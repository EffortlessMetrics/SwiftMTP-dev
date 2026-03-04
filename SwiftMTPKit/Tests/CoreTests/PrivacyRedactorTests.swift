// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2025 Effortless Metrics, Inc.

import XCTest

@testable import SwiftMTPCore

final class PrivacyRedactorTests: XCTestCase {

  // MARK: - Serial Redaction

  func testSerialRedactionPreservesPrefix() {
    let result = PrivacyRedactor.redactSerial("ABCDEF123456")
    XCTAssertTrue(result.hasPrefix("ABCD"), "Should keep first 4 chars")
    XCTAssertTrue(result.contains("…"), "Should contain ellipsis separator")
  }

  func testSerialRedactionProducesDeterministicOutput() {
    let a = PrivacyRedactor.redactSerial("SN-12345-XYZ")
    let b = PrivacyRedactor.redactSerial("SN-12345-XYZ")
    XCTAssertEqual(a, b, "Same input must produce same output")
  }

  func testSerialRedactionPreservesUniqueness() {
    let a = PrivacyRedactor.redactSerial("SERIAL_AAA")
    let b = PrivacyRedactor.redactSerial("SERIAL_BBB")
    XCTAssertNotEqual(a, b, "Different serials must produce different outputs")
  }

  func testSerialRedactionEmptyInput() {
    XCTAssertEqual(PrivacyRedactor.redactSerial(""), "")
  }

  func testSerialRedactionShortInput() {
    let result = PrivacyRedactor.redactSerial("AB")
    XCTAssertTrue(result.hasPrefix("AB"), "Short serials keep available prefix chars")
    XCTAssertTrue(result.contains("…"))
  }

  // MARK: - Path Redaction

  func testPathRedactionMacOS() {
    let result = PrivacyRedactor.redactPath("/Users/steven/Documents/photo.jpg")
    XCTAssertEqual(result, "/Users/[redacted]/Documents/photo.jpg")
  }

  func testPathRedactionLinux() {
    let result = PrivacyRedactor.redactPath("/home/alice/Pictures/cat.png")
    XCTAssertEqual(result, "/home/[redacted]/Pictures/cat.png")
  }

  func testPathRedactionWindows() {
    let result = PrivacyRedactor.redactPath(#"C:\Users\Bob\Desktop\file.txt"#)
    XCTAssertEqual(result, #"C:\Users\[redacted]\Desktop\file.txt"#)
  }

  func testPathRedactionPreservesNonUserPaths() {
    let path = "/var/lib/mtp/cache.db"
    XCTAssertEqual(PrivacyRedactor.redactPath(path), path)
  }

  func testPathRedactionEmptyInput() {
    XCTAssertEqual(PrivacyRedactor.redactPath(""), "")
  }

  func testPathRedactionPreservesStructure() {
    let result = PrivacyRedactor.redactPath("/Users/john/a/b/c/d.txt")
    XCTAssertTrue(result.contains("/a/b/c/d.txt"), "Directory structure after home should survive")
  }

  // MARK: - Filename Redaction

  func testFilenameRedactionPreservesExtension() {
    let result = PrivacyRedactor.redactFilename("vacation-photo.jpg")
    XCTAssertTrue(result.hasSuffix(".jpg"), "Extension must be preserved")
    XCTAssertTrue(result.hasPrefix("file_"), "Should use file_ prefix")
  }

  func testFilenameRedactionNoExtension() {
    let result = PrivacyRedactor.redactFilename("README")
    XCTAssertTrue(result.hasPrefix("file_"))
    XCTAssertFalse(result.contains("."))
  }

  func testFilenameRedactionEmptyInput() {
    XCTAssertEqual(PrivacyRedactor.redactFilename(""), "")
  }

  func testFilenameRedactionDeterministic() {
    let a = PrivacyRedactor.redactFilename("secret-doc.pdf")
    let b = PrivacyRedactor.redactFilename("secret-doc.pdf")
    XCTAssertEqual(a, b)
  }

  func testFilenameRedactionDifferentNames() {
    let a = PrivacyRedactor.redactFilename("photo1.jpg")
    let b = PrivacyRedactor.redactFilename("photo2.jpg")
    XCTAssertNotEqual(a, b, "Different filenames should produce different hashes")
  }

  // MARK: - Owner Name Redaction

  func testOwnerNameRedactionPossessive() {
    let result = PrivacyRedactor.redactOwnerName("John's iPhone")
    XCTAssertEqual(result, "[Owner]'s iPhone")
  }

  func testOwnerNameRedactionMultiWord() {
    let result = PrivacyRedactor.redactOwnerName("Mary Jane's Galaxy S24")
    XCTAssertEqual(result, "[Owner]'s Galaxy S24")
  }

  func testOwnerNameRedactionNoPossessive() {
    let input = "Pixel 7 Pro"
    XCTAssertEqual(PrivacyRedactor.redactOwnerName(input), input)
  }

  func testOwnerNameRedactionEmptyInput() {
    XCTAssertEqual(PrivacyRedactor.redactOwnerName(""), "")
  }

  // MARK: - VID:PID Not Redacted

  func testVIDPIDNotRedacted() {
    let json: [String: Any] = [
      "vendorId": "0x18d1",
      "productId": "0x4ee1",
      "serial": "ABC123XYZ",
    ]
    let redacted = PrivacyRedactor.redactSubmission(json)
    XCTAssertEqual(redacted["vendorId"] as? String, "0x18d1")
    XCTAssertEqual(redacted["productId"] as? String, "0x4ee1")
    XCTAssertNotEqual(redacted["serial"] as? String, "ABC123XYZ", "Serial should be redacted")
  }

  func testInterfaceDescriptorsNotRedacted() {
    let json: [String: Any] = [
      "interface": [
        "class": "0x06",
        "subclass": "0x01",
        "protocol": "0x01",
      ] as [String: Any]
    ]
    let redacted = PrivacyRedactor.redactSubmission(json)
    let iface = redacted["interface"] as? [String: Any]
    XCTAssertEqual(iface?["class"] as? String, "0x06")
    XCTAssertEqual(iface?["subclass"] as? String, "0x01")
  }

  // MARK: - Submission Redaction (Dictionary)

  func testSubmissionRedactsNestedPaths() {
    let json: [String: Any] = [
      "artifacts": [
        "path": "/Users/alice/mtp-bundle/probe.json"
      ] as [String: Any]
    ]
    let redacted = PrivacyRedactor.redactSubmission(json)
    let artifacts = redacted["artifacts"] as? [String: Any]
    let path = artifacts?["path"] as? String ?? ""
    XCTAssertTrue(path.contains("[redacted]"))
    XCTAssertFalse(path.contains("alice"))
  }

  func testSubmissionRedactsDeviceName() {
    let json: [String: Any] = [
      "deviceName": "Steven's Pixel 7"
    ]
    let redacted = PrivacyRedactor.redactSubmission(json)
    let name = redacted["deviceName"] as? String ?? ""
    XCTAssertTrue(name.contains("[Owner]"))
    XCTAssertFalse(name.contains("Steven"))
  }

  func testSubmissionRedactsFilenames() {
    let json: [String: Any] = [
      "filename": "my-secret-photo.jpg"
    ]
    let redacted = PrivacyRedactor.redactSubmission(json)
    let fname = redacted["filename"] as? String ?? ""
    XCTAssertTrue(fname.hasPrefix("file_"))
    XCTAssertTrue(fname.hasSuffix(".jpg"))
  }

  func testSubmissionPreservesNonSensitiveValues() {
    let json: [String: Any] = [
      "formatCode": "0x3801",
      "responseCode": "0x2001",
      "eventCode": "0x4002",
      "version": "1.0.0",
    ]
    let redacted = PrivacyRedactor.redactSubmission(json)
    XCTAssertEqual(redacted["formatCode"] as? String, "0x3801")
    XCTAssertEqual(redacted["responseCode"] as? String, "0x2001")
    XCTAssertEqual(redacted["eventCode"] as? String, "0x4002")
    XCTAssertEqual(redacted["version"] as? String, "1.0.0")
  }

  func testSubmissionHandlesArrayValues() {
    let json: [String: Any] = [
      "filename": ["photo1.jpg", "photo2.png"] as [Any]
    ]
    let redacted = PrivacyRedactor.redactSubmission(json)
    let names = redacted["filename"] as? [Any] ?? []
    XCTAssertEqual(names.count, 2)
    for name in names {
      let s = name as? String ?? ""
      XCTAssertTrue(s.hasPrefix("file_"), "Array filenames should be redacted")
    }
  }

  func testSubmissionEmptyDictionary() {
    let result = PrivacyRedactor.redactSubmission([:])
    XCTAssertTrue(result.isEmpty)
  }

  func testSubmissionPreservesNumericValues() {
    let json: [String: Any] = [
      "sizeBytes": 1024,
      "handle": 42,
    ]
    let redacted = PrivacyRedactor.redactSubmission(json)
    XCTAssertEqual(redacted["sizeBytes"] as? Int, 1024)
    XCTAssertEqual(redacted["handle"] as? Int, 42)
  }
}
